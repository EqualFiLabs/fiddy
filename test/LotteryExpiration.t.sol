// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Errors } from "../src/shared/Errors.sol";
import { AssetAccounting, LotteryConfig, RoundStatus } from "../src/shared/Types.sol";
import { IntegrationToken, LotteryIntegrationSetup } from "./utils/LotteryIntegrationSetup.sol";

contract BlockingTransferToken is IntegrationToken {
    bool internal transfersBlocked;

    error TransfersBlocked();

    constructor() IntegrationToken("Blocking Token", "BLOCK") { }

    function setTransfersBlocked(bool blocked) external {
        transfersBlocked = blocked;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (transfersBlocked && from != address(0) && to != address(0) && value != 0) {
            revert TransfersBlocked();
        }
        super._update(from, to, value);
    }
}

contract LotteryExpirationTest is LotteryIntegrationSetup {
    address internal refundReceiver = makeAddr("expirationRefundReceiver");

    function test_ExpirationCreatesOnlyExactPrincipalRefundLiabilities() public {
        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 2);
        vm.prank(bob);
        lottery.buyTickets(roundId, 3);

        vm.warp(stateView.round(roundId).expiresAt);
        lottery.expireRound(roundId);

        assertEq(uint8(stateView.round(roundId).status), uint8(RoundStatus.Expired));
        assertEq(stateView.refundableAmount(roundId, alice), 20);
        assertEq(stateView.refundableAmount(roundId, bob), 30);

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.activeRoundEscrow, 0);
        assertEq(accounting.winnerLiability, 0);
        assertEq(accounting.refundLiability, 50);
        assertEq(accounting.finalizerLiability, 0);
        assertEq(accounting.pendingOperatorRevenueTotal, 0);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(tokenA.balanceOf(address(diamond)), 50);
    }

    function test_RejectsMissingPrematureAndSoldOutExpiration() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 999));
        lottery.expireRound(999);

        vm.prank(alice);
        uint256 openRoundId = lottery.openRound(1, 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotExpired.selector, openRoundId));
        lottery.expireRound(openRoundId);

        vm.prank(alice);
        uint256 soldOutRoundId = lottery.openRound(2, 1);
        vm.prank(bob);
        lottery.buyTickets(soldOutRoundId, 4);
        vm.warp(stateView.round(soldOutRoundId).expiresAt);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotOpen.selector, soldOutRoundId));
        lottery.expireRound(soldOutRoundId);
    }

    function test_BlockedRefundPreservesLiabilityUntilRetrySucceeds() public {
        BlockingTransferToken token = new BlockingTransferToken();
        router.setAsset(address(token), true, true);
        LotteryConfig memory config = _config(address(token), 10, 10, 10, 1 days, 0);
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        token.mint(alice, 100);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 2);
        vm.warp(stateView.round(roundId).expiresAt);
        lottery.expireRound(roundId);
        token.setTransfersBlocked(true);

        vm.expectRevert(BlockingTransferToken.TransfersBlocked.selector);
        vm.prank(alice);
        claims.claimRefund(roundId, refundReceiver);

        assertEq(stateView.refundableAmount(roundId, alice), 20);
        assertEq(stateView.assetAccounting(address(token)).refundLiability, 20);
        assertEq(token.balanceOf(address(diamond)), 20);
        assertEq(token.balanceOf(refundReceiver), 0);

        token.setTransfersBlocked(false);
        vm.prank(alice);
        assertEq(claims.claimRefund(roundId, refundReceiver), 20);
        assertEq(stateView.refundableAmount(roundId, alice), 0);
        assertEq(stateView.assetAccounting(address(token)).refundLiability, 0);
        assertEq(token.balanceOf(address(diamond)), 0);
        assertEq(token.balanceOf(refundReceiver), 20);

        vm.expectRevert(Errors.NoRefund.selector);
        vm.prank(alice);
        claims.claimRefund(roundId, refundReceiver);
    }
}
