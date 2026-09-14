// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { StaticsLotteryDiamond } from "../src/StaticsLotteryDiamond.sol";
import { DiamondCutFacet } from "../src/facets/DiamondCutFacet.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { ILotteryView } from "../src/interfaces/ILotteryView.sol";
import { FacetCut, FacetCutAction } from "../src/shared/DiamondTypes.sol";
import { Errors } from "../src/shared/Errors.sol";
import {
    TestnetLifecycleUpgradeFacet,
    TestnetOperatorFlushProbe
} from "../script/testnet/TestnetLifecycleHelpers.sol";

contract RevertingRevenueTarget {
    uint256 internal pending = 17;

    error RouterUnavailable();

    function pendingOperatorRevenue(uint64, address) external view returns (uint256) {
        return pending;
    }

    function flushOperatorRevenue(uint64, address, uint256) external pure returns (uint256) {
        revert RouterUnavailable();
    }
}

contract TestnetLifecycleHelpersTest is Test {
    address internal authority = makeAddr("authority");
    address internal outsider = makeAddr("outsider");

    function test_ProbeRecordsFailureWithoutChangingPendingLiability() public {
        RevertingRevenueTarget target = new RevertingRevenueTarget();
        TestnetOperatorFlushProbe probe = new TestnetOperatorFlushProbe();

        probe.expectFailure(address(target), 1, makeAddr("asset"), 17);
        assertEq(target.pendingOperatorRevenue(1, address(0)), 17);
    }

    function test_UpgradeFacetUsesIsolatedStorageAndAuthority() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        StaticsLotteryDiamond diamond = new StaticsLotteryDiamond(authority, address(cutFacet));
        TestnetLifecycleUpgradeFacet upgradeFacet = new TestnetLifecycleUpgradeFacet();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = TestnetLifecycleUpgradeFacet.setLifecycleMarker.selector;
        selectors[1] = TestnetLifecycleUpgradeFacet.lifecycleMarker.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(upgradeFacet), FacetCutAction.Add, selectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        bytes32 marker = keccak256("marker");
        vm.prank(authority);
        TestnetLifecycleUpgradeFacet(address(diamond)).setLifecycleMarker(marker);
        assertEq(TestnetLifecycleUpgradeFacet(address(diamond)).lifecycleMarker(), marker);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, outsider));
        vm.prank(outsider);
        TestnetLifecycleUpgradeFacet(address(diamond)).setLifecycleMarker(bytes32(uint256(1)));
    }
}
