// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IClaims } from "../interfaces/IClaims.sol";
import { LibExactToken } from "../libraries/LibExactToken.sol";
import { LibLotteryStorage } from "../libraries/LibLotteryStorage.sol";
import { LibReentrancy } from "../libraries/LibReentrancy.sol";
import { Errors } from "../shared/Errors.sol";
import { AssetAccounting, Round, RoundStatus } from "../shared/Types.sol";

contract ClaimsFacet is IClaims {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function claimWinner(uint256 roundId, address receiver)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _validateReceiver(receiver);
        Round storage round = LibLotteryStorage.gameStorage().rounds[roundId];
        if (round.status == RoundStatus.None) revert Errors.RoundNotFound(roundId);
        if (round.status != RoundStatus.Settled) revert Errors.RoundNotSettled(roundId);
        if (msg.sender != round.winner) revert Errors.NotWinner(msg.sender);

        amount = round.winnerClaimable;
        if (amount == 0) revert Errors.NoWinnerClaim();
        round.winnerClaimable = 0;

        address paymentToken = round.config.paymentToken;
        LibLotteryStorage.accountingStorage()
                .assetAccounting[paymentToken]
                .winnerLiability -= amount;
        LibExactToken.pushExact(paymentToken, receiver, amount);
        emit WinnerClaimed(roundId, msg.sender, receiver, paymentToken, amount);
    }

    function claimRefund(uint256 roundId, address receiver)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _validateReceiver(receiver);
        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        Round storage round = gs.rounds[roundId];
        if (round.status == RoundStatus.None) revert Errors.RoundNotFound(roundId);
        if (round.status != RoundStatus.Expired) revert Errors.RoundNotExpired(roundId);

        amount = gs.refundCredit[roundId][msg.sender];
        if (amount == 0) revert Errors.NoRefund();
        gs.refundCredit[roundId][msg.sender] = 0;

        address paymentToken = round.config.paymentToken;
        LibLotteryStorage.accountingStorage()
                .assetAccounting[paymentToken]
                .refundLiability -= amount;
        LibExactToken.pushExact(paymentToken, receiver, amount);
        emit RefundClaimed(roundId, msg.sender, receiver, paymentToken, amount);
    }

    function claimFinalizerTips(address asset, address receiver)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _validateReceiver(receiver);
        LibLotteryStorage.AccountingStorage storage accountingStorage =
            LibLotteryStorage.accountingStorage();
        amount = accountingStorage.finalizerCredits[asset][msg.sender];
        if (amount == 0) revert Errors.NoFinalizerCredit();
        accountingStorage.finalizerCredits[asset][msg.sender] = 0;

        AssetAccounting storage accounting = accountingStorage.assetAccounting[asset];
        accounting.finalizerLiability -= amount;
        LibExactToken.pushExact(asset, receiver, amount);
        emit FinalizerTipClaimed(msg.sender, asset, receiver, amount);
    }

    function _validateReceiver(address receiver) private view {
        if (receiver == address(0) || receiver == address(this)) {
            revert Errors.InvalidAddress();
        }
    }
}
