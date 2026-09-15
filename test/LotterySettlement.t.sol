// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IEqualFiDrandRegistry } from "../src/interfaces/IEqualFiDrandRegistry.sol";
import { ISettlement } from "../src/interfaces/ISettlement.sol";
import { Errors } from "../src/shared/Errors.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    RoundStatus
} from "../src/shared/Types.sol";
import {
    ConfiguredDrandRegistry,
    LotteryIntegrationSetup
} from "./utils/LotteryIntegrationSetup.sol";

contract ReentrantDrandRegistry is IEqualFiDrandRegistry {
    function firstRoundAfter(uint256 timestamp) external pure returns (uint64) {
        return uint64(timestamp / 3 + 1);
    }

    function roundTime(uint64 round) public pure returns (uint64) {
        return round * 3;
    }

    function hasSig(uint64) external pure returns (bool) {
        return false;
    }

    function randomnessOf(uint64) external pure returns (bytes32) {
        return bytes32(0);
    }

    function postedAt(uint64) external pure returns (uint64) {
        return 0;
    }

    function postSig(uint64 round, bytes calldata) external returns (bool) {
        ISettlement(msg.sender).settleRound(round, "");
        return true;
    }
}

contract LotterySettlementTest is LotteryIntegrationSetup {
    function test_SettlesMaximumReachableRoundReceipts() public {
        uint96 price = type(uint96).max;
        uint32 count = type(uint32).max;
        uint256 gross = uint256(price) * count;
        LotteryConfig memory config = _config(address(tokenA), price, count, count, 1 days, 0);

        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        tokenA.mint(alice, gross);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, count);
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("maximum receipts"), soldOut.selloutAt + 1);
        settlement.settleRound(roundId, "");

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(soldOut.receipts, gross);
        assertEq(
            accounting.winnerLiability + accounting.pendingOperatorRevenueTotal
                + accounting.treasuryAvailable + accounting.finalizerLiability,
            gross
        );
    }

    function test_SubmittedProofSettlesIntoExactTokenLiabilities() public {
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        bytes memory proof = hex"123456";
        _prepareProof(roundId, proof);
        uint256 diamondBalanceBefore = tokenA.balanceOf(address(diamond));

        vm.prank(finalizer);
        (uint32 winningTicket, address winner) = settlement.settleRound(roundId, proof);

        Round memory settled = stateView.round(roundId);
        bytes32 expectedSeed = keccak256(
            abi.encode(
                registry.randomnessOf(soldOut.drandRound), block.chainid, address(diamond), roundId
            )
        );
        assertEq(settled.settledAt, block.timestamp);
        assertEq(uint8(settled.status), uint8(RoundStatus.Settled));
        assertEq(settled.applicationSeed, expectedSeed);
        assertEq(settled.winningTicket, uint32(uint256(expectedSeed) % 10));
        assertEq(winningTicket, settled.winningTicket);
        assertEq(winner, stateView.ticketOwner(roundId, winningTicket));
        assertEq(settled.winner, winner);
        assertEq(settled.winnerClaimable, 80);
        assertEq(stateView.activeRoundCount(), 0);

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.activeRoundEscrow, 0);
        assertEq(accounting.winnerLiability, 80);
        assertEq(accounting.pendingOperatorRevenueTotal, 10);
        assertEq(accounting.treasuryAvailable, 7);
        assertEq(accounting.finalizerLiability, 3);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 3);
        assertEq(tokenA.balanceOf(address(diamond)), diamondBalanceBefore);
        assertEq(
            accounting.winnerLiability + accounting.pendingOperatorRevenueTotal
                + accounting.treasuryAvailable + accounting.finalizerLiability,
            soldOut.receipts
        );
    }

    function test_ReusesCachedCommittedRandomnessWithoutProof() public {
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        bytes32 randomness = keccak256("cached randomness");
        registry.cache(soldOut.drandRound, randomness, soldOut.selloutAt + 1);

        vm.prank(finalizer);
        settlement.settleRound(roundId, "");

        bytes32 expectedSeed =
            keccak256(abi.encode(randomness, block.chainid, address(diamond), roundId));
        assertEq(stateView.round(roundId).applicationSeed, expectedSeed);
    }

    function test_RejectsUnavailableRandomnessWithoutChangingSettlementState() public {
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        vm.warp(registry.roundTime(soldOut.drandRound));
        registry.setReturnWithoutStoring(true);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.RandomnessUnavailable.selector, soldOut.drandRound)
        );
        vm.prank(finalizer);
        settlement.settleRound(roundId, hex"1234");

        Round memory unchanged = stateView.round(roundId);
        assertEq(uint8(unchanged.status), uint8(RoundStatus.SoldOut));
        assertEq(unchanged.winner, address(0));
        assertEq(unchanged.winnerClaimable, 0);
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 100);
    }

    function test_RegistryProofFailureBubblesAndPreservesEscrow() public {
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        bytes memory expectedProof = hex"aaaa";
        registry.expectProof(soldOut.drandRound, expectedProof);
        vm.warp(registry.roundTime(soldOut.drandRound));

        vm.expectRevert(ConfiguredDrandRegistry.InvalidProof.selector);
        vm.prank(finalizer);
        settlement.settleRound(roundId, hex"bbbb");

        assertEq(uint8(stateView.round(roundId).status), uint8(RoundStatus.SoldOut));
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 100);
    }

    function test_RejectsRandomnessPostedAtOrBeforeSellout() public {
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("stale"), soldOut.selloutAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.RandomnessPredatesSellout.selector,
                soldOut.drandRound,
                soldOut.selloutAt,
                soldOut.selloutAt
            )
        );
        settlement.settleRound(roundId, "");

        assertEq(uint8(stateView.round(roundId).status), uint8(RoundStatus.SoldOut));
    }

    function test_RejectsOpenExpiredAndAlreadySettledRounds() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 999));
        settlement.settleRound(999, "");

        vm.prank(alice);
        uint256 openRoundId = lottery.openRound(1, 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotSoldOut.selector, openRoundId));
        settlement.settleRound(openRoundId, "");

        Round memory open = stateView.round(openRoundId);
        vm.warp(open.expiresAt);
        lottery.expireRound(openRoundId);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotSoldOut.selector, openRoundId));
        settlement.settleRound(openRoundId, "");

        uint256 soldOutRoundId = _sellOutRoundA();
        bytes memory proof = hex"1234";
        _prepareProof(soldOutRoundId, proof);
        settlement.settleRound(soldOutRoundId, proof);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotSoldOut.selector, soldOutRoundId));
        settlement.settleRound(soldOutRoundId, proof);
    }

    function test_PauseCannotBlockSettlement() public {
        uint256 roundId = _sellOutRoundA();
        bytes memory proof = hex"1234";
        _prepareProof(roundId, proof);
        vm.prank(guardian);
        governance.setPaused(true);

        vm.prank(finalizer);
        settlement.settleRound(roundId, proof);

        assertEq(uint8(stateView.round(roundId).status), uint8(RoundStatus.Settled));
    }

    function test_RegistryCannotReenterSettlement() public {
        ReentrantDrandRegistry reentrantRegistry = new ReentrantDrandRegistry();
        vm.prank(authority);
        governance.setIntegrationConfig(
            IntegrationConfig(address(reentrantRegistry), address(router))
        );
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        vm.warp(reentrantRegistry.roundTime(soldOut.drandRound));

        vm.expectRevert(Errors.Reentrancy.selector);
        settlement.settleRound(roundId, hex"1234");

        assertEq(uint8(stateView.round(roundId).status), uint8(RoundStatus.SoldOut));
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 100);
    }

    function test_DomainSeparatesRoundsUsingSameRegistryRandomness() public {
        vm.startPrank(authority);
        governance.createLotteryConfig(_config(address(tokenA), 10, 10, 10, 1 days, 30));
        governance.setLotteryConfigEnabled(3, true);
        vm.stopPrank();

        uint256 firstRoundId = _sellOutRoundA();
        vm.prank(alice);
        uint256 secondRoundId = lottery.openRound(3, 10);
        Round memory first = stateView.round(firstRoundId);
        Round memory second = stateView.round(secondRoundId);
        assertEq(first.drandRound, second.drandRound);

        bytes32 sharedRandomness = keccak256("shared randomness");
        registry.cache(first.drandRound, sharedRandomness, first.selloutAt + 1);
        settlement.settleRound(firstRoundId, "");
        settlement.settleRound(secondRoundId, "");

        bytes32 firstSeed = stateView.round(firstRoundId).applicationSeed;
        bytes32 secondSeed = stateView.round(secondRoundId).applicationSeed;
        assertNotEq(firstSeed, secondSeed);
        assertEq(
            firstSeed,
            keccak256(abi.encode(sharedRandomness, block.chainid, address(diamond), firstRoundId))
        );
        assertEq(
            secondSeed,
            keccak256(abi.encode(sharedRandomness, block.chainid, address(diamond), secondRoundId))
        );
    }

    function test_FinalizerTipIsCappedToTreasuryWithoutReducingOtherShares() public {
        vm.startPrank(authority);
        governance.createLotteryConfig(_config(address(tokenA), 1, 10, 10, 1 days, 0));
        governance.setLotteryConfigEnabled(3, true);
        vm.stopPrank();

        vm.prank(alice);
        uint256 roundId = lottery.openRound(3, 10);
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("cap"), soldOut.selloutAt + 1);
        vm.prank(finalizer);
        settlement.settleRound(roundId, "");

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 8);
        assertEq(accounting.pendingOperatorRevenueTotal, 1);
        assertEq(accounting.finalizerLiability, 1);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 1);
    }

    function test_SettlesZeroWinnerAndOperatorSharesEntirelyToTreasury() public {
        LotteryConfig memory config = _config(address(tokenA), 10, 10, 10, 1 days, 0);
        config.winnerBps = 0;
        config.operatorProtocolBps = 0;
        config.finalizerTip = 0;
        _settleWithConfig(config, keccak256("zero shares"));

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 0);
        assertEq(accounting.pendingOperatorRevenueTotal, 0);
        assertEq(accounting.treasuryAvailable, 100);
        assertEq(accounting.finalizerLiability, 0);
    }

    function test_SettlesFullWinnerShareWithoutProtocolLiabilities() public {
        LotteryConfig memory config = _config(address(tokenA), 10, 10, 10, 1 days, 0);
        config.winnerBps = 10_000;
        config.operatorProtocolBps = 10_000;
        _settleWithConfig(config, keccak256("full winner"));

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 100);
        assertEq(accounting.pendingOperatorRevenueTotal, 0);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(accounting.finalizerLiability, 0);
    }

    function test_SettlesFullOperatorProtocolShareWithoutTreasuryOrTip() public {
        LotteryConfig memory config = _config(address(tokenA), 10, 10, 10, 1 days, 0);
        config.winnerBps = 5000;
        config.operatorProtocolBps = 10_000;
        _settleWithConfig(config, keccak256("full operator"));

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 50);
        assertEq(accounting.pendingOperatorRevenueTotal, 50);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(accounting.finalizerLiability, 0);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 50);
    }

    function test_RoundsSharesDownAndAssignsRemainderToTreasury() public {
        LotteryConfig memory config = _config(address(tokenA), 1, 7, 7, 1 days, 0);
        config.winnerBps = 3333;
        config.operatorProtocolBps = 3333;
        config.finalizerTip = 1;
        _settleWithConfig(config, keccak256("rounding"));

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 2);
        assertEq(accounting.pendingOperatorRevenueTotal, 1);
        assertEq(accounting.treasuryAvailable, 3);
        assertEq(accounting.finalizerLiability, 1);
        assertEq(
            accounting.winnerLiability + accounting.pendingOperatorRevenueTotal
                + accounting.treasuryAvailable + accounting.finalizerLiability,
            7
        );
    }

    function _settleWithConfig(LotteryConfig memory config, bytes32 randomness)
        private
        returns (uint256 roundId)
    {
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        vm.prank(alice);
        roundId = lottery.openRound(version, config.ticketCount);
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, randomness, soldOut.selloutAt + 1);
        vm.prank(finalizer);
        settlement.settleRound(roundId, "");
    }
}
