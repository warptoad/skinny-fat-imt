// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {FatIMTPoseidon2WriteStorage} from "../FatIMTPoseidon2WriteStorage.sol";
import {FatIMTReadableStorage} from "../../FatIMTReadableStorage.sol";
import {FatIMTDataStorage} from "../../InternalFatIMTStorage.sol";
import {SkinnyIMTPoseidon2WriteStorage} from "@zk-kit/skinny-imt.sol/poseidon2/SkinnyIMTPoseidon2WriteStorage.sol";
import {SkinnyIMTReadableStorage} from "@zk-kit/skinny-imt.sol/SkinnyIMTReadableStorage.sol";
import {SkinnyIMTDataStorage} from "@zk-kit/skinny-imt.sol/InternalSkinnyIMTStorage.sol";

/// Holds a fat *and* a skinny tree in one contract, which is the case the two readable bases have to
/// coexist for. Because every name in both bases is family-prefixed down to the external ABI, the two
/// share no selector and no internal hook — except `supportsInterface`, whose selector ERC-165 fixes
/// and which therefore cannot be prefixed. So inheriting both costs the two `_get*Tree` resolvers
/// plus that one disambiguating override, and nothing else. The families keep separate id spaces, so
/// `1` here names two distinct trees.
contract FatAndSkinnyIMTPoseidon2Test is FatIMTReadableStorage, SkinnyIMTReadableStorage {
    mapping(uint256 => FatIMTDataStorage) internal fatTrees;
    mapping(uint256 => SkinnyIMTDataStorage) internal skinnyTrees;

    function _getFatStorageTree(uint256 treeId) internal view override returns (FatIMTDataStorage storage) {
        return fatTrees[treeId];
    }

    function _getSkinnyStorageTree(uint256 treeId) internal view override returns (SkinnyIMTDataStorage storage) {
        return skinnyTrees[treeId];
    }

    /// Solidity will not pick between two inherited implementations of one function, so this override
    /// is required rather than stylistic. `super` is enough to make it correct: both families root at
    /// the same OpenZeppelin `ERC165`, so C3 linearization threads the walk through all four readable
    /// bases and every id gets reported.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(FatIMTReadableStorage, SkinnyIMTReadableStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function initFat(uint256 treeId) external returns (uint256) {
        return FatIMTPoseidon2WriteStorage.init(fatTrees[treeId]);
    }

    function initSkinny(uint256 treeId) external returns (uint256) {
        return SkinnyIMTPoseidon2WriteStorage.init(skinnyTrees[treeId]);
    }

    function insertManyFat(uint256 treeId, uint256[] calldata leaves) external {
        FatIMTPoseidon2WriteStorage.insertMany(fatTrees[treeId], leaves);
    }

    function insertManySkinny(uint256 treeId, uint256[] calldata leaves) external {
        SkinnyIMTPoseidon2WriteStorage.insertMany(skinnyTrees[treeId], leaves);
    }
}
