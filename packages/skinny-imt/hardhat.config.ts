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
            // this library compiles with extremely high runs because the inlined poseidon libraries benefit greatly
            // from this. However the down side is that the contract size becomes massive, skinny and fat imt already
            // split into read and write to deal with this and to stay under the EIP-170 24576-byte limit.
            // allowUnlimitedContractSize: true
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
