methods {
 function configBpsValid(uint64) external returns(bool) envfree;
 function roundBpsValid(uint256) external returns(bool) envfree;
 function bucket(address,uint256) external returns(uint256) envfree;
 function pending(uint64,address) external returns(uint256) envfree;
 function credit(address,address) external returns(uint256) envfree;
 function roundAsset(uint256) external returns(address) envfree;
 function roundClaim(uint256) external returns(uint256) envfree;
 function roundFacts(uint256) external returns(uint256,uint256,uint256,uint256,uint256,uint256) envfree;
 function nextId() external returns(uint256) envfree;
 function roundState(uint256) external returns(uint256) envfree;
 function roundReceipts(uint256) external returns(uint256) envfree;
 function futureEmpty(uint256) external returns(bool) envfree;
 function onlySettledClaim(uint256) external returns(bool) envfree;
 function roundSound(uint256) external returns(bool) envfree;
 function roundVersion(uint256) external returns(uint64) envfree;
 function activeSlot(uint64) external returns(uint256) envfree;
 function ownsActiveSlot(uint256) external returns(bool) envfree;
 function validActiveSlot(uint64) external returns(bool) envfree;
 function snapshotHash(uint256) external returns(bytes32) envfree;
 function activeCount() external returns(uint256) envfree;
 function _.pullExact(address a,address who,uint256 n) internal => receiveExact(a,n) expect void;
 function _.pushExact(address a,address who,uint256 n) internal => sendExact(a,n) expect void;
 function _.contributeExact(address router,address a,uint256 n) internal => sendExact(a,n) expect void;
 function _.enforceReady(address,address) internal => NONDET;
 function _.ownerOfTicket(SettlementFacet.TicketRange[] storage,uint32) internal => NONDET;
 function _.firstRoundAfter(uint256) external => NONDET;
 function _.roundTime(uint64) external => NONDET;
 function _.hasSig(uint64) external => NONDET;
 function _.postedAt(uint64) external => NONDET;
 function _.postSig(uint64,bytes) external => NONDET;
 function _.randomnessOf(uint64) external => NONDET;
 function _.balanceOf(address who) external => observeBalance(calledContract) expect uint256;
}
strong invariant noRefunds(address a) bucket(a,2)==0;

ghost mapping(address=>mathint) operatorSum { init_state axiom forall address a. operatorSum[a]==0; }
ghost mapping(address=>mathint) finalizerSum { init_state axiom forall address a. finalizerSum[a]==0; }
hook Sstore (slot 11953619035274406818380538113995734185542561697706027140398485023291975846870)[KEY uint64 v][KEY address a] uint256 n (uint256 o) {operatorSum[a]=operatorSum[a]+n-o;}
hook Sstore (slot 11953619035274406818380538113995734185542561697706027140398485023291975846871)[KEY address a][KEY address who] uint256 n (uint256 o) {finalizerSum[a]=finalizerSum[a]+n-o;}
strong invariant operatorAggregation(address a) bucket(a,4)==operatorSum[a];
strong invariant finalizerAggregation(address a) bucket(a,3)==finalizerSum[a];

ghost mapping(address=>mathint) custody {init_state axiom forall address a. custody[a]==0;}
function receiveExact(address a,uint256 n) { require custody[a]+n<=max_uint256; custody[a]=custody[a]+n; }
function sendExact(address a,uint256 n) { require custody[a]>=n; custody[a]=custody[a]-n; }
// Every balance read may observe additional donations. No balance decrease outside exact exits.
function observeBalance(address a) returns(uint256) {uint256 observed; require observed>=custody[a];custody[a]=observed;return observed;}
strong invariant configuredBps(uint64 v) configBpsValid(v);
strong invariant snapshottedBps(uint256 id) roundBpsValid(id)
{
 preserved openRound(uint64 v,uint32 n) with(env e) { requireInvariant configuredBps(v); }
}
strong invariant solventAcrossHistories(address a)
 to_mathint(bucket(a,0))+bucket(a,1)+bucket(a,2)+bucket(a,3)+bucket(a,4)+bucket(a,5)<=custody[a] && custody[a]<=max_uint256
{
 preserved settleRound(uint256 id,bytes signature) with(env e) { requireInvariant snapshottedBps(id); }
}

ghost mapping(address=>mathint) winnerSum {init_state axiom forall address a. winnerSum[a]==0;}
ghost mapping(address=>mathint) escrowSum {init_state axiom forall address a. escrowSum[a]==0;}
ghost mathint liveRounds {init_state axiom liveRounds==0;}
function isActive(uint256 n) returns(bool){return n==1 || n==2;}
hook Sstore (slot 29180370985926144450051246501047677242371663152765100515973595910178012149620)[KEY uint256 id].(offset 192) uint256 n (uint256 o) {address a=roundAsset(id);winnerSum[a]=winnerSum[a]+n-o;}
hook Sstore (slot 29180370985926144450051246501047677242371663152765100515973595910178012149620)[KEY uint256 id].(offset 160) uint256 n (uint256 o) {address a=roundAsset(id);if(isActive(roundState(id))){escrowSum[a]=escrowSum[a]+n-o;}}
hook Sstore (slot 29180370985926144450051246501047677242371663152765100515973595910178012149620)[KEY uint256 id].(offset 128) uint8 n (uint8 o) {
 address a=roundAsset(id);uint256 r=roundReceipts(id);
 if(isActive(n) && !isActive(o)){escrowSum[a]=escrowSum[a]+r;liveRounds=liveRounds+1;}
 if(!isActive(n) && isActive(o)){escrowSum[a]=escrowSum[a]-r;liveRounds=liveRounds-1;}
}
strong invariant futureRoundsAreEmpty(uint256 id) futureEmpty(id);
strong invariant claimsOnlyAfterSettlement(uint256 id) onlySettledClaim(id)
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
}
strong invariant exactRoundReceipts(uint256 id) roundSound(id)
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
}
strong invariant winnerAggregation(address a) bucket(a,1)==winnerSum[a]
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
 preserved settleRound(uint256 id,bytes signature) with(env e) {requireInvariant claimsOnlyAfterSettlement(id);}
}
strong invariant escrowAggregation(address a) bucket(a,0)==escrowSum[a]
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
}
strong invariant activeRoundAggregation() activeCount()==liveRounds
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
}

// Move all contributions when a stored token changes. This keeps the sums exact even
// before the separate existing-round snapshot immutability theorem is applied.
hook Sstore (slot 29180370985926144450051246501047677242371663152765100515973595910178012149620)[KEY uint256 id] address n (address o) {
 if(n!=o){uint256 c=roundClaim(id);winnerSum[o]=winnerSum[o]-c;winnerSum[n]=winnerSum[n]+c;
 if(isActive(roundState(id))){uint256 r=roundReceipts(id);escrowSum[o]=escrowSum[o]-r;escrowSum[n]=escrowSum[n]+r;}}
}
strong invariant activeRoundsOwnTheirSlot(uint256 id) ownsActiveSlot(id)
{
 preserved openRound(uint64 v,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
 preserved settleRound(uint256 target,bytes signature) with(env e) {requireInvariant activeRoundsOwnTheirSlot(target);}
}
strong invariant activeSlotsAreLive(uint64 v) validActiveSlot(v)
{
 preserved openRound(uint64 config,uint32 n) with(env e) {uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}}
}
rule existingRoundSnapshotsNeverChange(method f,env e,calldataarg args,uint256 id) {
 require roundState(id)!=0;
 uint256 next=nextId();if(next<max_uint256){requireInvariant futureRoundsAreEmpty(assert_uint256(next+1));}
 bytes32 before=snapshotHash(id);
 f(e,args);
 assert snapshotHash(id)==before;
}
