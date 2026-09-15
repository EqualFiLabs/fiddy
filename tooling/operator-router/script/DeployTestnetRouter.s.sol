// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { OperatorFeeRouter } from "operator-fee-router/src/OperatorFeeRouter.sol";
import { TestnetRouterAdmin } from "../src/TestnetRouterAdmin.sol";

contract DeployTestnetRouter is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant OPERATOR_COLLECTION = 0x6c9197347161FC140a209175849d443FeaAF509c;
    address internal constant ACTIVATION_REGISTRY = 0x8cE462A801726FA030e06264f3423Be2Ae8d6414;
    address internal constant OPERATOR_VAULT = 0x8D3a32ddF8bD529EC847457eC79620D2870FFdc4;

    error UnexpectedDeployer(address actual);
    error WrongChain(uint256 actual);

    function run() external returns (TestnetRouterAdmin admin, OperatorFeeRouter router) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("ROUTER_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert UnexpectedDeployer(deployer);

        vm.startBroadcast(deployerKey);
        admin = new TestnetRouterAdmin(deployer);
        router = new OperatorFeeRouter(
            OPERATOR_COLLECTION, ACTIVATION_REGISTRY, OPERATOR_VAULT, address(admin)
        );
        admin.bindRouter(address(router));
        vm.stopBroadcast();
    }
}
