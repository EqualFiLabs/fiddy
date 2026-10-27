methods {
 function guard() external returns(uint256) envfree;
 function bucket(address,uint256) external returns(uint256) envfree;
 function pending(uint64,address) external returns(uint256) envfree;
 function credit(address,address) external returns(uint256) envfree;
 function roundAsset(uint256) external returns(address) envfree;
 function roundClaim(uint256) external returns(uint256) envfree;
 function snapshotHash(uint256) external returns(bytes32) envfree;
 function activeCount() external returns(uint256) envfree;
 function activeSlot(uint64) external returns(uint256) envfree;
 function roundState(uint256) external returns(uint256) envfree;
 function roundReceipts(uint256) external returns(uint256) envfree;
 function nextId() external returns(uint256) envfree;
}
rule evenAuthorityCallbacksPreserveLedgerAndExistingSnapshots(method f,env e,calldataarg args,address a,address who,uint64 v,uint256 id) {
 require guard()==2;
 uint256 b0=bucket(a,0);uint256 b1=bucket(a,1);uint256 b2=bucket(a,2);uint256 b3=bucket(a,3);uint256 b4=bucket(a,4);uint256 b5=bucket(a,5);
 uint256 p=pending(v,a);uint256 c=credit(a,who);address asset=roundAsset(id);uint256 claim=roundClaim(id);bytes32 snap=snapshotHash(id);
 uint256 count=activeCount();uint256 slot=activeSlot(v);uint256 state=roundState(id);uint256 receipts=roundReceipts(id);uint256 next=nextId();
 f@withrevert(e,args);
 assert guard()==2;
 assert bucket(a,0)==b0&&bucket(a,1)==b1&&bucket(a,2)==b2&&bucket(a,3)==b3&&bucket(a,4)==b4&&bucket(a,5)==b5;
 assert pending(v,a)==p&&credit(a,who)==c;
 assert roundAsset(id)==asset&&roundClaim(id)==claim&&snapshotHash(id)==snap;
 assert activeCount()==count&&activeSlot(v)==slot&&roundState(id)==state&&roundReceipts(id)==receipts&&nextId()==next;
}
