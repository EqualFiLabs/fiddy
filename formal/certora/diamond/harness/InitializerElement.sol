// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {IGovernance} from "../../../../src/interfaces/IGovernance.sol";
import {LibLotteryConfig} from "../../../../src/libraries/LibLotteryConfig.sol";
import {LibLotteryStorage} from "../../../../src/libraries/LibLotteryStorage.sol";
import {AssetAccounting,LotteryConfig} from "../../../../src/shared/Types.sol";
contract InitializerElement {
 function append(LotteryConfig calldata config) external {
  LibLotteryStorage.GameStorage storage game=LibLotteryStorage.gameStorage();
  LibLotteryStorage.AccountingStorage storage accounting=LibLotteryStorage.accountingStorage();
            LibLotteryConfig.validate(config);

            uint64 version = ++game.nextConfigVersion;
            game.configs[version] = config;
            game.configEnabled[version] = true;
            accounting.admittedPaymentToken[config.paymentToken] = true;

            emit IGovernance.LotteryConfigCreated(version, config.paymentToken, config);
            emit IGovernance.LotteryConfigEnabled(version, true);
 }
 function next() external view returns(uint64){return LibLotteryStorage.gameStorage().nextConfigVersion;}
 function configHash(uint64 v) external view returns(bytes32){return keccak256(abi.encode(LibLotteryStorage.gameStorage().configs[v]));}
 function configEquals(uint64 v,LotteryConfig calldata c) external view returns(bool){return keccak256(abi.encode(c))==keccak256(abi.encode(LibLotteryStorage.gameStorage().configs[v]));}
 function enabled(uint64 v) external view returns(bool){return LibLotteryStorage.gameStorage().configEnabled[v];}
 function admitted(address a) external view returns(bool){return LibLotteryStorage.accountingStorage().admittedPaymentToken[a];}
 function configBps(uint64 v) external view returns(bool){LotteryConfig storage c=LibLotteryStorage.gameStorage().configs[v];return c.winnerBps<=10000&&c.operatorProtocolBps<=10000;}
 function frame(address asset,uint256 id,address user,uint64 v) external view returns(bytes32){
  LibLotteryStorage.GameStorage storage g=LibLotteryStorage.gameStorage();LibLotteryStorage.AccountingStorage storage a=LibLotteryStorage.accountingStorage();
  bytes32 gameHash=keccak256(abi.encode(g.maxActiveRounds,g.nextRoundId,g.activeRoundCount,g.rounds[id],g.entries[id].length,g.refundCredit[id][user],g.activeRoundForConfig[v]));
  bytes32 accountHash=keccak256(abi.encode(a.assetAccounting[asset],a.finalizerCredits[asset][user],a.pendingOperatorRevenue[v][asset],LibLotteryStorage.reentrancyStorage().status));
  return keccak256(abi.encode(gameHash,accountHash));

 }
}
