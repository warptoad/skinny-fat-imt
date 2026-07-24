// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

import {InternalFatIMTStorage, FatIMTDataFullNode} from "../InternalFatIMTStorage.sol";

library FatIMTPoseidonWriteFullNode {
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function init(FatIMTDataFullNode storage self) public returns (uint256) {
        return InternalFatIMTStorage._init(self);
    }

    function reset(FatIMTDataFullNode storage self) internal {
        InternalFatIMTStorage._reset(self);
    }

    // getNodes and getLeaves both live in FatIMTPoseidonRead to keep this library under the EIP-170
    // size limit (getNodes reads `.treeData`; getLeaves takes the whole full-node struct for `leaves`).

    function insert(FatIMTDataFullNode storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalFatIMTStorage._insertBN254(self, leaf, hasher);
    }

    function insertMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTStorage._insertManyBN254(self, leaves, hasher);
    }

    function insertManyRepeated(
        FatIMTDataFullNode storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTStorage._insertManyRepeatedBN254(self, value, amount, hasher);
    }

    function precomputeRepeatedCache(FatIMTDataFullNode storage self, uint256 value, uint256 upToLevel) internal {
        return InternalFatIMTStorage._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(
        FatIMTDataFullNode storage self,
        uint256 newLeaf,
        uint256 leafIndex
    ) public returns (uint256, uint256) {
        return InternalFatIMTStorage._updateBN254(self, newLeaf, leafIndex, hasher);
    }

    function updateMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256, uint256[] memory) {
        return InternalFatIMTStorage._updateManyBN254(self, newLeaves, leafIndexes, hasher);
    }
}
