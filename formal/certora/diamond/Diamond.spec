methods {
 function authority() external returns(address) envfree;
 function frozen() external returns(bool) envfree;
 function target(bytes4) external returns(address) envfree;
 function selectorPosition(bytes4) external returns(uint256) envfree;
 function selectorCount(address) external returns(uint256) envfree;
 function lastSelector(address) external returns(bytes4) envfree;
 function facetPosition(address) external returns(uint256) envfree;
 function lastFacet() external returns(address) envfree;
 function numFacets() external returns(uint256) envfree;
 function selectorSound(bytes4) external returns(bool) envfree;
 function reverseSound(address,uint256) external returns(bool) envfree;
 function facetSound(address) external returns(bool) envfree;
 function listSound(uint256) external returns(bool) envfree;
}
invariant selectorConsistency(bytes4 s) selectorSound(s)
{
 preserved step(address newFacet,uint8 op,bytes4 c) with(env e) {
  address priorFacet=target(c);address last=lastFacet();
  requireInvariant selectorConsistency(c);
  requireInvariant selectorConsistency(lastSelector(priorFacet));
  requireInvariant facetConsistency(priorFacet);
  requireInvariant facetConsistency(newFacet);
  requireInvariant facetConsistency(last);
  if(selectorCount(priorFacet)>0){requireInvariant reverseConsistency(priorFacet,assert_uint256(selectorCount(priorFacet)-1));}
  if(numFacets()>0){requireInvariant listConsistency(assert_uint256(numFacets()-1));}
  requireInvariant listConsistency(facetPosition(priorFacet));
  requireInvariant listConsistency(facetPosition(newFacet));
 }
}
invariant reverseConsistency(address a,uint256 i) reverseSound(a,i)
{
 preserved step(address newFacet,uint8 op,bytes4 c) with(env e) {
  address priorFacet=target(c);address last=lastFacet();
  requireInvariant selectorConsistency(c);
  requireInvariant selectorConsistency(lastSelector(priorFacet));
  requireInvariant facetConsistency(priorFacet);
  requireInvariant facetConsistency(newFacet);
  requireInvariant facetConsistency(last);
  if(selectorCount(priorFacet)>0){requireInvariant reverseConsistency(priorFacet,assert_uint256(selectorCount(priorFacet)-1));}
  if(numFacets()>0){requireInvariant listConsistency(assert_uint256(numFacets()-1));}
  requireInvariant listConsistency(facetPosition(priorFacet));
  requireInvariant listConsistency(facetPosition(newFacet));
 }
}
invariant facetConsistency(address a) facetSound(a)
{
 preserved step(address newFacet,uint8 op,bytes4 c) with(env e) {
  address priorFacet=target(c);address last=lastFacet();
  requireInvariant selectorConsistency(c);
  requireInvariant selectorConsistency(lastSelector(priorFacet));
  requireInvariant facetConsistency(priorFacet);
  requireInvariant facetConsistency(newFacet);
  requireInvariant facetConsistency(last);
  if(selectorCount(priorFacet)>0){requireInvariant reverseConsistency(priorFacet,assert_uint256(selectorCount(priorFacet)-1));}
  if(numFacets()>0){requireInvariant listConsistency(assert_uint256(numFacets()-1));}
  requireInvariant listConsistency(facetPosition(priorFacet));
  requireInvariant listConsistency(facetPosition(newFacet));
 }
}
invariant listConsistency(uint256 i) listSound(i)
{
 preserved step(address newFacet,uint8 op,bytes4 c) with(env e) {
  address priorFacet=target(c);address last=lastFacet();
  requireInvariant selectorConsistency(c);
  requireInvariant selectorConsistency(lastSelector(priorFacet));
  requireInvariant facetConsistency(priorFacet);
  requireInvariant facetConsistency(newFacet);
  requireInvariant facetConsistency(last);
  if(selectorCount(priorFacet)>0){requireInvariant reverseConsistency(priorFacet,assert_uint256(selectorCount(priorFacet)-1));}
  if(numFacets()>0){requireInvariant listConsistency(assert_uint256(numFacets()-1));}
  requireInvariant listConsistency(facetPosition(priorFacet));
  requireInvariant listConsistency(facetPosition(newFacet));
 }
}
rule onlyAuthorityCanMutate(method f){
 env e;calldataarg args;require e.msg.sender!=authority();
 address a;bytes4 s;uint256 n=numFacets();address t=target(s);bool z=frozen();
 f@withrevert(e,args);
 assert numFacets()==n && target(s)==t && frozen()==z;
}
rule freezeIsPermanent(method f){env e;calldataarg args;require frozen();f@withrevert(e,args);assert frozen();}
rule singleCutEffect(env e,address a,uint8 op,bytes4 s){
 require op<=2;step(e,a,op,s);assert target(s)==(op==2?0:a);
}

rule frozenRejectsStep(env e,address a,uint8 op,bytes4 s){require frozen();step@withrevert(e,a,op,s);assert lastReverted;}
rule outsiderRejectedStep(env e,address a,uint8 op,bytes4 s){require e.msg.sender!=authority();step@withrevert(e,a,op,s);assert lastReverted;}
