// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

import {InternalFatIMTEvent} from "../InternalFatIMTEvent.sol";
import {FatIMTData} from "../InternalFatIMTCore.sol";
import {TreeEmpty} from "../InternalFatIMTCore.sol";
import {InternalFatIMTStorage, FatIMTDataFullNode} from "../InternalFatIMTStorage.sol";

/// @title FatIMTPoseidonRead
/// @notice Stateless proof verification (`proofToRoot` / `proofManyToRoot`) split out of
/// `FatIMTPoseidonWriteArchiveNode` and `FatIMTPoseidonWriteFullNode` to keep those libraries under the
/// EIP-170 contract size limit. Both functions take the whole proof as parameters and touch no
/// storage, so a single library serves the plain and full-node trees alike.
library FatIMTPoseidonRead {
    function hasher(uint256[2] memory input) internal pure returns (uint256) {
        return PoseidonT3.hash(input);
    }

    function root(FatIMTData storage self) public view returns (uint256) {
        return InternalFatIMTEvent._root(self);
    }

    /// @notice Batch node getter. Reads the `nodes` mapping, which lives in `FatIMTData` for both the
    /// plain and full-node trees — a full-node caller passes its `.treeData`. Hosted here (rather
    /// than in the two wrapper libraries) to keep them under the EIP-170 size limit. set level 0 to
    /// get the leaves.
    function getNodes(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex,
        uint256 level
    ) public view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self, firstIndex, endIndex, level);
    }

    /// @notice Leaf getter for the plain/archive tree: its leaves live in the `nodes` mapping at
    /// level 0, so this is `getNodes(self, ..., 0)`.
    function getLeaves(
        FatIMTData storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) public view returns (uint256[] memory) {
        return InternalFatIMTEvent._getNodes(self, firstIndex, endIndex, 0);
    }

    /// @notice Leaf getter for the full-node tree: reads its dedicated `leaves` array (consecutive
    /// storage slots, fast via debug_storageRangeAt). Pass the whole full-node struct, not `.treeData`.
    function getLeaves(
        FatIMTDataFullNode storage self,
        uint256 firstIndex,
        uint256 endIndex
    ) public view returns (uint256[] memory) {
        return InternalFatIMTStorage._getLeaves(self, firstIndex, endIndex);
    }

    function proofToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return InternalFatIMTEvent._proofToRootBN254(treeDepth, treeSize, leaf, leafIndex, proofSiblings, hasher);
    }

    function proofManyToRootBN254(
        uint256 treeDepth,
        uint256 treeSize,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (uint256) {
        return
            InternalFatIMTEvent._proofManyToRootBN254(treeDepth, treeSize, leaves, leafIndexes, proofSiblings, hasher);
    }

    function verify(
        FatIMTData storage self,
        uint256 leaf,
        uint256 leafIndex,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalFatIMTEvent._proofToRootBN254(
            self.depth,
            self.size,
            leaf,
            leafIndex,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalFatIMTEvent._root(self);
        return provenRoot == currentRoot;
    }

    function verifyMany(
        FatIMTData storage self,
        uint256[] calldata leaves,
        uint256[] calldata leafIndexes,
        uint256[] calldata proofSiblings
    ) public view returns (bool) {
        if (self.size == 0) {
            revert TreeEmpty();
        }
        uint256 provenRoot = InternalFatIMTEvent._proofManyToRootBN254(
            self.depth,
            self.size,
            leaves,
            leafIndexes,
            proofSiblings,
            hasher
        );
        uint256 currentRoot = InternalFatIMTEvent._root(self);
        return provenRoot == currentRoot;
    }
}
