// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2WriteArchiveNode, SkinnyIMTData} from "../SkinnyIMTPoseidon2WriteArchiveNode.sol";
import {SkinnyIMTPoseidon2Read} from "../SkinnyIMTPoseidon2Read.sol";

// verify/verifyMany are wrapped as state-changing (event-emitting) txs rather than
// plain `view` so they appear in the hardhat gas report. Tests read the boolean
// result via `.staticCall` and send the real tx to record gas.
event VerifyResult(bool result);
event VerifyManyResult(bool result);

contract SkinnyIMTPoseidon2Test {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMTPoseidon2WriteArchiveNode.init(data);
    }

    function reset() external {
        SkinnyIMTPoseidon2WriteArchiveNode.reset(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon2WriteArchiveNode.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteArchiveNode.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon2WriteArchiveNode.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMTPoseidon2WriteArchiveNode.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon2WriteArchiveNode.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2WriteArchiveNode.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external returns (bool) {
        bool result = SkinnyIMTPoseidon2Read.verify(data, leaf, index, siblingsNodes);
        emit VerifyResult(result);
        return result;
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external returns (bool) {
        bool result = SkinnyIMTPoseidon2Read.verifyMany(data, leaves, leafIndexes, proofSiblings);
        emit VerifyManyResult(result);
        return result;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon2Read.root(data);
    }
}
