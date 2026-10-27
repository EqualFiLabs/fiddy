// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LibLotteryStorage as S} from "../../../../src/libraries/LibLotteryStorage.sol";
import {LibDiamond} from "../../../../src/libraries/LibDiamond.sol";
import {Round,AssetAccounting,TicketRange} from "../../../../src/shared/Types.sol";
contract AuthorityBoundary {
 constructor(){LibDiamond.initializeAuthority(msg.sender);S.gameStorage().maxActiveRounds=type(uint16).max;S.governanceStorage().treasuryRecipient=msg.sender;S.reentrancyStorage().status=1;}
 function guard() external view returns(uint256){return S.reentrancyStorage().status;}
 function bucket(address a,uint256 i) external view returns(uint256){AssetAccounting storage b=S.accountingStorage().assetAccounting[a];if(i==0)return b.activeRoundEscrow;if(i==1)return b.winnerLiability;if(i==2)return b.refundLiability;if(i==3)return b.finalizerLiability;if(i==4)return b.pendingOperatorRevenueTotal;return b.treasuryAvailable;}
 function pending(uint64 v,address a) external view returns(uint256){return S.accountingStorage().pendingOperatorRevenue[v][a];}
 function credit(address a,address who) external view returns(uint256){return S.accountingStorage().finalizerCredits[a][who];}
 function roundAsset(uint256 id) external view returns(address){return S.gameStorage().rounds[id].config.paymentToken;}
 function roundClaim(uint256 id) external view returns(uint256){return S.gameStorage().rounds[id].winnerClaimable;}
 function roundFacts(uint256 id) external view returns(uint256,uint256,uint256,uint256,uint256,uint256){Round storage r=S.gameStorage().rounds[id];return(uint256(r.status),r.receipts,r.config.ticketPrice,r.soldTickets,r.config.winnerBps,r.config.operatorProtocolBps);}
 function configBpsValid(uint64 v) external view returns(bool){return S.gameStorage().configs[v].winnerBps<=10000 && S.gameStorage().configs[v].operatorProtocolBps<=10000;}
 function roundBpsValid(uint256 id) external view returns(bool){return S.gameStorage().rounds[id].config.winnerBps<=10000 && S.gameStorage().rounds[id].config.operatorProtocolBps<=10000;}
 function nextId() external view returns(uint256){return S.gameStorage().nextRoundId;}
 function roundState(uint256 id) external view returns(uint256){return uint256(S.gameStorage().rounds[id].status);}
 function roundReceipts(uint256 id) external view returns(uint256){return S.gameStorage().rounds[id].receipts;}
 function futureEmpty(uint256 id) external view returns(bool){Round storage r=S.gameStorage().rounds[id];return id<=S.gameStorage().nextRoundId || (uint256(r.status)==0 && r.receipts==0 && r.soldTickets==0 && r.winnerClaimable==0);}
 function onlySettledClaim(uint256 id) external view returns(bool){Round storage r=S.gameStorage().rounds[id];return uint256(r.status)==3 || r.winnerClaimable==0;}
 function roundSound(uint256 id) external view returns(bool){Round storage r=S.gameStorage().rounds[id];return r.receipts==uint256(r.config.ticketPrice)*r.soldTickets && r.soldTickets<=r.config.ticketCount;}
 function roundVersion(uint256 id) external view returns(uint64){return S.gameStorage().rounds[id].configVersion;}
 function activeSlot(uint64 v) external view returns(uint256){return S.gameStorage().activeRoundForConfig[v];}
 function ownsActiveSlot(uint256 id) external view returns(bool){Round storage r=S.gameStorage().rounds[id];return (uint256(r.status)!=1 && uint256(r.status)!=2) || (id!=0 && S.gameStorage().activeRoundForConfig[r.configVersion]==id);}
 function validActiveSlot(uint64 v) external view returns(bool){uint256 id=S.gameStorage().activeRoundForConfig[v];Round storage r=S.gameStorage().rounds[id];return id==0 || ((uint256(r.status)==1 || uint256(r.status)==2) && r.configVersion==v);}
 function snapshotHash(uint256 id) external view returns(bytes32){Round storage r=S.gameStorage().rounds[id];return keccak256(abi.encode(r.config,r.configVersion,r.integrationVersion,r.openedAt,r.expiresAt));}
 function activeCount() external view returns(uint256){return S.gameStorage().activeRoundCount;}
}
