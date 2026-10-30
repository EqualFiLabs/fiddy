// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { LibFiddyStorage } from "../libraries/LibFiddyStorage.sol";
import {
    FiddyConfig,
    FiddyAccount,
    FiddyAsset,
    FiddyCredit,
    FiddyBatch
} from "../shared/FiddyTypes.sol";

contract FiddyViewFacet {
    function fiddyBindings()
        external
        view
        returns (address underlying, address positionNFT, address operators, address registry)
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        return (s.underlying, s.positionNFT, s.operators, s.registry);
    }

    function fiddyReserve()
        external
        view
        returns (
            uint256 inventory,
            uint256 backing,
            uint256 custody,
            bool wrapEnabled,
            bool unwrapEnabled,
            uint256 cap,
            uint256 outstanding
        )
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        return (
            s.inventory,
            s.allocatedBacking,
            s.custodyTotal,
            s.wrapEnabled,
            s.unwrapEnabled,
            s.wrapCap,
            s.wrapOutstanding
        );
    }

    function fiddyAccount(uint256 id) external view returns (FiddyAccount memory) {
        return LibFiddyStorage.state().accounts[id];
    }

    function fiddyConfig(uint64 version) external view returns (FiddyConfig memory) {
        return LibFiddyStorage.state().configs[version];
    }

    function fiddyRoundConfig(uint256 roundId) external view returns (FiddyConfig memory) {
        return LibFiddyStorage.state().rounds[roundId];
    }

    function fiddyAsset(address asset) external view returns (FiddyAsset memory) {
        return LibFiddyStorage.state().assets[asset];
    }

    function fiddyCredit(uint256 id, address asset) external view returns (FiddyCredit memory) {
        return LibFiddyStorage.state().credits[id][asset];
    }

    function fiddyOperatorAccount(uint256 operatorId) external view returns (uint256) {
        return LibFiddyStorage.state().operatorAccount[operatorId];
    }

    function fiddyProcessing()
        external
        view
        returns (
            uint256 transferCursor,
            uint256 nextBatch,
            uint256 batchCount,
            uint256 transferAccount,
            uint256 assetCursor,
            uint256 totalWeight,
            uint256 revision,
            bool boostsEnabled
        )
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        return (
            s.transferCursor,
            s.batchCursor,
            s.batches.length,
            s.transferAccount,
            s.transferAssetCursor,
            s.totalWeight,
            s.revision,
            s.boostsEnabled
        );
    }

    function fiddyBatch(uint256 index) external view returns (FiddyBatch memory) {
        return LibFiddyStorage.state().batches[index];
    }

    function fiddyRevenueAssets(uint256 cursor, uint256 limit)
        external
        view
        returns (address[] memory assets, uint256 next)
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        if (limit > 100) limit = 100;
        if (cursor > s.revenueAssets.length) cursor = s.revenueAssets.length;
        next = cursor + limit;
        if (next > s.revenueAssets.length) next = s.revenueAssets.length;
        assets = new address[](next - cursor);
        for (uint256 i; cursor < next; ++cursor) {
            assets[i++] = s.revenueAssets[cursor];
        }
    }
}
