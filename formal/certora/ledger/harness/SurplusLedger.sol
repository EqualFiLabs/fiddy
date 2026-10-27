// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import {RevenueFacet} from "../../../../src/facets/RevenueFacet.sol";
import {LibLotteryStorage as L} from "../../../../src/libraries/LibLotteryStorage.sol";
import {LibReentrancy} from "../../../../src/libraries/LibReentrancy.sol";
import {AssetAccounting} from "../../../../src/shared/Types.sol";
contract SurplusLedger is RevenueFacet {
 constructor(){LibReentrancy.initialize();}
 function admit(address asset) external {L.accountingStorage().admittedPaymentToken[asset]=true;}
 function bucket(address asset,uint256 i) external view returns(uint256){AssetAccounting storage a=L.accountingStorage().assetAccounting[asset];if(i==0)return a.activeRoundEscrow;if(i==1)return a.winnerLiability;if(i==2)return a.refundLiability;if(i==3)return a.finalizerLiability;if(i==4)return a.pendingOperatorRevenueTotal;return a.treasuryAvailable;}
}
