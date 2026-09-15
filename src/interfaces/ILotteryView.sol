// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    RoundConfigSnapshot,
    TicketRange
} from "../shared/Types.sol";

interface ILotteryView {
    function latestLotteryConfigVersion() external view returns (uint64);
    function latestRoundId() external view returns (uint256);
    function round(uint256 roundId) external view returns (Round memory);
    function roundConfig(uint256 roundId) external view returns (RoundConfigSnapshot memory);
    function ticketOwner(uint256 roundId, uint32 ticket) external view returns (address);
    function purchaseEntryCount(uint256 roundId) external view returns (uint256);
    function purchaseEntry(uint256 roundId, uint256 index)
        external
        view
        returns (TicketRange memory);
    function refundableAmount(uint256 roundId, address account) external view returns (uint256);
    function lotteryConfig(uint64 version)
        external
        view
        returns (LotteryConfig memory config, bool enabled);
    function currentIntegration()
        external
        view
        returns (IntegrationConfig memory config, uint64 version);
    function integrationAt(uint64 version) external view returns (IntegrationConfig memory);
    function activeRoundCount() external view returns (uint256);
    function maxActiveRounds() external view returns (uint16);
    function pendingOperatorRevenue(uint64 integrationVersion, address asset)
        external
        view
        returns (uint256);
    function assetAccounting(address asset) external view returns (AssetAccounting memory);
    function finalizerCredit(address asset, address account) external view returns (uint256);
}
