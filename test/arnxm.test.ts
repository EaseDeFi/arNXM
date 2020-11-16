import { ethers } from "hardhat";
import { time } from "@openzeppelin/test-helpers";
import { Contract, Signer, BigNumber } from "ethers";
import { NexusMutual } from "./NexusMutual";

function ether(amount: string) : BigNumber {
  return ethers.utils.parseEther(amount);
}

const EXCHANGE_TOKEN = ether('10000');
const EXCHANGE_ETHER = ether('10');

describe('arnxm', function(){
  let arNXM : Contract;
  let owner : Signer;
  let nxm : NexusMutual;
  beforeEach(async function(){
    let signers = await ethers.getSigners();
    owner = signers[0];
    nxm = new NexusMutual(owner);
  });

  it('deploy check', async function(){
    // deploy external contracts
    const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
    const ExchangeFactoryMock = await ethers.getContractFactory('ExchangeFactoryMock');
    const ExchangeMock = await ethers.getContractFactory('ExchangeMock');
    const dai = await ERC20Mock.deploy();
    const factory = await ExchangeFactoryMock.deploy();
    const exchange = await ExchangeMock.deploy(dai.address, factory.address);

    // initialize external contracts
    await dai.connect(owner).mint(await owner.getAddress(), ether('10000000'));
    await factory.setFactory(dai.address, exchange.address);
    await dai.transfer(exchange.address, EXCHANGE_TOKEN);
    await exchange.recieveEther({ value: EXCHANGE_ETHER });
    await nxm.deploy(dai, factory);
  });
});
