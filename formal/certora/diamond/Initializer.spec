methods {
 function next() external returns(uint64) envfree;
 function configHash(uint64) external returns(bytes32) envfree;
 function configEquals(uint64,InitializerElement.LotteryConfig) external returns(bool) envfree;
 function enabled(uint64) external returns(bool) envfree;
 function admitted(address) external returns(bool) envfree;
 function configBps(uint64) external returns(bool) envfree;
 function frame(address,uint256,address,uint64) external returns(bytes32) envfree;
}
invariant initializedBps(uint64 v) configBps(v);
rule elementMonotonicity(env e,InitializerElement.LotteryConfig cfg,uint64 probe,address asset,uint256 id,address user){
 uint64 n=next();bytes32 beforeConfig=configHash(probe);bool wasEnabled=enabled(probe);bool wasAdmitted=admitted(asset);bytes32 beforeFrame=frame(asset,id,user,probe);
 append(e,cfg);
 assert next()==n+1;
 assert configEquals(assert_uint64(n+1),cfg);
 assert enabled(assert_uint64(n+1));assert admitted(cfg.paymentToken);
 assert probe==n+1 || configHash(probe)==beforeConfig;
 assert probe==n+1 || enabled(probe)==wasEnabled;
 assert !wasAdmitted || admitted(asset);
 assert beforeFrame==frame(asset,id,user,probe);
}
