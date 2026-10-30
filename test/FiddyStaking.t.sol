// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import { FiddySetup } from "./utils/FiddySetup.sol";
import { FiddyConfig } from "../src/shared/FiddyTypes.sol";
import { FiddyErrors } from "../src/shared/FiddyErrors.sol";

contract FiddyStakingTest is FiddySetup {
    function _start() internal {
        _wrap(1, alice, 100);
        _wrap(2, bob, 100);
        vm.prank(alice);
        staking.stakeFiddy(1, 100);
        vm.prank(bob);
        staking.stakeFiddy(2, 100);
        vm.prank(authority);
        staking.setFiddyBoostsEnabled(true);
        vm.prank(alice);
        operators.activate(1, 12_500);
        vm.prank(alice);
        staking.registerFiddyOperator(1, 1);
    }

    function _settle(address asset, bool deadline) internal returns (uint256 id) {
        vm.startPrank(authority);
        uint64 version = governance.createRewardLotteryConfig(
            _config(asset, 100, 10, 10, 1 days, 0), FiddyConfig(0, 5000, false)
        );
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
        vm.prank(alice);
        id = lottery.openRound(version, deadline ? 5 : 10);
        bytes memory proof = abi.encode(id);
        _prepareProof(id, proof);
        vm.prank(finalizer);
        settlement.settleRound(id, proof);
    }

    function _checkpoint(uint256 id) internal {
        staking.checkpointFiddyAccount(id, 100);
    }

    function testFundedBoundariesRetainPriorBoostAndInvalidateRoundTrip() public {
        _start();
        _settle(address(tokenB), false); // 100 staker units; 125:100 weights
        vm.prank(alice);
        positions.transferFrom(alice, bob, 1);
        vm.prank(bob);
        positions.transferFrom(bob, alice, 1);
        _settle(address(tokenB), false); // 100 units; 100:100 weights
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.SynchronizationRequired.selector);
        staking.unstakeFiddy(1, 100);
        staking.processFiddyRevenue(1); // indexes first boundary only
        (uint256 first,) = staking.indexedFiddyRevenue(1, address(tokenB));
        assertEq(first, 55);
        staking.processFiddyRevenue(1); // begins invalidation
        staking.processFiddyRevenue(1); // checkpoints asset; cannot index second batch
        assertEq(fiddyView.fiddyAccount(1).weight, 125);
        // Claims remain available during catch-up, including pause.
        vm.prank(authority);
        governance.setPaused(true);
        vm.prank(alice);
        assertEq(staking.claimFiddyRevenue(1, address(tokenB), alice), 55);
        staking.processFiddyRevenue(100);
        assertEq(fiddyView.fiddyAccount(1).weight, 100);
        assertFalse(fiddyView.fiddyAccount(1).registered);
        assertEq(fiddyView.fiddyOperatorAccount(1), 0);
        (uint256 later,) = staking.indexedFiddyRevenue(1, address(tokenB));
        assertEq(later, 50);
        (uint256 bobAmount,) = staking.indexedFiddyRevenue(2, address(tokenB));
        assertEq(bobAmount, 94);
        assertEq(revenue.availableTokenSurplus(address(tokenB)), 0);
    }

    function testMultiAssetCheckpointAndCompleteAccountLifecycle() public {
        _start();
        _settle(address(tokenA), false);
        _settle(address(tokenB), true);
        staking.processFiddyRevenue(100);
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.AccountCheckpointRequired.selector);
        staking.unstakeFiddy(1, 100);
        staking.checkpointFiddyAccount(1, 1);
        assertEq(fiddyView.fiddyAccount(1).checkpointCursor, 1);
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.AccountCheckpointRequired.selector);
        staking.unstakeFiddy(1, 100);
        staking.checkpointFiddyAccount(1, 1);
        vm.prank(alice);
        staking.unstakeFiddy(1, 100);
        vm.prank(alice);
        fiddy.withdrawFiddy(1, 100, alice);
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.AccountNotEmpty.selector);
        staking.cleanupFiddyAccount(1, 100);
        vm.prank(alice);
        staking.claimFiddyRevenue(1, address(tokenA), alice);
        vm.prank(alice);
        staking.claimFiddyRevenue(1, address(tokenB), alice);
        vm.prank(alice);
        assertFalse(staking.cleanupFiddyAccount(1, 1));
        vm.prank(alice);
        assertTrue(staking.cleanupFiddyAccount(1, 1));
        assertEq(positions.legs(1), 0);
        vm.prank(alice);
        positions.close(1);
        assertEq(fiddy.totalSupply(), 200);
        assertEq(tokenA.balanceOf(address(diamond)), 1145); // backing plus receipts less the 55-unit revenue claim
        assertEq(revenue.availableTokenSurplus(address(tokenA)), 0);
    }

    function testRegistrationOwnershipUniquenessAndProspectiveRefresh() public {
        _start();
        positions.mint(alice, 3);
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.OperatorAlreadyRegistered.selector);
        staking.registerFiddyOperator(3, 1);
        vm.prank(bob);
        vm.expectRevert(FiddyErrors.NotPositionOwner.selector);
        staking.registerFiddyOperator(1, 1);
        vm.prank(alice);
        operators.transferFrom(alice, bob, 1);
        vm.prank(bob);
        operators.transferFrom(bob, alice, 1);
        staking.processFiddyRevenue(100);
        assertEq(fiddyView.fiddyAccount(1).weight, 100);
        vm.prank(alice);
        operators.activate(1, 12_500);
        assertEq(fiddyView.fiddyAccount(1).weight, 100);
        vm.prank(alice);
        staking.registerFiddyOperator(1, 1);
        assertEq(fiddyView.fiddyAccount(1).weight, 125);
        positions.setReady(false);
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.HistoryUnavailable.selector);
        staking.registerFiddyOperator(1, 1);
    }

    function testZeroWeightCannotBeCapturedByLaterEntrant() public {
        _settle(address(tokenB), false);
        staking.processFiddyRevenue(100);
        assertEq(fiddyView.fiddyAsset(address(tokenB)).reserved, 0);
        _wrap(1, alice, 100);
        _checkpoint(1);
        vm.prank(alice);
        staking.stakeFiddy(1, 100);
        (uint256 amount,) = staking.indexedFiddyRevenue(1, address(tokenB));
        assertEq(amount, 0);
        assertEq(stateView.assetAccounting(address(tokenB)).treasuryAvailable, 100);
    }
}
