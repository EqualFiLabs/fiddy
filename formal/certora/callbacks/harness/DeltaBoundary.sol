// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LibExactToken} from "../../../../src/libraries/LibExactToken.sol";
import {LibOperatorFeeRouter} from "../../../../src/libraries/LibOperatorFeeRouter.sol";
contract DeltaBoundary {
 function pull(address a,address who,uint256 n) external {LibExactToken.pullExact(a,who,n);}
 function push(address a,address who,uint256 n) external {LibExactToken.pushExact(a,who,n);}
 function contribute(address a,address who,uint256 n) external {LibOperatorFeeRouter.contributeExact(who,a,n);}
}
