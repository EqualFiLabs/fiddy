// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

struct FiddyConfig {
    uint96 unitsPerTicket;
    uint16 stakerProtocolBps;
    bool participation;
}

struct FiddyAccount {
    uint256 balance;
    uint256 staked;
    uint256 weight;
    uint256 operatorId;
    uint256 multiplierBps;
    uint256 positionSequence;
    uint256 operatorSequence;
    uint256 checkpointRevision;
    uint256 checkpointCursor;
    uint256 cleanupCursor;
    bool registered;
    bool attached;
}

struct FiddyAsset {
    uint256 indexRay;
    uint256 reserved;
    uint256 pending;
    uint256 dustRay;
    bool listed;
}

struct FiddyCredit {
    uint256 paidIndex;
    uint256 claimable;
    uint256 remainderRay;
}

struct FiddyBatch {
    address asset;
    uint256 amount;
    uint256 boundary;
}
