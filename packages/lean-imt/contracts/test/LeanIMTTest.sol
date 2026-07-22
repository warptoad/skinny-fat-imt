// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {LeanIMT, LeanIMTData} from "../LeanIMT.sol";

contract LeanIMTTest {
    LeanIMTData public data;

    function insert(uint256 leaf) external {
        LeanIMT.insert(data, leaf);
    }

    function insertMany(uint256[] calldata leaves) external {
        LeanIMT.insertMany(data, leaves);
    }

    function update(uint256 oldLeaf, uint256 newLeaf, uint256[] calldata siblingNodes) external {
        LeanIMT.update(data, oldLeaf, newLeaf, siblingNodes);
    }

    // LeanIMT has no batch-update primitive; loop single updates. Each update consumes a proof for
    // the tree state left by the previous one, so the caller supplies the sibling arrays in order.
    // Stand-in for skinny/fat's `updateMany`, kept separate so it doesn't pollute the `update` row.
    function updateMany(
        uint256[] calldata oldLeaves,
        uint256[] calldata newLeaves,
        uint256[][] calldata siblingNodes
    ) external {
        for (uint256 i = 0; i < oldLeaves.length; ) {
            LeanIMT.update(data, oldLeaves[i], newLeaves[i], siblingNodes[i]);
            unchecked {
                ++i;
            }
        }
    }

    // LeanIMT has no repeated-insert path and forbids zero/duplicate leaves, so this stand-in just
    // batches `amount` distinct leaves through insertMany — the closest "add N leaves in one call"
    // equivalent to skinny/fat's `insertManyRepeated` for a gas comparison. Kept separate so it
    // doesn't pollute the `insertMany` row.
    function insertManyRepeated(uint256 value, uint256 amount) external {
        uint256[] memory leaves = new uint256[](amount);
        for (uint256 i = 0; i < amount; ) {
            leaves[i] = value + i;
            unchecked {
                ++i;
            }
        }
        LeanIMT.insertMany(data, leaves);
    }

    function remove(uint256 leaf, uint256[] calldata siblingNodes) external {
        LeanIMT.remove(data, leaf, siblingNodes);
    }

    function has(uint256 leaf) external view returns (bool) {
        return LeanIMT.has(data, leaf);
    }

    function indexOf(uint256 leaf) external view returns (uint256) {
        return LeanIMT.indexOf(data, leaf);
    }

    function root() public view returns (uint256) {
        return LeanIMT.root(data);
    }
}
