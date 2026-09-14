// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

library Errors {
    error AlreadyFinalized();
    error AlreadyInitialized();
    error CutsDisabled();
    error ConfigNotFound(uint64 version);
    error EmptyInitializationData();
    error EmptySelectors();
    error FunctionNotFound(bytes4 selector);
    error InitializationFailed(bytes reason);
    error InvalidAddress();
    error InvalidConfig();
    error InvalidFacetAction(uint8 action);
    error NativeEthRejected();
    error NoCode(address target);
    error NotAuthority(address caller);
    error NotGuardian(address caller);
    error Reentrancy();
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error UnexpectedInitializationData();
    error UnpauseRequiresAuthority(address caller);
    error InexactTokenTransfer(address asset, uint256 expected, uint256 spent, uint256 received);
}
