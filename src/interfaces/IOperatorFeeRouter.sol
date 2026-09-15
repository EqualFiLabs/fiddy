// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

interface IOperatorFeeRouter {
    function addRewards(address asset, uint256 amount) external;
    function isRewardAsset(address asset) external view returns (bool);
    function rewardAssetEnabled(address asset) external view returns (bool);
    function bootstrapFinalized() external view returns (bool);
    function totalEffectiveWeight() external view returns (uint256 weight);
}
