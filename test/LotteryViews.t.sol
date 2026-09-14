// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Errors } from "../src/shared/Errors.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    RoundConfigSnapshot,
    RoundStatus,
    TicketRange
} from "../src/shared/Types.sol";
import { LotteryIntegrationSetup } from "./utils/LotteryIntegrationSetup.sol";

contract LotteryViewsTest is LotteryIntegrationSetup {
    function test_ExposesConfigurationCatalogAndOpeningPolicy() public view {
        assertEq(stateView.latestLotteryConfigVersion(), 2);
        assertEq(stateView.latestRoundId(), 0);
        assertEq(stateView.activeRoundCount(), 0);
        assertEq(stateView.maxActiveRounds(), 2);

        (LotteryConfig memory first, bool firstEnabled) = stateView.lotteryConfig(1);
        (LotteryConfig memory second, bool secondEnabled) = stateView.lotteryConfig(2);
        assertEq(first.paymentToken, address(tokenA));
        assertEq(first.ticketPrice, 10);
        assertEq(first.ticketCount, 10);
        assertEq(first.maxTicketsPerPurchase, 10);
        assertTrue(firstEnabled);
        assertEq(second.paymentToken, address(tokenB));
        assertEq(second.ticketPrice, 20);
        assertEq(second.ticketCount, 5);
        assertEq(second.maxTicketsPerPurchase, 5);
        assertTrue(secondEnabled);

        (IntegrationConfig memory current, uint64 version) = stateView.currentIntegration();
        assertEq(version, 1);
        assertEq(current.drandRegistry, address(registry));
        assertEq(current.operatorFeeRouter, address(router));

        IntegrationConfig memory historical = stateView.integrationAt(1);
        assertEq(historical.drandRegistry, address(registry));
        assertEq(historical.operatorFeeRouter, address(router));
    }

    function test_RejectsUnknownConfigurationAndIntegrationVersions() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ConfigNotFound.selector, 0));
        stateView.lotteryConfig(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ConfigNotFound.selector, 3));
        stateView.lotteryConfig(3);

        vm.expectRevert(abi.encodeWithSelector(Errors.IntegrationNotFound.selector, 0));
        stateView.integrationAt(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.IntegrationNotFound.selector, 2));
        stateView.integrationAt(2);
    }

    function test_ExposesRoundSnapshotProgressAndTicketRanges() public {
        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 4);
        vm.prank(bob);
        lottery.buyTickets(roundId, 3);

        assertEq(stateView.latestRoundId(), roundId);
        assertEq(stateView.activeRoundCount(), 1);

        Round memory value = stateView.round(roundId);
        assertEq(uint8(value.status), uint8(RoundStatus.Open));
        assertEq(value.configVersion, 1);
        assertEq(value.integrationVersion, 1);
        assertEq(value.soldTickets, 7);
        assertEq(value.receipts, 70);

        RoundConfigSnapshot memory config = stateView.roundConfig(roundId);
        assertEq(config.paymentToken, address(tokenA));
        assertEq(config.ticketPrice, 10);
        assertEq(config.ticketCount, 10);
        assertEq(config.salesDuration, 1 days);
        assertEq(config.randomnessDelay, 30);
        assertEq(config.maxTicketsPerPurchase, 10);
        assertEq(config.winnerBps, 8000);
        assertEq(config.operatorProtocolBps, 5000);
        assertEq(config.finalizerTip, 3);

        assertEq(stateView.purchaseEntryCount(roundId), 2);
        TicketRange memory first = stateView.purchaseEntry(roundId, 0);
        TicketRange memory second = stateView.purchaseEntry(roundId, 1);
        assertEq(first.buyer, alice);
        assertEq(first.endExclusive, 4);
        assertEq(second.buyer, bob);
        assertEq(second.endExclusive, 7);
        assertEq(stateView.ticketOwner(roundId, 0), alice);
        assertEq(stateView.ticketOwner(roundId, 3), alice);
        assertEq(stateView.ticketOwner(roundId, 4), bob);
        assertEq(stateView.ticketOwner(roundId, 6), bob);
        assertEq(stateView.refundableAmount(roundId, alice), 40);
        assertEq(stateView.refundableAmount(roundId, bob), 30);
    }

    function test_RejectsUnknownRoundsAndInvalidTicketEntries() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 1));
        stateView.round(1);

        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 1));
        stateView.roundConfig(1);

        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 1));
        stateView.purchaseEntryCount(1);

        vm.expectRevert(abi.encodeWithSelector(Errors.RoundNotFound.selector, 1));
        stateView.refundableAmount(1, alice);

        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.PurchaseEntryNotFound.selector, roundId, 1));
        stateView.purchaseEntry(roundId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTicket.selector, 1));
        stateView.ticketOwner(roundId, 1);
    }

    function test_ExposesTokenScopedSettlementAndRefundAccounting() public {
        uint256 settledRoundId = _sellOutRoundA();
        bytes memory proof = hex"a1b2c3";
        _prepareProof(settledRoundId, proof);
        vm.prank(finalizer);
        settlement.settleRound(settledRoundId, proof);

        vm.prank(alice);
        uint256 expiredRoundId = lottery.openRound(2, 2);
        vm.warp(stateView.round(expiredRoundId).expiresAt);
        lottery.expireRound(expiredRoundId);

        Round memory settled = stateView.round(settledRoundId);
        Round memory expired = stateView.round(expiredRoundId);
        assertEq(uint8(settled.status), uint8(RoundStatus.Settled));
        assertEq(settled.winnerClaimable, 80);
        assertEq(uint8(expired.status), uint8(RoundStatus.Expired));
        assertEq(stateView.refundableAmount(expiredRoundId, alice), 40);

        AssetAccounting memory accountingA = stateView.assetAccounting(address(tokenA));
        assertEq(accountingA.activeRoundEscrow, 0);
        assertEq(accountingA.winnerLiability, 80);
        assertEq(accountingA.refundLiability, 0);
        assertEq(accountingA.finalizerLiability, 3);
        assertEq(accountingA.pendingOperatorRevenueTotal, 10);
        assertEq(accountingA.treasuryAvailable, 7);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.finalizerCredit(address(tokenA), finalizer), 3);

        AssetAccounting memory accountingB = stateView.assetAccounting(address(tokenB));
        assertEq(accountingB.activeRoundEscrow, 0);
        assertEq(accountingB.winnerLiability, 0);
        assertEq(accountingB.refundLiability, 40);
        assertEq(accountingB.finalizerLiability, 0);
        assertEq(accountingB.pendingOperatorRevenueTotal, 0);
        assertEq(accountingB.treasuryAvailable, 0);
    }
}
