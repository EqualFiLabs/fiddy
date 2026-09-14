// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { StaticsLotteryDiamond } from "../../src/StaticsLotteryDiamond.sol";
import { ClaimsFacet } from "../../src/facets/ClaimsFacet.sol";
import { DiamondCutFacet } from "../../src/facets/DiamondCutFacet.sol";
import { GovernanceFacet } from "../../src/facets/GovernanceFacet.sol";
import { LotteryFacet } from "../../src/facets/LotteryFacet.sol";
import { RevenueFacet } from "../../src/facets/RevenueFacet.sol";
import { SettlementFacet } from "../../src/facets/SettlementFacet.sol";
import { IDiamondCut } from "../../src/interfaces/IDiamondCut.sol";
import { IClaims } from "../../src/interfaces/IClaims.sol";
import { IEqualFiDrandRegistry } from "../../src/interfaces/IEqualFiDrandRegistry.sol";
import { IGovernance } from "../../src/interfaces/IGovernance.sol";
import { ILottery } from "../../src/interfaces/ILottery.sol";
import { IRevenue } from "../../src/interfaces/IRevenue.sol";
import { ISettlement } from "../../src/interfaces/ISettlement.sol";
import { LibLotteryStorage } from "../../src/libraries/LibLotteryStorage.sol";
import { LibReentrancy } from "../../src/libraries/LibReentrancy.sol";
import { LibTicketRanges } from "../../src/libraries/LibTicketRanges.sol";
import { FacetCut, FacetCutAction } from "../../src/shared/DiamondTypes.sol";
import {
    AssetAccounting,
    IntegrationConfig,
    LotteryConfig,
    Round,
    TicketRange
} from "../../src/shared/Types.sol";

contract IntegrationToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract ConfiguredDrandRegistry is IEqualFiDrandRegistry {
    mapping(uint64 round => bool cached) internal signatures;
    mapping(uint64 round => bytes32 randomness) internal randomness;
    mapping(uint64 round => uint64 timestamp) internal postingTimes;
    mapping(uint64 round => bytes32 proofHash) internal expectedProofHashes;
    bool internal returnWithoutStoring;

    error InvalidProof();
    error ProofTooEarly();

    function expectProof(uint64 round, bytes calldata proof) external {
        expectedProofHashes[round] = keccak256(proof);
    }

    function setReturnWithoutStoring(bool enabled) external {
        returnWithoutStoring = enabled;
    }

    function cache(uint64 round, bytes32 value, uint64 timestamp) external {
        signatures[round] = true;
        randomness[round] = value;
        postingTimes[round] = timestamp;
    }

    function firstRoundAfter(uint256 timestamp) external pure returns (uint64) {
        return uint64(timestamp / 3 + 1);
    }

    function roundTime(uint64 round) public pure returns (uint64) {
        return round * 3;
    }

    function hasSig(uint64 round) external view returns (bool) {
        return signatures[round];
    }

    function randomnessOf(uint64 round) external view returns (bytes32) {
        return randomness[round];
    }

    function postedAt(uint64 round) external view returns (uint64) {
        return postingTimes[round];
    }

    function postSig(uint64 round, bytes calldata signature) external returns (bool newlyStored) {
        if (signatures[round]) return false;
        if (returnWithoutStoring) return false;
        if (block.timestamp < roundTime(round)) revert ProofTooEarly();
        if (
            expectedProofHashes[round] == bytes32(0)
                || keccak256(signature) != expectedProofHashes[round]
        ) {
            revert InvalidProof();
        }

        signatures[round] = true;
        randomness[round] = keccak256(abi.encode(round, signature));
        postingTimes[round] = uint64(block.timestamp);
        return true;
    }
}

contract IntegrationEndpoint {
    using SafeERC20 for IERC20;

    bool public bootstrapFinalized = true;
    uint256 public totalEffectiveWeight = 1;
    bool public rejectRewards;
    mapping(address asset => bool registered) internal registeredAssets;
    mapping(address asset => bool enabled) internal enabledAssets;
    mapping(address asset => uint256 amount) public totalAdded;

    error RewardsRejected();

    function setBootstrapFinalized(bool finalized) external {
        bootstrapFinalized = finalized;
    }

    function setTotalEffectiveWeight(uint256 weight) external {
        totalEffectiveWeight = weight;
    }

    function setAsset(address asset, bool registered, bool enabled) external {
        registeredAssets[asset] = registered;
        enabledAssets[asset] = enabled;
    }

    function setRejectRewards(bool rejected) external {
        rejectRewards = rejected;
    }

    function isRewardAsset(address asset) external view returns (bool) {
        return registeredAssets[asset];
    }

    function rewardAssetEnabled(address asset) external view returns (bool) {
        return enabledAssets[asset];
    }

    function addRewards(address asset, uint256 amount) external {
        if (rejectRewards) revert RewardsRejected();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        totalAdded[asset] += amount;
    }
}

contract IntegrationInitializer {
    function initialize() external {
        LibReentrancy.initialize();
    }
}

contract IntegrationStateFacet {
    function roundState(uint256 roundId) external view returns (Round memory) {
        return LibLotteryStorage.gameStorage().rounds[roundId];
    }

    function activeRoundCount() external view returns (uint256) {
        return LibLotteryStorage.gameStorage().activeRoundCount;
    }

    function refundCredit(uint256 roundId, address account) external view returns (uint256) {
        return LibLotteryStorage.gameStorage().refundCredit[roundId][account];
    }

    function purchaseEntryCount(uint256 roundId) external view returns (uint256) {
        return LibLotteryStorage.gameStorage().entries[roundId].length;
    }

    function purchaseEntry(uint256 roundId, uint256 index)
        external
        view
        returns (TicketRange memory)
    {
        return LibLotteryStorage.gameStorage().entries[roundId][index];
    }

    function ticketOwner(uint256 roundId, uint32 ticket) external view returns (address) {
        return
            LibTicketRanges.ownerOfTicket(LibLotteryStorage.gameStorage().entries[roundId], ticket);
    }

    function assetAccounting(address asset) external view returns (AssetAccounting memory) {
        return LibLotteryStorage.accountingStorage().assetAccounting[asset];
    }

    function pendingOperatorRevenue(uint64 integrationVersion, address asset)
        external
        view
        returns (uint256)
    {
        return
            LibLotteryStorage.accountingStorage().pendingOperatorRevenue[integrationVersion][asset];
    }

    function finalizerCredit(address asset, address account) external view returns (uint256) {
        return LibLotteryStorage.accountingStorage().finalizerCredits[asset][account];
    }
}

abstract contract LotteryIntegrationSetup is Test {
    address internal authority = makeAddr("authority");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal finalizer = makeAddr("finalizer");

    StaticsLotteryDiamond internal diamond;
    IGovernance internal governance;
    ILottery internal lottery;
    ISettlement internal settlement;
    IClaims internal claims;
    IRevenue internal revenue;
    IntegrationStateFacet internal stateView;
    IntegrationToken internal tokenA;
    IntegrationToken internal tokenB;
    ConfiguredDrandRegistry internal registry;
    IntegrationEndpoint internal router;

    function setUp() public virtual {
        vm.warp(1_000_000);
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new StaticsLotteryDiamond(authority, address(cutFacet));
        GovernanceFacet governanceFacet = new GovernanceFacet();
        LotteryFacet lotteryFacet = new LotteryFacet();
        SettlementFacet settlementFacet = new SettlementFacet();
        ClaimsFacet claimsFacet = new ClaimsFacet();
        RevenueFacet revenueFacet = new RevenueFacet();
        IntegrationStateFacet viewFacet = new IntegrationStateFacet();
        IntegrationInitializer initializer = new IntegrationInitializer();

        FacetCut[] memory cuts = new FacetCut[](6);
        cuts[0] = _cut(address(governanceFacet), _governanceSelectors());
        cuts[1] = _cut(address(lotteryFacet), _lotterySelectors());
        cuts[2] = _cut(address(settlementFacet), _settlementSelectors());
        cuts[3] = _cut(address(claimsFacet), _claimsSelectors());
        cuts[4] = _cut(address(revenueFacet), _revenueSelectors());
        cuts[5] = _cut(address(viewFacet), _stateSelectors());
        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts, address(initializer), abi.encodeCall(IntegrationInitializer.initialize, ())
            );

        governance = IGovernance(address(diamond));
        lottery = ILottery(address(diamond));
        settlement = ISettlement(address(diamond));
        claims = IClaims(address(diamond));
        revenue = IRevenue(address(diamond));
        stateView = IntegrationStateFacet(address(diamond));
        tokenA = new IntegrationToken("Payment A", "PAYA");
        tokenB = new IntegrationToken("Payment B", "PAYB");
        registry = new ConfiguredDrandRegistry();
        router = new IntegrationEndpoint();
        router.setAsset(address(tokenA), true, true);
        router.setAsset(address(tokenB), true, true);

        vm.startPrank(authority);
        governance.setIntegrationConfig(IntegrationConfig(address(registry), address(router)));
        governance.setTreasuryRecipient(treasury);
        governance.setGuardian(guardian);
        governance.setMaxActiveRounds(2);
        governance.createLotteryConfig(_config(address(tokenA), 10, 10, 10, 1 days, 30));
        governance.setLotteryConfigEnabled(1, true);
        governance.createLotteryConfig(_config(address(tokenB), 20, 5, 5, 2 days, 0));
        governance.setLotteryConfigEnabled(2, true);
        vm.stopPrank();

        _fundAndApprove(tokenA, alice);
        _fundAndApprove(tokenA, bob);
        _fundAndApprove(tokenB, alice);
        _fundAndApprove(tokenB, bob);
    }

    function _sellOutRoundA() internal returns (uint256 roundId) {
        vm.prank(alice);
        roundId = lottery.openRound(1, 4);
        vm.prank(bob);
        lottery.buyTickets(roundId, 6);
    }

    function _prepareProof(uint256 roundId, bytes memory proof) internal {
        Round memory round = stateView.roundState(roundId);
        registry.expectProof(round.drandRound, proof);
        vm.warp(registry.roundTime(round.drandRound));
    }

    function _fundAndApprove(IntegrationToken token, address account) internal {
        token.mint(account, 10_000);
        vm.prank(account);
        token.approve(address(diamond), type(uint256).max);
    }

    function _config(
        address paymentToken,
        uint96 price,
        uint32 count,
        uint32 limit,
        uint32 duration,
        uint32 delay
    ) internal pure returns (LotteryConfig memory) {
        return LotteryConfig({
            paymentToken: paymentToken,
            ticketPrice: price,
            ticketCount: count,
            salesDuration: duration,
            randomnessDelay: delay,
            maxTicketsPerPurchase: limit,
            winnerBps: 8000,
            operatorProtocolBps: 5000,
            finalizerTip: 3
        });
    }

    function _cut(address facet, bytes4[] memory selectors)
        internal
        pure
        returns (FacetCut memory)
    {
        return FacetCut(facet, FacetCutAction.Add, selectors);
    }

    function _governanceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](13);
        selectors[0] = IGovernance.createLotteryConfig.selector;
        selectors[1] = IGovernance.setLotteryConfigEnabled.selector;
        selectors[2] = IGovernance.setMaxActiveRounds.selector;
        selectors[3] = IGovernance.integrationConfig.selector;
        selectors[4] = IGovernance.setIntegrationConfig.selector;
        selectors[5] = IGovernance.setTreasuryRecipient.selector;
        selectors[6] = IGovernance.setGuardian.selector;
        selectors[7] = IGovernance.setPaused.selector;
        selectors[8] = IGovernance.paused.selector;
        selectors[9] = IGovernance.guardian.selector;
        selectors[10] = IGovernance.treasuryRecipient.selector;
        selectors[11] = IGovernance.protocolFinalized.selector;
        selectors[12] = IGovernance.finalizeProtocol.selector;
    }

    function _lotterySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ILottery.openRound.selector;
        selectors[1] = ILottery.buyTickets.selector;
        selectors[2] = ILottery.expireRound.selector;
    }

    function _settlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ISettlement.settleRound.selector;
    }

    function _claimsSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IClaims.claimWinner.selector;
        selectors[1] = IClaims.claimRefund.selector;
        selectors[2] = IClaims.claimFinalizerTips.selector;
    }

    function _revenueSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IRevenue.flushOperatorRevenue.selector;
        selectors[1] = IRevenue.flushTreasury.selector;
        selectors[2] = IRevenue.availableTokenSurplus.selector;
        selectors[3] = IRevenue.absorbTokenSurplus.selector;
        selectors[4] = IRevenue.flushNativeSurplus.selector;
    }

    function _stateSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IntegrationStateFacet.roundState.selector;
        selectors[1] = IntegrationStateFacet.activeRoundCount.selector;
        selectors[2] = IntegrationStateFacet.refundCredit.selector;
        selectors[3] = IntegrationStateFacet.purchaseEntryCount.selector;
        selectors[4] = IntegrationStateFacet.purchaseEntry.selector;
        selectors[5] = IntegrationStateFacet.ticketOwner.selector;
        selectors[6] = IntegrationStateFacet.assetAccounting.selector;
        selectors[7] = IntegrationStateFacet.pendingOperatorRevenue.selector;
        selectors[8] = IntegrationStateFacet.finalizerCredit.selector;
    }
}
