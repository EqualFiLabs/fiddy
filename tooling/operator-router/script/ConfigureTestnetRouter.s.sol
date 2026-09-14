// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { OperatorFeeRouter } from "operator-fee-router/src/OperatorFeeRouter.sol";
import { TestnetRouterAdmin } from "../src/TestnetRouterAdmin.sol";

contract ConfigureTestnetRouter is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant WETH = 0x33e4191705c386532ba27cBF171Db86919200B94;
    address internal constant STATICS = 0xb6Cc79B2d892798d8e469A1efBF0713Fc2e51f86;

    error ConfigurationMismatch();
    error UnexpectedDeployer(address actual);
    error WrongChain(uint256 actual);

    function run() external {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("ROUTER_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert UnexpectedDeployer(deployer);

        TestnetRouterAdmin admin = TestnetRouterAdmin(vm.envAddress("TESTNET_ROUTER_ADMIN"));
        OperatorFeeRouter router = OperatorFeeRouter(payable(vm.envAddress("OPERATOR_FEE_ROUTER")));
        if (
            admin.owner() != deployer || admin.router() != address(router)
                || router.routerTimelock() != address(admin)
        ) {
            revert ConfigurationMismatch();
        }

        vm.startBroadcast(deployerKey);
        if (!router.bootstrapFinalized()) {
            while (router.nextOperatorId() <= router.LAST_OPERATOR_ID()) {
                router.bootstrapOperators(router.MAX_BOOTSTRAP_BATCH());
            }
            router.finalizeBootstrap();
        }
        _enableAsset(admin, router, WETH);
        _enableAsset(admin, router, STATICS);
        vm.stopBroadcast();
    }

    function _enableAsset(TestnetRouterAdmin admin, OperatorFeeRouter router, address asset)
        private
    {
        if (!router.isRewardAsset(asset)) {
            admin.registerRewardAsset(asset);
        } else if (!router.rewardAssetEnabled(asset)) {
            admin.setRewardAssetEnabled(asset, true);
        }
    }
}
