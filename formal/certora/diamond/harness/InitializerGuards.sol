// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LotteryInit} from "../../../../src/initializers/LotteryInit.sol";
import {LibDiamond} from "../../../../src/libraries/LibDiamond.sol";
import {LibLotteryStorage} from "../../../../src/libraries/LibLotteryStorage.sol";
contract InitializerGuards is LotteryInit {
 constructor(bool wasInitialized){LibDiamond.initializeAuthority(msg.sender);if(wasInitialized)LibLotteryStorage.reentrancyStorage().status=1;}
 function authority() external view returns(address){return LibDiamond.authority();}
 function status() external view returns(uint256){return LibLotteryStorage.reentrancyStorage().status;}
}
