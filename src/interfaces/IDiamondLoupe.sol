// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Facet } from "../shared/DiamondTypes.sol";

interface IDiamondLoupe {
    function facets() external view returns (Facet[] memory);
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory);
    function facetAddresses() external view returns (address[] memory);
    function facetAddress(bytes4 selector) external view returns (address);
}
