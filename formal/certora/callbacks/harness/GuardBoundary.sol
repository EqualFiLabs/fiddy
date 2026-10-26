// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LibLotteryStorage as S} from "../../../../src/libraries/LibLotteryStorage.sol";
contract GuardBoundary {
 function status() external view returns(uint256){return S.reentrancyStorage().status;}
}
