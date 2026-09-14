// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

interface IClaims {
    event WinnerClaimed(
        uint256 indexed roundId,
        address indexed winner,
        address indexed receiver,
        address paymentToken,
        uint256 amount
    );
    event RefundClaimed(
        uint256 indexed roundId,
        address indexed user,
        address indexed receiver,
        address paymentToken,
        uint256 amount
    );
    event FinalizerTipClaimed(
        address indexed finalizer, address indexed asset, address indexed receiver, uint256 amount
    );

    function claimWinner(uint256 roundId, address receiver) external returns (uint256 amount);
    function claimRefund(uint256 roundId, address receiver) external returns (uint256 amount);
    function claimFinalizerTips(address asset, address receiver) external returns (uint256 amount);
}
