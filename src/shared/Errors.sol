// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

library Errors {
    error AlreadyFinalized();
    error AlreadyInitialized();
    error ActiveRoundLimitReached();
    error CutsDisabled();
    error ConfigNotFound(uint64 version);
    error ConfigDisabled(uint64 version);
    error EmptyInitializationData();
    error EmptySelectors();
    error FunctionNotFound(bytes4 selector);
    error InitializationFailed(bytes reason);
    error InvalidAddress();
    error InvalidConfig();
    error InvalidRandomnessRound(uint64 drandRound);
    error InvalidTicket(uint32 ticket);
    error InvalidTicketQuantity();
    error InvalidTicketRange();
    error InvalidFacetAction(uint8 action);
    error NativeEthRejected();
    error NoCode(address target);
    error NoFinalizerCredit();
    error NoRefund();
    error NoWinnerClaim();
    error NotAuthority(address caller);
    error NotGuardian(address caller);
    error NotWinner(address caller);
    error ProtocolPaused();
    error RandomnessPredatesSellout(uint64 drandRound, uint64 postedAt, uint64 selloutAt);
    error RandomnessUnavailable(uint64 drandRound);
    error Reentrancy();
    error RoundExpired(uint256 roundId);
    error RoundNotExpired(uint256 roundId);
    error RoundNotFound(uint256 roundId);
    error RoundNotOpen(uint256 roundId);
    error RoundNotSettled(uint256 roundId);
    error RoundNotSoldOut(uint256 roundId);
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error StaleRandomnessRound(uint64 drandRound);
    error TicketLimitExceeded();
    error IntegrationNotConfigured();
    error UnexpectedInitializationData();
    error UnpauseRequiresAuthority(address caller);
    error InexactTokenTransfer(address asset, uint256 expected, uint256 spent, uint256 received);
}
