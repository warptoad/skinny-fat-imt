import { task, types } from "hardhat/config"
import { ethers } from "ethers"
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers"
import { SkinnyIMTSha256__factory } from "../typechain-types"

// sha256 is a built-in EVM precompile at address 0x02 — no external deployment needed.
export async function deploySha256(_provider: ethers.Provider, _sender: ethers.Signer | HardhatEthersSigner) {
    // nothing to deploy
}

task("deploy:imt-sha256-test", "Deploy an IMT contract for testing a library")
    .addParam<string>("library", "The name of the library", undefined, types.string)
    .addOptionalParam<boolean>("logs", "Print the logs", true, types.boolean)
    .addOptionalParam<number>("arity", "The arity of the tree", 2, types.int)
    .setAction(async ({ logs, library: libraryName, arity }, { ethers }): Promise<any> => {
        const LibraryFactory = (await ethers.getContractFactory(libraryName, {
            libraries: {}
        })) as SkinnyIMTSha256__factory

        const library = await LibraryFactory.deploy()
        const libraryAddress = await library.getAddress()

        if (logs) {
            console.info(`${libraryName} library has been deployed to: ${libraryAddress}`)
        }

        const ContractFactory = await ethers.getContractFactory(`${libraryName}Test`, {
            libraries: {
                [libraryName]: libraryAddress
            }
        })

        const contract = await ContractFactory.deploy()
        const contractAddress = await contract.getAddress()

        if (logs) {
            console.info(`${libraryName}Test contract has been deployed to: ${contractAddress}`)
        }

        return { library, contract }
    })
