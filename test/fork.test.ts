import { network, ethers } from "hardhat";
import { providers, Contract, Signer, BigNumber } from "ethers";
import { expect } from "chai";
const pool_mainnet = "0x84edffa16bb0b9ab1163abb0a13ff0744c11272f";
const arnxm_mainnet = "0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4";
const gov_mainnet = "0x1f28ed9d4792a567dad779235c2b766ab84d8e33";
const nxm_whale = "0x598Dbe6738E0AcA4eAbc22feD2Ac737dbd13Fb8F";
const nxm_mainnet = "0xd7c49cee7e9188cca6ad8ff264c1da2e69d4cf3b";
describe.only('arnxm', function(){
  let arNXMVault : Contract;
  let pool : Contract;
  let nxm : Contract;
  let owner : Signer;
  let others : Signer;
  let whale : Signer;

  const desired = {
    protocols : ["0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F", "0xe80d347DF1209a76DD9d2319d62912ba98C54DDD", "0xb529964F86fbf99a6aA67f72a27e59fA3fa4FEaC", "0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e", "0x3e532e6222afe9Bcf02DCB87216802c75D5113aE", "0xA51156F3F1e39d1036Ca4ba4974107A1C1815d1e", "0x77208a6000691E440026bEd1b178EF4661D37426", "0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258", "0x878F15ffC8b894A1BA7647c7176E4C01f74e140b", "0xC57d000000000000000000000000000000000003", "0x12f208476F64De6e6f933E55069Ba9596D818e08", "0x71CD6666064C3A1354a3B4dca5fA1E2D3ee7D303", "0xC57d000000000000000000000000000000000006", "0x3A97247DF274a17C59A3bd12735ea3FcDFb49950", "0x5d22045DAcEAB03B158031eCB7D9d06Fad24609b", "0x12D66f87A04A9E220743712cE6d9bB1B5616B8Fc", "0x02285AcaafEB533e03A7306C55EC031297df9224","0x7C06792Af1632E77cb27a558Dc0885338F4Bdf8E", "0xC57D000000000000000000000000000000000005", "0xE75D77B1865Ae93c7eaa3040B038D7aA7BC02F70", "0x99c666810bA4Bf9a4C2318CE60Cb2c279Ee2cF56", "0x0000000000000000000000000000000000000001", "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", "0xB17640796e4c27a39AF51887aff3F8DC0daF9567", "0xe20A5C79b39bC8C363f0f49ADcFa82C2a01ab64a", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31", "0x7a9701453249e84fd0D5AfE5951e9cBe9ed2E90f", "0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", "0x0000000000000000000000000000000000000008", "0x0000000000000000000000000000000000000007", "0x0000000000000000000000000000000000000004", "0x1F98431c8aD98523631AE4a59f267346ea31F984", "0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", "0xC57d000000000000000000000000000000000011", "0x9D25057e62939D3408406975aD75Ffe834DA4cDd", "0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C", "0x4B8d90D68F26DEF303Dcb6CFc9b63A1aAEC15840", "0xCB876f60399897db24058b2d58D0B9f713175eeF"],
    amounts : ["5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000","5000000000000000000000"]
  }
  //const desired = {
  //  protocols : ["0x99c666810bA4Bf9a4C2318CE60Cb2c279Ee2cF56", "0x0000000000000000000000000000000000000001", "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", "0xB17640796e4c27a39AF51887aff3F8DC0daF9567", "0xe20A5C79b39bC8C363f0f49ADcFa82C2a01ab64a", "0xF403C135812408BFbE8713b5A23a04b3D48AAE31", "0x7a9701453249e84fd0D5AfE5951e9cBe9ed2E90f", "0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2", "0x0000000000000000000000000000000000000008", "0x0000000000000000000000000000000000000007", "0x0000000000000000000000000000000000000004", "0x1F98431c8aD98523631AE4a59f267346ea31F984", "0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9", "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", "0xC57d000000000000000000000000000000000011", "0x9D25057e62939D3408406975aD75Ffe834DA4cDd", "0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C", "0x4B8d90D68F26DEF303Dcb6CFc9b63A1aAEC15840", "0xCB876f60399897db24058b2d58D0B9f713175eeF"],
  //amounts : [20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000, 20000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000]
  //};
  let toBe = {
    protocols : [],
    amounts: []
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
        const VaultFactory = await ethers.getContractFactory("arNXMVault");
    const newVault = await VaultFactory.deploy();
    const ProxyFactory = await ethers.getContractFactory("OwnedUpgradeabilityProxy");
    const toUpdate = await ProxyFactory.attach(arNXMVault.address);
    await toUpdate.connect(owner).upgradeTo(newVault.address);


    const oldProtocols = await pool.stakerContractsArray(arnxm_mainnet);
    await arNXMVault.connect(owner).changeReserveAmount(0);
    //first fill in the old protocols
    for(let i = 0; i < oldProtocols.length; i++) {
      const idx = desired.protocols.findIndex((e) => e.toLowerCase() === oldProtocols[i].toLowerCase());
      if(idx === -1) {
        toBe.protocols.push(oldProtocols[i]);
        toBe.amounts.push(BigNumber.from(0));
      } else {
        toBe.protocols.push(oldProtocols[i]);
        if(desired.amounts.length <= idx) {
          toBe.amounts.push(BigNumber.from(0));
        } else {
          toBe.amounts.push(BigNumber.from(desired.amounts[idx]));
          desired.amounts.splice(idx, 1);
        }
        desired.protocols.splice(idx, 1);
      }
    }
    // then fill new protocols
    for(let i = 0; i< desired.protocols.length; i++){
      if(desired.amounts.length > i){ 
        toBe.protocols.push(desired.protocols[i]);
        toBe.amounts.push(BigNumber.from(desired.amounts[i]));
      }
    }
    for(let i = 0; i<oldProtocols.length; i++){
      console.log(oldProtocols[i]);
      console.log(toBe.protocols[i]);
    }
    console.log(oldProtocols.length);
    console.log(toBe.protocols.length);
    console.log("BALANCE");
    console.log(await nxm.balanceOf(arNXMVault.address));
    console.log("pending");
    console.log(await arNXMVault.totalPending());
  });

  it("should manual stake", async function(){
    const res = arNXMVault.interface.encodeFunctionData("stakeNxmManual", [toBe.protocols, toBe.amounts]);
    console.log(res);
    await arNXMVault.connect(owner).stakeNxmManual(toBe.protocols, toBe.amounts);
  });
});
