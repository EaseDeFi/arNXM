import { network, ethers } from "hardhat";
import { providers, Contract, Signer, BigNumber, utils } from "ethers";
import { expect } from "chai";
import { increase, getTimestamp } from './utils';
const pool_mainnet = "0x84edffa16bb0b9ab1163abb0a13ff0744c11272f";
const arnxm_mainnet = "0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4";
const gov_mainnet = "0x1f28ed9d4792a567dad779235c2b766ab84d8e33";
const nxm_whale = "0x598Dbe6738E0AcA4eAbc22feD2Ac737dbd13Fb8F";
const nxm_mainnet = "0xd7c49cee7e9188cca6ad8ff264c1da2e69d4cf3b";

BigNumber.prototype.toJSON = function toJSON(key) {
    return this.toString();
};

let arNXMVault : Contract;
let pool : Contract;
let nxm : Contract;
let owner : Signer;

async function restake(protocols: string[]) {
  await increase(86400 + 1);
  await pool.processPendingActions(100);
  await pool.processPendingActions(100);
  await pool.processPendingActions(100);
  await pool.processPendingActions(100);
  await pool.processPendingActions(100);
  await pool.processPendingActions(100);
  console.log((await getTimestamp()).toString());
  await printStatus(protocols);
  let lastId = await pool.lastUnstakeRequestId();
  const request = await pool.unstakeRequests(lastId);
  if(request.unstakeAt.toNumber() == 0) {
    lastId = 0;
  }
  await arNXMVault.connect(owner).restake(lastId);
  await printStatus(protocols);
}
async function printStatus(protocols : string[]) {
  if(protocols.length == 0){
    protocols = await pool.stakerContractsArray(arnxm_mainnet);
  }
  let list = [];
  let stakeSum = BigNumber.from(0);
  for(let i = 0; i<protocols.length; i++) {
    const data = {
      protocol : protocols[i],
      stake : utils.formatEther(await pool.stakerContractStake(arNXMVault.address, protocols[i])),
      unstake : utils.formatEther(await pool.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[i])),
      net : utils.formatEther((await pool.stakerContractStake(arNXMVault.address, protocols[i])).sub(await pool.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[i]))),
    }
    stakeSum = stakeSum.add(await pool.stakerContractStake(arNXMVault.address, protocols[i]));
    list.push(data);
  }
  const protocolData = {
    balance : utils.formatEther(await nxm.balanceOf(arNXMVault.address)),
    deposit : utils.formatEther(await pool.stakerDeposit(arNXMVault.address)),
    withdrawable : utils.formatEther(await pool.stakerMaxWithdrawable(arNXMVault.address)),
    totalPending : utils.formatEther(await arNXMVault.totalPending()),
    reserve : utils.formatEther(await arNXMVault.reserveAmount()),
    exposure : utils.formatEther(stakeSum)
  }
  console.table(protocolData);
  console.table(list);
}
describe.only('arnxm', function(){
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

    let lastId = await pool.lastUnstakeRequestId();
    const oldProtocols = await pool.stakerContractsArray(arnxm_mainnet);
    //first fill in the old protocols
    for(let i = 0; i < oldProtocols.length; i++) {
      const idx = desired.protocols.findIndex((e) => e.toLowerCase() === oldProtocols[i].toLowerCase());
      if(idx === -1) {
        toBe.protocols.push(oldProtocols[i]);
        toBe.amounts.push(BigNumber.from(0));
        toBe.unstakePercents.push(BigNumber.from(700));
      } else {
        toBe.protocols.push(oldProtocols[i]);
        if(desired.amounts.length <= idx) {
          toBe.amounts.push(BigNumber.from(0));
          toBe.unstakePercents.push(BigNumber.from(700));
        } else {
          toBe.amounts.push(BigNumber.from(desired.amounts[idx]));
          toBe.unstakePercents.push(BigNumber.from(700));
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
    lastId = await pool.lastUnstakeRequestId();
  });

  it.skip("current status", async function(){
    await printStatus(toBe.protocols);
  })

  it.only('changeProtocol - stakeManual', async function() {
    let unstaking = {
      address : [
        "0xf403c135812408bfbe8713b5a23a04b3d48aae31",
        "0xc57d000000000000000000000000000000000013",
        "0xc57d000000000000000000000000000000000012",
        "0xa39739ef8b0231dbfa0dcda07d7e29faabcf4bb2",
        "0xcc88a9d330da1133df3a7bd823b95e52511a6962",
        "0x0000000000000000000000000000000000000001",
        "0xb17640796e4c27a39af51887aff3f8dc0daf9567",
        "0x99c666810ba4bf9a4c2318ce60cb2c279ee2cf56",
      ],
      percents : [
        "330",
        "750",
        "750",
        "750",
        "750",
        "330",
        "750",
        "750",

      ]
    }
    const staking = {
      address : [
        "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9",
      ],
      amounts : [
        "100000000000000000000000",
      ]
    }
    for(let i = 0; i<staking.address.length; i++){
      unstaking.address.push(staking.address[i]);
      unstaking.percents.push("70");
    }
    await printStatus([]);
    let lastId = await pool.lastUnstakeRequestId();
    const ci  = arNXMVault.interface;
    //console.log(unstaking.address);
    //console.log(unstaking.percents);
    //console.log(lastId);
    //await arNXMVault.connect(owner).changeProtocols(unstaking.address, unstaking.percents, [], lastId);
    //await arNXMVault.connect(owner).changeCheckpointAndStart(0,0);
    console.log(staking.address);
    console.log(staking.amounts);
    console.log(arNXMVault.interface.encodeFunctionData("stakeNxmManual", [staking.address, staking.amounts]));
    await arNXMVault.connect(owner).stakeNxmManual(staking.address, staking.amounts);
    //console.log(ci.encodeFunctionData("restake", [lastId]));
    //await arNXMVault.connect(owner).restake(lastId);
    await printStatus([]);

    //await restake(unstaking.address);
  });
});
