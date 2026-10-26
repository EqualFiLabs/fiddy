methods { }
invariant capacity() currentContract.entries.length<=max_uint32
{ preserved append(address b,uint32 n) with(env e) {uint256 len=currentContract.entries.length;if(len>0){requireInvariant endpoint(assert_uint256(len-1));}} }
invariant endpoint(uint256 i) i<currentContract.entries.length => (i<currentContract.entries[i].endExclusive && currentContract.entries[i].buyer!=0)
{ preserved append(address b,uint32 n) with(env e) { uint256 len=currentContract.entries.length; if(len>0){requireInvariant endpoint(assert_uint256(len-1));} } }
invariant ordering(uint256 i,uint256 j) (i<j && j<currentContract.entries.length) => currentContract.entries[i].endExclusive<currentContract.entries[j].endExclusive
{ preserved append(address b,uint32 n) with(env e) { uint256 len=currentContract.entries.length; if(len>0 && i<len){requireInvariant ordering(i,assert_uint256(len-1));} } }
invariant soldEndpoint() (currentContract.entries.length==0 && currentContract.sold==0) || (currentContract.entries.length>0 && currentContract.entries[assert_uint256(currentContract.entries.length-1)].endExclusive==currentContract.sold);
rule appendWitness(address buyer,uint32 n){env e;require currentContract.entries.length==0;require buyer!=0 && n>0;append(e,buyer,n);satisfy currentContract.entries.length==1 && currentContract.sold==n;}
