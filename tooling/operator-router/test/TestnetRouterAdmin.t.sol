// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { TestnetRouterAdmin } from "../src/TestnetRouterAdmin.sol";

contract RouterAdminTarget {
    address public lastAsset;
    bool public lastEnabled;

    function registerRewardAsset(address asset) external {
        lastAsset = asset;
        lastEnabled = true;
    }

    function setRewardAssetEnabled(address asset, bool enabled) external {
        lastAsset = asset;
        lastEnabled = enabled;
    }
}

contract TestnetRouterAdminTest is Test {
    address internal owner = makeAddr("owner");
    address internal outsider = makeAddr("outsider");
    address internal asset = makeAddr("asset");

    TestnetRouterAdmin internal admin;
    RouterAdminTarget internal target;

    function setUp() public {
        vm.chainId(46_630);
        admin = new TestnetRouterAdmin(owner);
        target = new RouterAdminTarget();
    }

    function test_BindsOneRouterAndForwardsOnlyForOwner() public {
        vm.prank(owner);
        admin.bindRouter(address(target));
        assertEq(admin.router(), address(target));

        vm.prank(owner);
        admin.registerRewardAsset(asset);
        assertEq(target.lastAsset(), asset);
        assertTrue(target.lastEnabled());

        vm.prank(owner);
        admin.setRewardAssetEnabled(asset, false);
        assertFalse(target.lastEnabled());

        vm.expectRevert(TestnetRouterAdmin.AlreadyBound.selector);
        vm.prank(owner);
        admin.bindRouter(address(target));

        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.NotOwner.selector, outsider));
        vm.prank(outsider);
        admin.registerRewardAsset(asset);
    }

    function test_RejectsWrongChainAndInvalidBinding() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.WrongChain.selector, 1));
        new TestnetRouterAdmin(owner);

        vm.chainId(46_630);
        vm.expectRevert(TestnetRouterAdmin.InvalidAddress.selector);
        vm.prank(owner);
        admin.bindRouter(address(0));
    }
}
