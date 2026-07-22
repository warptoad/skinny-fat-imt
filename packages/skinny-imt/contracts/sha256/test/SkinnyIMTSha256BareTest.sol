// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTCore, SkinnyIMTData, MultiProof} from "../../InternalSkinnyIMTCore.sol";

// TEST-ONLY "bare" variant: stores leaves NOWHERE (no events, no leaves array) and has NO
// init / NotInitialized guard. It calls InternalSkinnyIMTCore directly, so it measures the pure tree-
// algorithm gas floor. NOT for production - a tree whose leaves no client can read is useless.
library SkinnyIMTSha256Bare {
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return uint256(sha256(abi.encodePacked(input[0], input[1])));
    }

    function insert(SkinnyIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalSkinnyIMTCore._insert(self, leaf, hasher);
    }

    function insertMany(
        SkinnyIMTData storage self,
        uint256[] calldata leaves
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTCore._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        SkinnyIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalSkinnyIMTCore._insertManyRepeated(self, value, amount, hasher);
    }

    function update(
        SkinnyIMTData storage self,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        return InternalSkinnyIMTCore._update(self, oldLeaf, newLeaf, leafIndex, proofSiblings, hasher);
    }

    function updateMany(
        SkinnyIMTData storage self,
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public returns (uint256) {
        MultiProof memory proof = MultiProof(self.depth, self.size - 1, leafIndexes, proofSiblings);
        return InternalSkinnyIMTCore._updateMany(self, oldLeaves, newLeaves, proof, hasher);
    }

    function root(SkinnyIMTData storage self) public view returns (uint256) {
        return InternalSkinnyIMTCore._root(self);
    }
}

contract SkinnyIMTSha256BareTest {
    SkinnyIMTData internal data;

    function insert(uint256 leaf) external {
        SkinnyIMTSha256Bare.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTSha256Bare.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTSha256Bare.insertManyRepeated(data, value, amount);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTSha256Bare.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTSha256Bare.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function root() public view returns (uint256) {
        return SkinnyIMTSha256Bare.root(data);
    }

    function size() external view returns (uint256) {
        return data.size;
    }
}
