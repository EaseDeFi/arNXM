import { ethers } from "hardhat";
import { providers, Contract, Signer, BigNumber } from "ethers";

export function hexSized(str: string, length: number) : string {
  const raw = Buffer.from(str).toString('hex');
  const pad = "0".repeat(length*2 - raw.length);
  return '0x' + raw + pad;
}
export function hex(str: string) : string {
  return '0x' + Buffer.from(str).toString('hex');
}
export function sleep(ms: number) {
  new Promise(resolve => setTimeout(resolve, ms));
}
export async function increase(seconds: number) {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  await (signer.provider as providers.JsonRpcProvider).send(
    "evm_increaseTime",
    [seconds]
  );
}

export async function getTimestamp(): Promise<BigNumber> {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  const res = await (signer.provider as providers.JsonRpcProvider).send(
    "eth_getBlockByNumber",
    ["latest", false]
  );
  return BigNumber.from(res.timestamp);
}

