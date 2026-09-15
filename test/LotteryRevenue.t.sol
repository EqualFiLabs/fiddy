// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IERC20Errors } from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Errors } from "../src/shared/Errors.sol";
import { IRevenue } from "../src/interfaces/IRevenue.sol";
import { AssetAccounting, IntegrationConfig, LotteryConfig, Round } from "../src/shared/Types.sol";
import {
    IntegrationEndpoint,
    IntegrationToken,
    LotteryIntegrationSetup
} from "./utils/LotteryIntegrationSetup.sol";

contract RevenueSenderFeeToken is IntegrationToken {
    bool internal feesEnabled;

    constructor() IntegrationToken("Revenue Sender Fee Token", "RSFEE") { }

    function setFeesEnabled(bool enabled) external {
        feesEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (feesEnabled && from != address(0) && to != address(0) && value != 0) {
            super._update(from, address(0), 1);
        }
    }
}

contract BalanceDriftToken is IntegrationToken {
    constructor() IntegrationToken("Balance Drift Token", "DRIFT") { }

    function driftDown(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract SharedBalanceLedger {
    mapping(address account => uint256 amount) internal balances;
    mapping(address facade => bool enabled) internal facades;
    uint256 internal supply;

    function admitFacade(address facade) external {
        facades[facade] = true;
    }

    function mint(address receiver, uint256 amount) external {
        balances[receiver] += amount;
        supply += amount;
    }

    function totalSupply() external view returns (uint256) {
        return supply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function move(address from, address to, uint256 amount) external {
        require(facades[msg.sender], "unadmitted facade");
        uint256 available = balances[from];
        if (available < amount) {
            revert IERC20Errors.ERC20InsufficientBalance(from, available, amount);
        }
        unchecked {
            balances[from] = available - amount;
            balances[to] += amount;
        }
    }
}

contract SharedLedgerToken is IERC20 {
    SharedBalanceLedger internal immutable ledger;
    mapping(address owner => mapping(address spender => uint256 amount)) internal allowances;

    constructor(SharedBalanceLedger ledger_) {
        ledger = ledger_;
        ledger_.admitFacade(address(this));
    }

    function totalSupply() external view returns (uint256) {
        return ledger.totalSupply();
    }

    function balanceOf(address account) external view returns (uint256) {
        return ledger.balanceOf(account);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        ledger.move(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 available = allowances[from][msg.sender];
        if (available != type(uint256).max) {
            require(available >= amount, "insufficient allowance");
            unchecked {
                allowances[from][msg.sender] = available - amount;
            }
            emit Approval(from, msg.sender, allowances[from][msg.sender]);
        }
        ledger.move(from, to, amount);
        emit Transfer(from, to, amount);
        return true;
    }
}

contract RejectingTreasury {
    receive() external payable {
        revert("native rejected");
    }
}

contract ReentrantRevenueRouter {
    function bootstrapFinalized() external pure returns (bool) {
        return true;
    }

    function totalEffectiveWeight() external pure returns (uint256) {
        return 1;
    }

    function isRewardAsset(address) external pure returns (bool) {
        return true;
    }

    function rewardAssetEnabled(address) external pure returns (bool) {
        return true;
    }

    function addRewards(address asset, uint256 amount) external {
        IRevenue(msg.sender).flushOperatorRevenue(2, asset, amount);
    }
}

contract LotteryRevenueTest is LotteryIntegrationSetup {
    function test_FlushesExactOperatorRevenuePermissionlessly() public {
        _settleRoundA();
        AssetAccounting memory beforeFlush = stateView.assetAccounting(address(tokenA));

        vm.prank(alice);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 10), 10);

        AssetAccounting memory afterFlush = stateView.assetAccounting(address(tokenA));
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
        assertEq(afterFlush.pendingOperatorRevenueTotal, 0);
        assertEq(afterFlush.winnerLiability, beforeFlush.winnerLiability);
        assertEq(afterFlush.finalizerLiability, beforeFlush.finalizerLiability);
        assertEq(afterFlush.treasuryAvailable, beforeFlush.treasuryAvailable);
        assertEq(tokenA.balanceOf(address(router)), 10);
        assertEq(router.totalAdded(address(tokenA)), 10);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);
    }

    function test_PartialOperatorFlushLeavesExactVersionTokenRemainder() public {
        _settleRoundA();

        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 4), 4);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 6);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 6);
        assertEq(tokenA.balanceOf(address(router)), 4);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientOperatorRevenue.selector, 1, 7, 6)
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 7);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 6);
    }

    function test_RouterFailureAndReadinessChangesPreservePendingRevenue() public {
        _settleRoundA();
        router.setRejectRewards(true);

        vm.expectRevert(IntegrationEndpoint.RewardsRejected.selector);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 10);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);

        router.setRejectRewards(false);
        router.setAsset(address(tokenA), true, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRouterUnavailable.selector, address(router), address(tokenA)
            )
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);

        router.setAsset(address(tokenA), true, true);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
    }

    function test_OpeningRequiresRouterReadinessOnlyForOperatorConfigs() public {
        router.setBootstrapFinalized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRouterUnavailable.selector, address(router), address(tokenA)
            )
        );
        vm.prank(alice);
        lottery.openRound(1, 1);

        LotteryConfig memory noOperator = _config(address(tokenA), 10, 10, 10, 1 days, 0);
        noOperator.operatorProtocolBps = 0;
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(noOperator);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 1);
        assertEq(stateView.round(roundId).config.operatorProtocolBps, 0);
    }

    function test_OpeningRejectsEveryUnavailableRouterState() public {
        router.setBootstrapFinalized(false);
        _expectUnavailableOpening();

        router.setBootstrapFinalized(true);
        router.setTotalEffectiveWeight(0);
        _expectUnavailableOpening();

        router.setTotalEffectiveWeight(1);
        router.setAsset(address(tokenA), false, false);
        _expectUnavailableOpening();

        router.setAsset(address(tokenA), true, false);
        _expectUnavailableOpening();

        router.setAsset(address(tokenA), true, true);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(1, 1);
        assertEq(stateView.round(roundId).soldTickets, 1);
    }

    function test_HistoricalRevenueUsesSnapshottedRouterAndToken() public {
        _settleRoundA();
        IntegrationEndpoint nextRouter = new IntegrationEndpoint();
        nextRouter.setAsset(address(tokenB), true, true);
        vm.prank(authority);
        governance.setIntegrationConfig(IntegrationConfig(address(registry), address(nextRouter)));

        vm.prank(alice);
        uint256 roundB = lottery.openRound(2, 5);
        Round memory soldOutB = stateView.round(roundB);
        registry.cache(soldOutB.drandRound, keccak256("token B"), soldOutB.selloutAt + 1);
        settlement.settleRound(roundB, "");

        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.pendingOperatorRevenue(2, address(tokenB)), 10);
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        revenue.flushOperatorRevenue(2, address(tokenB), 10);
        assertEq(tokenA.balanceOf(address(router)), 10);
        assertEq(tokenA.balanceOf(address(nextRouter)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(nextRouter)), 10);
    }

    function test_FlushesOnlyTreasuryAvailableToConfiguredRecipient() public {
        _settleRoundA();
        uint256 treasuryBefore = tokenA.balanceOf(treasury);

        vm.prank(bob);
        assertEq(revenue.flushTreasury(address(tokenA), 7), 7);

        AssetAccounting memory accounting = stateView.assetAccounting(address(tokenA));
        assertEq(tokenA.balanceOf(treasury), treasuryBefore + 7);
        assertEq(accounting.treasuryAvailable, 0);
        assertEq(accounting.winnerLiability, 80);
        assertEq(accounting.pendingOperatorRevenueTotal, 10);
        assertEq(accounting.finalizerLiability, 3);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientTreasuryBalance.selector, 1, 0));
        revenue.flushTreasury(address(tokenA), 1);
    }

    function test_AbsorbsOnlyProvableTokenSurplusIntoSameTokenTreasury() public {
        _settleRoundA();
        vm.prank(alice);
        tokenA.transfer(address(diamond), 25);

        assertEq(revenue.availableTokenSurplus(address(tokenA)), 25);
        assertEq(revenue.availableTokenSurplus(address(tokenB)), 0);
        assertEq(revenue.absorbTokenSurplus(address(tokenA)), 25);
        assertEq(revenue.availableTokenSurplus(address(tokenA)), 0);
        assertEq(stateView.assetAccounting(address(tokenA)).treasuryAvailable, 32);
        assertEq(stateView.assetAccounting(address(tokenB)).treasuryAvailable, 0);

        revenue.flushTreasury(address(tokenA), 25);
        assertEq(tokenA.balanceOf(treasury), 25);
        assertEq(stateView.assetAccounting(address(tokenA)).treasuryAvailable, 7);
        vm.expectRevert(Errors.NoTokenSurplus.selector);
        revenue.absorbTokenSurplus(address(tokenA));
    }

    function test_UnadmittedSharedLedgerAliasCannotAbsorbConfiguredCustody() public {
        SharedBalanceLedger ledger = new SharedBalanceLedger();
        SharedLedgerToken canonicalToken = new SharedLedgerToken(ledger);
        SharedLedgerToken aliasToken = new SharedLedgerToken(ledger);
        router.setAsset(address(canonicalToken), true, true);

        LotteryConfig memory config = _config(address(canonicalToken), 10, 10, 10, 1 days, 0);
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        ledger.mint(alice, 100);
        vm.prank(alice);
        canonicalToken.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        lottery.openRound(version, 5);

        assertEq(canonicalToken.balanceOf(address(diamond)), 50);
        assertEq(aliasToken.balanceOf(address(diamond)), 50);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SurplusAssetNotAdmitted.selector, address(aliasToken))
        );
        revenue.availableTokenSurplus(address(aliasToken));
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SurplusAssetNotAdmitted.selector, address(aliasToken))
        );
        revenue.absorbTokenSurplus(address(aliasToken));

        assertEq(canonicalToken.balanceOf(address(diamond)), 50);
        assertEq(stateView.assetAccounting(address(canonicalToken)).activeRoundEscrow, 50);
        assertEq(stateView.assetAccounting(address(aliasToken)).treasuryAvailable, 0);
    }

    function test_DownwardBalanceDriftCannotBecomeSurplusAndPreservesRefund() public {
        BalanceDriftToken token = new BalanceDriftToken();
        router.setAsset(address(token), true, true);
        LotteryConfig memory config = _config(address(token), 10, 10, 10, 1 days, 0);
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();

        token.mint(alice, 50);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 5);
        token.driftDown(address(diamond), 1);

        Round memory open = stateView.round(roundId);
        vm.warp(open.expiresAt);
        lottery.expireRound(roundId);

        assertEq(revenue.availableTokenSurplus(address(token)), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(diamond), 49, 50
            )
        );
        vm.prank(alice);
        claims.claimRefund(roundId, alice);

        assertEq(stateView.refundableAmount(roundId, alice), 50);
        assertEq(stateView.assetAccounting(address(token)).refundLiability, 50);
        assertEq(token.balanceOf(address(diamond)), 49);
    }

    function test_InexactRouterTransferRollsBackLiabilityAndRouterState() public {
        RevenueSenderFeeToken token = new RevenueSenderFeeToken();
        router.setAsset(address(token), true, true);
        LotteryConfig memory config = _config(address(token), 10, 10, 10, 1 days, 0);
        vm.startPrank(authority);
        uint64 version = governance.createLotteryConfig(config);
        governance.setLotteryConfigEnabled(version, true);
        vm.stopPrank();
        token.mint(alice, 1000);
        vm.prank(alice);
        token.approve(address(diamond), type(uint256).max);
        vm.prank(alice);
        uint256 roundId = lottery.openRound(version, 10);
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("sender fee"), soldOut.selloutAt + 1);
        settlement.settleRound(roundId, "");
        token.setFeesEnabled(true);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 10, 11, 10)
        );
        revenue.flushOperatorRevenue(1, address(token), 10);

        assertEq(stateView.pendingOperatorRevenue(1, address(token)), 10);
        assertEq(stateView.assetAccounting(address(token)).pendingOperatorRevenueTotal, 10);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(router.totalAdded(address(token)), 0);
        assertEq(token.allowance(address(diamond), address(router)), 0);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InexactTokenTransfer.selector, address(token), 7, 8, 7)
        );
        revenue.flushTreasury(address(token), 7);
        assertEq(stateView.assetAccounting(address(token)).treasuryAvailable, 7);
        assertEq(token.balanceOf(treasury), 0);
    }

    function test_RouterCapacityFailuresPreserveRevenueUntilRetry() public {
        _settleRoundA();
        router.setRejectLiabilityCapacity(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IntegrationEndpoint.RewardLiabilityLimitExceeded.selector,
                address(tokenA),
                type(uint96).max,
                10,
                type(uint96).max
            )
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        _assertPendingOperatorRevenue();

        router.setRejectLiabilityCapacity(false);
        router.setRejectIndexCapacity(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IntegrationEndpoint.RewardIndexCapacityExceeded.selector, address(tokenA)
            )
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 10);
        _assertPendingOperatorRevenue();

        router.setRejectIndexCapacity(false);
        assertEq(revenue.flushOperatorRevenue(1, address(tokenA), 10), 10);
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 0);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);
    }

    function test_ReentrantRouterCannotConsumeOperatorRevenue() public {
        ReentrantRevenueRouter reentrantRouter = new ReentrantRevenueRouter();
        vm.prank(authority);
        governance.setIntegrationConfig(
            IntegrationConfig(address(registry), address(reentrantRouter))
        );
        uint256 roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("reentrant router"), soldOut.selloutAt + 1);
        settlement.settleRound(roundId, "");

        vm.expectRevert(Errors.Reentrancy.selector);
        revenue.flushOperatorRevenue(2, address(tokenA), 10);

        assertEq(stateView.pendingOperatorRevenue(2, address(tokenA)), 10);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 10);
        assertEq(tokenA.balanceOf(address(diamond)), 100);
        assertEq(tokenA.balanceOf(address(reentrantRouter)), 0);
        assertEq(tokenA.allowance(address(diamond), address(reentrantRouter)), 0);
    }

    function test_ForcedNativeSurplusFlushesOnlyToTreasury() public {
        vm.deal(address(diamond), 1 ether);
        uint256 treasuryBefore = treasury.balance;

        vm.prank(alice);
        assertEq(revenue.flushNativeSurplus(), 1 ether);

        assertEq(address(diamond).balance, 0);
        assertEq(treasury.balance, treasuryBefore + 1 ether);
    }

    function test_FailedNativeSurplusFlushPreservesBalance() public {
        RejectingTreasury rejectingTreasury = new RejectingTreasury();
        vm.prank(authority);
        governance.setTreasuryRecipient(address(rejectingTreasury));
        vm.deal(address(diamond), 1 ether);

        vm.expectRevert(Errors.NativeTransferFailed.selector);
        revenue.flushNativeSurplus();
        assertEq(address(diamond).balance, 1 ether);
    }

    function test_RejectsZeroAndMissingRevenueRequests() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        revenue.flushOperatorRevenue(1, address(tokenA), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.IntegrationNotFound.selector, 0));
        revenue.flushOperatorRevenue(0, address(tokenA), 1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientOperatorRevenue.selector, 1, 1, 0)
        );
        revenue.flushOperatorRevenue(1, address(tokenA), 1);
        vm.expectRevert(Errors.ZeroAmount.selector);
        revenue.flushTreasury(address(tokenA), 0);
        vm.expectRevert(Errors.NoNativeSurplus.selector);
        revenue.flushNativeSurplus();
    }

    function _settleRoundA() private returns (uint256 roundId) {
        roundId = _sellOutRoundA();
        Round memory soldOut = stateView.round(roundId);
        registry.cache(soldOut.drandRound, keccak256("revenue randomness"), soldOut.selloutAt + 1);
        vm.prank(finalizer);
        settlement.settleRound(roundId, "");
    }

    function _expectUnavailableOpening() private {
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.OperatorRouterUnavailable.selector, address(router), address(tokenA)
            )
        );
        vm.prank(alice);
        lottery.openRound(1, 1);
    }

    function _assertPendingOperatorRevenue() private view {
        assertEq(stateView.pendingOperatorRevenue(1, address(tokenA)), 10);
        assertEq(stateView.assetAccounting(address(tokenA)).pendingOperatorRevenueTotal, 10);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(router.totalAdded(address(tokenA)), 0);
        assertEq(tokenA.allowance(address(diamond), address(router)), 0);
    }
}
