// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import { FiddySetup } from "./utils/FiddySetup.sol";
import { FiddyConfig } from "../src/shared/FiddyTypes.sol";
import { FiddyErrors } from "../src/shared/FiddyErrors.sol";

contract FiddyParticipationTest is FiddySetup {
    function _rewardConfig() internal returns (uint64 version) {
        vm.startPrank(authority);
        version = governance.createRewardLotteryConfig(
            _config(address(tokenB), 20, 5, 5, 2 days, 0), FiddyConfig(10, 0, true)
        );
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
    }

    function testOpeningAndPurchasesIssueOnlyFundedUnits() public {
        uint64 version = _rewardConfig();
        vm.prank(alice);
        fiddy.fundFiddyReserve(25);
        vm.prank(alice);
        uint256 roundId = lottery.openRoundForPosition(version, 2, 1);
        assertEq(fiddyView.fiddyAccount(1).balance, 20);
        vm.prank(bob);
        lottery.buyTicketsForPosition(roundId, 3, 2);
        assertEq(fiddyView.fiddyAccount(2).balance, 5);
        assertEq(fiddy.totalSupply(), 25);
        assertEq(tokenA.balanceOf(address(diamond)), 25);
        assertEq(stateView.round(roundId).receipts, 100);
        assertEq(stateView.ticketOwner(roundId, 0), alice);
        vm.prank(alice);
        positions.transferFrom(alice, bob, 1);
        assertEq(stateView.ticketOwner(roundId, 0), alice);
        assertEq(revenue.availableTokenSurplus(address(tokenA)), 0);
    }

    function testAccountlessPurchaseCannotBypassAttributionEvenWhenEmptyInventory() public {
        uint64 version = _rewardConfig();
        vm.prank(alice);
        vm.expectRevert(FiddyErrors.PositionRequired.selector);
        lottery.openRound(version, 1);
        vm.prank(alice);
        uint256 roundId = lottery.openRoundForPosition(version, 1, 1);
        vm.prank(bob);
        vm.expectRevert(FiddyErrors.PositionRequired.selector);
        lottery.buyTickets(roundId, 1);
        vm.prank(bob);
        vm.expectRevert(FiddyErrors.NotPositionOwner.selector);
        lottery.buyTicketsForPosition(roundId, 1, 1);
        assertEq(fiddy.totalSupply(), 0);
        assertEq(stateView.round(roundId).soldTickets, 1);
    }

    function testFirstIssuanceBridgeFailureIsAtomic() public {
        uint64 version = _rewardConfig();
        vm.prank(alice);
        fiddy.fundFiddyReserve(100);
        positions.setRejectAttach(true);
        uint256 before = tokenB.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        lottery.openRoundForPosition(version, 1, 1);
        assertEq(tokenB.balanceOf(alice), before);
        assertEq(stateView.latestRoundId(), 0);
        assertEq(fiddy.totalSupply(), 0);
    }
}
