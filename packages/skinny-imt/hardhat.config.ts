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
    networks: {
        hardhat: {
            // libraries are compiled with runs: 2**32-1 (min runtime gas), so some exceed the
            // EIP-170 24576-byte limit. Allow deploying them on the test network for now; the size
            // golfing is a follow-up.
            allowUnlimitedContractSize: true
        }
    },
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
