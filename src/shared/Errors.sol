// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

library Errors {
    error AlreadyFinalized();
    error CutsDisabled();
    error EmptyInitializationData();
    error EmptySelectors();
    error FunctionNotFound(bytes4 selector);
    error InitializationFailed(bytes reason);
    error InvalidAddress();
    error InvalidFacetAction(uint8 action);
    error NativeEthRejected();
    error NoCode(address target);
    error NotAuthority(address caller);
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error UnexpectedInitializationData();
}
