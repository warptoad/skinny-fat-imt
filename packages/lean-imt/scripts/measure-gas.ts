// Baseline benchmark for vanilla lean-IMT (PoseidonT3), matched to the skinny/fat version harness.
// Emits a single `DATA Lean {json}` line; the root orchestrator (scripts/gen-gas-comparison.mjs)
// parses it to rebuild GAS_COMPARISON.md. Run standalone with:  hardhat run scripts/measure-gas.ts
import { LeanIMT as JSLeanIMT } from "@zk-kit/lean-imt"
import { ethers, run } from "hardhat"
import { poseidon2 } from "poseidon-lite"

async function deploy() {
    const { contract } = await run("deploy:imt-test", { library: "LeanIMT", logs: false })
    return contract
}
const g = async (txp: any) => (await (await txp).wait()).gasUsed as bigint
const range = (n: number, f: (i: number) => bigint) => Array.from({ length: n }, (_, i) => f(i))

async function main() {
    const R: Record<string, bigint> = {}

    {
        const c = await deploy()
        await (await c.insertMany(range(127, (i) => BigInt(i + 1)))).wait()
        R.insert128 = await g(c.insert(128))
    }
    {
        const c = await deploy()
        await (await c.insertMany(range(126, (i) => BigInt(i + 1)))).wait()
        R.insertMany18 = await g(c.insertMany(range(18, (i) => BigInt(1000 + i))))
    }
    {
        // lean has no repeated-insert primitive; its LeanIMTTest stand-in batches `amount` DISTINCT
        // leaves through insertMany (lean forbids zero/duplicate leaves) — see GAS_COMPARISON.md note.
        const c = await deploy()
        R.insertManyRepeated128 = await g(c.insertManyRepeated(7, 128))
    }
    {
        const c = await deploy()
        const js = new JSLeanIMT((a, b) => poseidon2([a, b]))
        for (let b = 0; b < 8; b++) {
            const e = range(18, (i) => BigInt(b * 18 + i + 1))
            js.insertMany(e)
            await (await c.insertMany(e)).wait()
        }
        const { siblings } = js.generateProof(0)
        R.update144 = await g(c.update(1, 6969, siblings)) // lean update: (oldLeaf, newLeaf, siblings) — no index
    }
    {
        // lean has no batch update; its stand-in loops single updates, so each step needs a proof for
        // the tree state the previous step left. Build the sibling arrays in order off the JS mirror.
        const c = await deploy()
        const js = new JSLeanIMT((a, b) => poseidon2([a, b]))
        const e = range(8, (i) => BigInt(i + 1))
        js.insertMany(e)
        await (await c.insertMany(e)).wait()
        const oldLeaves: bigint[] = []
        const newLeaves: bigint[] = []
        const sibs: bigint[][] = []
        for (let idx = 0; idx < 8; idx++) {
            const { siblings } = js.generateProof(idx)
            oldLeaves.push(e[idx])
            newLeaves.push(BigInt(5000 + idx))
            sibs.push(siblings)
            js.update(idx, BigInt(5000 + idx))
        }
        R.updateMany8 = await g(c.updateMany(oldLeaves, newLeaves, sibs))
    }
    {
        const c = await deploy()
        R.deploy = (await ethers.provider.getTransactionReceipt(c.deploymentTransaction()!.hash))!.gasUsed
    }

    const obj = Object.fromEntries(Object.entries(R).map(([k, v]) => [k, v.toString()]))
    console.log(`DATA Lean ${JSON.stringify(obj)}`)
}
main().catch((e) => {
    console.error(e)
    process.exit(1)
})
