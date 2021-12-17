import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "solidity-coverage";
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
    console.log((await account.getBalance()).toString());
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
task("arnft-withdraw", "print nxm cover note list", async (args, hre) => {
  const contract = await hre.ethers.getContractAt('IQuotation', '0xB365FA523d853fbfA5608E3e4c8457166287D958');
  const res = await contract.getWithdrawableCoverNoteCoverIds('0x1337DEF1e9c7645352D93baf0b789D04562b4185');
  const ids = res[0];
  const reasons = res[1];
  let reasonSorted = [];
  let idsSorted = [];
  const tc = await hre.ethers.getContractAt('ITokenController', '0x5407381b6c251cFd498ccD4A1d877739CB7960B8');
  const raw = await tc.getLockReasons('0x1337DEF1e9c7645352D93baf0b789D04562b4185');
  for(let i = 0; i< raw.length; i++) {
    const r = raw[i];
    const idx = reasons.findIndex((e) => e.toLowerCase() === r.toLowerCase());
    if(idx == -1){
      console.log(`Cannot find ${r}`);
    } else {
      console.log(idx);
      const x = ids[idx];
      console.log(x);
      idsSorted.push(x);
      reasonSorted.push(i);
    }
  }
  console.log(reasonSorted);
  const WINDOW = 100;
  console.log(`Lists... total ${idsSorted.length}`);
  for(let i = 0; i<(idsSorted.length / WINDOW) + 1; i++) {
    console.log(`iter : ${i}`);
    let tIds = [];
    let tReasons = [];

    for(let j = 0; j < WINDOW && i*WINDOW + j < idsSorted.length; j++) {
      tIds.push(idsSorted[i * WINDOW + j].toNumber());
    }
    for(let j = 0; j < WINDOW && i*WINDOW + j < idsSorted.length; j++) {
      tReasons.push(reasonSorted[i*WINDOW + j]);
    }
    console.log('ids');
    console.log(tIds.toString());
    console.log('reasons');
    console.log(tReasons.toString());
  }
});


export default {
  solidity: {
    compilers :[
      {
        version: "0.6.12",
        settings: {
          optimizer : {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.5.17",
        settings: {
          optimizer : {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {
      gas: 10000000,
      accounts: {
        accountsBalance: "100000000000000000000000000"
      },
      allowUnlimitedContractSize: true,
      timeout: 1000000
    },
    coverage: {
      url: 'http://localhost:8555'
    },
    mainnet: {
      url: "https://eth-mainnet.alchemyapi.io/v2/aSehDzePbrHy0EI_mDd66KeBeF1yYwi3"
    }

  }
};

