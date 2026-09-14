// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOperatorFeeRouter } from "../interfaces/IOperatorFeeRouter.sol";
import { Errors } from "../shared/Errors.sol";

library LibOperatorFeeRouter {
    using SafeERC20 for IERC20;

    function enforceReady(address router, address asset) internal view {
        IOperatorFeeRouter operatorRouter = IOperatorFeeRouter(router);
        if (
            !operatorRouter.bootstrapFinalized() || operatorRouter.totalEffectiveWeight() == 0
                || !operatorRouter.isRewardAsset(asset) || !operatorRouter.rewardAssetEnabled(asset)
        ) {
            revert Errors.OperatorRouterUnavailable(router, asset);
        }
    }

    function contributeExact(address router, address asset, uint256 amount) internal {
        enforceReady(router, asset);
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(address(this));
        uint256 receiverBefore = token.balanceOf(router);

        token.forceApprove(router, amount);
        IOperatorFeeRouter(router).addRewards(asset, amount);
        token.forceApprove(router, 0);

        uint256 senderAfter = token.balanceOf(address(this));
        uint256 receiverAfter = token.balanceOf(router);
        uint256 spent = senderBefore >= senderAfter ? senderBefore - senderAfter : 0;
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (spent != amount || received != amount) {
            revert Errors.InexactTokenTransfer(asset, amount, spent, received);
        }
    }
}
