// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { LibLotteryStorage } from "../src/libraries/LibLotteryStorage.sol";

contract LotteryStorageHarness {
    function writeDomains(address asset, address guardian) external {
        LibLotteryStorage.gameStorage().nextRoundId = 11;
        LibLotteryStorage.integrationStorage().currentVersion = 22;
        LibLotteryStorage.accountingStorage().assetAccounting[asset].treasuryAvailable = 33;
        LibLotteryStorage.governanceStorage().guardian = guardian;
        LibLotteryStorage.reentrancyStorage().status = 44;
    }

    function writeAdmissionState(address asset, uint64 configVersion, uint256 activeRoundId)
        external
    {
        LibLotteryStorage.gameStorage().activeRoundForConfig[configVersion] = activeRoundId;
        LibLotteryStorage.accountingStorage().admittedPaymentToken[asset] = true;
    }

    function activeRoundForConfig(uint64 configVersion) external view returns (uint256) {
        return LibLotteryStorage.gameStorage().activeRoundForConfig[configVersion];
    }

    function admittedPaymentToken(address asset) external view returns (bool) {
        return LibLotteryStorage.accountingStorage().admittedPaymentToken[asset];
    }

    function readDomains(address asset)
        external
        view
        returns (
            uint256 roundId,
            uint64 integrationVersion,
            uint256 treasuryAvailable,
            address guardian,
            uint256 reentrancyStatus
        )
    {
        roundId = LibLotteryStorage.gameStorage().nextRoundId;
        integrationVersion = LibLotteryStorage.integrationStorage().currentVersion;
        treasuryAvailable =
        LibLotteryStorage.accountingStorage().assetAccounting[asset].treasuryAvailable;
        guardian = LibLotteryStorage.governanceStorage().guardian;
        reentrancyStatus = LibLotteryStorage.reentrancyStorage().status;
    }
}

contract LotteryStorageTest is Test {
    function test_UsesIndependentNamespacedStorageDomains() public {
        LotteryStorageHarness harness = new LotteryStorageHarness();
        address asset = makeAddr("asset");
        address guardian = makeAddr("guardian");

        harness.writeDomains(asset, guardian);
        (
            uint256 roundId,
            uint64 integrationVersion,
            uint256 treasuryAvailable,
            address storedGuardian,
            uint256 reentrancyStatus
        ) = harness.readDomains(asset);

        assertEq(roundId, 11);
        assertEq(integrationVersion, 22);
        assertEq(treasuryAvailable, 33);
        assertEq(storedGuardian, guardian);
        assertEq(reentrancyStatus, 44);

        harness.writeAdmissionState(asset, 55, 66);
        assertEq(harness.activeRoundForConfig(55), 66);
        assertTrue(harness.admittedPaymentToken(asset));

        (roundId, integrationVersion, treasuryAvailable, storedGuardian, reentrancyStatus) =
            harness.readDomains(asset);
        assertEq(roundId, 11);
        assertEq(integrationVersion, 22);
        assertEq(treasuryAvailable, 33);
        assertEq(storedGuardian, guardian);
        assertEq(reentrancyStatus, 44);
    }
}
