// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IStaticsExternalModules } from "../interfaces/IStaticsExternalModules.sol";
import { LibFiddyStorage } from "./LibFiddyStorage.sol";
import { LibLotteryStorage } from "./LibLotteryStorage.sol";
import { FiddyAccount, FiddyAsset, FiddyCredit, FiddyBatch } from "../shared/FiddyTypes.sol";
import { FiddyErrors } from "../shared/FiddyErrors.sol";

library LibFiddyStaking {
    uint256 internal constant RAY = 1e27;
    event FiddyRevenueIndexed(
        address indexed asset, uint256 amount, uint256 weight, uint256 indexRay
    );
    event FiddyBoostInvalidated(
        uint256 indexed positionId, uint256 indexed operatorId, uint256 sequence
    );
    event FiddyZeroWeightRevenue(address indexed asset, uint256 amount);

    function workLimit(uint256 limit) internal pure {
        if (limit == 0 || limit > 100) revert FiddyErrors.InvalidWorkLimit();
    }

    function accrued(uint256 id, address asset)
        internal
        view
        returns (uint256 whole, uint256 remainder)
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyCredit storage c = s.credits[id][asset];
        uint256 delta = s.assets[asset].indexRay - c.paidIndex;
        uint256 weight = s.accounts[id].weight;
        whole = c.claimable + Math.mulDiv(weight, delta, RAY);
        uint256 fraction = mulmod(weight, delta, RAY) + c.remainderRay;
        whole += fraction / RAY;
        remainder = fraction % RAY;
    }

    function checkpoint(uint256 id, address asset) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyCredit storage c = s.credits[id][asset];
        (c.claimable, c.remainderRay) = accrued(id, asset);
        c.paidIndex = s.assets[asset].indexRay;
    }

    function prepare(uint256 id, uint256 limit) internal {
        workLimit(limit);
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyAccount storage a = s.accounts[id];
        if (a.checkpointRevision != s.revision) {
            a.checkpointRevision = s.revision;
            a.checkpointCursor = 0;
        }
        uint256 stop = a.checkpointCursor + limit;
        if (stop > s.revenueAssets.length) stop = s.revenueAssets.length;
        while (a.checkpointCursor < stop) checkpoint(id, s.revenueAssets[a.checkpointCursor++]);
    }

    function enforceSynchronized() internal view {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        if (
            s.transferAccount != 0 || s.batchCursor != s.batches.length
                || s.transferCursor != IStaticsExternalModules(s.positionNFT).transferHead()
        ) revert FiddyErrors.SynchronizationRequired();
    }

    function enforceCheckpoint(uint256 id) internal view {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        if (s.revenueAssets.length == 0) return;
        FiddyAccount storage a = s.accounts[id];
        if (a.checkpointRevision != s.revision || a.checkpointCursor != s.revenueAssets.length) {
            revert FiddyErrors.AccountCheckpointRequired();
        }
    }

    function updateWeight(uint256 id) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyAccount storage a = s.accounts[id];
        uint256 weight = Math.mulDiv(a.staked, a.registered ? a.multiplierBps : 10_000, 10_000);
        s.totalWeight = s.totalWeight - a.weight + weight;
        a.weight = weight;
    }

    function clearRegistration(uint256 id) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyAccount storage a = s.accounts[id];
        if (a.registered) delete s.operatorAccount[a.operatorId];
        a.registered = false;
        a.operatorId = 0;
        a.multiplierBps = 10_000;
        a.positionSequence = 0;
        a.operatorSequence = 0;
    }

    function dust(address asset, uint256 scaled) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyAsset storage book = s.assets[asset];
        // Consume whole dust immediately so accumulated scaled values remain bounded.
        uint256 whole = scaled / RAY;
        uint256 fraction = book.dustRay + scaled % RAY;
        whole += fraction / RAY;
        book.dustRay = fraction % RAY;
        if (whole != 0) {
            book.reserved -= whole;
            LibLotteryStorage.accountingStorage().assetAccounting[asset].treasuryAvailable += whole;
        }
    }

    function process(uint256 maxWork) internal returns (uint256 used) {
        workLimit(maxWork);
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        IStaticsExternalModules core = IStaticsExternalModules(s.positionNFT);
        // Each iteration handles one transfer, one asset checkpoint, one completed
        // invalidation, or one funded batch. No loop depends on all stakers.
        while (used < maxWork) {
            if (s.transferAccount != 0) {
                _continueTransfer();
            } else {
                bool queued = s.batchCursor < s.batches.length;
                uint256 boundary = queued ? s.batches[s.batchCursor].boundary : core.transferHead();
                if (s.transferCursor < boundary) {
                    (IStaticsExternalModules.TransferChange[] memory changes, uint256 next) =
                        core.transferChanges(s.transferCursor, 1);
                    if (changes.length != 1 || next != s.transferCursor + 1) {
                        revert FiddyErrors.HistoryUnavailable();
                    }
                    _beginTransfer(changes[0], next);
                } else if (queued) {
                    _indexBatch(s.batches[s.batchCursor++]);
                } else {
                    break;
                }
            }
            ++used;
        }
    }

    function _beginTransfer(IStaticsExternalModules.TransferChange memory change, uint256 sequence)
        private
    {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        uint256 id;
        if (change.collection == s.positionNFT) id = change.tokenId;
        else if (change.collection == s.operators) id = s.operatorAccount[change.tokenId];
        FiddyAccount storage a = s.accounts[id];
        uint256 marker =
            change.collection == s.positionNFT ? a.positionSequence : a.operatorSequence;
        if (id != 0 && a.registered && sequence > marker) {
            s.transferAccount = id;
            s.transferAssetCursor = 0;
        } else {
            s.transferCursor = sequence;
        }
    }

    function _continueTransfer() private {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        uint256 id = s.transferAccount;
        if (s.transferAssetCursor < s.revenueAssets.length) {
            checkpoint(id, s.revenueAssets[s.transferAssetCursor++]);
        } else {
            uint256 operatorId = s.accounts[id].operatorId;
            clearRegistration(id);
            updateWeight(id);
            s.accounts[id].checkpointRevision = s.revision;
            s.accounts[id].checkpointCursor = s.revenueAssets.length;
            s.transferAccount = 0;
            s.transferAssetCursor = 0;
            ++s.transferCursor;
            emit FiddyBoostInvalidated(id, operatorId, s.transferCursor);
        }
    }

    function _indexBatch(FiddyBatch storage batch) private {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        address asset = batch.asset;
        FiddyAsset storage book = s.assets[asset];
        book.pending -= batch.amount;
        if (!book.listed) {
            book.listed = true;
            s.revenueAssets.push(asset);
        }
        if (s.totalWeight == 0) {
            book.reserved -= batch.amount;
            LibLotteryStorage.accountingStorage()
                .assetAccounting[asset]
                .treasuryAvailable += batch.amount;
            emit FiddyZeroWeightRevenue(asset, batch.amount);
        } else {
            book.indexRay += Math.mulDiv(batch.amount, RAY, s.totalWeight);
            dust(asset, mulmod(batch.amount, RAY, s.totalWeight));
            emit FiddyRevenueIndexed(asset, batch.amount, s.totalWeight, book.indexRay);
        }
        ++s.revision;
    }
}
