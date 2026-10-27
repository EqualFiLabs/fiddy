methods {
 function allocation(uint128,uint16,uint16,uint96) external returns(uint256,uint256,uint256,uint256) envfree;
 function bucket(address,uint256) external returns(uint256) envfree;
 function pending(address,uint64) external returns(uint256) envfree;
 function credit(address,address) external returns(uint256) envfree;
 function claimable(uint256) external returns(uint256) envfree;
 function active(uint64) external returns(uint256) envfree;
 function count() external returns(uint256) envfree;
 function status(uint256) external returns(uint256) envfree;
}
rule settlementPreservesSolventLedger(env e,address asset,uint256 id,uint128 gross,uint256 w,uint256 o,uint256 t,uint256 f) {
 require e.msg.value == 0;
 require e.block.timestamp <= max_uint64;
 require id != 0;
 require to_mathint(w)+o+t+f == gross;
 mathint escrow=bucket(asset,0);
 mathint winner=bucket(asset,1);
 mathint refund=bucket(asset,2);
 mathint finalizer=bucket(asset,3);
 mathint operator=bucket(asset,4);
 mathint treasury=bucket(asset,5);
 mathint selected=pending(asset,3);
 mathint other=pending(asset,4);
 mathint callerCredit=credit(asset,e.msg.sender);
 require escrow >= gross;
 require escrow+winner+refund+finalizer+operator+treasury <= max_uint256;
 require selected <= operator;
 require callerCredit <= finalizer;
 prepare(e,id,asset,gross);
 recordAmounts(e,id,w,o,t,f);
 assert bucket(asset,0) == escrow-gross;
 assert bucket(asset,1) == winner+w;
 assert bucket(asset,2) == refund;
 assert bucket(asset,3) == finalizer+f;
 assert bucket(asset,4) == operator+o;
 assert bucket(asset,5) == treasury+t;
 assert pending(asset,3) == selected+o;
 assert pending(asset,4) == other;
 assert credit(asset,e.msg.sender) == callerCredit+f;
 assert claimable(id) == w;
 assert status(id) == 3;
 assert active(7) == 0;
 assert active(8) == 99;
 assert count() == 1;
 mathint after=bucket(asset,0)+to_mathint(bucket(asset,1))+bucket(asset,2)+bucket(asset,3)+bucket(asset,4)+bucket(asset,5);
 assert after == escrow+winner+refund+finalizer+operator+treasury;
}
rule settlementIsolatesOtherToken(env e,address asset,address isolated,uint256 id,uint128 gross,uint256 w,uint256 o,uint256 t,uint256 f) {
 require e.msg.value == 0;
 require e.block.timestamp <= max_uint64;
 require asset != isolated;
 require id != 0;
 require to_mathint(w)+o+t+f == gross;
 require bucket(asset,0) >= gross;
 require to_mathint(bucket(asset,1))+gross <= max_uint256;
 require to_mathint(bucket(asset,3))+gross <= max_uint256;
 require to_mathint(bucket(asset,4))+gross <= max_uint256;
 require to_mathint(bucket(asset,5))+gross <= max_uint256;
 require to_mathint(pending(asset,3))+gross <= max_uint256;
 require to_mathint(credit(asset,e.msg.sender))+gross <= max_uint256;
 mathint b0=bucket(isolated,0);mathint b1=bucket(isolated,1);mathint b2=bucket(isolated,2);
 mathint b3=bucket(isolated,3);mathint b4=bucket(isolated,4);mathint b5=bucket(isolated,5);
 mathint p=pending(isolated,3);mathint c=credit(isolated,e.msg.sender);
 prepare(e,id,asset,gross);recordAmounts(e,id,w,o,t,f);
 assert bucket(isolated,0)==b0 && bucket(isolated,1)==b1 && bucket(isolated,2)==b2;
 assert bucket(isolated,3)==b3 && bucket(isolated,4)==b4 && bucket(isolated,5)==b5;
 assert pending(isolated,3)==p && credit(isolated,e.msg.sender)==c;
}

rule fullWidthAllocationConservesGross(uint128 gross,uint16 w,uint16 o,uint96 tip) {
 require w <= 10000;
 require o <= 10000;
 uint256 winner; uint256 operator; uint256 treasury; uint256 finalizer;
 winner,operator,treasury,finalizer=allocation(gross,w,o,tip);
 assert to_mathint(winner)+operator+treasury+finalizer == gross;
 assert winner == to_mathint(gross)*w/10000;
 assert operator == (to_mathint(gross)-winner)*o/10000;
 assert finalizer <= tip;
}

rule allocatedSettlementPreservesSolventLedger(env e,address asset,uint256 id,uint128 gross,uint16 winnerBps,uint16 operatorBps,uint96 tip) {
 require e.msg.value == 0;
 require e.block.timestamp <= max_uint64;
 require id != 0;
 require winnerBps <= 10000 && operatorBps <= 10000;
 uint256 w;uint256 o;uint256 t;uint256 f;
 w,o,t,f=allocation(gross,winnerBps,operatorBps,tip);
 mathint escrow=bucket(asset,0);
 mathint winner=bucket(asset,1);
 mathint refund=bucket(asset,2);
 mathint finalizer=bucket(asset,3);
 mathint operator=bucket(asset,4);
 mathint treasury=bucket(asset,5);
 mathint selected=pending(asset,3);
 mathint other=pending(asset,4);
 mathint callerCredit=credit(asset,e.msg.sender);
 require escrow >= gross;
 require escrow+winner+refund+finalizer+operator+treasury <= max_uint256;
 require selected <= operator;
 require callerCredit <= finalizer;
 prepare(e,id,asset,gross);
 recordAllocated(e,id,gross,winnerBps,operatorBps,tip);
 assert bucket(asset,0) == escrow-gross;
 assert bucket(asset,1) == winner+w;
 assert bucket(asset,2) == refund;
 assert bucket(asset,3) == finalizer+f;
 assert bucket(asset,4) == operator+o;
 assert bucket(asset,5) == treasury+t;
 assert pending(asset,3) == selected+o;
 assert pending(asset,4) == other;
 assert credit(asset,e.msg.sender) == callerCredit+f;
 assert claimable(id) == w;
 assert status(id) == 3;
 assert active(7) == 0;
 assert active(8) == 99;
 assert count() == 1;
 mathint after=bucket(asset,0)+to_mathint(bucket(asset,1))+bucket(asset,2)+bucket(asset,3)+bucket(asset,4)+bucket(asset,5);
 assert after == escrow+winner+refund+finalizer+operator+treasury;
}

rule ticketReceiptFitsSettlementWidth(uint96 price,uint32 quantity) {
 assert to_mathint(price)*quantity <= max_uint128;
}
