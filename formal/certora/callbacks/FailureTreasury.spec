using AtomicToken as token;
using AtomicRouter as router;
methods {
 function pending(address) external returns(uint256) envfree;
 function aggregate(address) external returns(uint256) envfree;
 function treasury(address) external returns(uint256) envfree;
 function guard() external returns(uint256) envfree;
 function token.balanceOf(address) external returns(uint256) envfree;
 function token.allowance(address,address) external returns(uint256) envfree;
 function token.attempts() external returns(uint256) envfree;
 function token.escaped() external returns(bool) envfree;
 function router.funded() external returns(uint256) envfree;
}
rule actualTreasuryFailureRollsBackEveryContract(env e,uint256 n,uint256 mode) {
 require e.msg.value==0;
 require n>0 && n<=max_uint128;
 prepare(e,token,router,n);
 token.configure(e,currentContract,assert_uint256(2*n+1),mode);
 require token.balanceOf(router)==0;
 require token.balanceOf(0xBEEF)==0;
 require router.funded()==0;
 require token.allowance(currentContract,router)==0;
 flushTreasury@withrevert(e,token,n);
 require lastReverted;
 assert pending(token)==n && aggregate(token)==n && treasury(token)==n;
 assert guard()==1;
 assert token.balanceOf(currentContract)==2*n+1;
 assert token.balanceOf(router)==0 && token.balanceOf(0xBEEF)==0;
 assert router.funded()==0;
 assert token.allowance(currentContract,router)==0;
 assert token.attempts()==0 && !token.escaped();
}
