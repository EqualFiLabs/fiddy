// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {RevenueFacet} from "../../../../src/facets/RevenueFacet.sol";
import {LibLotteryStorage as S} from "../../../../src/libraries/LibLotteryStorage.sol";
import {LibReentrancy} from "../../../../src/libraries/LibReentrancy.sol";
import {Errors} from "../../../../src/shared/Errors.sol";
interface RevenueTarget {function flushTreasury(address,uint256) external returns(uint256);}
contract AtomicToken {
 mapping(address=>uint256) public balanceOf;
 mapping(address=>mapping(address=>uint256)) public allowance;
 address public target;uint256 public mode;uint256 public attempts;bool public escaped;
 function configure(address t,uint256 n,uint256 m) external {target=t;balanceOf[t]=n;mode=m;attempts=0;escaped=false;}
 function poke() public {attempts++;try RevenueTarget(target).flushTreasury(address(this),1) returns(uint256){escaped=true;}catch(bytes memory reason){if(reason.length!=4||bytes4(reason)!=Errors.Reentrancy.selector)escaped=true;}}
 function approve(address who,uint256 n) external returns(bool){poke();if(mode==7&&n==0)revert();allowance[msg.sender][who]=n;return true;}
 function transfer(address to,uint256 n) external returns(bool){return move(msg.sender,to,n);}
 function transferFrom(address from,address to,uint256 n) external returns(bool){allowance[from][msg.sender]-=n;return move(from,to,n);}
 function move(address from,address to,uint256 n) private returns(bool){poke();require(mode!=4);balanceOf[from]-=n+(mode==2?1:0);balanceOf[to]+=n-(mode==1?1:0);if(mode==5){assembly("memory-safe"){mstore(0,1)return(31,1)}}return mode!=3;}
}
contract AtomicRouter {
 uint256 public funded;
 function addRewards(address a,uint256 n) external {AtomicToken(a).poke();require(AtomicToken(a).transferFrom(msg.sender,address(this),n));funded+=n;}
 function bootstrapFinalized() external pure returns(bool){return true;}
 function totalEffectiveWeight() external pure returns(uint256){return 1;}
 function isRewardAsset(address) external pure returns(bool){return true;}
 function rewardAssetEnabled(address) external pure returns(bool){return true;}
}
contract AtomicBoundary is RevenueFacet {
 function prepare(address token,address router,uint256 n) external {
  S.reentrancyStorage().status=1;S.governanceStorage().treasuryRecipient=address(0xBEEF);
  S.accountingStorage().pendingOperatorRevenue[1][token]=n;S.accountingStorage().assetAccounting[token].pendingOperatorRevenueTotal=n;
  S.accountingStorage().assetAccounting[token].treasuryAvailable=n;
  S.integrationStorage().currentVersion=1;S.integrationStorage().integrations[1].operatorFeeRouter=router;
 }
 function pending(address a) external view returns(uint256){return S.accountingStorage().pendingOperatorRevenue[1][a];}
 function aggregate(address a) external view returns(uint256){return S.accountingStorage().assetAccounting[a].pendingOperatorRevenueTotal;}
 function treasury(address a) external view returns(uint256){return S.accountingStorage().assetAccounting[a].treasuryAvailable;}
 function guard() external view returns(uint256){return S.reentrancyStorage().status;}
}
