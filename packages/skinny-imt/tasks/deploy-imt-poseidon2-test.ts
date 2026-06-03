import { task, types } from "hardhat/config"
import { proxy } from "poseidon-solidity"
import { ethers } from "ethers"
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers"
import {
    Poseidon2YulFixed__factory,
    SkinnyIMTPoseidon2__factory,
    SkinnyIMTPoseidon2Test__factory
} from "../typechain-types"
export async function deployPoseidon2(provider: ethers.Provider, sender: ethers.Signer | HardhatEthersSigner) {
    const salt = "0x0b00000000000000254810000000000000000000000000000000000000000000"
    // Our reduction-corrected copy of zemse's Poseidon2Yul (the upstream one overflows on
    // some inputs). See contracts/poseidon2/Poseidon2YulFixed.sol.
    const expectedPose2Addr = "0x77553EFE11B53f1e882716b43bCe3530fc0a9327"
    // no constructor args -> initCode is the bytecode as-is.
    const initCode = Poseidon2YulFixed__factory.bytecode
    const calculatedPos2Addr = ethers.getCreate2Address(proxy.address, salt, ethers.keccak256(initCode))
    if (ethers.getAddress(calculatedPos2Addr) !== ethers.getAddress(expectedPose2Addr)) {
        throw new Error(
            `expected address: ${expectedPose2Addr} but got ${calculatedPos2Addr}, from initCode: ${initCode}`
        )
    }

    const poseidonDoesNotExist = (await provider.getCode(calculatedPos2Addr)) === "0x"
    // poseidon from chance and poseidon2 from zemse use the same create2 proxy
    const proxyDoesNotExist = (await provider.getCode(proxy.address)) === "0x"
    // First check if the proxy exists
    if (proxyDoesNotExist) {
        // fund the keyless account
        await sender.sendTransaction({
            to: proxy.from,
            value: proxy.gas
        })
        // then send the presigned transaction deploying the proxy
        await provider.broadcastTransaction(proxy.tx)
    }

    // Then deploy the hasher, if needed
    if (poseidonDoesNotExist) {
        //readme is wrong having typo here: send.sendTransaction instead of sender
        await sender.sendTransaction({
            to: proxy.address,
            data: ethers.concat([salt, initCode])
        })
    }

    return calculatedPos2Addr
}

task("deploy:imt-poseidon2-test", "Deploy an IMT contract for testing a library")
    .addParam<string>("library", "The name of the library", undefined, types.string)
    .addOptionalParam<boolean>("logs", "Print the logs", true, types.boolean)
    .addOptionalParam<number>("arity", "The arity of the tree", 2, types.int)
    .setAction(async ({ logs, library: libraryName, arity }, { ethers }): Promise<any> => {
        const provider = ethers.provider
        const [sender] = await ethers.getSigners()
        const poseidonAddress = await deployPoseidon2(provider, sender)

        if (logs) {
            console.info(`PoseidonT${arity + 1} library has been deployed to: ${poseidonAddress}`)
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
