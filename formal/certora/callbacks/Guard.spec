methods {
 function status() external returns(uint256) envfree;
 function _.pullExact(address,address,uint256) internal => guardedInteraction() expect void;
 function _.pushExact(address,address,uint256) internal => guardedInteraction() expect void;
 function _.contributeExact(address,address,uint256) internal => guardedInteraction() expect void;
 function _.enforceReady(address,address) internal => guardedInteraction() expect void;
 function _.ownerOfTicket(SettlementFacet.TicketRange[] storage,uint32) internal => NONDET;
 function _.firstRoundAfter(uint256) external => external64() expect uint64;
 function _.roundTime(uint64) external => external64() expect uint64;
 function _.hasSig(uint64) external => externalBool() expect bool;
 function _.postedAt(uint64) external => external64() expect uint64;
 function _.postSig(uint64,bytes) external => externalBool() expect bool;
 function _.randomnessOf(uint64) external => externalWord() expect bytes32;
 function _.balanceOf(address) external => externalAttempt() expect uint256;
}
persistent ghost mathint interactions;
function externalAttempt() returns(uint256){ assert status()==2; interactions=interactions+1; uint256 x;return x;}
rule enteredGuardRejectsEveryProtectedEntry(method f,env e,calldataarg args)
 filtered {f -> f.selector!=sig:status().selector && f.selector!=sig:availableTokenSurplus(address).selector}
{
 require status()==2;
 interactions=0;
 f@withrevert(e,args);
 assert lastReverted;
 assert status()==2;
 assert interactions==0;
}

function external64() returns(uint64){ assert status()==2; interactions=interactions+1;uint64 x;return x;}
function externalBool() returns(bool){assert status()==2; interactions=interactions+1;bool x;return x;}
function externalWord() returns(bytes32){assert status()==2; interactions=interactions+1;bytes32 x;return x;}

function guardedInteraction(){assert status()==2;interactions=interactions+1;}
rule successfulProtectedCallsRestoreGuard(method f,env e,calldataarg args)
 filtered {f -> f.selector!=sig:status().selector && f.selector!=sig:availableTokenSurplus(address).selector}
{ require status()==1;f(e,args);assert status()==1;}
