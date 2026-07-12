// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibPoseidon2Yul} from "poseidon2-evm/src/bn254/yul/LibPoseidon2Yul.sol";

import {InternalFatIMTStorage, FatIMTDataFullNode} from "../InternalFatIMTStorage.sol";

library FatIMTPoseidon2FullNode {
    using InternalFatIMTStorage for *;

    function hasher(uint256[2] memory leaves) public pure returns (uint256) {
        return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
    }

    function init(FatIMTDataFullNode storage self) public returns (uint256) {
        return InternalFatIMTStorage._init(self);
    }

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

    function precomputeRepeatedCache(FatIMTDataFullNode storage self, uint256 value, uint256 upToLevel) public {
        return InternalFatIMTStorage._precomputeRepeatedCacheBN254(self, value, upToLevel, hasher);
    }

    function update(FatIMTDataFullNode storage self, uint256 newLeaf, uint256 index) public returns (uint256) {
        return InternalFatIMTStorage._updateBN254(self, newLeaf, index, hasher);
    }

    function updateMany(
        FatIMTDataFullNode storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256) {
        return InternalFatIMTStorage._updateManyBN254(self, newLeaves, leafIndexes, hasher);
    }

    function root(FatIMTDataFullNode storage self) public view returns (uint256) {
        return InternalFatIMTStorage._root(self);
    }
}
