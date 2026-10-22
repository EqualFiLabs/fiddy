// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { LotteryDeadlineHalmosTest } from "./formal/LotteryProperties.halmos.t.sol";

/// @dev Concrete controls ensure symbolic harness setup executes real successful transitions.
contract LotteryFormalSanityTest is LotteryDeadlineHalmosTest {
    function testDeadlinePurchaseProofHasSuccessfulControl() public {
        check_deadlineRejectsPurchasesAtOrAfterClose(0);
    }

    function testDeadlinePrematureSettlementProofHasValidState() public {
        check_deadlineRejectsPrematureSettlement(1);
    }

    function testDeadlineSettlementProofExecutes() public {
        check_deadlineWinnerIsSoldAndRevenueConserved(1);
    }
}
