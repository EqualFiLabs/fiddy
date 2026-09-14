// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Errors } from "../src/shared/Errors.sol";
import { AssetAccounting, IntegrationConfig, LotteryConfig, Round } from "../src/shared/Types.sol";
import {
    IntegrationEndpoint,
    IntegrationToken,
    LotteryIntegrationSetup
} from "./utils/LotteryIntegrationSetup.sol";

contract RevenueSenderFeeToken is IntegrationToken {
    bool internal feesEnabled;

    constructor() IntegrationToken("Revenue Sender Fee Token", "RSFEE") { }

    function setFeesEnabled(bool enabled) external {
        feesEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (feesEnabled && from != address(0) && to != address(0) && value != 0) {
            super._update(from, address(0), 1);
        }
    }
}

contract RejectingTreasury {
    receive() external payable {
        revert("native rejected");
    }
}

contract LotteryRevenueTest is LotteryIntegrationSetup {
    function test_FlushesExactOperatorRevenuePermissionlessly() public {
        _settleRoundA();
        AssetAccounting memory beforeFlush = stateView.assetAccounting(address(tokenA));

        vm.prank(alice);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 10), 10);

        AssetAccounting memory afterFlush = stateView.assetAccounting(address(tokenA));
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
        assertEq(afterFlush.pendingOperatorRevenueTotal, 0);
        assertEq(afterFlush.winnerLiability, beforeFlush.winnerLiability);
        assertEq(afterFlush.finalizerLiability, beforeFlush.finalizerLiability);
        assertEq(afterFlush.treasuryAvailable, beforeFlush.treasuryAvailable);
        assertEq(tokenA.balanceOf(address(router)), 10);
        assertEq(router.totalAdded(address(tokenA)), 10);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);
    }

    function test_PartialOperatorFlushLeavesExactVersionTokenRemainder() public {
        _settleRoundA();

        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 4), 4);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 6);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 6);
        assertEq(tokenA.balanceOf(address(router)), 4);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientOperatorRevenue.selector, 1, 7, 6)
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 7);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 6);
    }

    function test_RouterFailureAndReadinessChangesPreservePendingRevenue() public {
        _settleRoundA();
        router.setRejectRewards(true);

        vm.expectRevert(IntegrationEndpoint.RewardsRejected.selector);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 10);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);

        router.setRejectRewards(false);
        router.setAsset(address(tokenA), true, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRouterUnavailable.selector, address(router), address(tokenA)
            )
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);

        router.setAsset(address(tokenA), true, true);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
    }

    function test_OpeningRequiresRouterReadinessOnlyForOperatorConfigs() public {
        router.setBootstrapFinalized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRouterUnavailable.selector, address(router), address(tokenA)
            )
        );
        vm.prank(alice);
        lottery.openRound(1, 1);

        LotteryConfig memory noOperator = _config(address(tokenA), 10, 10, 10, 1 days, 0);
        noOperator.operatorProtocolBps = 0;
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(noOperator);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 1);
        assertEq(stateView.roundState(roundId).config.operatorProtocolBps, 0);
    }

    function test_HistoricalRevenueUsesSnapshottedRouterAndToken() public {
        _settleRoundA();
        IntegrationEndpoint nextRouter = new IntegrationEndpoint();
        nextRouter.setAsset(address(tokenB), true, true);
        vm.prank(authority);
        governance.setIntegrationConfig(IntegrationConfig(address(registry), address(nextRouter)));

        vm.prank(alice);
        uint256 roundB = lottery.openRound(2, 5);
        Round memory soldOutB = stateView.roundState(roundB);
        registry.cache(soldOutB.drandRound, keccak256("token B"), soldOutB.selloutAt + 1);
        settlement.settleRound(roundB, "");

        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.pendingOperatorRevenue(2, address(tokenB)), 10);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        revenue.flushOperatorRevenue(2, address(tokenB), 10);
        assertEq(tokenA.balanceOf(address(router)), 10);
        assertEq(tokenA.balanceOf(address(nextRouter)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(nextRouter)), 10);
    }

    function test_FlushesOnlyTreasuryAvailableToConfiguredRecipient() public {
        _settleRoundA();
        uint256 treasuryBefore = tokenA.balanceOf(treasury);

        vm.prank(bob);
        assertEq(revenue.flushTreasury(address(tokenA), 7), 7);

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(tokenA.balanceOf(treasury), treasuryBefore + 7);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(accounting.winnerLiability, 80);
        assertEq(accounting.pendingOperatorRevenueTotal, 10);
        assertEq(accounting.finalizerLiability, 3);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientTreasuryBalance.selector, 1, 0));
        revenue.flushTreasury(address(tokenA), 1);
    }

    function test_AbsorbsOnlyProvableTokenSurplusIntoSameTokenTreasury() public {
        _settleRoundA();
        vm.prank(alice);
        tokenA.transfer(address(diamond), 25);

        assertEq(revenue.availableTokenSurplus(address(tokenA)), 25);
        assertEq(revenue.availableTokenSurplus(address(tokenB)), 0);
        assertEq(revenue.absorbTokenSurplus(address(tokenA)), 25);
        assertEq(revenue.availableTokenSurplus(address(tokenA)), 0);
        assertEq(stateView.assetAccounting(address(tokenA)).treasuryAvailable, 32);
        assertEq(stateView.assetAccounting(address(tokenB)).treasuryAvailable, 0);

        revenue.flushTreasury(address(tokenA), 25);
        assertEq(tokenA.balanceOf(treasury), 25);
        assertEq(stateView.assetAccounting(address(tokenA)).treasuryAvailable, 7);
        vm.expectRevert(Errors.NoTokenSurplus.selector);
        revenue.absorbTokenSurplus(address(tokenA));
    }

    function test_InexactRouterTransferRollsBackLiabilityAndRouterState() public {
        RevenueSenderFeeToken token = new RevenueSenderFeeToken();
        router.setAsset(address(token), true, true);
        LotteryConfig memory config = _config(address(token), 10, 10, 10, 1 days, 0);
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
        token.mint(alice, 1000);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 10);
        Round memory soldOut = stateView.roundState(roundId);
        registry.cache(soldOut.drandRound, keccak256("sender fee"), soldOut.selloutAt + 1);
        settlement.settleRound(roundId, "");
        token.setFeesEnabled(true);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 10, 11, 10)
        );
        revenue.flushOperatorRevenue(1, address(token), 10);

        assertEq(stateView.pendingOperatorRevenue(1, address(token)), 10);
        assertEq(stateView.assetAccounting(address(token)).pendingOperatorRevenueTotal, 10);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(router.totalAdded(address(token)), 0);
        assertEq(token.allowance(address(diamond), address(router)), 0);
    }

    function test_ForcedNativeSurplusFlushesOnlyToTreasury() public {
        vm.deal(address(diamond), 1 ether);
        uint256 treasuryBefore = treasury.balance;

        vm.prank(alice);
        assertEq(revenue.flushNativeSurplus(), 1 ether);

        assertEq(address(diamond).balance, 0);
        assertEq(treasury.balance, treasuryBefore + 1 ether);
    }

    function test_FailedNativeSurplusFlushPreservesBalance() public {
        RejectingTreasury rejectingTreasury = new RejectingTreasury();
        vm.prank(authority);
        governance.setTreasuryRecipient(address(rejectingTreasury));
        vm.deal(address(diamond), 1 ether);

        vm.expectRevert(Errors.NativeTransferFailed.selector);
        revenue.flushNativeSurplus();
        assertEq(address(diamond).balance, 1 ether);
    }

    function test_RejectsZeroAndMissingRevenueRequests() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        revenue.flushOperatorRevenue(1, address(tokenA), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.IntegrationNotFound.selector, 0));
        revenue.flushOperatorRevenue(0, address(tokenA), 1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientOperatorRevenue.selector, 1, 1, 0)
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 1);
        vm.expectRevert(Errors.ZeroAmount.selector);
        revenue.flushTreasury(address(tokenA), 0);
        vm.expectRevert(Errors.NoNativeSurplus.selector);
        revenue.flushNativeSurplus();
    }

    function _settleRoundA() private returns (uint256 roundId) {
        roundId = _sellOutRoundA();
        Round memory soldOut = stateView.roundState(roundId);
        registry.cache(soldOut.drandRound, keccak256("revenue randomness"), soldOut.selloutAt + 1);
        vm.prank(finalizer);
        settlement.settleRound(roundId, "");
    }
}
