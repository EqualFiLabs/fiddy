// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;
import { FiddyRevenueSetup } from "./FiddyStaking.t.sol";
import { FiddyAccount } from "../src/shared/FiddyTypes.sol";
import { AssetAccounting } from "../src/shared/Types.sol";

contract FiddyStatefulTest is FiddyRevenueSetup {
    function setUp() public override {
        super.setUp();
        tokenA.mint(alice, 1e30);
        tokenA.mint(bob, 1e30);
        tokenB.mint(alice, 1e30);
        _start();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = this.act.selector;
        targetSelector(FuzzSelector(address(this), selectors));
        targetContract(address(this));
    }

    function act(uint256 seed) external {
        staking.processFiddyRevenue(100);
        uint256 id = 1 + seed % 2;
        address owner = positions.ownerOf(id);
        staking.checkpointFiddyAccount(id, 100);
        FiddyAccount memory a = fiddyView.fiddyAccount(id);
        uint256 mode = (seed >> 16) % 7;
        if (mode == 0) {
            _settle(seed % 2 == 0 ? address(tokenA) : address(tokenB), seed % 3 == 0);
        } else if (mode == 1 && a.balance > a.staked) {
            vm.prank(owner);
            staking.stakeFiddy(id, 1 + seed % (a.balance - a.staked));
        } else if (mode == 2 && a.staked > 0) {
            vm.prank(owner);
            staking.unstakeFiddy(id, 1 + seed % a.staked);
        } else if (mode == 3) {
            _wrap(id, owner, 1 + seed % 1000);
        } else if (mode == 4) {
            vm.prank(owner);
            positions.transferFrom(owner, owner == alice ? bob : alice, id);
        } else if (mode == 5) {
            vm.prank(owner);
            staking.claimFiddyRevenue(id, seed % 2 == 0 ? address(tokenA) : address(tokenB), owner);
        } else if (mode == 6 && a.balance > a.staked) {
            uint256 amount = 1 + seed % (a.balance - a.staked);
            vm.prank(owner);
            fiddy.withdrawFiddy(id, amount, owner);
            vm.prank(owner);
            fiddy.approve(address(diamond), amount);
            vm.prank(owner);
            fiddy.depositFiddy(id, amount);
        }
    }

    function invariantBackingCustodyAndEveryAssetConserved() public view {
        (uint256 inventory, uint256 backing, uint256 custody,,,,) = fiddyView.fiddyReserve();
        assertEq(fiddy.totalSupply(), backing);
        assertEq(fiddy.balanceOf(address(diamond)), custody);
        FiddyAccount memory a = fiddyView.fiddyAccount(1);
        FiddyAccount memory b = fiddyView.fiddyAccount(2);
        assertEq(custody, a.balance + b.balance);
        (,,,,, uint256 totalWeight,,) = fiddyView.fiddyProcessing();
        assertEq(totalWeight, a.weight + b.weight);
        assertLe(a.staked, a.balance);
        assertLe(b.staked, b.balance);
        assertEq(tokenA.balanceOf(address(diamond)), _owed(address(tokenA)) + inventory + backing);
        assertEq(tokenB.balanceOf(address(diamond)), _owed(address(tokenB)));
        assertEq(revenue.availableTokenSurplus(address(tokenA)), 0);
        assertEq(revenue.availableTokenSurplus(address(tokenB)), 0);
        _entitlement(address(tokenA));
        _entitlement(address(tokenB));
    }

    function _entitlement(address asset) internal view {
        (uint256 wholeA, uint256 remA) = staking.indexedFiddyRevenue(1, asset);
        (uint256 wholeB, uint256 remB) = staking.indexedFiddyRevenue(2, asset);
        uint256 ray = 1e27;
        assertEq(
            fiddyView.fiddyAsset(asset).reserved * ray,
            fiddyView.fiddyAsset(asset).pending * ray + (wholeA + wholeB) * ray + remA + remB
                + fiddyView.fiddyAsset(asset).dustRay
        );
    }

    function _owed(address asset) internal view returns (uint256) {
        AssetAccounting memory a = stateView.assetAccounting(asset);
        return a.activeRoundEscrow + a.winnerLiability + a.refundLiability + a.finalizerLiability
            + a.pendingOperatorRevenueTotal + a.treasuryAvailable
            + fiddyView.fiddyAsset(asset).reserved;
    }
}
