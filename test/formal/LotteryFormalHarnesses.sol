// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { ClaimsFacet } from "../../src/facets/ClaimsFacet.sol";
import { LotteryFacet } from "../../src/facets/LotteryFacet.sol";
import { RevenueFacet } from "../../src/facets/RevenueFacet.sol";
import { SettlementFacet } from "../../src/facets/SettlementFacet.sol";
import { IClaims } from "../../src/interfaces/IClaims.sol";
import { IEqualFiDrandRegistry } from "../../src/interfaces/IEqualFiDrandRegistry.sol";
import { ILottery } from "../../src/interfaces/ILottery.sol";
import { IOperatorFeeRouter } from "../../src/interfaces/IOperatorFeeRouter.sol";
import { IRevenue } from "../../src/interfaces/IRevenue.sol";
import { ISettlement } from "../../src/interfaces/ISettlement.sol";
import { LibLotteryStorage } from "../../src/libraries/LibLotteryStorage.sol";
import { LibReentrancy } from "../../src/libraries/LibReentrancy.sol";
import { LibTicketRanges } from "../../src/libraries/LibTicketRanges.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    Round,
    RoundConfigSnapshot,
    RoundStatus
} from "../../src/shared/Types.sol";

contract FormalToken is ERC20 {
    constructor(string memory symbol) ERC20(symbol, symbol) { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract FormalRegistry is IEqualFiDrandRegistry {
    bool internal immutable beaconAvailable;

    constructor(bool available) {
        beaconAvailable = available;
    }

    function firstRoundAfter(uint256 timestamp) external pure returns (uint64) {
        return uint64(timestamp + 1);
    }

    function roundTime(uint64 round) external pure returns (uint64) {
        return round;
    }

    function hasSig(uint64 round) external view returns (bool) {
        return beaconAvailable && round == 2;
    }

    function randomnessOf(uint64) external pure returns (bytes32) {
        return keccak256("formal randomness");
    }

    function postedAt(uint64 round) external pure returns (uint64) {
        return round;
    }

    function postSig(uint64, bytes calldata) external pure returns (bool) {
        return false;
    }
}

contract FormalRouter is IOperatorFeeRouter {
    using SafeERC20 for IERC20;

    bool internal immutable rejectContribution;

    error ContributionRejected();

    constructor(bool rejected) {
        rejectContribution = rejected;
    }

    function addRewards(address asset, uint256 amount) external {
        if (rejectContribution) revert ContributionRejected();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function isRewardAsset(address) external pure returns (bool) {
        return true;
    }

    function rewardAssetEnabled(address) external pure returns (bool) {
        return true;
    }

    function bootstrapFinalized() external pure returns (bool) {
        return true;
    }

    function totalEffectiveWeight() external pure returns (uint256) {
        return 1;
    }
}

struct CommitmentObservation {
    uint64 drandRound;
    uint64 registryRoundTime;
    uint256 commitmentBoundary;
    uint64 targetAfterCalls;
    RoundStatus status;
    uint32 catalogDelay;
    bool buySucceeded;
    bool expireSucceeded;
}

struct SettlementObservation {
    AssetAccounting paymentAccounting;
    AssetAccounting isolatedAccounting;
    uint256 versionedOperator;
    uint256 finalizerCredit;
    uint256 paymentCustody;
    uint256 isolatedCustody;
    RoundStatus status;
    uint64 drandRound;
}

struct ClaimObservation {
    uint256 firstAmount;
    uint256 remainingClaim;
    uint256 aggregateLiability;
    uint256 receiverBalance;
    uint256 custodyBalance;
    bool repeatedSucceeded;
}

struct RevenueObservation {
    uint256 paymentPending;
    uint256 paymentAggregate;
    uint256 paymentCustody;
    uint256 routerCustody;
    uint256 allowance;
    uint256 isolatedPending;
    uint256 isolatedAggregate;
    uint256 isolatedCustody;
    bool succeeded;
}

abstract contract FormalFacetHost {
    function _delegate(address facet, bytes memory callData)
        internal
        returns (bytes memory result)
    {
        (bool succeeded, bytes memory returnedData) = facet.delegatecall(callData);
        if (!succeeded) {
            assembly ("memory-safe") {
                revert(add(returnedData, 0x20), mload(returnedData))
            }
        }
        return returnedData;
    }

    function _tryDelegate(address facet, bytes memory callData) internal returns (bool succeeded) {
        (succeeded,) = facet.delegatecall(callData);
    }
}

contract LotteryCommitmentHarness is LotteryFacet {
    constructor() {
        LibReentrancy.initialize();
    }

    function executeCommitment(FormalToken token, FormalRegistry registry, uint32 delay)
        external
        nonReentrant
        returns (CommitmentObservation memory result)
    {
        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        integrations.integrations[1] = IntegrationConfig(address(registry), address(0));

        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        gs.configs[1].randomnessDelay = delay;

        uint256 roundId = 1;
        Round storage round = gs.rounds[roundId];
        round.config = RoundConfigSnapshot({
            paymentToken: address(token),
            ticketPrice: 1,
            ticketCount: 1,
            salesDuration: 1 days,
            randomnessDelay: delay,
            maxTicketsPerPurchase: 1,
            winnerBps: 10_000,
            operatorProtocolBps: 0,
            finalizerTip: 0
        });
        round.integrationVersion = 1;
        round.expiresAt = uint64(block.timestamp + 1 days);
        round.status = RoundStatus.Open;

        _buyTickets(gs, round, roundId, 1);
        result.drandRound = round.drandRound;
        result.registryRoundTime = registry.roundTime(round.drandRound);
        result.commitmentBoundary = uint256(round.selloutAt) + round.config.randomnessDelay;
        result.status = round.status;

        uint32 replacementDelay = delay == type(uint32).max ? 0 : delay + 1;
        gs.configs[1].randomnessDelay = replacementDelay;
        result.catalogDelay = gs.configs[1].randomnessDelay;
        (result.buySucceeded,) = address(this)
            .call(abi.encodeWithSelector(ILottery.buyTickets.selector, roundId, uint32(1)));
        (result.expireSucceeded,) =
            address(this).call(abi.encodeWithSelector(ILottery.expireRound.selector, roundId));
        result.targetAfterCalls = round.drandRound;
    }
}

contract LotterySettlementHarness is FormalFacetHost {
    constructor() {
        LibReentrancy.initialize();
    }

    function executeSettlement(
        SettlementFacet facet,
        FormalRegistry registry,
        FormalToken paymentToken,
        FormalToken isolatedToken,
        uint96 gross,
        uint16 winnerBps,
        uint16 operatorBps,
        uint96 finalizerTip
    ) external returns (SettlementObservation memory result) {
        paymentToken.mint(address(this), gross);
        isolatedToken.mint(address(this), 17);

        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        integrations.currentVersion = 1;
        integrations.integrations[1].drandRegistry = address(registry);

        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        Round storage round = gs.rounds[1];
        round.config.paymentToken = address(paymentToken);
        round.config.ticketCount = 1;
        round.config.winnerBps = winnerBps;
        round.config.operatorProtocolBps = operatorBps;
        round.config.finalizerTip = finalizerTip;
        round.integrationVersion = 1;
        round.selloutAt = 1;
        round.drandRound = 2;
        round.soldTickets = 1;
        round.status = RoundStatus.SoldOut;
        round.receipts = gross;
        gs.activeRoundCount = 1;
        LibTicketRanges.append(gs.entries[1], msg.sender, 1);

        LibLotteryStorage.AccountingStorage storage accountingStorage =
            LibLotteryStorage.accountingStorage();
        accountingStorage.assetAccounting[address(paymentToken)].activeRoundEscrow = gross;
        accountingStorage.assetAccounting[address(isolatedToken)].treasuryAvailable = 17;

        _delegate(address(facet), abi.encodeWithSelector(ISettlement.settleRound.selector, 1, ""));

        result.paymentAccounting = accountingStorage.assetAccounting[address(paymentToken)];
        result.isolatedAccounting = accountingStorage.assetAccounting[address(isolatedToken)];
        result.versionedOperator =
            accountingStorage.pendingOperatorRevenue[1][address(paymentToken)];
        result.finalizerCredit =
            accountingStorage.finalizerCredits[address(paymentToken)][msg.sender];
        result.paymentCustody = paymentToken.balanceOf(address(this));
        result.isolatedCustody = isolatedToken.balanceOf(address(this));
        result.status = round.status;
        result.drandRound = round.drandRound;
    }
}

contract LotteryClaimsHarness is FormalFacetHost {
    constructor() {
        LibReentrancy.initialize();
    }

    function executeWinnerClaim(
        ClaimsFacet facet,
        FormalToken token,
        uint96 amount,
        address receiver
    ) external returns (ClaimObservation memory result) {
        token.mint(address(this), amount);

        Round storage round = LibLotteryStorage.gameStorage().rounds[1];
        round.config.paymentToken = address(token);
        round.status = RoundStatus.Settled;
        round.winner = msg.sender;
        round.winnerClaimable = amount;
        AssetAccounting storage accounting =
            LibLotteryStorage.accountingStorage().assetAccounting[address(token)];
        accounting.winnerLiability = amount;

        result.firstAmount = abi.decode(
            _delegate(
                address(facet), abi.encodeWithSelector(IClaims.claimWinner.selector, 1, receiver)
            ),
            (uint256)
        );
        result.repeatedSucceeded = _tryDelegate(
            address(facet), abi.encodeWithSelector(IClaims.claimWinner.selector, 1, receiver)
        );
        result.remainingClaim = round.winnerClaimable;
        result.aggregateLiability = accounting.winnerLiability;
        result.receiverBalance = token.balanceOf(receiver);
        result.custodyBalance = token.balanceOf(address(this));
    }

    function executeRefundClaim(
        ClaimsFacet facet,
        FormalToken token,
        uint96 amount,
        address receiver
    ) external returns (ClaimObservation memory result) {
        token.mint(address(this), amount);

        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        Round storage round = gs.rounds[2];
        round.config.paymentToken = address(token);
        round.status = RoundStatus.Expired;
        gs.refundCredit[2][msg.sender] = amount;
        AssetAccounting storage accounting =
            LibLotteryStorage.accountingStorage().assetAccounting[address(token)];
        accounting.refundLiability = amount;

        result.firstAmount = abi.decode(
            _delegate(
                address(facet), abi.encodeWithSelector(IClaims.claimRefund.selector, 2, receiver)
            ),
            (uint256)
        );
        result.repeatedSucceeded = _tryDelegate(
            address(facet), abi.encodeWithSelector(IClaims.claimRefund.selector, 2, receiver)
        );
        result.remainingClaim = gs.refundCredit[2][msg.sender];
        result.aggregateLiability = accounting.refundLiability;
        result.receiverBalance = token.balanceOf(receiver);
        result.custodyBalance = token.balanceOf(address(this));
    }
}

contract LotteryRevenueHarness is FormalFacetHost {
    constructor() {
        LibReentrancy.initialize();
    }

    function executeOperatorFlush(
        RevenueFacet facet,
        FormalRouter router,
        FormalToken paymentToken,
        FormalToken isolatedToken,
        uint96 amount,
        uint96 isolatedAmount
    ) external returns (RevenueObservation memory result) {
        paymentToken.mint(address(this), amount);
        isolatedToken.mint(address(this), isolatedAmount);

        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        integrations.currentVersion = 1;
        integrations.integrations[1].operatorFeeRouter = address(router);

        LibLotteryStorage.AccountingStorage storage accountingStorage =
            LibLotteryStorage.accountingStorage();
        accountingStorage.pendingOperatorRevenue[1][address(paymentToken)] = amount;
        accountingStorage.assetAccounting[address(paymentToken)].pendingOperatorRevenueTotal =
        amount;
        accountingStorage.pendingOperatorRevenue[1][address(isolatedToken)] = isolatedAmount;
        accountingStorage.assetAccounting[address(isolatedToken)].pendingOperatorRevenueTotal =
        isolatedAmount;

        result.succeeded = _tryDelegate(
            address(facet),
            abi.encodeWithSelector(
                IRevenue.flushOperatorRevenue.selector, 1, address(paymentToken), amount
            )
        );
        result.paymentPending = accountingStorage.pendingOperatorRevenue[1][address(paymentToken)];
        result.paymentAggregate =
        accountingStorage.assetAccounting[address(paymentToken)].pendingOperatorRevenueTotal;
        result.paymentCustody = paymentToken.balanceOf(address(this));
        result.routerCustody = paymentToken.balanceOf(address(router));
        result.allowance = paymentToken.allowance(address(this), address(router));
        result.isolatedPending = accountingStorage.pendingOperatorRevenue[1][address(isolatedToken)];
        result.isolatedAggregate =
        accountingStorage.assetAccounting[address(isolatedToken)].pendingOperatorRevenueTotal;
        result.isolatedCustody = isolatedToken.balanceOf(address(this));
    }
}
