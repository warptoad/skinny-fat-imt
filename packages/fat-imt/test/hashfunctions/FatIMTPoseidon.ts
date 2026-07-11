import { poseidon2 } from "poseidon-lite"
import { runFatIMTTests } from "../shared/fatIMTTests"

runFatIMTTests({
    deployTaskName: "deploy:imt-poseidon-test",
    libraryName: "FatIMTPoseidon",
    hashFn: (a, b) => poseidon2([a, b])
})
