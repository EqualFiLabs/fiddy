// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IRevenue } from "../../src/interfaces/IRevenue.sol";
import { ILotteryView } from "../../src/interfaces/ILotteryView.sol";
import { LibDiamond } from "../../src/libraries/LibDiamond.sol";

/// @notice Testnet evidence helper proving a failed Router call preserves its Lottery liability.
contract TestnetOperatorFlushProbe {
    event OperatorFlushFailureObserved(
        address indexed diamond,
        uint64 indexed integrationVersion,
        address indexed asset,
        uint256 amount,
        bytes revertData
    );

    error LiabilityChanged(uint256 beforeAmount, uint256 afterAmount);
    error UnexpectedSuccess();

    function expectFailure(
        address diamond,
        uint64 integrationVersion,
        address asset,
        uint256 amount
    ) external {
        uint256 beforeAmount =
            ILotteryView(diamond).pendingOperatorRevenue(integrationVersion, asset);
        (bool success, bytes memory reason) = diamond.call(
            abi.encodeCall(IRevenue.flushOperatorRevenue, (integrationVersion, asset, amount))
        );
        if (success) revert UnexpectedSuccess();

        uint256 afterAmount =
            ILotteryView(diamond).pendingOperatorRevenue(integrationVersion, asset);
        if (afterAmount != beforeAmount) revert LiabilityChanged(beforeAmount, afterAmount);

        emit OperatorFlushFailureObserved(diamond, integrationVersion, asset, amount, reason);
    }
}

/// @notice Testnet-only Diamond extension used to prove an upgrade preserves Lottery storage.
contract TestnetLifecycleUpgradeFacet {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("statics.lottery.testnet.lifecycle.upgrade.v1");

    struct Storage {
        bytes32 marker;
    }

    event LifecycleMarkerUpdated(bytes32 indexed marker);

    function setLifecycleMarker(bytes32 marker) external {
        LibDiamond.enforceAuthority();
        _storage().marker = marker;
        emit LifecycleMarkerUpdated(marker);
    }

    function lifecycleMarker() external view returns (bytes32) {
        return _storage().marker;
    }

    function _storage() private pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}
