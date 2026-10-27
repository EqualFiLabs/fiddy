rule appendBuyerAndPrefix(env e,address buyer,uint32 end,uint256 i){
 uint256 len=currentContract.entries.length;require len<=max_uint32;
 address oldBuyer=i<len?currentContract.entries[i].buyer:0;
 uint32 oldEnd=i<len?currentContract.entries[i].endExclusive:0;
 append(e,buyer,end);
 assert currentContract.entries.length==len+1;
 assert currentContract.entries[len].buyer==buyer && currentContract.entries[len].endExclusive==end;
 assert i>=len || (currentContract.entries[i].buyer==oldBuyer && currentContract.entries[i].endExclusive==oldEnd);
}
