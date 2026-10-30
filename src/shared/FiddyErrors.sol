// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

library FiddyErrors {
    error NotPositionOwner();
    error InvalidBinding();
    error AlreadyInitialized();
    error NotInitialized();
    error OnlyProtocol();
    error TransferRestricted();
    error ConversionDisabled();
    error WrapCapacityExceeded();
    error InsufficientFiddy();
    error InvalidRewardsConfig();
    error PositionRequired();
    error SynchronizationRequired();
    error AccountCheckpointRequired();
    error InvalidWorkLimit();
    error InvalidRegistration();
    error OperatorAlreadyRegistered();
    error HistoryUnavailable();
    error AccountNotEmpty();
}
