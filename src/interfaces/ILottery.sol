// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

interface ILottery {
    event RoundOpened(
        uint256 indexed roundId,
        uint64 indexed configVersion,
        uint64 indexed integrationVersion,
        address paymentToken,
        uint64 openedAt,
        uint64 expiresAt
    );
    event TicketsPurchased(
        uint256 indexed roundId,
        address indexed buyer,
        address indexed paymentToken,
        uint32 startTicket,
        uint32 quantity,
        uint32 endExclusive,
        uint256 amount
    );
    event RoundSoldOut(uint256 indexed roundId, uint64 selloutAt, uint64 drandRound);
    event RoundExpired(
        uint256 indexed roundId, address indexed paymentToken, uint256 refundLiability
    );

    function openRound(uint64 configVersion, uint32 ticketQuantity)
        external
        returns (uint256 roundId);
    function buyTickets(uint256 roundId, uint32 ticketQuantity) external;
    function expireRound(uint256 roundId) external;
}
