// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { LibReentrancy } from "../src/libraries/LibReentrancy.sol";
import { Errors } from "../src/shared/Errors.sol";

contract ReentrancyHarness {
    uint256 public calls;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function initializeGuard() external {
        LibReentrancy.initialize();
    }

    function guardedCall(bool recurse) external nonReentrant {
        ++calls;
        if (recurse) this.guardedCall(false);
    }

    function entered() external view returns (bool) {
        return LibReentrancy.entered();
    }
}

contract ReentrancyGuardTest is Test {
    function test_RequiresInitializationAndRejectsReentry() public {
        ReentrancyHarness harness = new ReentrancyHarness();

        vm.expectRevert(Errors.Reentrancy.selector);
        harness.guardedCall(false);

        harness.initializeGuard();
        vm.expectRevert(Errors.Reentrancy.selector);
        harness.guardedCall(true);

        assertEq(harness.calls(), 0);
        assertFalse(harness.entered());

        harness.guardedCall(false);
        assertEq(harness.calls(), 1);
        assertFalse(harness.entered());
    }

    function test_RejectsRepeatedInitialization() public {
        ReentrancyHarness harness = new ReentrancyHarness();
        harness.initializeGuard();

        vm.expectRevert(Errors.AlreadyInitialized.selector);
        harness.initializeGuard();
    }
}
