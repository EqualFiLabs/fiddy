// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { ILotteryView } from "../interfaces/ILotteryView.sol";
import { LibLotteryStorage } from "../libraries/LibLotteryStorage.sol";
import { LibTicketRanges } from "../libraries/LibTicketRanges.sol";
import { Errors } from "../shared/Errors.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    RoundConfigSnapshot,
    RoundStatus,
    TicketRange
} from "../shared/Types.sol";

contract LotteryViewFacet is ILotteryView {
    function latestLotteryConfigVersion() external view returns (uint64) {
        return LibLotteryStorage.gameStorage().nextConfigVersion;
    }

    function latestRoundId() external view returns (uint256) {
        return LibLotteryStorage.gameStorage().nextRoundId;
    }

    function round(uint256 roundId) external view returns (Round memory value) {
        Round storage storedRound = _round(roundId);
        value = storedRound;
    }

    function roundConfig(uint256 roundId)
        external
        view
        returns (RoundConfigSnapshot memory config)
    {
        config = _round(roundId).config;
    }

    function ticketOwner(uint256 roundId, uint32 ticket) external view returns (address) {
        _round(roundId);
        return
            LibTicketRanges.ownerOfTicket(LibLotteryStorage.gameStorage().entries[roundId], ticket);
    }

    function purchaseEntryCount(uint256 roundId) external view returns (uint256) {
        _round(roundId);
        return LibLotteryStorage.gameStorage().entries[roundId].length;
    }

    function purchaseEntry(uint256 roundId, uint256 index)
        external
        view
        returns (TicketRange memory)
    {
        _round(roundId);
        TicketRange[] storage entries = LibLotteryStorage.gameStorage().entries[roundId];
        if (index >= entries.length) revert Errors.PurchaseEntryNotFound(roundId, index);
        return entries[index];
    }

    function refundableAmount(uint256 roundId, address account) external view returns (uint256) {
        _round(roundId);
        return LibLotteryStorage.gameStorage().refundCredit[roundId][account];
    }

    function lotteryConfig(uint64 version)
        external
        view
        returns (LotteryConfig memory config, bool enabled)
    {
        LibLotteryStorage.GameStorage storage gs = LibLotteryStorage.gameStorage();
        if (version == 0 || version > gs.nextConfigVersion) {
            revert Errors.ConfigNotFound(version);
        }
        return (gs.configs[version], gs.configEnabled[version]);
    }

    function currentIntegration()
        external
        view
        returns (IntegrationConfig memory config, uint64 version)
    {
        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        version = integrations.currentVersion;
        config = integrations.integrations[version];
    }

    function integrationAt(uint64 version) external view returns (IntegrationConfig memory) {
        LibLotteryStorage.IntegrationStorage storage integrations =
            LibLotteryStorage.integrationStorage();
        if (version == 0 || version > integrations.currentVersion) {
            revert Errors.IntegrationNotFound(version);
        }
        return integrations.integrations[version];
    }

    function activeRoundCount() external view returns (uint256) {
        return LibLotteryStorage.gameStorage().activeRoundCount;
    }

    function maxActiveRounds() external view returns (uint16) {
        return LibLotteryStorage.gameStorage().maxActiveRounds;
    }

    function pendingOperatorRevenue(uint64 integrationVersion, address asset)
        external
        view
        returns (uint256)
    {
        return
            LibLotteryStorage.accountingStorage().pendingOperatorRevenue[integrationVersion][asset];
    }

    function assetAccounting(address asset) external view returns (AssetAccounting memory) {
        return LibLotteryStorage.accountingStorage().assetAccounting[asset];
    }

    function finalizerCredit(address asset, address account) external view returns (uint256) {
        return LibLotteryStorage.accountingStorage().finalizerCredits[asset][account];
    }

    function _round(uint256 roundId) private view returns (Round storage storedRound) {
        storedRound = LibLotteryStorage.gameStorage().rounds[roundId];
        if (storedRound.status == RoundStatus.None) revert Errors.RoundNotFound(roundId);
    }
}
