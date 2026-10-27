// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import {TicketRange} from "../../../../src/shared/Types.sol";
contract TicketSearchStep {
 TicketRange[] internal entries;
 // Exact loop iteration from LibTicketRanges.ownerOfTicket; state is explicit for induction.
 function step(uint256 low,uint256 high,uint32 ticket) external view returns(uint256,uint256){
  if(low<high){uint256 middle=(low+high)>>1;if(ticket<entries[middle].endExclusive){high=middle;}else{low=middle+1;}}
  return(low,high);
 }
}
