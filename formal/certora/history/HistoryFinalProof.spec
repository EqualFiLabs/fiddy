methods {
 function rangeCount(uint256) external returns(uint256) envfree;
 function rangeEnd(uint256,uint256) external returns(uint32) envfree;
 function rangeBuyer(uint256,uint256) external returns(address) envfree;
 function soldTickets(uint256) external returns(uint32) envfree;
 function futureEmpty(uint256) external returns(bool) envfree;
 function nextId() external returns(uint256) envfree;
 function _.pullExact(address,address,uint256) internal => NONDET;
 function _.pushExact(address,address,uint256) internal => NONDET;
 function _.contributeExact(address,address,uint256) internal => NONDET;
 function _.enforceReady(address,address) internal => NONDET;
 function _.ownerOfTicket(SettlementFacet.TicketRange[] storage,uint32) internal => NONDET;
 function _.firstRoundAfter(uint256) external => NONDET;
 function _.roundTime(uint64) external => NONDET;
 function _.hasSig(uint64) external => NONDET;
 function _.postedAt(uint64) external => NONDET;
 function _.postSig(uint64,bytes) external => NONDET;
 function _.randomnessOf(uint64) external => NONDET;
 function _.balanceOf(address) external => NONDET;
}
invariant futureRoundState(uint256 id) futureEmpty(id);
invariant futureEntriesEmpty(uint256 id) id>nextId() => rangeCount(id)==0
{preserved buyTickets(uint256 target,uint32 n) with(env e){requireInvariant futureRoundState(target);}}
invariant rangeCapacity(uint256 id) rangeCount(id)<=max_uint32
{ preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureEntriesEmpty(assert_uint256(next+1));}} preserved buyTickets(uint256 target,uint32 n) with(env e) {uint256 len=rangeCount(target);if(len>0){requireInvariant rangeEndpoint(target,assert_uint256(len-1));}} }
invariant rangeEndpoint(uint256 id,uint256 i) i<rangeCount(id) => (i<rangeEnd(id,i) && rangeBuyer(id,i)!=0)
{ preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureEntriesEmpty(assert_uint256(next+1));}} preserved buyTickets(uint256 target,uint32 n) with(env e) {uint256 len=rangeCount(target);if(len>0){requireInvariant rangeEndpoint(target,assert_uint256(len-1));}} }
invariant rangeOrder(uint256 id,uint256 i,uint256 j) (i<j && j<rangeCount(id)) => rangeEnd(id,i)<rangeEnd(id,j)
{ preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureEntriesEmpty(assert_uint256(next+1));}} preserved buyTickets(uint256 target,uint32 n) with(env e) {uint256 len=rangeCount(target);if(len>0 && i<len){requireInvariant rangeOrder(target,i,assert_uint256(len-1));}} }
invariant rangeSold(uint256 id) (rangeCount(id)==0 && soldTickets(id)==0) || (rangeCount(id)>0 && rangeEnd(id,assert_uint256(rangeCount(id)-1))==soldTickets(id))
{preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureEntriesEmpty(assert_uint256(next+1));}}}

rule settlementTicketInSoldRange(uint256 id,bytes signature){
 env e;uint32 sold=soldTickets(id);uint32 ticket;address winner;
 ticket,winner=settleRound(e,id,signature);
 assert ticket<sold;
}
