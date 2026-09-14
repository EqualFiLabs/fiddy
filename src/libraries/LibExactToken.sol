// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Errors } from "../shared/Errors.sol";

library LibExactToken {
    using SafeERC20 for IERC20;

    function pullExact(address asset, address sender, uint256 amount) internal {
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(sender);
        uint256 receiverBefore = token.balanceOf(address(this));

        token.safeTransferFrom(sender, address(this), amount);

        uint256 senderAfter = token.balanceOf(sender);
        uint256 receiverAfter = token.balanceOf(address(this));
        uint256 spent = senderBefore >= senderAfter ? senderBefore - senderAfter : 0;
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (spent != amount || received != amount) {
            revert Errors.InexactTokenTransfer(asset, amount, spent, received);
        }
    }

    function pushExact(address asset, address receiver, uint256 amount) internal {
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(address(this));
        uint256 receiverBefore = token.balanceOf(receiver);

        token.safeTransfer(receiver, amount);

        uint256 senderAfter = token.balanceOf(address(this));
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 spent = senderBefore >= senderAfter ? senderBefore - senderAfter : 0;
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (spent != amount || received != amount) {
            revert Errors.InexactTokenTransfer(asset, amount, spent, received);
        }
    }
}
