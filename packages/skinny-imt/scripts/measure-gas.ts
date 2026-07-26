// Benchmark harness for the bare / event / full versions across all three hash functions.
// Emits one `DATA Skinny <Hash> <Version> {json}` line per (hash, version); the root
// orchestrator (scripts/gen-gas-comparison.mjs) parses these to rebuild GAS_COMPARISON.md.
// Run standalone with:  hardhat run scripts/measure-gas.ts
import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { ethers, run } from "hardhat"
import { poseidon2 } from "poseidon-lite"
// @ts-ignore - @zkpassport/poseidon2 ships types but its exports map omits the "types" condition
import { poseidon2Hash } from "@zkpassport/poseidon2"
import { deployPoseidon } from "../tasks/deploy-imt-poseidon-test"
import { deployPoseidon2 } from "../tasks/deploy-imt-poseidon2-test"

const P = "Skinny" // package label
const PROOFLESS = false // skinny's update/updateMany consume a merkle proof

type Hash = "Poseidon" | "Poseidon2" | "Sha256"
type Version = "Bare" | "Event" | "Full"
const HASHES: Hash[] = ["Poseidon", "Poseidon2", "Sha256"]
const VERSIONS: Version[] = ["Bare", "Event", "Full"]

const jsHash: Record<Hash, (a: bigint, b: bigint) => bigint> = {
    Poseidon: (a, b) => poseidon2([a, b]),
    Poseidon2: (a, b) => poseidon2Hash([a, b]),
    Sha256: (a, b) => BigInt(ethers.sha256(ethers.solidityPacked(["uint256", "uint256"], [a, b])))
}
const eventTask: Record<Hash, string> = {
    Poseidon: "deploy:imt-poseidon-test",
    Poseidon2: "deploy:imt-poseidon2-test",
    Sha256: "deploy:imt-sha256-test"
}

// deploy any hasher infrastructure the linked libraries need, returning the {name: address} link map
async function hasherLibs(h: Hash): Promise<Record<string, string>> {
    const [sender] = await ethers.getSigners()
    if (h === "Poseidon") return { PoseidonT3: await deployPoseidon(ethers.provider, sender, 2) }
    if (h === "Poseidon2") {
        await deployPoseidon2(ethers.provider, sender)
        return {}
    }
    return {} // sha256 precompile, nothing to deploy
}

async function deployLibAndTest(name: string, libs: Record<string, string>) {
    const lib = await (await ethers.getContractFactory(name, { libraries: libs })).deploy()
    return (await ethers.getContractFactory(`${name}Test`, { libraries: { [name]: await lib.getAddress() } })).deploy()
}

// returns { contract, deployGas } for a (hash, version)
async function deployVersion(h: Hash, v: Version) {
    if (v === "Event") {
        const { contract } = await run(eventTask[h], { library: `${P}IMT${h}`, logs: false })
        const dg = (await ethers.provider.getTransactionReceipt(contract.deploymentTransaction()!.hash))!.gasUsed
        return { contract, deployGas: dg }
    }
    const libName = v === "Bare" ? `${P}IMT${h}Bare` : `${P}IMT${h}Storage`
    const contract = await deployLibAndTest(libName, await hasherLibs(h))
    const dg = (await ethers.provider.getTransactionReceipt(contract.deploymentTransaction()!.hash))!.gasUsed
    return { contract, deployGas: dg }
}

const g = async (txp: any) => (await (await txp).wait()).gasUsed as bigint
const range = (n: number, f: (i: number) => bigint) => Array.from({ length: n }, (_, i) => f(i))

async function measure(h: Hash, v: Version) {
    const hash = jsHash[h]
    const R: Record<string, bigint> = {}

    // insert · 128th leaf (deepest single insert): seed 127 via insertMany, then one insert
    {
        const { contract } = await deployVersion(h, v)
        await (await contract.insertMany(range(127, (i) => BigInt(i + 1)))).wait()
        R.insert128 = await g(contract.insert(128))
    }
    // insertMany · 18 into a 126-leaf tree
    {
        const { contract } = await deployVersion(h, v)
        await (await contract.insertMany(range(126, (i) => BigInt(i + 1)))).wait()
        R.insertMany18 = await g(contract.insertMany(range(18, (i) => BigInt(1000 + i))))
    }
    // insertManyRepeated · 128 copies in one call, into an empty tree
    {
        const { contract } = await deployVersion(h, v)
        R.insertManyRepeated128 = await g(contract.insertManyRepeated(7, 128))
    }
    // update · leaf at index 0 of a 144-leaf tree (grown via eight 18-leaf batches)
    {
        const { contract } = await deployVersion(h, v)
        const js = new JSLeanIMT(hash)
        for (let b = 0; b < 8; b++) {
            const e = range(18, (i) => BigInt(b * 18 + i + 1))
            js.insertMany(e)
            await (await contract.insertMany(e)).wait()
        }
        if (PROOFLESS) {
            R.update144 = await g(contract.update(6969, 0))
        } else {
            const { siblings } = js.generateProof(0)
            R.update144 = await g(contract.update(1, 6969, 0, siblings))
        }
    }
    // updateMany · all 8 leaves of a size-8 tree (all leaves supplied -> empty sibling list)
    {
        const { contract } = await deployVersion(h, v)
        await (await contract.insertMany(range(8, (i) => BigInt(i + 1)))).wait()
        const newLeaves = range(8, (i) => BigInt(5000 + i))
        const leafIndexes = range(8, (i) => i) as unknown as number[]
        if (PROOFLESS) {
            R.updateMany8 = await g(contract.updateMany(newLeaves, leafIndexes))
        } else {
            const oldLeaves = range(8, (i) => BigInt(i + 1))
            R.updateMany8 = await g(contract.updateMany(oldLeaves, newLeaves, leafIndexes, []))
        }
    }
    // deploy cost of the test-wrapper contract
    R.deploy = (await deployVersion(h, v)).deployGas
    return R
}

async function main() {
    for (const h of HASHES) {
        for (const v of VERSIONS) {
            const r = Object.fromEntries(Object.entries(await measure(h, v)).map(([k, val]) => [k, val.toString()]))
            console.log(`DATA ${P} ${h} ${v} ${JSON.stringify(r)}`)
        }
    }
}
main().catch((e) => {
    console.error(e)
    process.exit(1)
})
