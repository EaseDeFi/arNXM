import { network, ethers } from "hardhat";
import { providers, Contract, Signer, BigNumber } from "ethers";
import { expect } from "chai";
const pool_mainnet = "0x84edffa16bb0b9ab1163abb0a13ff0744c11272f";
const arnxm_mainnet = "0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4";
const gov_mainnet = "0x1f28ed9d4792a567dad779235c2b766ab84d8e33";
const nxm_whale = "0x598Dbe6738E0AcA4eAbc22feD2Ac737dbd13Fb8F";
const nxm_mainnet = "0xd7c49cee7e9188cca6ad8ff264c1da2e69d4cf3b";

BigNumber.prototype.toJSON = function toJSON(key) {
    return this.toString();
};
describe.only('arnxm', function(){
  let arNXMVault : Contract;
  let pool : Contract;
  let nxm : Contract;
  let owner : Signer;
  let others : Signer;
  let whale : Signer;

  const toStake = {
    protocols : ["0x99c666810bA4Bf9a4C2318CE60Cb2c279Ee2cF56", "0x0000000000000000000000000000000000000001", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31", "0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", "0xB17640796e4c27a39AF51887aff3F8DC0daF9567", "0xc57d000000000000000000000000000000000013", "0xCC88a9d330da1133Df3A7bD823B95e52511A6962", "0xC57d000000000000000000000000000000000012", "0xC57d000000000000000000000000000000000003"],
    amounts : ["10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000","10000000000000000000000"]
    }

  let desired = {
    protocols : ["0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F", "0xe80d347DF1209a76DD9d2319d62912ba98C54DDD", "0xb529964F86fbf99a6aA67f72a27e59fA3fa4FEaC", "0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e", "0x3e532e6222afe9Bcf02DCB87216802c75D5113aE", "0xA51156F3F1e39d1036Ca4ba4974107A1C1815d1e", "0x77208a6000691E440026bEd1b178EF4661D37426", "0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258", "0x878F15ffC8b894A1BA7647c7176E4C01f74e140b", "0xC57d000000000000000000000000000000000003", "0x12f208476F64De6e6f933E55069Ba9596D818e08", "0x71CD6666064C3A1354a3B4dca5fA1E2D3ee7D303", "0xC57d000000000000000000000000000000000006", "0x3A97247DF274a17C59A3bd12735ea3FcDFb49950", "0x5d22045DAcEAB03B158031eCB7D9d06Fad24609b", "0x12D66f87A04A9E220743712cE6d9bB1B5616B8Fc", "0x02285AcaafEB533e03A7306C55EC031297df9224","0x7C06792Af1632E77cb27a558Dc0885338F4Bdf8E", "0xC57D000000000000000000000000000000000005", "0xE75D77B1865Ae93c7eaa3040B038D7aA7BC02F70", "0x99c666810bA4Bf9a4C2318CE60Cb2c279Ee2cF56", "0x0000000000000000000000000000000000000001", "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", "0xB17640796e4c27a39AF51887aff3F8DC0daF9567", "0xe20A5C79b39bC8C363f0f49ADcFa82C2a01ab64a", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31", "0x7a9701453249e84fd0D5AfE5951e9cBe9ed2E90f", "0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", "0x0000000000000000000000000000000000000008", "0x0000000000000000000000000000000000000007", "0x0000000000000000000000000000000000000004", "0x1F98431c8aD98523631AE4a59f267346ea31F984", "0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", "0xC57d000000000000000000000000000000000011", "0x9D25057e62939D3408406975aD75Ffe834DA4cDd", "0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C", "0x4B8d90D68F26DEF303Dcb6CFc9b63A1aAEC15840", "0xCB876f60399897db24058b2d58D0B9f713175eeF"],
    amounts : ["5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000"]
  };
  const unstake = {
    removedProtocols :["0xC57D000000000000000000000000000000000002", "0xB1dD690Cc9AF7BB1a906A9B5A94F94191cc553Ce", "0xAFcE80b19A8cE13DEc0739a1aaB7A028d6845Eb3", "0xfA5047c9c78B8877af97BDcb85Db743fD7313d4a", "0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F", "0xB27F1DB0a7e473304A5a06E54bdf035F671400C0", "0x11111254369792b2Ca5d084aB5eEA397cA8fa48B", "0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B", "0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd", "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f", "0x67B66C99D3Eb37Fa76Aa3Ed1ff33E8e39F0b9c7A"],
  }
  let toBe = {
    protocols : [],
    amounts: [],
    unstakePercents : []
  }
  beforeEach(async function(){
    others = (await ethers.getSigners())[3];
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [gov_mainnet]
    });
    owner = await ethers.provider.getSigner(gov_mainnet);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [nxm_whale]
    });
    whale = await ethers.provider.getSigner(nxm_whale);

    arNXMVault = await ethers.getContractAt("arNXMVault", arnxm_mainnet);
    nxm = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", nxm_mainnet);
    pool = await ethers.getContractAt("contracts/interfaces/INexusMutual.sol:IPooledStaking", pool_mainnet);
    //    const VaultFactory = await ethers.getContractFactory("arNXMVault");
    //const newVault = await VaultFactory.deploy();
    //const ProxyFactory = await ethers.getContractFactory("OwnedUpgradeabilityProxy");
    //const toUpdate = await ProxyFactory.attach(arNXMVault.address);
    //await toUpdate.connect(owner).upgradeTo(newVault.address);

    for(let i = 0; i< toStake.protocols.length; i++) {
      const idx = desired.protocols.findIndex((e) => e.toLowerCase() === toStake.protocols[i].toLowerCase());
      if(idx === -1) {
        desired.protocols.unshift(toStake.protocols[i]);
        desired.amounts.unshift(toStake.amounts[i]);
      } else {
        if(desired.amounts.length <= idx) {
          desired.protocols.splice(idx, 1);
          desired.protocols.unshift(toStake.protocols[i]);
          desired.amounts.unshift(toStake.amounts[i]);
        } else {
          desired.protocols.splice(idx, 1);
          desired.amounts.splice(idx, 1);
          desired.protocols.unshift(toStake.protocols[i]);
          desired.amounts.unshift(toStake.amounts[i]);
        }
      }
    }

    const lastId = await pool.lastUnstakeRequestId();
    const oldProtocols = await pool.stakerContractsArray(arnxm_mainnet);
    //first fill in the old protocols
    for(let i = 0; i < oldProtocols.length; i++) {
      const idx = desired.protocols.findIndex((e) => e.toLowerCase() === oldProtocols[i].toLowerCase());
      if(idx === -1) {
        toBe.protocols.push(oldProtocols[i]);
        toBe.amounts.push(BigNumber.from(0));
        toBe.unstakePercents.push(BigNumber.from(70));
      } else {
        toBe.protocols.push(oldProtocols[i]);
        if(desired.amounts.length <= idx) {
          toBe.amounts.push(BigNumber.from(0));
          toBe.unstakePercents.push(BigNumber.from(70));
        } else {
          toBe.amounts.push(BigNumber.from(desired.amounts[idx]));
          toBe.unstakePercents.push(BigNumber.from(70));
          desired.amounts.splice(idx, 1);
        }
        desired.protocols.splice(idx, 1);
        console.log(desired.protocols);
      }
    }
    // then fill new protocols
    console.log(desired.protocols);
    for(let i = 0; i< desired.protocols.length; i++){
      const idx = toBe.protocols.findIndex((e) => e.toLowerCase() == desired.protocols[i].toLowerCase());
      console.log(toBe.protocols);
      console.log(desired.protocols);
      if(idx == -1) {
        console.log("HUH");
        if(desired.amounts.length > i){ 
          toBe.protocols.push(desired.protocols[i]);
          toBe.amounts.push(BigNumber.from(desired.amounts[i]));
          toBe.unstakePercents.push(BigNumber.from(0));
        } else {
          toBe.protocols.push(desired.protocols[i]);
          toBe.amounts.push(BigNumber.from(0));
          toBe.unstakePercents.push(BigNumber.from(70));
        }
      }
    }

    for(let i = 0; i< toBe.protocols.length; i++){
      console.log(toBe.protocols[i]);
    }
    const data = arNXMVault.interface.encodeFunctionData("changeProtocols", [toBe.protocols, toBe.unstakePercents, unstake.removedProtocols, lastId]);
    console.log("arg0");
    console.log(toBe.protocols);
    console.log("arg1");
    console.log(JSON.stringify(toBe.unstakePercents, null,2));
    console.log("]");
    console.log("arg2");
    console.log(unstake.removedProtocols);
    console.log("arg3");
    console.log(lastId.toString());
    await arNXMVault.connect(owner).changeProtocols(toBe.protocols, toBe.unstakePercents, unstake.removedProtocols, 0);
  });

  it("should manual stake", async function(){
    const res = arNXMVault.interface.encodeFunctionData("stakeNxmManual", [toBe.protocols, toBe.amounts]);
    console.log("arg0");
    console.log(toBe.protocols);
    console.log("arg1");
    console.log(JSON.stringify(toBe.amounts, null, 2));
    await arNXMVault.connect(owner).stakeNxmManual(toBe.protocols, toBe.amounts);
  });
});
