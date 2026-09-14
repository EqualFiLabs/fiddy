// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { FacetCut } from "../shared/DiamondTypes.sol";

interface IDiamondCut {
    event DiamondCut(FacetCut[] cuts, address indexed init, bytes data);

    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external;
}
