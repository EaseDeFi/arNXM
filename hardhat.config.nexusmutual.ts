import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
//import "solidity-coverage";
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

export default {
  solidity: {
    version: "0.5.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 300
      }
    }
  },
  networks: {
    hardhat: {
      gas: "auto",
      accounts: {
        accountsBalance: "1000000000000000000000000"
      },
      allowUnlimitedContractSize: true
    },
    coverage: {
      url: 'http://localhost:8555'
    }
  },
  paths: {
    sources: "./nexusmutual_contracts"
  }
};

