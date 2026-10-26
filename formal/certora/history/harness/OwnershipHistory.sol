// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import {HistoryLottery} from "./HistoryLottery.sol";
import {LibLotteryStorage as S} from "../../../../src/libraries/LibLotteryStorage.sol";
contract OwnershipHistory is HistoryLottery {
 function rangeCount(uint256 id) external view returns(uint256){return S.gameStorage().entries[id].length;}
 function rangeEnd(uint256 id,uint256 i) external view returns(uint32){return S.gameStorage().entries[id][i].endExclusive;}
 function rangeBuyer(uint256 id,uint256 i) external view returns(address){return S.gameStorage().entries[id][i].buyer;}
 function soldTickets(uint256 id) external view returns(uint32){return S.gameStorage().rounds[id].soldTickets;}
}
