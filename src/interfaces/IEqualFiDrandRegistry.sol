// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

interface IEqualFiDrandRegistry {
    function firstRoundAfter(uint256 timestamp) external pure returns (uint64);
    function roundTime(uint64 round) external pure returns (uint64);
    function hasSig(uint64 round) external view returns (bool);
    function randomnessOf(uint64 round) external view returns (bytes32);
    function postedAt(uint64 round) external view returns (uint64);
    function postSig(uint64 round, bytes calldata signature) external returns (bool newlyStored);
}
