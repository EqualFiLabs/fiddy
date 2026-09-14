// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { LibDiamond } from "./libraries/LibDiamond.sol";
import { Errors } from "./shared/Errors.sol";
import { FacetCut, FacetCutAction } from "./shared/DiamondTypes.sol";

contract StaticsLotteryDiamond {
    constructor(address authority, address cutFacet) {
        LibDiamond.initializeAuthority(authority);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;

        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(cutFacet, FacetCutAction.Add, selectors);
        LibDiamond.diamondCut(cuts, address(0), "");
    }

    receive() external payable {
        revert Errors.NativeEthRejected();
    }

    fallback() external payable {
        if (msg.value != 0) revert Errors.NativeEthRejected();

        address facet = LibDiamond.diamondStorage().selectorData[msg.sig].facet;
        if (facet == address(0)) revert Errors.FunctionNotFound(msg.sig);

        assembly ("memory-safe") {
            let pointer := mload(0x40)
            calldatacopy(pointer, 0, calldatasize())
            let result := delegatecall(gas(), facet, pointer, calldatasize(), 0, 0)
            returndatacopy(pointer, 0, returndatasize())
            switch result
            case 0 { revert(pointer, returndatasize()) }
            default { return(pointer, returndatasize()) }
        }
    }
}
