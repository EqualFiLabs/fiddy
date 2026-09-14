// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Errors } from "../src/shared/Errors.sol";
import { AssetAccounting, Round, RoundStatus } from "../src/shared/Types.sol";
import { IntegrationEndpoint, LotteryIntegrationSetup } from "./utils/LotteryIntegrationSetup.sol";

contract LotteryEndToEndTest is LotteryIntegrationSetup {
    address internal winnerReceiver = makeAddr("winnerReceiver");
    address internal refundReceiver = makeAddr("refundReceiver");
    address internal finalizerReceiver = makeAddr("finalizerReceiver");

    function test_CompletesConcurrentSettlementAndRefundWithIsolatedAccounting() public {
        uint256 settledRoundId = _sellOutRoundA();
        vm.prank(alice);
        uint256 expiredRoundId = lottery.openRound(2, 2);

        assertEq(stateView.activeRoundCount(), 2);
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 100);
        assertEq(stateView.assetAccounting(address(tokenB)).activeRoundEscrow, 40);

        router.setRejectRewards(true);
        bytes memory proof = hex"11223344";
        _prepareProof(settledRoundId, proof);
        vm.prank(finalizer);
        settlement.settleRound(settledRoundId, proof);

        Round memory settled = stateView.round(settledRoundId);
        assertEq(uint8(settled.status), uint8(RoundStatus.Settled));
        assertEq(uint8(stateView.round(expiredRoundId).status), uint8(RoundStatus.Open));
        assertEq(stateView.activeRoundCount(), 1);
        _assertSettledAccounting();

        vm.expectRevert(IntegrationEndpoint.RewardsRejected.selector);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        _assertSettledAccounting();
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);

        vm.prank(settled.winner);
        assertEq(claims.claimWinner(settledRoundId, winnerReceiver), 80);
        vm.prank(bob);
        assertEq(revenue.flushTreasury(address(tokenA), 7), 7);
        vm.prank(finalizer);
        assertEq(claims.claimFinalizerTips(address(tokenA), finalizerReceiver), 3);

        assertEq(tokenA.balanceOf(winnerReceiver), 80);
        assertEq(tokenA.balanceOf(treasury), 7);
        assertEq(tokenA.balanceOf(finalizerReceiver), 3);
        assertEq(tokenA.balanceOf(address(diamond)), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);

        router.setRejectRewards(false);
        vm.prank(alice);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 10), 10);
        assertEq(router.totalAdded(address(tokenA)), 10);
        assertEq(tokenA.balanceOf(address(diamond)), 0);

        vm.warp(stateView.round(expiredRoundId).expiresAt);
        vm.prank(bob);
        lottery.expireRound(expiredRoundId);
        assertEq(stateView.refundableAmount(expiredRoundId, alice), 40);
        assertEq(stateView.assetAccounting(address(tokenB)).refundLiability, 40);
        assertEq(stateView.assetAccounting(address(tokenA)).refundLiability, 0);

        vm.prank(alice);
        assertEq(claims.claimRefund(expiredRoundId, refundReceiver), 40);
        assertEq(tokenB.balanceOf(refundReceiver), 40);
        assertEq(tokenB.balanceOf(address(diamond)), 0);
        assertEq(router.totalAdded(address(tokenB)), 0);
        assertEq(stateView.activeRoundCount(), 0);

        _assertAccountingCleared(address(tokenA));
        _assertAccountingCleared(address(tokenB));
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenB)), 0);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 0);
        assertEq(stateView.refundableAmount(expiredRoundId, alice), 0);
        assertEq(stateView.round(settledRoundId).winnerClaimable, 0);
    }

    function _assertSettledAccounting() private view {
        AssetAccounting memory settled = stateView.assetAccounting(address(tokenA));
        assertEq(settled.activeRoundEscrow, 0);
        assertEq(settled.winnerLiability, 80);
        assertEq(settled.refundLiability, 0);
        assertEq(settled.finalizerLiability, 3);
        assertEq(settled.pendingOperatorRevenueTotal, 10);
        assertEq(settled.treasuryAvailable, 7);

        AssetAccounting memory stillOpen = stateView.assetAccounting(address(tokenB));
        assertEq(stillOpen.activeRoundEscrow, 40);
        assertEq(stillOpen.winnerLiability, 0);
        assertEq(stillOpen.refundLiability, 0);
        assertEq(stillOpen.finalizerLiability, 0);
        assertEq(stillOpen.pendingOperatorRevenueTotal, 0);
        assertEq(stillOpen.treasuryAvailable, 0);
    }

    function _assertAccountingCleared(address asset) private view {
        AssetAccounting memory accounting = stateView.assetAccounting(asset);
        assertEq(accounting.activeRoundEscrow, 0);
        assertEq(accounting.winnerLiability, 0);
        assertEq(accounting.refundLiability, 0);
        assertEq(accounting.finalizerLiability, 0);
        assertEq(accounting.pendingOperatorRevenueTotal, 0);
        assertEq(accounting.treasuryAvailable, 0);
    }
}
