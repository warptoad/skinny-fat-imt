import { ethers } from "hardhat"
import { runSkinnyIMTTests } from "../shared/skinnyIMTTests"

function sha256Hash(a: bigint, b: bigint): bigint {
    return BigInt(ethers.sha256(ethers.solidityPacked(["uint256", "uint256"], [a, b])))
}

runSkinnyIMTTests({
    deployTaskName: "deploy:imt-sha256-test",
    libraryName: "SkinnyIMTSha256",
    hashFn: sha256Hash,
    hasSnarkFieldCheck: false
})
