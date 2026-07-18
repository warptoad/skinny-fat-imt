// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {InternalSkinnyIMTStorage, SkinnyIMTDataFullNode} from "./InternalSkinnyIMTStorage.sol";

/// @title SkinnyIMTFullNodeReadable
/// @dev Optional base for a full-node consumer. Holds the tree's `SkinnyIMTDataFullNode` storage and
/// exposes `getLeaves` for off-chain readers (RPC / `eth_call`). It is hash-function agnostic — reading
/// leaves never hashes — so a single base works for poseidon / poseidon2 / sha256. The consumer still
/// wires the hash-specific operations itself, e.g.:
///
///   contract MyTree is SkinnyIMTFullNodeReadable {
///       using SkinnyIMTPoseidon2FullNode for SkinnyIMTDataFullNode;
///       constructor() { data.init(); }
///       function insert(uint256 leaf) external onlyOwner { data.insert(leaf); }
///       // ...update / insertMany / root / size, all on `data`...
///   }
///
/// `data` is the first state variable of this base, so in a consumer that inherits it first the tree
/// (and thus `data.leaves`) sits at a predictable base storage slot — see the note at the bottom for the
/// slot getter a storage-reading client library would want.
abstract contract SkinnyIMTFullNodeReadable {
    SkinnyIMTDataFullNode internal data;

    /// @notice Returns the leaves in the half-open range [from, to).
    /// @dev Convenience reader for full nodes. Meant for off-chain `eth_call` (no gas paid); for large
    /// ranges page it, since the return array is bounded by the node's `eth_call` gas/response limits.
    function getLeaves(uint256 from, uint256 to) external view returns (uint256[] memory) {
        return InternalSkinnyIMTStorage._getLeaves(data, from, to);
    }

    // used in skinnyfatJs lib to find the slot of leaves
    function leavesBaseSlot() external pure returns (uint256 s) {
        assembly {
            s := data.slot
        }
    }
}
