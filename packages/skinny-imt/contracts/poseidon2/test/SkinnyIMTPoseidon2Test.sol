// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {SkinnyIMTPoseidon2, SkinnyIMTData} from "../SkinnyIMTPoseidon2.sol";
// TODO move here
import {TreeEmpty} from "../../InternalSkinnyIMT.sol";

contract SkinnyIMTPoseidon2Test {
    SkinnyIMTData internal data;

    constructor() {
        SkinnyIMTPoseidon2.init(data);
    }

    function insert(uint256 leaf) external {
        SkinnyIMTPoseidon2.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2.insertMany(data, leaves);
    }

    function insertManyRepeated(uint256 value, uint256 amount) external {
        SkinnyIMTPoseidon2.insertManyRepeated(data, value, amount);
    }

    function precomputeRepeatedCache(uint256 value, uint256 upToLevel) external {
        SkinnyIMTPoseidon2.precomputeRepeatedCache(data, value, upToLevel);
    }

    function size() external view returns (uint256) {
        return data.size;
    }

    function depth() external view returns (uint256) {
        return data.depth;
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256 index, uint256[] calldata siblingNodes) external {
        SkinnyIMTPoseidon2.update(data, oldLeaf, newLeaf, index, siblingNodes);
    }

    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external {
        SkinnyIMTPoseidon2.updateMany(data, oldLeaves, newLeaves, leafIndexes, proofSiblings);
    }

    // verify/verifyMany are wrapped as state-changing (event-emitting) txs rather than
    // plain `view` so they appear in the hardhat gas report. Tests read the boolean
    // result via `.staticCall` and send the real tx to record gas.
    event VerifyResult(bool result);
    event VerifyManyResult(bool result);

    function verify(uint256 leaf, uint256 index, uint256[] calldata siblingsNodes) external returns (bool) {
        uint256 _currentRoot = SkinnyIMTPoseidon2.root(data);
        uint256 _provenRoot = SkinnyIMTPoseidon2.proofToRoot(data.depth, data.size, leaf, index, siblingsNodes);
        bool result = _currentRoot == _provenRoot;
        emit VerifyResult(result);
        return result;
    }

    function verifyMany(
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) external returns (bool) {
        if (data.size == 0) {
            revert TreeEmpty();
        }
        uint256 computedRoot = SkinnyIMTPoseidon2.proofManyToRoot(
            data.depth,
            data.size - 1,
            leaves,
            leafIndexes,
            proofSiblings
        );
        bool result = computedRoot == SkinnyIMTPoseidon2.root(data);
        emit VerifyManyResult(result);
        return result;
    }

    function root() public view returns (uint256) {
        return SkinnyIMTPoseidon2.root(data);
    }
}
