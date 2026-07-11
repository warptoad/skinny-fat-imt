import { ethers } from "hardhat"
import { runFatIMTTests } from "../shared/fatIMTTests"

function sha256Hash(a: bigint, b: bigint): bigint {
    return BigInt(ethers.sha256(ethers.solidityPacked(["uint256", "uint256"], [a, b])))
}

runFatIMTTests({
    deployTaskName: "deploy:imt-sha256-test",
    libraryName: "FatIMTSha256",
    hashFn: sha256Hash,
    hasSnarkFieldCheck: false
})
