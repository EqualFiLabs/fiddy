// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    TicketRange
} from "../shared/Types.sol";

library LibLotteryStorage {
    bytes32 internal constant GAME_STORAGE_SLOT = keccak256("statics.lottery.storage.game.v1");
    bytes32 internal constant INTEGRATION_STORAGE_SLOT =
        keccak256("statics.lottery.storage.integration.v1");
    bytes32 internal constant ACCOUNTING_STORAGE_SLOT =
        keccak256("statics.lottery.storage.accounting.v1");
    bytes32 internal constant GOVERNANCE_STORAGE_SLOT =
        keccak256("statics.lottery.storage.governance.v1");
    bytes32 internal constant REENTRANCY_STORAGE_SLOT =
        keccak256("statics.lottery.storage.reentrancy.v1");

    struct GameStorage {
        uint64 nextConfigVersion;
        uint16 maxActiveRounds;
        uint256 nextRoundId;
        uint256 activeRoundCount;
        mapping(uint64 version => LotteryConfig config) configs;
        mapping(uint64 version => bool enabled) configEnabled;
        mapping(uint256 roundId => Round round) rounds;
        mapping(uint256 roundId => TicketRange[] entries) entries;
        mapping(uint256 roundId => mapping(address user => uint256 amount)) refundCredit;
    }

    struct IntegrationStorage {
        uint64 currentVersion;
        mapping(uint64 version => IntegrationConfig config) integrations;
    }

    struct AccountingStorage {
        mapping(address asset => AssetAccounting accounting) assetAccounting;
        mapping(uint64 integrationVersion => mapping(address asset => uint256 amount))
            pendingOperatorRevenue;
        mapping(address asset => mapping(address finalizer => uint256 amount)) finalizerCredits;
    }

    struct GovernanceStorage {
        address guardian;
        address treasuryRecipient;
        bool paused;
    }

    struct ReentrancyStorage {
        uint256 status;
    }

    function gameStorage() internal pure returns (GameStorage storage s) {
        bytes32 slot = GAME_STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function integrationStorage() internal pure returns (IntegrationStorage storage s) {
        bytes32 slot = INTEGRATION_STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function accountingStorage() internal pure returns (AccountingStorage storage s) {
        bytes32 slot = ACCOUNTING_STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function governanceStorage() internal pure returns (GovernanceStorage storage s) {
        bytes32 slot = GOVERNANCE_STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function reentrancyStorage() internal pure returns (ReentrancyStorage storage s) {
        bytes32 slot = REENTRANCY_STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}
