// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IERC721 } from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import { IFiddyActivation } from "../interfaces/IFiddyProtocol.sol";
import { IStaticsExternalModules } from "../interfaces/IStaticsExternalModules.sol";
import { LibFiddyStorage } from "./LibFiddyStorage.sol";
import { LibLotteryStorage } from "./LibLotteryStorage.sol";
import { FiddyConfig, FiddyAccount, FiddyBatch } from "../shared/FiddyTypes.sol";
import { FiddyErrors } from "../shared/FiddyErrors.sol";

library LibFiddy {
    bytes32 internal constant MODULE = keccak256("statics.lottery.fiddy.account.v1");
    event FiddyParticipation(
        uint256 indexed roundId,
        uint256 indexed positionId,
        uint256 requested,
        uint256 issued,
        uint256 shortfall
    );
    event FiddyAccountAttached(uint256 indexed positionId);
    event FiddyRevenueReserved(
        uint256 indexed roundId, address indexed asset, uint256 amount, uint256 boundary
    );

    function enforceInitialized() internal view {
        if (LibFiddyStorage.state().underlying == address(0)) revert FiddyErrors.NotInitialized();
    }

    function enforceOwner(uint256 id) internal view {
        enforceInitialized();
        if (IERC721(LibFiddyStorage.state().positionNFT).ownerOf(id) != msg.sender) {
            revert FiddyErrors.NotPositionOwner();
        }
    }

    function attach(uint256 id) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        if (!s.accounts[id].attached) {
            s.accounts[id].attached = true;
            IStaticsExternalModules(s.positionNFT).attachExternalAccountLeg(id, MODULE, bytes32(id));
            emit FiddyAccountAttached(id);
        }
    }

    function creditBalance(uint256 id, uint256 amount) internal {
        attach(id);
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        s.accounts[id].balance += amount;
        s.accounts[id].cleanupCursor = 0;
        s.custodyTotal += amount;
    }

    function debitBalance(uint256 id, uint256 amount) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyAccount storage a = s.accounts[id];
        if (amount > a.balance - a.staked) revert FiddyErrors.InsufficientFiddy();
        a.balance -= amount;
        s.custodyTotal -= amount;
    }

    function issue(uint256 roundId, uint256 id, uint256 quantity) internal {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        FiddyConfig storage config = s.rounds[roundId];
        if (!config.participation) return;
        if (id == 0) revert FiddyErrors.PositionRequired();
        enforceOwner(id);
        uint256 requested = uint256(config.unitsPerTicket) * quantity;
        uint256 issued = requested < s.inventory ? requested : s.inventory;
        if (issued != 0) {
            creditBalance(id, issued);
            s.inventory -= issued;
        }
        emit FiddyParticipation(roundId, id, requested, issued, requested - issued);
    }

    function reserve(uint256 roundId, address asset, uint256 amount) internal {
        if (amount == 0) return;
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        uint256 boundary = IStaticsExternalModules(s.positionNFT).transferHead();
        s.assets[asset].reserved += amount;
        s.assets[asset].pending += amount;
        s.batches.push(FiddyBatch(asset, amount, boundary));
        emit FiddyRevenueReserved(roundId, asset, amount, boundary);
    }

    function extraReserved(address asset) internal view returns (uint256 amount) {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        amount = s.assets[asset].reserved;
        if (asset == s.underlying) amount += s.allocatedBacking;
        if (asset == address(this)) amount += s.inventory + s.custodyTotal;
    }

    function enforceHistory() internal view {
        LibFiddyStorage.State storage s = LibFiddyStorage.state();
        IStaticsExternalModules core = IStaticsExternalModules(s.positionNFT);
        if (
            !core.historyCoverage(s.positionNFT).ready || !core.historyCoverage(s.operators).ready
                || IFiddyActivation(s.registry).activeConsumer() != s.positionNFT
        ) revert FiddyErrors.HistoryUnavailable();
    }
}
