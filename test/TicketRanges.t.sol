// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { LibTicketRanges } from "../src/libraries/LibTicketRanges.sol";
import { Errors } from "../src/shared/Errors.sol";
import { TicketRange } from "../src/shared/Types.sol";

contract TicketRangeHarness {
    TicketRange[] internal entries;

    function append(address buyer, uint32 endExclusive) external {
        LibTicketRanges.append(entries, buyer, endExclusive);
    }

    function ownerOf(uint32 ticket) external view returns (address) {
        return LibTicketRanges.ownerOfTicket(entries, ticket);
    }

    function entry(uint256 index) external view returns (TicketRange memory) {
        return entries[index];
    }
}

contract TicketRangesTest is Test {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function test_ResolvesCumulativeRangesWithBinarySearch() public {
        TicketRangeHarness harness = new TicketRangeHarness();
        harness.append(alice, 5);
        harness.append(bob, 8);
        harness.append(carol, 20);

        assertEq(harness.ownerOf(0), alice);
        assertEq(harness.ownerOf(4), alice);
        assertEq(harness.ownerOf(5), bob);
        assertEq(harness.ownerOf(7), bob);
        assertEq(harness.ownerOf(8), carol);
        assertEq(harness.ownerOf(19), carol);

        TicketRange memory middle = harness.entry(1);
        assertEq(middle.buyer, bob);
        assertEq(middle.endExclusive, 8);
    }

    function test_RejectsMissingOrOutOfRangeTickets() public {
        TicketRangeHarness harness = new TicketRangeHarness();
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTicket.selector, 0));
        harness.ownerOf(0);

        harness.append(alice, 5);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTicket.selector, 5));
        harness.ownerOf(5);
    }

    function test_RejectsInvalidRanges() public {
        TicketRangeHarness harness = new TicketRangeHarness();
        vm.expectRevert(Errors.InvalidTicketRange.selector);
        harness.append(address(0), 1);

        vm.expectRevert(Errors.InvalidTicketRange.selector);
        harness.append(alice, 0);

        harness.append(alice, 5);
        vm.expectRevert(Errors.InvalidTicketRange.selector);
        harness.append(bob, 5);

        vm.expectRevert(Errors.InvalidTicketRange.selector);
        harness.append(bob, 4);
    }
}
