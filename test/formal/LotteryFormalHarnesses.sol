// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { ClaimsFacet } from "../../src/facets/ClaimsFacet.sol";
import { LotteryFacet } from "../../src/facets/LotteryFacet.sol";
import { RevenueFacet } from "../../src/facets/RevenueFacet.sol";
import { SettlementFacet } from "../../src/facets/SettlementFacet.sol";
import { IEqualFiDrandRegistry } from "../../src/interfaces/IEqualFiDrandRegistry.sol";
import { IOperatorFeeRouter } from "../../src/interfaces/IOperatorFeeRouter.sol";
import { LibLotteryStorage } from "../../src/libraries/LibLotteryStorage.sol";
import { LibReentrancy } from "../../src/libraries/LibReentrancy.sol";
import { LibTicketRanges } from "../../src/libraries/LibTicketRanges.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    RoundStatus
} from "../../src/shared/Types.sol";

contract FormalToken is ERC20 {
    constructor(string memory symbol) ERC20(symbol, symbol) { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract FormalRegistry is IEqualFiDrandRegistry {
    mapping(uint64 round => bool available) internal cached;
    mapping(uint64 round => bytes32 value) internal randomness;
    mapping(uint64 round => uint64 timestamp) internal postingTime;

    function cache(uint64 round, bytes32 value, uint64 timestamp) external {
        cached[round] = true;
        randomness[round] = value;
        postingTime[round] = timestamp;
    }

    function firstRoundAfter(uint256 timestamp) external pure returns (uint64) {
        return uint64(timestamp + 1);
    }

    function roundTime(uint64 round) external pure returns (uint64) {
        return round;
    }

    function hasSig(uint64 round) external view returns (bool) {
        return cached[round];
    }

    function randomnessOf(uint64 round) external view returns (bytes32) {
        return randomness[round];
    }

    function postedAt(uint64 round) external view returns (uint64) {
        return postingTime[round];
    }

    function postSig(uint64, bytes calldata) external pure returns (bool) {
        return false;
    }
}

contract FormalRouter is IOperatorFeeRouter {
    using SafeERC20 for IERC20;

    bool internal rejectContribution;

    error ContributionRejected();

    function setRejectContribution(bool rejected) external {
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

contract LotteryCommitmentHarness is LotteryFacet {
    constructor(FormalToken token, FormalRegistry registry, FormalRouter router, uint32 delay) {
        LibReentrancy.initialize();
        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        gs.nextConfigVersion = 1;
        gs.maxActiveRounds = 1;
        gs.configEnabled[1] = true;
        gs.configs[1] = LotteryConfig({
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

        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        integrations.currentVersion = 1;
        integrations.integrations[1] = IntegrationConfig(address(registry), address(router));
    }

    function setRandomnessDelay(uint32 delay) external {
        LibLotteryStorage.gameStorage().configs[1].randomnessDelay = delay;
    }

    function roundState(uint256 roundId) external view returns (Round memory) {
        return LibLotteryStorage.gameStorage().rounds[roundId];
    }
}

contract LotterySettlementHarness is SettlementFacet {
    constructor(
        FormalRegistry registry,
        FormalToken paymentToken,
        FormalToken isolatedToken,
        uint96 gross,
        uint16 winnerBps,
        uint16 operatorBps,
        uint96 finalizerTip
    ) {
        LibReentrancy.initialize();
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
        LibTicketRanges.append(gs.entries[1], address(this), 1);

        LibLotteryStorage.AccountingStorage storage accountingStorage =
            LibLotteryStorage.accountingStorage();
        accountingStorage.assetAccounting[address(paymentToken)].activeRoundEscrow = gross;
        accountingStorage.assetAccounting[address(isolatedToken)].treasuryAvailable = 17;
        paymentToken.mint(address(this), gross);
        isolatedToken.mint(address(this), 17);
    }

    function roundState() external view returns (Round memory) {
        return LibLotteryStorage.gameStorage().rounds[1];
    }

    function accounting(address asset) external view returns (AssetAccounting memory) {
        return LibLotteryStorage.accountingStorage().assetAccounting[asset];
    }

    function pendingOperator(address asset) external view returns (uint256) {
        return LibLotteryStorage.accountingStorage().pendingOperatorRevenue[1][asset];
    }

    function finalizerCredit(address asset, address account) external view returns (uint256) {
        return LibLotteryStorage.accountingStorage().finalizerCredits[asset][account];
    }
}

contract LotteryClaimsHarness is ClaimsFacet {
    constructor(FormalToken token, address claimant, uint96 amount, bool refund) {
        LibReentrancy.initialize();
        if (refund) {
            Round storage round = LibLotteryStorage.gameStorage().rounds[2];
            round.config.paymentToken = address(token);
            round.status = RoundStatus.Expired;
            LibLotteryStorage.gameStorage().refundCredit[2][claimant] = amount;
            LibLotteryStorage.accountingStorage().assetAccounting[address(token)].refundLiability =
                amount;
        } else {
            Round storage round = LibLotteryStorage.gameStorage().rounds[1];
            round.config.paymentToken = address(token);
            round.status = RoundStatus.Settled;
            round.winner = claimant;
            round.winnerClaimable = amount;
            LibLotteryStorage.accountingStorage().assetAccounting[address(token)].winnerLiability =
                amount;
        }
        token.mint(address(this), amount);
    }

    function winnerClaimable() external view returns (uint256) {
        return LibLotteryStorage.gameStorage().rounds[1].winnerClaimable;
    }

    function refundCredit(address claimant) external view returns (uint256) {
        return LibLotteryStorage.gameStorage().refundCredit[2][claimant];
    }

    function accounting(address asset) external view returns (AssetAccounting memory) {
        return LibLotteryStorage.accountingStorage().assetAccounting[asset];
    }
}

contract LotteryRevenueHarness is RevenueFacet {
    constructor(
        FormalRouter router,
        FormalToken paymentToken,
        FormalToken isolatedToken,
        uint96 amount,
        uint96 isolatedAmount
    ) {
        LibReentrancy.initialize();
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
        paymentToken.mint(address(this), amount);
        isolatedToken.mint(address(this), isolatedAmount);
    }

    function pendingOperator(address asset) external view returns (uint256) {
        return LibLotteryStorage.accountingStorage().pendingOperatorRevenue[1][asset];
    }

    function accounting(address asset) external view returns (AssetAccounting memory) {
        return LibLotteryStorage.accountingStorage().assetAccounting[asset];
    }
}
