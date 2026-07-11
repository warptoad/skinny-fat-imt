// @ts-ignore - @zkpassport/poseidon2's exports map omits a "types" condition, so
// exports-aware resolution can't find its (shipped) declarations. Types are fine at runtime.
import { poseidon2Hash } from "@zkpassport/poseidon2"
import { runFatIMTTests } from "../shared/fatIMTTests"

runFatIMTTests({
    deployTaskName: "deploy:imt-poseidon2-test",
    libraryName: "FatIMTPoseidon2",
    hashFn: (a, b) => poseidon2Hash([a, b])
})
