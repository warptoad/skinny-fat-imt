// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {FatIMTPoseidon2WriteFullNode} from "../FatIMTPoseidon2WriteFullNode.sol";
import {FatIMTFullNodeReadable} from "../../FatIMTFullNodeReadable.sol";
import {FatIMTDataFullNode} from "../../InternalFatIMTStorage.sol";
import {SkinnyIMTPoseidon2WriteFullNode} from "@zk-kit/skinny-imt.sol/poseidon2/SkinnyIMTPoseidon2WriteFullNode.sol";
import {SkinnyIMTFullNodeReadable} from "@zk-kit/skinny-imt.sol/SkinnyIMTFullNodeReadable.sol";
import {SkinnyIMTDataFullNode} from "@zk-kit/skinny-imt.sol/InternalSkinnyIMTStorage.sol";

/// Holds a fat *and* a skinny tree in one contract, which is the case the two readable bases have to
/// coexist for. Because every name in both bases is family-prefixed down to the external ABI, the two
/// share no selector and no internal hook: inheriting both costs exactly the two `_get*Tree` resolvers
/// below and nothing else. The families keep separate id spaces, so `1` here names two distinct trees.
contract FatAndSkinnyIMTPoseidon2Test is FatIMTFullNodeReadable, SkinnyIMTFullNodeReadable {
    mapping(uint256 => FatIMTDataFullNode) internal fatTrees;
    mapping(uint256 => SkinnyIMTDataFullNode) internal skinnyTrees;

    function _getFatTree(uint256 treeId) internal view override returns (FatIMTDataFullNode storage) {
        return fatTrees[treeId];
    }

    function _getSkinnyTree(uint256 treeId) internal view override returns (SkinnyIMTDataFullNode storage) {
        return skinnyTrees[treeId];
    }

    function initFat(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2WriteFullNode.init(fatTrees[treeId]);
    }

    function initSkinny(uint256 treeId) external returns (uint256) {
        return SkinnyIMTPoseidon2WriteFullNode.init(skinnyTrees[treeId]);
    }

    function insertManyFat(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteFullNode.insertMany(fatTrees[treeId], leaves);
    }

    function insertManySkinny(uint256 treeId, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteFullNode.insertMany(skinnyTrees[treeId], leaves);
    }
}
