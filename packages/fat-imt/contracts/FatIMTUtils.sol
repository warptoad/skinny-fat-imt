// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {UpdatedLeaf} from "./interfaces/events.sol";
import {SNARK_SCALAR_FIELD} from "./Constants.sol";
import {FatIMTData} from "./InternalFatIMTCore.sol";

error LeafGreaterThanSnarkScalarField();

// // @TODO ask zemse if the wants to make Poseidon2Yul_BN254 an library with public functions, would add 50~150 gas
// // Hardcoded since poseidon2 is deployed as a contract instead of a library
// // This is because author used a gas saving trick with .fallback
// // address internal constant HASHER_ADDRESS = 0xB2542195Ad96AcfBC962C48A97D7640A9F5386D2;
// // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT.
// // function hasher(uint256[2] memory leaves) internal pure returns (uint256) {
// //     return IPoseidon2(HASHER_ADDRESS).hash_2(leaves[0], leaves[1]);
// // }

// // The function used for hashing. Passed as a function parameter in functions from InternalLazyIMT.
// function _poseidon2Hasher(uint256[2] memory leaves) pure returns (uint256) {
//     return LibPoseidon2Yul.hash_2(leaves[0], leaves[1]);
// }

/// @dev Emits one `UpdatedLeaf` per updated leaf, mirroring `update`.
function _emitUpdatedMany(
    uint256 treeId,
    uint256[] calldata leafIndexes,
    uint256[] calldata oldLeaves,
    uint256[] calldata newLeaves
) {
    for (uint256 i = 0; i < leafIndexes.length; i++) {
        emit UpdatedLeaf(treeId, leafIndexes[i], newLeaves[i], oldLeaves[i]);
    }
}

/// @dev Reverts with `LeafGreaterThanSnarkScalarField` if `v` is not in the BN254 scalar field.
function _requireInField(uint256 v) pure {
    if (v >= SNARK_SCALAR_FIELD) {
        revert LeafGreaterThanSnarkScalarField();
    }
}

/// @dev Reverts unless every value is within the snark scalar field.
function _requireAllInField(uint256[] calldata values) pure {
    for (uint256 i = 0; i < values.length; i++) {
        _requireInField(values[i]);
    }
}
