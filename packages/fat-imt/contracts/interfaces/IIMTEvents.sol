// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IIMTEvents {
    event NewLeaf(uint256 indexed treeId, uint256 indexed index, uint256 indexed leaf);
    event UpdatedLeaf(uint256 indexed treeId, uint256 indexed index, uint256 indexed newLeaf, uint256 oldLeaf);
    event RepeatedLeafs(uint256 indexed treeId, uint256 indexed startIndex, uint256 nextIndex, uint256 indexed leaf);
    event NewTree(uint256 indexed treeId);
    event NewRoot(uint256 indexed treeId, uint256 indexed root, uint256 size);
}
