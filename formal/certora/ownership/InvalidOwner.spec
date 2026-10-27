methods {function owner(uint32) external returns(address) envfree;}
rule invalidTicketReverts(uint32 ticket){
 require currentContract.entries.length==0 || ticket>=currentContract.entries[assert_uint256(currentContract.entries.length-1)].endExclusive;
 owner@withrevert(ticket);assert lastReverted;
}
rule successfulOwnerWitness(address buyer){
 env e;require currentContract.entries.length==0;require buyer!=0;
 append(e,buyer,1);address actual=owner@withrevert(0);assert !lastReverted;assert actual==buyer;satisfy actual==buyer;
}
