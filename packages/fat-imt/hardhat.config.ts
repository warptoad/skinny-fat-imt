import "@nomicfoundation/hardhat-toolbox"
import { HardhatUserConfig } from "hardhat/config"
import "./tasks/deploy-imt-poseidon-test"
import "./tasks/deploy-imt-poseidon2-test"
import "./tasks/deploy-imt-sha256-test"
import "dotenv/config"

const hardhatConfig: HardhatUserConfig = {
    solidity: {
        version: "0.8.23",
        settings: {
            optimizer: {
                enabled: true,
                runs: 2 ** 32 - 1
            }
        }
    },
    // not needed rn since we are below the contract byte size limit
    // networks: {
    //     // The fat test wrappers inline every function and, now that all nodes are stored, exceed the
    //     // 24576-byte EIP-170 limit. Allow oversized contracts on the in-process test network so the
    //     // suite can deploy them; this does not affect the library's real-world gas/size.
    //     hardhat: {
    //         allowUnlimitedContractSize: true
    //     }
    // },
    gasReporter: {
        currency: "USD",
        enabled: process.env.REPORT_GAS === "true",
        outputJSONFile: "gas-report-skinnyimt.json",
        outputJSON: process.env.REPORT_GAS_OUTPUT_JSON === "true"
    },
    typechain: {
        target: "ethers-v6"
    }
}

export default hardhatConfig
