// @ts-ignore - @zkpassport/poseidon2's exports map omits a "types" condition, so
// exports-aware resolution can't find its (shipped) declarations. Types are fine at runtime.
import { poseidon2Hash } from "@zkpassport/poseidon2"
import { runSkinnyIMTTests } from "../shared/skinnyIMTTests"

runSkinnyIMTTests({
    deployTaskName: "deploy:imt-poseidon2-test",
    libraryName: "SkinnyIMTPoseidon2",
    hashFn: (a, b) => poseidon2Hash([a, b]),
    hasVerifyMany: true
})
