import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer } from "ethers";

export async function deployProxy(contract: ContractFactory) : Promise<Contract> {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const implementation = await contract.deploy();
  const proxy = await OwnedUpgradeabilityProxy.deploy(implementation.address);
  return contract.attach(proxy.address);
};

export async function upgradeProxy(proxyAddress: string, contract: ContractFactory) {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const implementation = await contract.deploy();
  const proxy = await OwnedUpgradeabilityProxy.attach(proxyAddress);
  await proxy.upgradeTo(implementation.address);
};

export async function transferProxyOwnership(proxyAddress: string, deployOwner: string) {
  const OwnedUpgradeabilityProxy = await ethers.getContractFactory('OwnedUpgradeabilityProxy');
  const proxy = await OwnedUpgradeabilityProxy.attach(proxyAddress);
  await proxy.transferProxyOwnership(deployOwner);
};
