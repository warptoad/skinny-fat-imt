import { task, types } from "hardhat/config"
import { createPublicClient, createWalletClient, custom } from "viem"
import { hardhat } from "viem/chains"
import { SkinnyIMTPoseidon2__factory } from "../typechain-types"
import { deployPoseidon2Huff } from "@warptoad/gigabridge-js"

task("deploy:imt-poseidon2-test", "Deploy an IMT contract for testing a library")
    .addParam<string>("library", "The name of the library", undefined, types.string)
    .addOptionalParam<boolean>("logs", "Print the logs", true, types.boolean)
    .addOptionalParam<number>("arity", "The arity of the tree", 2, types.int)
    .addOptionalParam<string>(
        "huffsalt",
        "Salt for CREATE2 deployment of Poseidon2 Huff",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        types.string
    )
    .setAction(async ({ logs, library: libraryName, arity, huffsalt }, hre): Promise<any> => {
        const { ethers, network } = hre
        const [sender] = await ethers.getSigners()

        const publicClient = createPublicClient({
            chain: hardhat,
            transport: custom(network.provider)
        })
        const walletClient = createWalletClient({
            chain: hardhat,
            transport: custom(network.provider),
            account: sender.address as `0x${string}`
        })

        const { poseidon2HuffAddress } = await deployPoseidon2Huff(publicClient as any, walletClient as any, huffsalt)

        if (logs) {
            console.info(`PoseidonT${arity + 1} library has been deployed to: ${poseidon2HuffAddress}`)
        }

        const LibraryFactory = (await ethers.getContractFactory(libraryName, {
            libraries: {}
        })) as SkinnyIMTPoseidon2__factory

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
