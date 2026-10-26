// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import {SettlementFacet} from "../../../../src/facets/SettlementFacet.sol";
import {LotteryFacet} from "../../../../src/facets/LotteryFacet.sol";
import {ClaimsFacet} from "../../../../src/facets/ClaimsFacet.sol";
import {RevenueFacet} from "../../../../src/facets/RevenueFacet.sol";
import {LibLotteryStorage as L} from "../../../../src/libraries/LibLotteryStorage.sol";
import {LibReentrancy} from "../../../../src/libraries/LibReentrancy.sol";
import {LibTicketRanges} from "../../../../src/libraries/LibTicketRanges.sol";
import {AssetAccounting,Round,RoundStatus,TicketRange,LotteryConfig} from "../../../../src/shared/Types.sol";

contract ExpandedSettlement is SettlementFacet {
    constructor() {LibReentrancy.initialize();}
    function allocation(uint128 gross,uint16 w,uint16 o,uint96 tip) external pure returns(uint256,uint256,uint256,uint256) {
        SettlementAmounts memory a=_allocateValues(gross,w,o,tip);
        return(a.winner,a.operator,a.treasury,a.finalizer);
    }
    function seedAccounting(address asset,AssetAccounting calldata a,uint256 selected,uint256 credit) external {
        L.accountingStorage().assetAccounting[asset]=a;
        L.accountingStorage().pendingOperatorRevenue[3][asset]=selected;
        L.accountingStorage().pendingOperatorRevenue[4][asset]=a.pendingOperatorRevenueTotal-selected;
        L.accountingStorage().finalizerCredits[asset][msg.sender]=credit;
    }
    function prepare(uint256 id,address asset,uint128 gross) external {
        Round storage r=L.gameStorage().rounds[id];
        r.config.paymentToken=asset;r.configVersion=7;r.integrationVersion=3;r.receipts=gross;r.status=RoundStatus.SoldOut;
        L.gameStorage().activeRoundCount=2;L.gameStorage().activeRoundForConfig[7]=id;L.gameStorage().activeRoundForConfig[8]=99;
    }
    function recordAmounts(uint256 id,uint256 w,uint256 o,uint256 t,uint256 f) external {
        _recordSettlement(L.gameStorage(),L.gameStorage().rounds[id],0,msg.sender,bytes32(uint256(19)),SettlementAmounts(w,o,t,f));
    }
    function recordAllocated(uint256 id,uint128 gross,uint16 w,uint16 o,uint96 tip) external {
        _recordSettlement(L.gameStorage(),L.gameStorage().rounds[id],0,msg.sender,bytes32(uint256(19)),_allocateValues(gross,w,o,tip));
    }
    function bucket(address asset,uint256 index) external view returns(uint256) {
        AssetAccounting storage a=L.accountingStorage().assetAccounting[asset];
        if(index==0)return a.activeRoundEscrow;if(index==1)return a.winnerLiability;
        if(index==2)return a.refundLiability;if(index==3)return a.finalizerLiability;
        if(index==4)return a.pendingOperatorRevenueTotal;return a.treasuryAvailable;
    }
    function pending(address asset,uint64 version) external view returns(uint256){return L.accountingStorage().pendingOperatorRevenue[version][asset];}
    function credit(address asset,address who) external view returns(uint256){return L.accountingStorage().finalizerCredits[asset][who];}
    function claimable(uint256 id) external view returns(uint256){return L.gameStorage().rounds[id].winnerClaimable;}
    function active(uint64 version) external view returns(uint256){return L.gameStorage().activeRoundForConfig[version];}
    function count() external view returns(uint256){return L.gameStorage().activeRoundCount;}
    function status(uint256 id) external view returns(uint256){return uint256(L.gameStorage().rounds[id].status);}
}
