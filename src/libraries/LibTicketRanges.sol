// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Errors } from "../shared/Errors.sol";
import { TicketRange } from "../shared/Types.sol";

library LibTicketRanges {
    function append(TicketRange[] storage entries, address buyer, uint32 endExclusive) internal {
        uint256 length = entries.length;
        if (
            buyer == address(0) || endExclusive == 0
                || (length != 0 && endExclusive <= entries[length - 1].endExclusive)
        ) {
            revert Errors.InvalidTicketRange();
        }
        entries.push(TicketRange(buyer, endExclusive));
    }

    function ownerOfTicket(TicketRange[] storage entries, uint32 ticket)
        internal
        view
        returns (address)
    {
        uint256 high = entries.length;
        if (high == 0 || ticket >= entries[high - 1].endExclusive) {
            revert Errors.InvalidTicket(ticket);
        }

        uint256 low = 0;
        while (low < high) {
            uint256 middle = (low + high) >> 1;
            if (ticket < entries[middle].endExclusive) {
                high = middle;
            } else {
                low = middle + 1;
            }
        }
        return entries[low].buyer;
    }
}
