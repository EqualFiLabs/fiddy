methods {function step(uint256,uint256,uint32) external returns(uint256,uint256) envfree;}
rule searchStepInduction(uint256 low,uint256 high,uint256 k,uint32 ticket){
 require low<=k && k<=high && low<high;
 require high<=currentContract.entries.length && currentContract.entries.length<=max_uint32;
 uint256 middle=assert_uint256((low+high)/2);
 require (middle<k => currentContract.entries[middle].endExclusive<=ticket) && (middle>=k => ticket<currentContract.entries[middle].endExclusive);
 uint256 nextLow;uint256 nextHigh;nextLow,nextHigh=step@withrevert(low,high,ticket);
 assert !lastReverted;
 assert low<=nextLow && nextLow<=k && k<=nextHigh && nextHigh<=high;
 assert nextHigh-nextLow<high-low;
 assert nextHigh-nextLow<=(high-low)/2;
}
rule searchConvergence(uint256 low,uint256 high,uint256 k){require low<=k && k<=high && low>=high;assert low==k;}
rule thirtyTwoHalvingsSuffice(uint256 width){
 require width<=max_uint32;
 mathint w0=width;
 mathint w1=w0/2;
 mathint w2=w1/2;
 mathint w3=w2/2;
 mathint w4=w3/2;
 mathint w5=w4/2;
 mathint w6=w5/2;
 mathint w7=w6/2;
 mathint w8=w7/2;
 mathint w9=w8/2;
 mathint w10=w9/2;
 mathint w11=w10/2;
 mathint w12=w11/2;
 mathint w13=w12/2;
 mathint w14=w13/2;
 mathint w15=w14/2;
 mathint w16=w15/2;
 mathint w17=w16/2;
 mathint w18=w17/2;
 mathint w19=w18/2;
 mathint w20=w19/2;
 mathint w21=w20/2;
 mathint w22=w21/2;
 mathint w23=w22/2;
 mathint w24=w23/2;
 mathint w25=w24/2;
 mathint w26=w25/2;
 mathint w27=w26/2;
 mathint w28=w27/2;
 mathint w29=w28/2;
 mathint w30=w29/2;
 mathint w31=w30/2;
 mathint w32=w31/2;
 assert w32==0;
}

definition before(uint256 low,uint32 ticket) returns bool = forall uint256 i. i<low => currentContract.entries[i].endExclusive<=ticket;
definition after(uint256 high,uint32 ticket) returns bool = forall uint256 i. (i>=high && i<currentContract.entries.length) => ticket<currentContract.entries[i].endExclusive;
rule searchWindowInduction(uint256 low,uint256 high,uint32 ticket){
 require low<high && high<=currentContract.entries.length && currentContract.entries.length<=max_uint32;
 require before(low,ticket) && after(high,ticket);
 require forall uint256 i. forall uint256 j. (i<j && j<currentContract.entries.length) => currentContract.entries[i].endExclusive<currentContract.entries[j].endExclusive;
 uint256 nextLow;uint256 nextHigh;nextLow,nextHigh=step@withrevert(low,high,ticket);
 assert !lastReverted;
 assert before(nextLow,ticket) && after(nextHigh,ticket);
}
rule searchExitMembership(uint256 low,uint256 high,uint32 ticket){
 require currentContract.entries.length>0;
 require low==high && high<=currentContract.entries.length;
 require before(low,ticket) && after(high,ticket);
 require ticket<currentContract.entries[assert_uint256(currentContract.entries.length-1)].endExclusive;
 assert low<currentContract.entries.length;
 assert ticket<currentContract.entries[low].endExclusive;
 assert low==0 || ticket>=currentContract.entries[assert_uint256(low-1)].endExclusive;
}

rule searchInitialization(uint32 ticket){assert before(0,ticket) && after(currentContract.entries.length,ticket);}
rule searchStepBounds(uint256 low,uint256 high,uint32 ticket){
 require low<high && high<=currentContract.entries.length && currentContract.entries.length<=max_uint32;
 uint256 nextLow;uint256 nextHigh;nextLow,nextHigh=step@withrevert(low,high,ticket);
 assert !lastReverted;
 assert low<=nextLow && nextLow<=nextHigh && nextHigh<=high;
 assert nextHigh-nextLow<=(high-low)/2;
}
rule intervalUniqueness(uint256 i,uint256 j,uint32 ticket){
 require i<currentContract.entries.length && j<currentContract.entries.length;
 require forall uint256 a. forall uint256 b. (a<b && b<currentContract.entries.length) => currentContract.entries[a].endExclusive<currentContract.entries[b].endExclusive;
 require ticket<currentContract.entries[i].endExclusive && (i==0 || ticket>=currentContract.entries[assert_uint256(i-1)].endExclusive);
 require ticket<currentContract.entries[j].endExclusive && (j==0 || ticket>=currentContract.entries[assert_uint256(j-1)].endExclusive);
 assert i==j;
}
