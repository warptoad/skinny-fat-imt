// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";
import {InternalFatIMTCore, FatIMTData, MultiProof} from "../../InternalFatIMTCore.sol";

// TEST-ONLY "bare" variant: stores leaves NOWHERE (no events, no leaves array) and has NO
// init / NotInitialized guard. It calls InternalFatIMTCore directly, so it measures the pure tree-
// algorithm gas floor. NOT for production - a tree whose leaves no client can read is useless.
library FatIMTPoseidonBare {
    function hasher(uint256[2] memory input) private pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function insert(FatIMTData storage self, uint256 leaf) public returns (uint256, uint256) {
        return InternalFatIMTCore._insert(self, leaf, hasher);
    }

    function insertMany(FatIMTData storage self, uint256[] calldata leaves) public returns (uint256, uint256, uint256) {
        return InternalFatIMTCore._insertMany(self, leaves, hasher);
    }

    function insertManyRepeated(
        FatIMTData storage self,
        uint256 value,
        uint256 amount
    ) public returns (uint256, uint256, uint256) {
        return InternalFatIMTCore._insertManyRepeated(self, value, amount, hasher);
    }

    function update(FatIMTData storage self, uint256 newLeaf, uint256 leafIndex) public returns (uint256, uint256) {
        return InternalFatIMTCore._update(self, newLeaf, leafIndex, hasher);
    }

    function updateMany(
        FatIMTData storage self,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes
    ) public returns (uint256, uint256[] memory) {
        return InternalFatIMTCore._updateMany(self, newLeaves, leafIndexes, hasher);
    }

    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMTCore._root(self);
    }
}

contract FatIMTPoseidonBareTest {
    FatIMTData internal data;

    function insert(uint256 leaf) external {
        FatIMTPoseidonBare.insert(data, leaf);
    }
    function insertMany(uint256[] calldata leaves) external {
        FatIMTPoseidonBare.insertMany(data, leaves);
    }
    function insertManyRepeated(uint256 value, uint256 amount) external {
        FatIMTPoseidonBare.insertManyRepeated(data, value, amount);
    }
    function update(uint256 newLeaf, uint256 index) external {
        FatIMTPoseidonBare.update(data, newLeaf, index);
    }
    function updateMany(uint256[] calldata newLeaves, uint256[] calldata leafIndexes) external {
        FatIMTPoseidonBare.updateMany(data, newLeaves, leafIndexes);
    }
    function root() public view returns (uint256) {
        return FatIMTPoseidonBare.root(data);
    }
    function size() external view returns (uint256) {
        return data.size;
    }
}
