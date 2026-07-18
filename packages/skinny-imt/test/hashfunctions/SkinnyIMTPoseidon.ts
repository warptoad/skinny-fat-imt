import { poseidon2 } from "poseidon-lite"
import { runSkinnyIMTTests } from "../shared/skinnyIMTTests"

runSkinnyIMTTests({
    deployTaskName: "deploy:imt-poseidon-test",
    libraryName: "SkinnyIMTPoseidon",
    hashFn: (a, b) => poseidon2([a, b])
})
