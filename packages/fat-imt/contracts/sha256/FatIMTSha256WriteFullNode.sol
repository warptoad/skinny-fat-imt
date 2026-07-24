// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalFatIMTStorage, FatIMTDataFullNode} from "../InternalFatIMTStorage.sol";

library FatIMTSha256WriteFullNode {
    // sha256 is a built-in precompile (address 0x02); no external deployment needed.
    // Uses the non-field-checked (non-BN254) variants: sha256 outputs span the full uint256
    // range, so leaves and siblings are never required to be in the snark field.
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function init(FatIMTDataFullNode storage self) public returns (uint256) {
        return InternalFatIMTStorage._init(self);
    }

    function reset(FatIMTDataFullNode storage self) internal {
        InternalFatIMTStorage._reset(self);
    }

    // getNodes and getLeaves both live in FatIMTSha256Read to keep this library under the EIP-170
    // size limit (getNodes reads `.treeData`; getLeaves takes the whole full-node struct for `leaves`).

    function insert(FatIMTDataFullNode storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalFatIMTStorage._insert(self, leaf, hasher);
    }

    function insertMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTStorage._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTStorage._insertManyRepeated(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(FatIMTDataFullNode storage self, uint256 value, uint256 upToLevel) internal {
        return InternalFatIMTStorage._precomputeRepeatedCache(self, value, upToLevel, hasher);
    }

    function update(
        FatIMTDataFullNode storage self,
        uint256 newLeaf,
        uint256 leafIndex
    ) public returns (uint256, uint256) {
        return InternalFatIMTStorage._update(self, newLeaf, leafIndex, hasher);
    }

    function updateMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256, uint256[] memory) {
        return InternalFatIMTStorage._updateMany(self, newLeaves, leafIndexes, hasher);
    }
}
