// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { StaticsLotteryDiamond } from "../../src/StaticsLotteryDiamond.sol";
import { DiamondCutFacet } from "../../src/facets/DiamondCutFacet.sol";
import { GovernanceFacet } from "../../src/facets/GovernanceFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IGovernance } from "../../src/interfaces/IGovernance.sol";
import { ILottery } from "../../src/interfaces/ILottery.sol";
import { IRevenue } from "../../src/interfaces/IRevenue.sol";
import { FacetCut, FacetCutAction } from "../../src/shared/DiamondTypes.sol";
import { AssetAccounting, Round, RoundStatus } from "../../src/shared/Types.sol";
import {
    FormalRegistry,
    FormalRouter,
    FormalToken,
    LotteryClaimsHarness,
    LotteryCommitmentHarness,
    LotteryRevenueHarness,
    LotterySettlementHarness
} from "./LotteryFormalHarnesses.sol";

contract LotteryCommitmentHalmosTest is Test {
    function check_selloutCommitsOnceToStrictlyFutureRound(uint256 rawDelay) public {
        uint32 delay = uint32(bound(rawDelay, 0, type(uint32).max));
        FormalToken token = new FormalToken("COMMIT");
        FormalRegistry registry = new FormalRegistry();
        FormalRouter router = new FormalRouter();
        LotteryCommitmentHarness lottery = new LotteryCommitmentHarness(token, registry, router);
        lottery.setRandomnessDelay(delay);
        token.mint(address(this), 1);
        token.approve(address(lottery), 1);

        uint256 roundId = lottery.openRound(1, 1);
        Round memory committed = lottery.roundState(roundId);
        uint256 boundary = uint256(committed.selloutAt) + delay;
        assert(uint8(committed.status) == uint8(RoundStatus.SoldOut));
        assert(registry.roundTime(committed.drandRound) > boundary);
        assert(committed.drandRound == uint64(boundary + 1));

        uint32 replacementDelay = delay == type(uint32).max ? 0 : delay + 1;
        lottery.setRandomnessDelay(replacementDelay);
        (bool buySucceeded,) = address(lottery)
            .call(abi.encodeWithSelector(ILottery.buyTickets.selector, roundId, uint32(1)));
        (bool expireSucceeded,) =
            address(lottery).call(abi.encodeWithSelector(ILottery.expireRound.selector, roundId));
        assert(!buySucceeded);
        assert(!expireSucceeded);
        assert(lottery.roundState(roundId).drandRound == committed.drandRound);
    }
}

contract LotterySettlementHalmosTest is Test {
    function check_settlementConservesRevenueAndIsolatesTokens(
        uint256 rawGross,
        uint256 rawWinnerBps,
        uint256 rawOperatorBps,
        uint256 rawTip
    ) public {
        uint96 gross = uint96(bound(rawGross, 1, type(uint96).max));
        uint16 winnerBps = uint16(bound(rawWinnerBps, 0, 10_000));
        uint16 operatorBps = uint16(bound(rawOperatorBps, 0, 10_000));
        uint96 tip = uint96(bound(rawTip, 0, type(uint96).max));
        FormalToken paymentToken = new FormalToken("PRIMARY");
        FormalToken isolatedToken = new FormalToken("ISOLATED");
        FormalRegistry registry = new FormalRegistry();
        LotterySettlementHarness settlement = new LotterySettlementHarness(registry);
        settlement.seedSettlement(paymentToken, isolatedToken, gross, winnerBps, operatorBps, tip);
        registry.cache(2, keccak256("formal randomness"), 2);

        settlement.settleRound(1, "");

        AssetAccounting memory accounting = settlement.accounting(address(paymentToken));
        assert(accounting.activeRoundEscrow == 0);
        assert(accounting.refundLiability == 0);
        assert(
            accounting.winnerLiability + accounting.pendingOperatorRevenueTotal
                    + accounting.treasuryAvailable + accounting.finalizerLiability == gross
        );
        assert(
            settlement.pendingOperator(address(paymentToken))
                == accounting.pendingOperatorRevenueTotal
        );
        assert(
            settlement.finalizerCredit(address(paymentToken), address(this))
                == accounting.finalizerLiability
        );
        assert(settlement.accounting(address(isolatedToken)).treasuryAvailable == 17);
        assert(paymentToken.balanceOf(address(settlement)) == gross);
        assert(isolatedToken.balanceOf(address(settlement)) == 17);
        Round memory settledRound = settlement.roundState();
        assert(uint8(settledRound.status) == uint8(RoundStatus.Settled));
        assert(settledRound.drandRound == 2);
    }
}

contract LotteryClaimsHalmosTest is Test {
    address internal constant RECEIVER = address(0xBEEF);

    function check_winnerClaimCannotRepeat(uint256 rawAmount) public {
        uint96 amount = uint96(bound(rawAmount, 1, type(uint96).max));
        FormalToken token = new FormalToken("WINNER");
        LotteryClaimsHarness claims = new LotteryClaimsHarness();
        claims.seedWinner(token, address(this), amount);

        assert(claims.claimWinner(1, RECEIVER) == amount);
        (bool repeated,) = address(claims)
            .call(abi.encodeWithSelector(claims.claimWinner.selector, uint256(1), RECEIVER));
        assert(!repeated);
        assert(claims.winnerClaimable() == 0);
        assert(claims.accounting(address(token)).winnerLiability == 0);
        assert(token.balanceOf(RECEIVER) == amount);
        assert(token.balanceOf(address(claims)) == 0);
    }

    function check_refundClaimCannotRepeat(uint256 rawAmount) public {
        uint96 amount = uint96(bound(rawAmount, 1, type(uint96).max));
        FormalToken token = new FormalToken("REFUND");
        LotteryClaimsHarness claims = new LotteryClaimsHarness();
        claims.seedRefund(token, address(this), amount);

        assert(claims.claimRefund(2, RECEIVER) == amount);
        (bool repeated,) = address(claims)
            .call(abi.encodeWithSelector(claims.claimRefund.selector, uint256(2), RECEIVER));
        assert(!repeated);
        assert(claims.refundCredit(address(this)) == 0);
        assert(claims.accounting(address(token)).refundLiability == 0);
        assert(token.balanceOf(RECEIVER) == amount);
        assert(token.balanceOf(address(claims)) == 0);
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
        FormalRouter router = new FormalRouter();
        LotteryRevenueHarness revenue = new LotteryRevenueHarness(router);
        revenue.seedOperatorRevenue(paymentToken, amount);
        revenue.seedIsolatedToken(isolatedToken, isolatedAmount);
        router.setRejectContribution(rejectContribution);

        (bool succeeded,) = address(revenue)
            .call(
                abi.encodeWithSelector(
                    IRevenue.flushOperatorRevenue.selector,
                    uint64(1),
                    address(paymentToken),
                    uint256(amount)
                )
            );

        if (rejectContribution) {
            assert(!succeeded);
            assert(revenue.pendingOperator(address(paymentToken)) == amount);
            assert(revenue.accounting(address(paymentToken)).pendingOperatorRevenueTotal == amount);
            assert(paymentToken.balanceOf(address(revenue)) == amount);
            assert(paymentToken.balanceOf(address(router)) == 0);
        } else {
            assert(succeeded);
            assert(revenue.pendingOperator(address(paymentToken)) == 0);
            assert(revenue.accounting(address(paymentToken)).pendingOperatorRevenueTotal == 0);
            assert(paymentToken.balanceOf(address(revenue)) == 0);
            assert(paymentToken.balanceOf(address(router)) == amount);
        }
        assert(paymentToken.allowance(address(revenue), address(router)) == 0);
        assert(revenue.pendingOperator(address(isolatedToken)) == isolatedAmount);
        assert(
            revenue.accounting(address(isolatedToken)).pendingOperatorRevenueTotal == isolatedAmount
        );
        assert(isolatedToken.balanceOf(address(revenue)) == isolatedAmount);
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
