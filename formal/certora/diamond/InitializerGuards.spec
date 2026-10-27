methods {function authority() external returns(address) envfree;function status() external returns(uint256) envfree;}
rule priorInitializationRejectsAllInputs(method f) filtered {f -> !f.isView} {
 env e;calldataarg args;require status()!=0;
 f@withrevert(e,args);assert lastReverted;
}
rule outsiderRejectsAllInputs(method f) filtered {f -> !f.isView} {
 env e;calldataarg args;require e.msg.sender!=authority();
 f@withrevert(e,args);assert lastReverted;
}
