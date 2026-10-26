// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import {LibTicketRanges} from "../../../../src/libraries/LibTicketRanges.sol";
import {TicketRange} from "../../../../src/shared/Types.sol";
contract TicketOwnership {
 TicketRange[] internal entries;
 uint32 internal sold;
 function append(address buyer,uint32 endExclusive) external {LibTicketRanges.append(entries,buyer,endExclusive);sold=endExclusive;}
 function owner(uint32 ticket) external view returns(address){return LibTicketRanges.ownerOfTicket(entries,ticket);}
 function selectedOwner(bytes32 seed) external view returns(uint32,address){uint32 ticket=uint32(uint256(seed)%sold);return (ticket,LibTicketRanges.ownerOfTicket(entries,ticket));}
}
