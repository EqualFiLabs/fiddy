// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LibDiamond} from "../../../../src/libraries/LibDiamond.sol";
import {FacetCut,FacetCutAction} from "../../../../src/shared/DiamondTypes.sol";
contract DiamondModel {
 constructor(){LibDiamond.initializeAuthority(msg.sender);}
 function step(address facet,uint8 action,bytes4 selector) external {
  LibDiamond.enforceAuthority(); require(!LibDiamond.cutsDisabled());require(action<=2);
  FacetCut[] memory cuts=new FacetCut[](1);bytes4[] memory selectors=new bytes4[](1);selectors[0]=selector;
  cuts[0]=FacetCut(facet,FacetCutAction(action),selectors);LibDiamond.diamondCut(cuts,address(0),"");
 }
 function finalize() external {LibDiamond.enforceAuthority();LibDiamond.disableCuts();}
 function authority() external view returns(address){return LibDiamond.authority();}
 function frozen() external view returns(bool){return LibDiamond.cutsDisabled();}
 function target(bytes4 s) external view returns(address){return LibDiamond.diamondStorage().selectorData[s].facet;}
 function selectorPosition(bytes4 s) external view returns(uint256){return LibDiamond.diamondStorage().selectorData[s].selectorPosition;}
 function selectorCount(address a) external view returns(uint256){return LibDiamond.diamondStorage().facetData[a].selectors.length;}
 function lastSelector(address a) external view returns(bytes4){LibDiamond.FacetData storage f=LibDiamond.diamondStorage().facetData[a];return f.selectors.length==0?bytes4(0):f.selectors[f.selectors.length-1];}
 function facetPosition(address a) external view returns(uint256){return LibDiamond.diamondStorage().facetData[a].facetPosition;}
 function lastFacet() external view returns(address){address[] storage a=LibDiamond.diamondStorage().facetAddresses;return a.length==0?address(0):a[a.length-1];}
 function numFacets() external view returns(uint256){return LibDiamond.diamondStorage().facetAddresses.length;}
 function selectorSound(bytes4 s) external view returns(bool){LibDiamond.DiamondStorage storage d=LibDiamond.diamondStorage();address a=d.selectorData[s].facet;uint256 i=d.selectorData[s].selectorPosition;return a==address(0)||(i<d.facetData[a].selectors.length&&d.facetData[a].selectors[i]==s);}
 function reverseSound(address a,uint256 i) external view returns(bool){LibDiamond.DiamondStorage storage d=LibDiamond.diamondStorage();if(i>=d.facetData[a].selectors.length)return true;bytes4 s=d.facetData[a].selectors[i];return d.selectorData[s].facet==a&&d.selectorData[s].selectorPosition==i;}
 function facetSound(address a) external view returns(bool){LibDiamond.DiamondStorage storage d=LibDiamond.diamondStorage();uint256 i=d.facetData[a].facetPosition;return d.facetData[a].selectors.length==0||(i<d.facetAddresses.length&&d.facetAddresses[i]==a);}
 function listSound(uint256 i) external view returns(bool){LibDiamond.DiamondStorage storage d=LibDiamond.diamondStorage();if(i>=d.facetAddresses.length)return true;address a=d.facetAddresses[i];return a!=address(0)&&d.facetData[a].selectors.length!=0&&d.facetData[a].facetPosition==i;}
}
