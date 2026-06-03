import "@nomicfoundation/hardhat-toolbox"
import { HardhatUserConfig } from "hardhat/config"
import "./tasks/deploy-imt-poseidon-test"
import "./tasks/deploy-imt-poseidon2-test"
import "dotenv/config"

const hardhatConfig: HardhatUserConfig = {
    solidity: {
        version: "0.8.23",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
                //runs: 2 ** 32 - 1
            }
        }
    },
    gasReporter: {
        currency: "USD",
        enabled: process.env.REPORT_GAS === "true",
        outputJSONFile: "gas-report-leanimt.json",
        outputJSON: process.env.REPORT_GAS_OUTPUT_JSON === "true"
    },
    typechain: {
        target: "ethers-v6"
    }
}

export default hardhatConfig
