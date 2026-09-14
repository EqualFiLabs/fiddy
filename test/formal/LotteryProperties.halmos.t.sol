// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { StaticsLotteryDiamond } from "../../src/StaticsLotteryDiamond.sol";
import { ClaimsFacet } from "../../src/facets/ClaimsFacet.sol";
import { DiamondCutFacet } from "../../src/facets/DiamondCutFacet.sol";
import { GovernanceFacet } from "../../src/facets/GovernanceFacet.sol";
import { LotteryFacet } from "../../src/facets/LotteryFacet.sol";
import { RevenueFacet } from "../../src/facets/RevenueFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IGovernance } from "../../src/interfaces/IGovernance.sol";
import { FacetCut, FacetCutAction } from "../../src/shared/DiamondTypes.sol";
import { AssetAccounting, RoundStatus } from "../../src/shared/Types.sol";
import {
    AllocationObservation,
    ClaimObservation,
    CommitmentObservation,
    FormalRegistry,
    FormalRouter,
    FormalToken,
    LotteryClaimsHarness,
    LotteryCommitmentHarness,
    LotteryRevenueHarness,
    LotterySettlementHarness,
    RevenueObservation,
    SettlementObservation
} from "./LotteryFormalHarnesses.sol";

contract LotteryCommitmentHalmosTest is Test {
    function check_selloutCommitmentIsStrictlyFuture(uint256 rawDelay) public {
        (, CommitmentObservation memory observed) = _executeCommitment(rawDelay);
        assert(uint8(observed.status) == uint8(RoundStatus.SoldOut));
        assert(observed.registryRoundTime > observed.commitmentBoundary);
    }

    function check_selloutCommitmentMatchesRegistrySelection(uint256 rawDelay) public {
        (, CommitmentObservation memory observed) = _executeCommitment(rawDelay);
        assert(observed.drandRound == uint64(observed.commitmentBoundary + 1));
    }

    function check_selloutCommitmentIgnoresCatalogChanges(uint256 rawDelay) public {
        (uint32 delay, CommitmentObservation memory observed) = _executeCommitment(rawDelay);
        assert(observed.catalogDelay == (delay == type(uint32).max ? 0 : delay + 1));
        assert(observed.targetAfterCalls == observed.drandRound);
    }

    function _executeCommitment(uint256 rawDelay)
        private
        returns (uint32 delay, CommitmentObservation memory observed)
    {
        delay = uint32(bound(rawDelay, 0, type(uint32).max));
        FormalRegistry registry = new FormalRegistry(false);
        LotteryCommitmentHarness lottery = new LotteryCommitmentHarness();
        observed = lottery.executeCommitment(registry, delay);
    }
}

contract LotterySettlementHalmosTest is Test {
    function check_settlementConservesRevenue(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        uint64 gross = uint64(bound(rawGross, 1, type(uint64).max));
        uint16 winnerBps = uint16(bound(rawWinnerBps, 0, 10_000));
        uint16 operatorBps = uint16(bound(rawOperatorBps, 0, 10_000));
        uint64 tip = uint64(bound(rawTip, 0, type(uint64).max));
        LotterySettlementHarness settlement = new LotterySettlementHarness();
        AllocationObservation memory observed =
            settlement.executeAllocation(gross, winnerBps, operatorBps, tip);
        assert(
            observed.winner + observed.operator + observed.treasury + observed.finalizer == gross
        );
    }

    function check_settlementPreservesPaymentTokenSolvency(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        (uint64 gross, SettlementObservation memory observed) =
            _executeSettlement(rawGross, rawWinnerBps, rawOperatorBps, rawTip);
        AssetAccounting memory accounting = observed.paymentAccounting;
        assert(accounting.activeRoundEscrow == 0);
        assert(accounting.refundLiability == 0);
        assert(observed.paymentCustody == gross);
    }

    function check_settlementRecordsOperatorAndFinalizerLiabilities(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        (, SettlementObservation memory observed) =
            _executeSettlement(rawGross, rawWinnerBps, rawOperatorBps, rawTip);
        AssetAccounting memory accounting = observed.paymentAccounting;
        assert(observed.versionedOperator == accounting.pendingOperatorRevenueTotal);
        assert(observed.finalizerCredit == accounting.finalizerLiability);
    }

    function check_settlementDoesNotMutateIsolatedToken(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        (, SettlementObservation memory observed) =
            _executeSettlement(rawGross, rawWinnerBps, rawOperatorBps, rawTip);
        assert(observed.isolatedAccounting.treasuryAvailable == 17);
        assert(observed.isolatedCustody == 17);
    }

    function check_settlementRecordsTerminalStatus(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        (, SettlementObservation memory observed) =
            _executeSettlement(rawGross, rawWinnerBps, rawOperatorBps, rawTip);
        assert(uint8(observed.status) == uint8(RoundStatus.Settled));
    }

    function _executeSettlement(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) private returns (uint64 gross, SettlementObservation memory observed) {
        gross = uint64(bound(rawGross, 1, type(uint64).max));
        uint16 winnerBps = uint16(bound(rawWinnerBps, 0, 10_000));
        uint16 operatorBps = uint16(bound(rawOperatorBps, 0, 10_000));
        uint64 tip = uint64(bound(rawTip, 0, type(uint64).max));
        FormalToken paymentToken = new FormalToken("PRIMARY");
        FormalToken isolatedToken = new FormalToken("ISOLATED");
        LotterySettlementHarness settlement = new LotterySettlementHarness();
        observed = settlement.executeSettlement(
            paymentToken, isolatedToken, gross, winnerBps, operatorBps, tip
        );
    }
}

contract LotteryClaimsHalmosTest is Test {
    address internal constant RECEIVER = address(0xBEEF);

    function check_winnerClaimCannotRepeat(uint256 rawAmount) public {
        uint96 amount = uint96(bound(rawAmount, 1, type(uint96).max));
        FormalToken token = new FormalToken("WINNER");
        ClaimsFacet facet = new ClaimsFacet();
        LotteryClaimsHarness claims = new LotteryClaimsHarness();

        ClaimObservation memory observed = claims.executeWinnerClaim(facet, token, amount, RECEIVER);

        _assertClaimCleared(observed, amount);
    }

    function check_refundClaimCannotRepeat(uint256 rawAmount) public {
        uint96 amount = uint96(bound(rawAmount, 1, type(uint96).max));
        FormalToken token = new FormalToken("REFUND");
        ClaimsFacet facet = new ClaimsFacet();
        LotteryClaimsHarness claims = new LotteryClaimsHarness();

        ClaimObservation memory observed = claims.executeRefundClaim(facet, token, amount, RECEIVER);

        _assertClaimCleared(observed, amount);
    }

    function _assertClaimCleared(ClaimObservation memory observed, uint96 amount) private pure {
        assert(observed.firstAmount == amount);
        assert(!observed.repeatedSucceeded);
        assert(observed.remainingClaim == 0);
        assert(observed.aggregateLiability == 0);
        assert(observed.receiverBalance == amount);
        assert(observed.custodyBalance == 0);
    }
}

contract LotteryRevenueHalmosTest is Test {
    function check_operatorFlushIsAtomicAndTokenIsolated(
        uint256 rawAmount,
        uint256 rawIsolatedAmount,
        bool rejectContribution
    ) public {
        uint96 amount = uint96(bound(rawAmount, 1, type(uint64).max));
        uint96 isolatedAmount = uint96(bound(rawIsolatedAmount, 1, type(uint64).max));
        FormalToken paymentToken = new FormalToken("REVENUE");
        FormalToken isolatedToken = new FormalToken("OTHER");
        FormalRouter router = new FormalRouter(rejectContribution);
        RevenueFacet facet = new RevenueFacet();
        LotteryRevenueHarness revenue = new LotteryRevenueHarness();

        RevenueObservation memory observed = revenue.executeOperatorFlush(
            facet, router, paymentToken, isolatedToken, amount, isolatedAmount
        );

        if (rejectContribution) {
            assert(!observed.succeeded);
            assert(observed.paymentPending == amount);
            assert(observed.paymentAggregate == amount);
            assert(observed.paymentCustody == amount);
            assert(observed.routerCustody == 0);
        } else {
            assert(observed.succeeded);
            assert(observed.paymentPending == 0);
            assert(observed.paymentAggregate == 0);
            assert(observed.paymentCustody == 0);
            assert(observed.routerCustody == amount);
        }
        assert(observed.allowance == 0);
        assert(observed.isolatedPending == isolatedAmount);
        assert(observed.isolatedAggregate == isolatedAmount);
        assert(observed.isolatedCustody == isolatedAmount);
    }
}

contract LotteryCutsHalmosTest is Test {
    function check_cutFinalizationCannotBeReversed() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        StaticsLotteryDiamond diamond = new StaticsLotteryDiamond(address(this), address(cutFacet));
        GovernanceFacet governanceFacet = new GovernanceFacet();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IGovernance.protocolFinalized.selector;
        selectors[1] = IGovernance.finalizeProtocol.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(governanceFacet), FacetCutAction.Add, selectors);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        IGovernance governance = IGovernance(address(diamond));
        governance.finalizeProtocol();
        assert(governance.protocolFinalized());

        FacetCut[] memory emptyCuts = new FacetCut[](0);
        (bool cutSucceeded,) = address(diamond)
            .call(
                abi.encodeWithSelector(
                    IDiamondCut.diamondCut.selector, emptyCuts, address(0), bytes("")
                )
            );
        (bool repeatedFinalization,) =
            address(diamond).call(abi.encodeWithSelector(IGovernance.finalizeProtocol.selector));
        assert(!cutSucceeded);
        assert(!repeatedFinalization);
        assert(governance.protocolFinalized());
    }
}
