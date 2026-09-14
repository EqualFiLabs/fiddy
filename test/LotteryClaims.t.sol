// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IClaims } from "../src/interfaces/IClaims.sol";
import { Errors } from "../src/shared/Errors.sol";
import { AssetAccounting, LotteryConfig, Round, RoundStatus } from "../src/shared/Types.sol";
import { IntegrationToken, LotteryIntegrationSetup } from "./utils/LotteryIntegrationSetup.sol";

contract MutableReceiverFeeToken is IntegrationToken {
    bool internal feesEnabled;

    constructor() IntegrationToken("Mutable Fee Token", "MFEE") { }

    function setFeesEnabled(bool enabled) external {
        feesEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (feesEnabled && from != address(0) && to != address(0) && value != 0) {
            super._update(from, to, value - 1);
            super._update(from, address(0), 1);
        } else {
            super._update(from, to, value);
        }
    }
}

contract ReentrantClaimToken is IntegrationToken {
    address internal claimsTarget;
    uint256 internal attackedRound;
    bool internal attackEnabled;

    constructor() IntegrationToken("Reentrant Claim Token", "REENTER") { }

    function configureAttack(address target, uint256 roundId) external {
        claimsTarget = target;
        attackedRound = roundId;
        attackEnabled = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (attackEnabled && from == claimsTarget && to != address(0)) {
            IClaims(claimsTarget).claimRefund(attackedRound, to);
        }
    }
}

contract LotteryClaimsTest is LotteryIntegrationSetup {
    address internal receiver = makeAddr("receiver");

    function test_WinnerClaimsExactAmountToArbitraryReceiver() public {
        uint256 roundId = _settledRoundA(finalizer);
        Round memory settled = stateView.roundState(roundId);
        address winner = settled.winner;
        uint256 receiverBefore = tokenA.balanceOf(receiver);

        vm.prank(winner);
        uint256 amount = claims.claimWinner(roundId, receiver);

        assertEq(amount, 80);
        assertEq(tokenA.balanceOf(receiver), receiverBefore + 80);
        assertEq(tokenA.balanceOf(address(diamond)), 20);
        assertEq(stateView.roundState(roundId).winnerClaimable, 0);
        assertEq(stateView.assetAccounting(address(tokenA)).winnerLiability, 0);

        vm.expectRevert(Errors.NoWinnerClaim.selector);
        vm.prank(winner);
        claims.claimWinner(roundId, receiver);
    }

    function test_OnlyRecordedWinnerCanClaim() public {
        uint256 roundId = _settledRoundA(finalizer);
        address winner = stateView.roundState(roundId).winner;
        address outsider = winner == alice ? bob : alice;

        vm.expectRevert(abi.encodeWithSelector(Errors.NotWinner.selector, outsider));
        vm.prank(outsider);
        claims.claimWinner(roundId, receiver);

        assertEq(stateView.roundState(roundId).winnerClaimable, 80);
        assertEq(stateView.assetAccounting(address(tokenA)).winnerLiability, 80);
    }

    function test_ExpiredParticipantsClaimExactIndependentRefunds() public {
        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 2);
        vm.prank(bob);
        lottery.buyTickets(roundId, 3);
        vm.warp(stateView.roundState(roundId).expiresAt);
        lottery.expireRound(roundId);

        vm.prank(alice);
        assertEq(claims.claimRefund(roundId, receiver), 20);
        vm.prank(bob);
        assertEq(claims.claimRefund(roundId, bob), 30);

        assertEq(tokenA.balanceOf(receiver), 20);
        assertEq(tokenA.balanceOf(bob), 10_000);
        assertEq(tokenA.balanceOf(address(diamond)), 0);
        assertEq(stateView.refundCredit(roundId, alice), 0);
        assertEq(stateView.refundCredit(roundId, bob), 0);
        assertEq(stateView.assetAccounting(address(tokenA)).refundLiability, 0);

        vm.expectRevert(Errors.NoRefund.selector);
        vm.prank(alice);
        claims.claimRefund(roundId, receiver);
    }

    function test_FinalizerClaimsTipsAggregatedByToken() public {
        uint256 firstRoundId = _sellOutRoundA();
        uint256 secondRoundId = _sellOutRoundA();
        Round memory first = stateView.roundState(firstRoundId);
        registry.cache(first.drandRound, keccak256("shared"), first.selloutAt + 1);
        vm.startPrank(finalizer);
        settlement.settleRound(firstRoundId, "");
        settlement.settleRound(secondRoundId, "");
        vm.stopPrank();

        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 6);
        vm.prank(finalizer);
        assertEq(claims.claimFinalizerTips(address(tokenA), receiver), 6);
        assertEq(tokenA.balanceOf(receiver), 6);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 0);
        assertEq(stateView.assetAccounting(address(tokenA)).finalizerLiability, 0);

        vm.expectRevert(Errors.NoFinalizerCredit.selector);
        vm.prank(finalizer);
        claims.claimFinalizerTips(address(tokenA), receiver);
    }

    function test_RejectsClaimsInWrongStateAndZeroReceivers() public {
        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotSettled.selector, roundId));
        vm.prank(alice);
        claims.claimWinner(roundId, receiver);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotExpired.selector, roundId));
        vm.prank(alice);
        claims.claimRefund(roundId, receiver);
        vm.expectRevert(Errors.NoFinalizerCredit.selector);
        vm.prank(finalizer);
        claims.claimFinalizerTips(address(tokenA), receiver);

        vm.expectRevert(Errors.InvalidAddress.selector);
        vm.prank(alice);
        claims.claimRefund(roundId, address(0));
        vm.expectRevert(Errors.InvalidAddress.selector);
        vm.prank(finalizer);
        claims.claimFinalizerTips(address(tokenA), address(diamond));
    }

    function test_PauseCannotBlockWinnerRefundOrFinalizerClaims() public {
        uint256 settledRoundId = _settledRoundA(finalizer);
        address winner = stateView.roundState(settledRoundId).winner;

        vm.prank(alice);
        uint256 expiredRoundId = lottery.openRound(1, 1);
        vm.warp(stateView.roundState(expiredRoundId).expiresAt);
        lottery.expireRound(expiredRoundId);
        vm.prank(guardian);
        governance.setPaused(true);

        vm.prank(winner);
        claims.claimWinner(settledRoundId, winner);
        vm.prank(alice);
        claims.claimRefund(expiredRoundId, alice);
        vm.prank(finalizer);
        claims.claimFinalizerTips(address(tokenA), finalizer);

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(accounting.winnerLiability, 0);
        assertEq(accounting.refundLiability, 0);
        assertEq(accounting.finalizerLiability, 0);
    }

    function test_InexactOutboundTransferPreservesRefundEntitlement() public {
        MutableReceiverFeeToken token = new MutableReceiverFeeToken();
        uint64 version = _createTokenConfig(address(token));
        token.mint(alice, 100);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 2);
        vm.warp(stateView.roundState(roundId).expiresAt);
        lottery.expireRound(roundId);
        token.setFeesEnabled(true);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 20, 20, 19)
        );
        vm.prank(alice);
        claims.claimRefund(roundId, receiver);

        assertEq(stateView.refundCredit(roundId, alice), 20);
        assertEq(stateView.assetAccounting(address(token)).refundLiability, 20);
        assertEq(token.balanceOf(address(diamond)), 20);
        assertEq(token.balanceOf(receiver), 0);
    }

    function test_ReentrantTokenCannotConsumeRefund() public {
        ReentrantClaimToken token = new ReentrantClaimToken();
        uint64 version = _createTokenConfig(address(token));
        token.mint(alice, 100);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 2);
        vm.warp(stateView.roundState(roundId).expiresAt);
        lottery.expireRound(roundId);
        token.configureAttack(address(diamond), roundId);

        vm.expectRevert(Errors.Reentrancy.selector);
        vm.prank(alice);
        claims.claimRefund(roundId, receiver);

        assertEq(stateView.refundCredit(roundId, alice), 20);
        assertEq(stateView.assetAccounting(address(token)).refundLiability, 20);
        assertEq(token.balanceOf(address(diamond)), 20);
    }

    function _settledRoundA(address roundFinalizer) private returns (uint256 roundId) {
        roundId = _sellOutRoundA();
        Round memory soldOut = stateView.roundState(roundId);
        registry.cache(soldOut.drandRound, keccak256("claim randomness"), soldOut.selloutAt + 1);
        vm.prank(roundFinalizer);
        settlement.settleRound(roundId, "");
        assertEq(uint8(stateView.roundState(roundId).status), uint8(RoundStatus.Settled));
    }

    function _createTokenConfig(address paymentToken) private returns (uint64 version) {
        LotteryConfig memory config = _config(paymentToken, 10, 10, 10, 1 days, 0);
        router.setAsset(paymentToken, true, true);
        vm.startPrank(authority);
        version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
    }
}
