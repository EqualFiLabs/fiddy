// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { StaticsLotteryDiamond } from "../src/StaticsLotteryDiamond.sol";
import { DiamondCutFacet } from "../src/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../src/facets/DiamondLoupeFacet.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "../src/interfaces/IDiamondLoupe.sol";
import { LibDiamond } from "../src/libraries/LibDiamond.sol";
import { Errors } from "../src/shared/Errors.sol";
import { Facet, FacetCut, FacetCutAction } from "../src/shared/DiamondTypes.sol";

library LotteryDiamondTestStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("statics.lottery.test.storage.v1");

    struct Layout {
        uint256 value;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}

contract ValueFacet {
    function setValue(uint256 newValue) external {
        LotteryDiamondTestStorage.layout().value = newValue;
    }

    function value() external view returns (uint256) {
        return LotteryDiamondTestStorage.layout().value;
    }
}

contract IncrementedValueFacet {
    function value() external view returns (uint256) {
        return LotteryDiamondTestStorage.layout().value + 1;
    }
}

contract CutFinalizationFacet {
    function finalizeCuts() external {
        LibDiamond.enforceAuthority();
        LibDiamond.disableCuts();
    }

    function cutsDisabled() external view returns (bool) {
        return LibDiamond.cutsDisabled();
    }
}

contract ValueInitializer {
    function initializeValue(uint256 value) external {
        LotteryDiamondTestStorage.layout().value = value;
    }

    function failInitialization() external pure {
        revert("initializer failed");
    }
}

contract LotteryDiamondTest is Test {
    address internal authority = makeAddr("authority");
    address internal outsider = makeAddr("outsider");

    StaticsLotteryDiamond internal diamond;
    DiamondCutFacet internal cutFacet;
    DiamondLoupeFacet internal loupeFacet;
    ValueFacet internal valueFacet;
    CutFinalizationFacet internal finalizationFacet;

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        diamond = new StaticsLotteryDiamond(authority, address(cutFacet));
        loupeFacet = new DiamondLoupeFacet();
        valueFacet = new ValueFacet();
        finalizationFacet = new CutFinalizationFacet();

        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = _cut(address(loupeFacet), FacetCutAction.Add, _loupeSelectors());

        bytes4[] memory valueSelectors = new bytes4[](2);
        valueSelectors[0] = ValueFacet.setValue.selector;
        valueSelectors[1] = ValueFacet.value.selector;
        cuts[1] = _cut(address(valueFacet), FacetCutAction.Add, valueSelectors);

        bytes4[] memory finalizationSelectors = new bytes4[](2);
        finalizationSelectors[0] = CutFinalizationFacet.finalizeCuts.selector;
        finalizationSelectors[1] = CutFinalizationFacet.cutsDisabled.selector;
        cuts[2] = _cut(address(finalizationFacet), FacetCutAction.Add, finalizationSelectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_ConstructorInstallsCutFacet() public view {
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(IDiamondCut.diamondCut.selector),
            address(cutFacet)
        );
    }

    function test_ConstructorRejectsInvalidAuthorityAndCutFacet() public {
        vm.expectRevert(Errors.InvalidAddress.selector);
        new StaticsLotteryDiamond(address(0), address(cutFacet));

        vm.expectRevert(abi.encodeWithSelector(Errors.NoCode.selector, outsider));
        new StaticsLotteryDiamond(authority, outsider);
    }

    function test_RoutesCallsAndEnumeratesFacets() public {
        ValueFacet(address(diamond)).setValue(41);
        assertEq(ValueFacet(address(diamond)).value(), 41);

        IDiamondLoupe loupe = IDiamondLoupe(address(diamond));
        assertEq(loupe.facetAddresses().length, 4);
        assertEq(loupe.facetFunctionSelectors(address(valueFacet)).length, 2);
        assertEq(loupe.facetAddress(ValueFacet.value.selector), address(valueFacet));

        Facet[] memory facets = loupe.facets();
        assertEq(facets.length, 4);
        for (uint256 i; i < facets.length; ++i) {
            assertEq(
                facets[i].functionSelectors.length,
                loupe.facetFunctionSelectors(facets[i].facetAddress).length
            );
        }
    }

    function test_ReplacesSelectorWithoutChangingNamespacedState() public {
        ValueFacet(address(diamond)).setValue(41);
        IncrementedValueFacet replacement = new IncrementedValueFacet();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.value.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _cut(address(replacement), FacetCutAction.Replace, selectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        assertEq(IncrementedValueFacet(address(diamond)).value(), 42);
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(ValueFacet.value.selector),
            address(replacement)
        );
    }

    function test_RemovesSelectorWithoutCorruptingOtherRouting() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.setValue.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _cut(address(0), FacetCutAction.Remove, selectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        IDiamondLoupe loupe = IDiamondLoupe(address(diamond));
        assertEq(loupe.facetAddress(ValueFacet.setValue.selector), address(0));
        assertEq(loupe.facetAddress(ValueFacet.value.selector), address(valueFacet));
        assertEq(loupe.facetFunctionSelectors(address(valueFacet)).length, 1);
    }

    function test_ExecutesAuthorizedInitializer() public {
        ValueInitializer initializer = new ValueInitializer();
        FacetCut[] memory cuts = new FacetCut[](0);

        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts, address(initializer), abi.encodeCall(ValueInitializer.initializeValue, (73))
            );

        assertEq(ValueFacet(address(diamond)).value(), 73);
    }

    function test_RejectsUnauthorizedCut() public {
        FacetCut[] memory cuts = new FacetCut[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, outsider));
        vm.prank(outsider);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_RejectsInvalidInitializationCombinations() public {
        FacetCut[] memory cuts = new FacetCut[](0);

        vm.expectRevert(Errors.UnexpectedInitializationData.selector);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), hex"01");

        ValueInitializer initializer = new ValueInitializer();
        vm.expectRevert(Errors.EmptyInitializationData.selector);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(initializer), "");
    }

    function test_WrapsInitializerFailureWithoutChangingState() public {
        ValueInitializer initializer = new ValueInitializer();
        FacetCut[] memory cuts = new FacetCut[](0);
        bytes memory reason = abi.encodeWithSignature("Error(string)", "initializer failed");

        vm.expectRevert(abi.encodeWithSelector(Errors.InitializationFailed.selector, reason));
        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts, address(initializer), abi.encodeCall(ValueInitializer.failInitialization, ())
            );

        assertEq(ValueFacet(address(diamond)).value(), 0);
    }

    function test_RejectsDuplicateAndMissingSelectors() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.value.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _cut(address(valueFacet), FacetCutAction.Add, selectors);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.SelectorAlreadyExists.selector, ValueFacet.value.selector)
        );
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        selectors[0] = bytes4(keccak256("missing()"));
        cuts[0] = _cut(address(0), FacetCutAction.Remove, selectors);
        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorDoesNotExist.selector, selectors[0]));
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_RejectsMalformedCuts() public {
        bytes4[] memory emptySelectors = new bytes4[](0);
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _cut(address(valueFacet), FacetCutAction.Add, emptySelectors);

        vm.expectRevert(Errors.EmptySelectors.selector);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ValueFacet.value.selector;
        cuts[0] = _cut(address(valueFacet), FacetCutAction.Replace, selectors);
        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorUnchanged.selector, selectors[0]));
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        cuts[0] = _cut(address(valueFacet), FacetCutAction.Remove, selectors);
        vm.expectRevert(Errors.InvalidAddress.selector);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_FinalizationIrreversiblyDisablesCuts() public {
        vm.prank(authority);
        CutFinalizationFacet(address(diamond)).finalizeCuts();
        assertTrue(CutFinalizationFacet(address(diamond)).cutsDisabled());

        FacetCut[] memory cuts = new FacetCut[](0);
        vm.expectRevert(Errors.CutsDisabled.selector);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        vm.expectRevert(Errors.AlreadyFinalized.selector);
        vm.prank(authority);
        CutFinalizationFacet(address(diamond)).finalizeCuts();
    }

    function test_RejectsNativeEthThroughReceiveAndFallback() public {
        vm.deal(address(this), 2 wei);

        (bool receiveSuccess, bytes memory receiveReason) =
            address(diamond).call{ value: 1 wei }("");
        assertFalse(receiveSuccess);
        assertEq(receiveReason, abi.encodeWithSelector(Errors.NativeEthRejected.selector));

        (bool fallbackSuccess, bytes memory fallbackReason) =
            address(diamond).call{ value: 1 wei }(abi.encodeCall(ValueFacet.value, ()));
        assertFalse(fallbackSuccess);
        assertEq(fallbackReason, abi.encodeWithSelector(Errors.NativeEthRejected.selector));
        assertEq(address(diamond).balance, 0);
    }

    function test_RejectsUnknownSelector() public {
        bytes4 selector = bytes4(keccak256("unknown()"));
        (bool success, bytes memory reason) =
            address(diamond).call(abi.encodeWithSelector(selector));

        assertFalse(success);
        assertEq(reason, abi.encodeWithSelector(Errors.FunctionNotFound.selector, selector));
    }

    function _loupeSelectors() private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
    }

    function _cut(address facet, FacetCutAction action, bytes4[] memory selectors)
        private
        pure
        returns (FacetCut memory)
    {
        return FacetCut(facet, action, selectors);
    }
}
