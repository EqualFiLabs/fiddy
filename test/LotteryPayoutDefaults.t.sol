// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { DeployLottery } from "../script/DeployLottery.s.sol";
import { LotteryConfig, Round } from "../src/shared/Types.sol";
import { LotteryIntegrationSetup } from "./utils/LotteryIntegrationSetup.sol";

contract PayoutDefaultsDeploymentHarness is DeployLottery {
    function payoutConfig(address paymentToken) external pure returns (LotteryConfig memory) {
        return _lotteryConfig(paymentToken, 20, 3);
    }
}

contract LotteryPayoutDefaultsTest is LotteryIntegrationSetup {
    function test_DefaultPayoutsAfterFinalizationPreserveExistingRoundEconomics() public {
        vm.prank(alice);
        uint256 existingRound = lottery.openRound(1, 4);

        LotteryConfig memory config =
            new PayoutDefaultsDeploymentHarness().payoutConfig(address(tokenA));
        vm.startPrank(authority);
        governance.finalizeProtocol();
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        governance.setLotteryConfigEnabled(1, false);
        vm.stopPrank();
        assertTrue(governance.protocolFinalized());

        vm.prank(alice);
        uint256 newRound = lottery.openRound(version, 5);
        // Disabling the old version prevents new openings, but preserves existing purchases.
        vm.prank(bob);
        lottery.buyTickets(existingRound, 6);

        address winnerReceiver = makeAddr("winner receiver");
        address finalizerReceiver = makeAddr("finalizer receiver");
        _prepareProof(newRound, hex"aabb");
        vm.prank(finalizer);
        settlement.settleRound(newRound, hex"aabb");
        Round memory settled = stateView.round(newRound);
        assertEq(settled.receipts, 100);
        vm.prank(settled.winner);
        assertEq(claims.claimWinner(newRound, winnerReceiver), 50);
        assertEq(revenue.flushTreasury(address(tokenA), 27), 27);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 20), 20);
        vm.prank(finalizer);
        assertEq(claims.claimFinalizerTips(address(tokenA), finalizerReceiver), 3);
        assertEq(tokenA.balanceOf(winnerReceiver), 50);
        assertEq(tokenA.balanceOf(treasury), 27);
        assertEq(tokenA.balanceOf(address(router)), 20);
        assertEq(tokenA.balanceOf(finalizerReceiver), 3);
        assertEq(tokenA.balanceOf(address(diamond)), 100);
        assertEq(stateView.assetAccounting(address(tokenA)).activeRoundEscrow, 100);

        // The earlier round still pays its original 80/10/10 split, including its tip.
        _prepareProof(existingRound, hex"ccdd");
        vm.prank(finalizer);
        settlement.settleRound(existingRound, hex"ccdd");
        settled = stateView.round(existingRound);
        assertEq(settled.receipts, 100);
        vm.prank(settled.winner);
        assertEq(claims.claimWinner(existingRound, winnerReceiver), 80);
        assertEq(revenue.flushTreasury(address(tokenA), 7), 7);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 10), 10);
        vm.prank(finalizer);
        assertEq(claims.claimFinalizerTips(address(tokenA), finalizerReceiver), 3);
        assertEq(tokenA.balanceOf(winnerReceiver), 130);
        assertEq(tokenA.balanceOf(treasury), 34);
        assertEq(tokenA.balanceOf(address(router)), 30);
        assertEq(tokenA.balanceOf(finalizerReceiver), 6);
        assertEq(tokenA.balanceOf(address(diamond)), 0);
        assertEq(stateView.activeRoundCount(), 0);
    }
}
