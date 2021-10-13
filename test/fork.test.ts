import { network, ethers } from "hardhat";
import { providers, Contract, Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { increase } from './utils';
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
    protocols : [],
    amounts : []
  };
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
    /////
    const VaultFactory = await ethers.getContractFactory("arNXMVault");
    const newVault = await VaultFactory.deploy();
    const ProxyFactory = await ethers.getContractFactory("OwnedUpgradeabilityProxy");
    const toUpdate = await ProxyFactory.attach(arNXMVault.address);
    await toUpdate.connect(owner).upgradeTo(newVault.address);
    /////

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
    console.log("OLD");
    console.log(oldProtocols);
    console.log("OLD END");
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
      }
    }
    // fill new protocols
    for(let i = 0; i< desired.protocols.length; i++){
      const idx = toBe.protocols.findIndex((e) => e.toLowerCase() == desired.protocols[i].toLowerCase());
      if(idx == -1) {
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

    //for(let i = 0; i< toBe.protocols.length; i++){
    //  console.log(toBe.protocols[i]);
    //}
    //const data = arNXMVault.interface.encodeFunctionData("changeProtocols", [toBe.protocols, toBe.unstakePercents, unstake.removedProtocols, lastId]);
    //
    console.log("CURRENT STATUS");
    for(let i = 0; i<toBe.protocols.length; i++) {
      console.log("Protocol : " + toBe.protocols[i]);
      console.log("Stake : " + await pool.stakerContractStake(arNXMVault.address, toBe.protocols[i]));
      console.log("Unstake : " + await pool.stakerContractPendingUnstakeTotal(arNXMVault.address, toBe.protocols[i]));
    }
    await arNXMVault.connect(owner).changeProtocols(toBe.protocols, toBe.unstakePercents, [], 0);
  });

  it("should manual stake", async function(){
    const res = arNXMVault.interface.encodeFunctionData("stakeNxmManual", [toBe.protocols, toBe.amounts]);
    let lastId = await pool.lastUnstakeRequestId();
    await arNXMVault.connect(owner).restake(lastId);
    console.log("CURRENT STATUS : after restake");
    await increase(7 * 86400 + 1);
    await pool.processPendingActions(100);
    lastId = await pool.lastUnstakeRequestId();
    await arNXMVault.connect(owner).restake(lastId);
    await increase(7 * 86400 + 1);
    await pool.processPendingActions(100);
    lastId = await pool.lastUnstakeRequestId();
    await arNXMVault.connect(owner).restake(lastId);
    await increase(7 * 86400 + 1);
    await pool.processPendingActions(100);
    lastId = await pool.lastUnstakeRequestId();
    await arNXMVault.connect(owner).restake(lastId);

    //for(let i = 0; i<toBe.protocols.length; i++) {
    //  console.log("Protocol : " + toBe.protocols[i]);
    //  console.log("Stake : " + await pool.stakerContractStake(arNXMVault.address, toBe.protocols[i]));
    //  console.log("Unstake : " + await pool.stakerContractPendingUnstakeTotal(arNXMVault.address, toBe.protocols[i]));
    //  console.log("Net stake : " + (await pool.stakerContractStake(arNXMVault.address, toBe.protocols[i])).sub(await pool.stakerContractPendingUnstakeTotal(arNXMVault.address, toBe.protocols[i])));
    //}
  });
});
