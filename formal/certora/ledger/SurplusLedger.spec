methods {
 function bucket(address,uint256) external returns(uint256) envfree;
 function _.balanceOf(address owner) external => stableCustody(owner) expect uint256;
}
ghost uint256 tokenCustody;
// Absorption is accounting-only. The non-rebasing token balance remains constant.
function stableCustody(address owner) returns(uint256) {return tokenCustody;}
rule surplusAbsorptionPreservesAllLiabilities(env e,address asset) {
 require e.msg.value == 0;
 require asset != currentContract;
 mathint b0=bucket(asset,0);mathint b1=bucket(asset,1);mathint b2=bucket(asset,2);
 mathint b3=bucket(asset,3);mathint b4=bucket(asset,4);mathint b5=bucket(asset,5);
 mathint before=b0+b1+b2+b3+b4+b5;
 require before < tokenCustody;
 admit(e,asset);
 uint256 available=availableTokenSurplus(e,asset);
 assert available==tokenCustody-before;
 uint256 absorbed=absorbTokenSurplus(e,asset);
 assert absorbed==available;
 assert bucket(asset,0)==b0 && bucket(asset,1)==b1 && bucket(asset,2)==b2;
 assert bucket(asset,3)==b3 && bucket(asset,4)==b4;
 assert bucket(asset,5)==b5+absorbed;
 assert availableTokenSurplus(e,asset)==0;
 absorbTokenSurplus@withrevert(e,asset);
 assert lastReverted;
}
