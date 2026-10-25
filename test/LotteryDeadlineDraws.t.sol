// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { ILottery } from "../src/interfaces/ILottery.sol";
import { Errors } from "../src/shared/Errors.sol";
import { AssetAccounting, IntegrationConfig, Round, RoundStatus } from "../src/shared/Types.sol";
import {
    ConfiguredDrandRegistry,
    IntegrationToken,
    LotteryIntegrationSetup
} from "./utils/LotteryIntegrationSetup.sol";

contract DeadlineBlockingToken is IntegrationToken {
    bool internal blocked;
    error TransfersBlocked();
    constructor() IntegrationToken("Blocked", "BLOCK") { }

    function setBlocked(bool value) external {
        blocked = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (blocked && from != address(0) && to != address(0)) revert TransfersBlocked();
        super._update(from, to, value);
    }
}

contract LotteryDeadlineDrawsTest is LotteryIntegrationSetup {
    function test_OpeningSchedulesDeadlineBeaconBeforePurchases() public {
        uint64 closeAt = uint64(block.timestamp + 1 days);
        uint64 target = registry.firstRoundAfter(uint256(closeAt) + 30);
        vm.expectEmit(true, false, false, true, address(diamond));
        emit ILottery.RoundDrawScheduled(1, closeAt, target);
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 2);
        Round memory current = stateView.round(id);
        assertEq(current.drandRound, target);
        assertGt(registry.roundTime(target), uint256(current.expiresAt) + 30);
        assertEq(current.selloutAt, 0);
        assertEq(current.soldTickets, 2);
    }

    function test_DeadlineDrawUsesActualReceiptsAndSoldTickets() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 2);
        vm.prank(bob);
        lottery.buyTickets(id, 3);
        _prepareProof(id, hex"abcd");
        uint256 custody = tokenA.balanceOf(address(diamond));
        vm.prank(finalizer);
        (uint32 ticket, address winner) = settlement.settleRound(id, hex"abcd");
        Round memory current = stateView.round(id);
        assertLt(ticket, 5);
        assertEq(winner, ticket < 2 ? alice : bob);
        assertEq(current.receipts, 50);
        assertEq(current.selloutAt, 0);
        assertEq(uint8(current.status), uint8(RoundStatus.Settled));
        AssetAccounting memory ledger = stateView.assetAccounting(address(tokenA));
        assertEq(ledger.activeRoundEscrow, 0);
        assertEq(ledger.refundLiability, 0);
        assertEq(ledger.winnerLiability, 40);
        assertEq(ledger.pendingOperatorRevenueTotal, 5);
        assertEq(ledger.finalizerLiability, 3);
        assertEq(ledger.treasuryAvailable, 2);
        assertEq(tokenA.balanceOf(address(diamond)), custody);
        assertEq(stateView.activeRoundCount(), 0);
        assertEq(stateView.activeRoundForConfig(1), 0);
    }

    function test_OneTicketDrawAndCappedTipRemainClaimableWhilePaused() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 1);
        _prepareProof(id, hex"abcd");
        vm.prank(guardian);
        governance.setPaused(true);
        vm.prank(finalizer);
        settlement.settleRound(id, hex"abcd");
        assertEq(stateView.round(id).winner, alice);
        assertEq(stateView.round(id).winningTicket, 0);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 1);
        vm.prank(alice);
        assertEq(claims.claimWinner(id, bob), 8);
        vm.prank(finalizer);
        assertEq(claims.claimFinalizerTips(address(tokenA), bob), 1);
        revenue.flushOperatorRevenue(1, address(tokenA), 1);
        assertEq(tokenA.balanceOf(address(diamond)), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotReady.selector, id));
        settlement.settleRound(id, hex"abcd");
    }

    function test_DeadlineCannotBeExtendedByLateSettlerOrCatalogChanges() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 2);
        Round memory original = stateView.round(id);
        ConfiguredDrandRegistry replacement = new ConfiguredDrandRegistry();
        vm.startPrank(authority);
        governance.setIntegrationConfig(IntegrationConfig(address(replacement), address(router)));
        governance.setLotteryConfigEnabled(1, false);
        governance.createLotteryConfig(_config(address(tokenA), 99, 20, 20, 7 days, 60));
        vm.stopPrank();
        registry.expectProof(original.drandRound, hex"abcd");
        vm.warp(registry.roundTime(original.drandRound));
        registry.postSig(original.drandRound, hex"abcd");
        bytes32 expectedSeed = keccak256(
            abi.encode(
                registry.randomnessOf(original.drandRound), block.chainid, address(diamond), id
            )
        );
        vm.warp(block.timestamp + 14 days);
        settlement.settleRound(id, "");
        Round memory settled = stateView.round(id);
        assertEq(settled.drandRound, original.drandRound);
        assertEq(settled.expiresAt, original.expiresAt);
        assertEq(settled.integrationVersion, original.integrationVersion);
        assertEq(settled.applicationSeed, expectedSeed);
        assertEq(settled.winningTicket, uint256(expectedSeed) % original.soldTickets);
    }

    function test_SelloutSupersedesDeadlineOnceAndNeverUsesDeadlineProof() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 4);
        uint64 deadlineTarget = stateView.round(id).drandRound;
        vm.warp(block.timestamp + 1 hours);
        uint64 earlyTarget = registry.firstRoundAfter(block.timestamp + 30);
        vm.expectEmit(true, false, false, true, address(diamond));
        emit ILottery.RoundDrawScheduled(id, uint64(block.timestamp), earlyTarget);
        vm.prank(bob);
        lottery.buyTickets(id, 6);
        Round memory soldOut = stateView.round(id);
        assertEq(soldOut.drandRound, earlyTarget);
        assertLt(earlyTarget, deadlineTarget);
        _prepareProof(id, hex"abcd");
        settlement.settleRound(id, hex"abcd");
        assertEq(stateView.round(id).drandRound, earlyTarget);
    }

    function test_RejectsPrematureDrawAndPurchaseAtDeadlineIncludingFinalTicket() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 9);
        Round memory current = stateView.round(id);
        vm.warp(current.expiresAt - 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotReady.selector, id));
        settlement.settleRound(id, "");
        vm.warp(current.expiresAt);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundExpired.selector, id));
        vm.prank(bob);
        lottery.buyTickets(id, 1);
        vm.expectRevert(ConfiguredDrandRegistry.ProofTooEarly.selector);
        settlement.settleRound(id, hex"abcd");
        assertEq(stateView.round(id).soldTickets, 9);
        assertEq(uint8(stateView.round(id).status), uint8(RoundStatus.Open));
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 90);
    }

    function test_RejectsCachedDeadlineAtOpeningWithoutTakingPayment() public {
        uint64 target = registry.firstRoundAfter(block.timestamp + 1 days + 30);
        registry.cache(target, bytes32(uint256(1)), uint64(block.timestamp));
        uint256 balance = tokenA.balanceOf(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.StaleRandomnessRound.selector, target));
        vm.prank(alice);
        lottery.openRound(1, 1);
        assertEq(stateView.latestRoundId(), 0);
        assertEq(stateView.activeRoundCount(), 0);
        assertEq(tokenA.balanceOf(alice), balance);
    }

    function test_RejectsPostingAtDeadlineAndPreservesEscrow() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 1);
        Round memory current = stateView.round(id);
        vm.warp(current.expiresAt + 100);
        registry.cache(current.drandRound, bytes32(uint256(1)), current.expiresAt);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.RandomnessPredatesClose.selector,
                current.drandRound,
                current.expiresAt,
                current.expiresAt
            )
        );
        settlement.settleRound(id, "");
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 10);
        assertEq(stateView.activeRoundCount(), 1);
    }

    function test_WrongProofPreservesDeadlineTargetForRetry() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 2);
        uint64 target = stateView.round(id).drandRound;
        _prepareProof(id, hex"abcd");
        vm.expectRevert(ConfiguredDrandRegistry.InvalidProof.selector);
        settlement.settleRound(id, hex"ffff");
        assertEq(stateView.round(id).drandRound, target);
        assertFalse(registry.hasSig(target));
        settlement.settleRound(id, hex"abcd");
        assertEq(stateView.round(id).drandRound, target);
    }

    function test_DeadlineSettlementReleasesConfigurationForNextRound() public {
        vm.prank(alice);
        uint256 first = lottery.openRound(1, 1);
        _prepareProof(first, hex"abcd");
        settlement.settleRound(first, hex"abcd");
        vm.prank(bob);
        uint256 next = lottery.openRound(1, 1);
        assertGt(next, first);
        assertEq(stateView.activeRoundForConfig(1), next);
        assertEq(stateView.activeRoundCount(), 1);
        assertEq(stateView.round(first).winnerClaimable, 8);
    }

    function test_BlockedWinnerDeliveryPreservesLiabilityForSuccessfulRetry() public {
        DeadlineBlockingToken token = new DeadlineBlockingToken();
        router.setAsset(address(token), true, true);
        vm.startPrank(authority);
        uint64 version =
            governance.createLotteryConfig(_config(address(token), 10, 10, 10, 1 days, 0));
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
        token.mint(alice, 20);
        vm.startPrank(alice);
        token.approve(address(diamond), 20);
        uint256 id = lottery.openRound(version, 2);
        vm.stopPrank();
        _prepareProof(id, hex"abcd");
        token.setBlocked(true);
        settlement.settleRound(id, hex"abcd");
        vm.expectRevert(DeadlineBlockingToken.TransfersBlocked.selector);
        vm.prank(alice);
        claims.claimWinner(id, bob);
        assertEq(stateView.round(id).winnerClaimable, 16);
        assertEq(stateView.assetAccounting(address(token)).winnerLiability, 16);
        assertEq(token.balanceOf(address(diamond)), 20);
        token.setBlocked(false);
        vm.prank(alice);
        claims.claimWinner(id, bob);
        assertEq(token.balanceOf(bob), 16);
        assertEq(stateView.round(id).winnerClaimable, 0);
        assertEq(stateView.assetAccounting(address(token)).winnerLiability, 0);
    }

    function test_RetiredRefundSelectorsAreAbsent() public {
        vm.prank(alice);
        uint256 id = lottery.openRound(1, 1);
        vm.warp(stateView.round(id).expiresAt);
        bytes4[3] memory retired = [
            bytes4(keccak256("expireRound(uint256)")),
            bytes4(keccak256("claimRefund(uint256,address)")),
            bytes4(keccak256("refundableAmount(uint256,address)"))
        ];
        for (uint256 i; i < retired.length; ++i) {
            (bool success, bytes memory reason) =
                address(diamond).call(abi.encodeWithSelector(retired[i], id, alice));
            assertFalse(success);
            assertEq(reason, abi.encodeWithSelector(Errors.FunctionNotFound.selector, retired[i]));
        }
        assertEq(stateView.assetAccounting(address(tokenA)).refundLiability, 0);
    }

    function testFuzz_DeadlineDrawConservesReceiptsAndSelectsSoldTicket(
        uint256 rawSold,
        uint256 rawDuration,
        uint256 rawDelay
    ) public {
        uint32 sold = uint32(bound(rawSold, 1, 9));
        uint32 duration = uint32(bound(rawDuration, 1, 14 days));
        uint32 delay = uint32(bound(rawDelay, 0, 1 days));
        vm.startPrank(authority);
        uint64 version =
            governance.createLotteryConfig(_config(address(tokenA), 10, 10, 10, duration, delay));
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
        vm.prank(alice);
        uint256 id = lottery.openRound(version, sold);
        _prepareProof(id, hex"abcd");
        settlement.settleRound(id, hex"abcd");
        Round memory current = stateView.round(id);
        assertLt(current.winningTicket, sold);
        assertEq(current.winner, alice);
        assertGt(registry.roundTime(current.drandRound), uint256(current.expiresAt) + delay);
        AssetAccounting memory a = stateView.assetAccounting(address(tokenA));
        assertEq(
            a.winnerLiability + a.pendingOperatorRevenueTotal + a.treasuryAvailable
                + a.finalizerLiability,
            uint256(sold) * 10
        );
        assertEq(a.refundLiability, 0);
    }
}
