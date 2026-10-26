methods {
 function _.balanceOf(address) external => observe() expect uint256;
 function _.transfer(address,uint256) external => outcome() expect bool;
 function _.transferFrom(address,address,uint256) external => outcome() expect bool;
 function _.approve(address,uint256) external => outcome() expect bool;
 function _.addRewards(address,uint256) external => noOp() expect void;
 function _.safeTransfer(address,address,uint256) internal => noOp() expect void;
 function _.safeTransferFrom(address,address,address,uint256) internal => noOp() expect void;
 function _.forceApprove(address,address,uint256) internal => noOp() expect void;
 function _.bootstrapFinalized() external => ready() expect bool;
 function _.totalEffectiveWeight() external => weight() expect uint256;
 function _.isRewardAsset(address) external => ready() expect bool;
 function _.rewardAssetEnabled(address) external => ready() expect bool;
}
ghost mathint reads;
ghost uint256 b0;ghost uint256 b1;ghost uint256 b2;ghost uint256 b3;
function observe() returns(uint256){uint256 x; if(reads==0){b0=x;}if(reads==1){b1=x;}if(reads==2){b2=x;}if(reads==3){b3=x;}reads=reads+1;return x;}
function outcome() returns(bool){bool x;return x;}
function ready() returns(bool){return true;}
function weight() returns(uint256){return 1;}
rule successfulPullEnforcesExactObservedDeltas(env e,address a,address who,uint256 n) {
 require n>0;
 reads=0;
 pull(e,a,who,n);
 assert reads==4;
 assert to_mathint(b0)-b2==n;
 assert to_mathint(b3)-b1==n;
}
rule successfulPushEnforcesExactObservedDeltas(env e,address a,address who,uint256 n) {
 require n>0;
 reads=0;
 push(e,a,who,n);
 assert reads==4;
 assert to_mathint(b0)-b2==n;
 assert to_mathint(b3)-b1==n;
}
rule successfulContributeEnforcesExactObservedDeltas(env e,address a,address who,uint256 n) {
 require n>0;
 reads=0;
 contribute(e,a,who,n);
 assert reads==4;
 assert to_mathint(b0)-b2==n;
 assert to_mathint(b3)-b1==n;
}

function noOp() {}
