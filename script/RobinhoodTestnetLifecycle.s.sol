// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    TestnetLifecycleUpgradeFacet,
    TestnetOperatorFlushProbe
} from "./testnet/TestnetLifecycleHelpers.sol";
import { IClaims } from "../src/interfaces/IClaims.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { IGovernance } from "../src/interfaces/IGovernance.sol";
import { ILottery } from "../src/interfaces/ILottery.sol";
import { ILotteryView } from "../src/interfaces/ILotteryView.sol";
import { IRevenue } from "../src/interfaces/IRevenue.sol";
import { ISettlement } from "../src/interfaces/ISettlement.sol";
import { FacetCut, FacetCutAction } from "../src/shared/DiamondTypes.sol";
import { AssetAccounting, LotteryConfig, Round, RoundStatus } from "../src/shared/Types.sol";

interface IWeth is IERC20 {
    function deposit() external payable;
}

interface ITestnetRouterAdmin {
    function owner() external view returns (address);
    function router() external view returns (address);
    function setRewardAssetEnabled(address asset, bool enabled) external;
}

abstract contract RobinhoodTestnetLifecycleScript is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant DIAMOND = 0x89373b3946818811d9421a48410a6164D4608680;
    address internal constant ROUTER = 0xE7Bb1D2766377984546611291732cED1833C0c36;
    address internal constant ROUTER_ADMIN = 0x79c89f35d60fC2C0aEC9F5bB6D0B34d4c4B6dB87;
    address internal constant WETH = 0x33e4191705c386532ba27cBF171Db86919200B94;
    address internal constant STATICS = 0xb6Cc79B2d892798d8e469A1efBF0713Fc2e51f86;

    uint256 internal constant WETH_WRAP_AMOUNT = 0.0001 ether;
    uint256 internal constant WETH_OPERATOR_REVENUE = 0.000_005 ether;

    error AssertionFailed(string label);
    error UnexpectedDeployer(address actual);
    error WrongChain(uint256 actual);

    function _deployerKey() internal view returns (uint256 key) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        key = vm.envUint("LOTTERY_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        if (deployer != EXPECTED_DEPLOYER) revert UnexpectedDeployer(deployer);
    }

    function _assert(bool condition, string memory label) internal pure {
        if (!condition) revert AssertionFailed(label);
    }
}

contract DeployTestnetLifecycleHelpers is RobinhoodTestnetLifecycleScript {
    function run()
        external
        returns (TestnetOperatorFlushProbe flushProbe, TestnetLifecycleUpgradeFacet upgradeFacet)
    {
        uint256 key = _deployerKey();
        vm.startBroadcast(key);
        flushProbe = new TestnetOperatorFlushProbe();
        upgradeFacet = new TestnetLifecycleUpgradeFacet();
        vm.stopBroadcast();
    }
}

contract PrepareConcurrentTestnetRounds is RobinhoodTestnetLifecycleScript {
    function run() external returns (uint256 wethRoundId, uint256 staticsRoundId) {
        uint256 key = _deployerKey();
        ILotteryView stateView = ILotteryView(DIAMOND);
        _assert(stateView.latestRoundId() == 0, "Lottery must be unused");
        _assert(stateView.activeRoundCount() == 0, "active Round count must be zero");

        vm.startBroadcast(key);
        IWeth(WETH).deposit{ value: WETH_WRAP_AMOUNT }();
        SafeERC20.forceApprove(IERC20(WETH), DIAMOND, type(uint256).max);
        SafeERC20.forceApprove(IERC20(STATICS), DIAMOND, type(uint256).max);
        wethRoundId = ILottery(DIAMOND).openRound(1, 5);
        staticsRoundId = ILottery(DIAMOND).openRound(2, 1);
        vm.stopBroadcast();

        _assert(wethRoundId == 1 && staticsRoundId == 2, "unexpected Round IDs");
        _assert(stateView.activeRoundCount() == 2, "Rounds must be concurrent");
        _assert(stateView.round(wethRoundId).status == RoundStatus.SoldOut, "WETH not sold out");
        _assert(stateView.round(staticsRoundId).status == RoundStatus.Open, "STATICS not open");
    }
}

contract SettleWethTestnetRound is RobinhoodTestnetLifecycleScript {
    function run() external {
        uint256 key = _deployerKey();
        bytes memory signature = vm.envBytes("QUICKNET_SIGNATURE");
        TestnetOperatorFlushProbe probe =
            TestnetOperatorFlushProbe(vm.envAddress("OPERATOR_FLUSH_PROBE"));
        ILotteryView stateView = ILotteryView(DIAMOND);
        ITestnetRouterAdmin routerAdmin = ITestnetRouterAdmin(ROUTER_ADMIN);
        _assert(routerAdmin.owner() == EXPECTED_DEPLOYER, "unexpected Router admin owner");
        _assert(routerAdmin.router() == ROUTER, "unexpected Router admin binding");
        _assert(stateView.round(1).status == RoundStatus.SoldOut, "WETH Round not sold out");

        vm.startBroadcast(key);
        routerAdmin.setRewardAssetEnabled(WETH, false);
        ISettlement(DIAMOND).settleRound(1, signature);
        probe.expectFailure(DIAMOND, 1, WETH, WETH_OPERATOR_REVENUE);
        routerAdmin.setRewardAssetEnabled(WETH, true);
        IRevenue(DIAMOND).flushOperatorRevenue(1, WETH, WETH_OPERATOR_REVENUE);
        IClaims(DIAMOND).claimWinner(1, EXPECTED_DEPLOYER);
        IClaims(DIAMOND).claimFinalizerTips(WETH, EXPECTED_DEPLOYER);
        uint256 treasuryAmount = stateView.assetAccounting(WETH).treasuryAvailable;
        IRevenue(DIAMOND).flushTreasury(WETH, treasuryAmount);
        vm.stopBroadcast();

        AssetAccounting memory accounting = stateView.assetAccounting(WETH);
        _assert(stateView.round(1).status == RoundStatus.Settled, "WETH Round not settled");
        _assert(stateView.pendingOperatorRevenue(1, WETH) == 0, "WETH Operator pending");
        _assert(accounting.activeRoundEscrow == 0, "WETH escrow remains");
        _assert(accounting.winnerLiability == 0, "WETH winner liability remains");
        _assert(accounting.finalizerLiability == 0, "WETH finalizer liability remains");
        _assert(accounting.pendingOperatorRevenueTotal == 0, "WETH Router liability remains");
        _assert(accounting.treasuryAvailable == 0, "WETH Treasury balance remains");
        _assert(IERC20(WETH).balanceOf(DIAMOND) == 0, "WETH Diamond balance remains");
    }
}

contract ExpireAndRefundTestnetRound is RobinhoodTestnetLifecycleScript {
    function run() external {
        uint256 key = _deployerKey();
        uint256 roundId = vm.envUint("LOTTERY_ROUND_ID");
        ILotteryView stateView = ILotteryView(DIAMOND);
        Round memory beforeRound = stateView.round(roundId);
        _assert(beforeRound.status == RoundStatus.Open, "Round not open");
        // forge-lint: disable-next-line(block-timestamp)
        _assert(block.timestamp >= beforeRound.expiresAt, "Round not expired by time");
        uint256 expectedRefund = beforeRound.receipts;

        vm.startBroadcast(key);
        ILottery(DIAMOND).expireRound(roundId);
        IClaims(DIAMOND).claimRefund(roundId, EXPECTED_DEPLOYER);
        vm.stopBroadcast();

        _assert(stateView.round(roundId).status == RoundStatus.Expired, "Round not expired");
        _assert(stateView.refundableAmount(roundId, EXPECTED_DEPLOYER) == 0, "refund remains");
        _assert(expectedRefund != 0, "refund must be nonzero");
    }
}

contract OpenSoldOutStaticsTestnetRound is RobinhoodTestnetLifecycleScript {
    function run() external returns (uint256 roundId) {
        uint256 key = _deployerKey();
        ILotteryView stateView = ILotteryView(DIAMOND);
        _assert(stateView.activeRoundCount() == 0, "active Round remains");

        vm.startBroadcast(key);
        roundId = ILottery(DIAMOND).openRound(2, 5);
        vm.stopBroadcast();

        _assert(roundId == 3, "unexpected STATICS Round ID");
        _assert(stateView.round(roundId).status == RoundStatus.SoldOut, "STATICS not sold out");
    }
}

contract SettleStaticsTestnetRound is RobinhoodTestnetLifecycleScript {
    function run() external {
        uint256 key = _deployerKey();
        bytes memory signature = vm.envBytes("QUICKNET_SIGNATURE");
        ILotteryView stateView = ILotteryView(DIAMOND);
        Round memory beforeRound = stateView.round(3);
        _assert(beforeRound.status == RoundStatus.SoldOut, "STATICS Round not sold out");

        vm.startBroadcast(key);
        ISettlement(DIAMOND).settleRound(3, signature);
        uint256 operatorAmount = stateView.pendingOperatorRevenue(1, STATICS);
        IRevenue(DIAMOND).flushOperatorRevenue(1, STATICS, operatorAmount);
        IClaims(DIAMOND).claimWinner(3, EXPECTED_DEPLOYER);
        IClaims(DIAMOND).claimFinalizerTips(STATICS, EXPECTED_DEPLOYER);
        uint256 treasuryAmount = stateView.assetAccounting(STATICS).treasuryAvailable;
        IRevenue(DIAMOND).flushTreasury(STATICS, treasuryAmount);
        vm.stopBroadcast();

        AssetAccounting memory accounting = stateView.assetAccounting(STATICS);
        _assert(stateView.round(3).status == RoundStatus.Settled, "STATICS Round not settled");
        _assert(stateView.pendingOperatorRevenue(1, STATICS) == 0, "STATICS Operator pending");
        _assert(accounting.activeRoundEscrow == 0, "STATICS escrow remains");
        _assert(accounting.winnerLiability == 0, "STATICS winner liability remains");
        _assert(accounting.refundLiability == 0, "STATICS refund liability remains");
        _assert(accounting.finalizerLiability == 0, "STATICS finalizer liability remains");
        _assert(accounting.pendingOperatorRevenueTotal == 0, "STATICS Router liability remains");
        _assert(accounting.treasuryAvailable == 0, "STATICS Treasury balance remains");
        _assert(IERC20(STATICS).balanceOf(DIAMOND) == 0, "STATICS Diamond balance remains");
    }
}

contract UpgradeAndFinalizeTestnetLottery is RobinhoodTestnetLifecycleScript {
    bytes32 internal constant MARKER = keccak256("STATICS_LOTTERY_TESTNET_UPGRADE");

    function run() external {
        uint256 key = _deployerKey();
        address upgradeFacet = vm.envAddress("LOTTERY_UPGRADE_FACET");
        ILotteryView stateView = ILotteryView(DIAMOND);
        bytes32 roundsBefore = _roundStateHash(stateView);
        bytes32 configsBefore = _configStateHash(stateView);
        bytes32 accountingBefore = _accountingStateHash(stateView);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = TestnetLifecycleUpgradeFacet.setLifecycleMarker.selector;
        selectors[1] = TestnetLifecycleUpgradeFacet.lifecycleMarker.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(upgradeFacet, FacetCutAction.Add, selectors);

        vm.startBroadcast(key);
        IDiamondCut(DIAMOND).diamondCut(cuts, address(0), "");
        TestnetLifecycleUpgradeFacet(DIAMOND).setLifecycleMarker(MARKER);
        IGovernance(DIAMOND).finalizeProtocol();
        vm.stopBroadcast();

        _assert(
            TestnetLifecycleUpgradeFacet(DIAMOND).lifecycleMarker() == MARKER, "marker mismatch"
        );
        _assert(_roundStateHash(stateView) == roundsBefore, "Round storage changed");
        _assert(_configStateHash(stateView) == configsBefore, "config storage changed");
        _assert(_accountingStateHash(stateView) == accountingBefore, "accounting changed");
        _assert(IGovernance(DIAMOND).protocolFinalized(), "protocol not finalized");
    }

    function _roundStateHash(ILotteryView stateView) private view returns (bytes32) {
        return keccak256(abi.encode(stateView.round(1), stateView.round(2), stateView.round(3)));
    }

    function _configStateHash(ILotteryView stateView) private view returns (bytes32) {
        (LotteryConfig memory config1, bool enabled1) = stateView.lotteryConfig(1);
        (LotteryConfig memory config2, bool enabled2) = stateView.lotteryConfig(2);
        return keccak256(abi.encode(config1, enabled1, config2, enabled2));
    }

    function _accountingStateHash(ILotteryView stateView) private view returns (bytes32) {
        return keccak256(
            abi.encode(stateView.assetAccounting(WETH), stateView.assetAccounting(STATICS))
        );
    }
}

contract ConfirmFinalizedCutFailure is RobinhoodTestnetLifecycleScript {
    function run() external {
        uint256 key = _deployerKey();
        FacetCut[] memory cuts = new FacetCut[](0);

        vm.startBroadcast(key);
        (bool success,) =
            DIAMOND.call(abi.encodeCall(IDiamondCut.diamondCut, (cuts, address(0), "")));
        vm.stopBroadcast();

        _assert(!success, "finalized cut unexpectedly succeeded");
    }
}

contract OpenPostFinalizationTestnetRound is RobinhoodTestnetLifecycleScript {
    function run() external returns (uint256 roundId) {
        uint256 key = _deployerKey();
        IGovernance governance = IGovernance(DIAMOND);
        ILotteryView stateView = ILotteryView(DIAMOND);
        _assert(governance.protocolFinalized(), "protocol not finalized");
        _assert(stateView.activeRoundCount() == 0, "active Round remains");

        vm.startBroadcast(key);
        governance.setLotteryConfigEnabled(2, false);
        governance.setLotteryConfigEnabled(2, true);
        roundId = ILottery(DIAMOND).openRound(2, 1);
        vm.stopBroadcast();

        _assert(roundId == 4, "unexpected post-finalization Round ID");
        _assert(stateView.round(roundId).status == RoundStatus.Open, "Round not open");
    }
}
