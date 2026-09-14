// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { LibExactToken } from "../src/libraries/LibExactToken.sol";
import { Errors } from "../src/shared/Errors.sol";

contract ExactTokenHarness {
    function pull(address asset, address sender, uint256 amount) external {
        LibExactToken.pullExact(asset, sender, amount);
    }

    function push(address asset, address receiver, uint256 amount) external {
        LibExactToken.pushExact(asset, receiver, amount);
    }
}

contract ExactTransferToken is ERC20 {
    constructor() ERC20("Exact Transfer Token", "EXACT") { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract ReceiverFeeToken is ExactTransferToken {
    uint256 internal constant FEE = 1;

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value != 0) {
            super._update(from, to, value - FEE);
            super._update(from, address(0), FEE);
        } else {
            super._update(from, to, value);
        }
    }
}

contract SenderFeeToken is ExactTransferToken {
    uint256 internal constant FEE = 1;

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && to != address(0) && value != 0) {
            super._update(from, address(0), FEE);
        }
    }
}

contract NoReturnToken {
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address receiver, uint256 amount) external {
        balanceOf[receiver] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address receiver, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[receiver] += amount;
    }

    function transferFrom(address sender, address receiver, uint256 amount) external {
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[receiver] += amount;
    }
}

contract FalseReturnToken {
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    function mint(address receiver, uint256 amount) external {
        balanceOf[receiver] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract ExactTokenTest is Test {
    address internal sender = makeAddr("sender");
    address internal receiver = makeAddr("receiver");

    ExactTokenHarness internal harness;

    function setUp() public {
        harness = new ExactTokenHarness();
    }

    function test_PullsAndPushesExactTransfers() public {
        ExactTransferToken token = new ExactTransferToken();
        token.mint(sender, 100);
        vm.prank(sender);
        token.approve(address(harness), 40);

        harness.pull(address(token), sender, 40);
        assertEq(token.balanceOf(sender), 60);
        assertEq(token.balanceOf(address(harness)), 40);

        harness.push(address(token), receiver, 25);
        assertEq(token.balanceOf(address(harness)), 15);
        assertEq(token.balanceOf(receiver), 25);
    }

    function test_RejectsReceiverFeeOnInboundAndPreservesBalances() public {
        ReceiverFeeToken token = new ReceiverFeeToken();
        token.mint(sender, 100);
        vm.prank(sender);
        token.approve(address(harness), 40);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 40, 40, 39)
        );
        harness.pull(address(token), sender, 40);

        assertEq(token.balanceOf(sender), 100);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_RejectsSenderFeeOnInboundAndPreservesBalances() public {
        SenderFeeToken token = new SenderFeeToken();
        token.mint(sender, 100);
        vm.prank(sender);
        token.approve(address(harness), 40);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 40, 41, 40)
        );
        harness.pull(address(token), sender, 40);

        assertEq(token.balanceOf(sender), 100);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_RejectsReceiverFeeOnOutboundAndPreservesBalances() public {
        ReceiverFeeToken token = new ReceiverFeeToken();
        token.mint(address(harness), 100);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 40, 40, 39)
        );
        harness.push(address(token), receiver, 40);

        assertEq(token.balanceOf(address(harness)), 100);
        assertEq(token.balanceOf(receiver), 0);
    }

    function test_RejectsSenderFeeOnOutboundAndPreservesBalances() public {
        SenderFeeToken token = new SenderFeeToken();
        token.mint(address(harness), 100);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 40, 41, 40)
        );
        harness.push(address(token), receiver, 40);

        assertEq(token.balanceOf(address(harness)), 100);
        assertEq(token.balanceOf(receiver), 0);
    }

    function test_AcceptsNoReturnTokensWhenBalanceDeltasAreExact() public {
        NoReturnToken token = new NoReturnToken();
        token.mint(sender, 100);
        vm.prank(sender);
        token.approve(address(harness), 40);

        harness.pull(address(token), sender, 40);
        harness.push(address(token), receiver, 25);

        assertEq(token.balanceOf(sender), 60);
        assertEq(token.balanceOf(address(harness)), 15);
        assertEq(token.balanceOf(receiver), 25);
    }

    function test_RejectsFalseReturnTokensWithoutChangingBalances() public {
        FalseReturnToken token = new FalseReturnToken();
        token.mint(sender, 100);
        vm.prank(sender);
        token.approve(address(harness), 40);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token))
        );
        harness.pull(address(token), sender, 40);

        assertEq(token.balanceOf(sender), 100);
        assertEq(token.balanceOf(address(harness)), 0);
    }
}
