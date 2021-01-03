import { ethers } from "hardhat";
import { time } from "@openzeppelin/test-helpers";
import { providers, Contract, Signer, BigNumber } from "ethers";
import { NexusMutual } from "./NexusMutual";
import { expect } from "chai";

function ether(amount: string) : BigNumber {
  return ethers.utils.parseEther(amount);
}

async function increase(seconds: number) {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  await (signer.provider as providers.JsonRpcProvider).send("evm_increaseTime", [seconds]);
  await (signer.provider as providers.JsonRpcProvider).send("evm_mine", []);
}

const EXCHANGE_TOKEN = ether('10000');
const EXCHANGE_ETHER = ether('10');
const AMOUNT = ether('1000');
describe('arnxm', function(){
  let arNXMVault : Contract;
  let arNXM : Contract;
  let referralRewards : Contract;
  let owner : Signer;
  let user : Signer;
  let ownerAddress : string;
  let userAddress : string;
  let nxm : NexusMutual;
  let wNXM : Contract;

  let protocols : Contract[] = [];

  beforeEach(async function(){
    protocols = [];
    let signers = await ethers.getSigners();
    owner = signers[0];
    user = signers[1];
    userAddress = await user.getAddress();
    ownerAddress = await owner.getAddress();
    nxm = new NexusMutual(owner);
    // deploy external contracts
    const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
    const ExchangeFactoryMock = await ethers.getContractFactory('ExchangeFactoryMock');
    const ExchangeMock = await ethers.getContractFactory('ExchangeMock');
    const WNXM = await ethers.getContractFactory('wNXM');
    const ARNXM = await ethers.getContractFactory('ArNXMToken');
    const ARNXMVault = await ethers.getContractFactory('arNXMVault');
    const ReferralRewards = await ethers.getContractFactory('ReferralRewards');
    const dai = await ERC20Mock.deploy();
    const factory = await ExchangeFactoryMock.deploy();
    const exchange = await ExchangeMock.deploy(dai.address, factory.address);

    // initialize external contracts
    await dai.connect(owner).mint(ownerAddress, ether('10000000'));
    await factory.setFactory(dai.address, exchange.address);
    await dai.transfer(exchange.address, EXCHANGE_TOKEN);
    await exchange.recieveEther({ value: EXCHANGE_ETHER });
    await nxm.deploy(dai, factory);

    const protocol_0 = await ERC20Mock.deploy();
    const protocol_1 = await ERC20Mock.deploy();
    const protocol_2 = await ERC20Mock.deploy();
    const protocol_3 = await ERC20Mock.deploy();
    protocols.push(protocol_0);
    protocols.push(protocol_1);
    protocols.push(protocol_2);
    protocols.push(protocol_3);

    const protocolsAddress = protocols.map(x=>x.address);
    
    wNXM = await WNXM.deploy(nxm.nxm.address);
    arNXMVault = await ARNXMVault.deploy()
    arNXM = await ARNXM.deploy(arNXMVault.address);
    referralRewards = await ReferralRewards.deploy()
    await arNXMVault.initialize(protocolsAddress, wNXM.address, arNXM.address,nxm.nxm.address, nxm.master.address, referralRewards.address);
    await referralRewards.initialize(arNXM.address, arNXMVault.address);
    await nxm.registerUser(userAddress);
    await nxm.registerUser(wNXM.address);
    await nxm.registerUser(arNXMVault.address);
    await nxm.nxm.connect(owner).transfer(userAddress, AMOUNT.mul(1000)); 
    await nxm.nxm.connect(user).approve(wNXM.address, AMOUNT.mul(1000));
    await nxm.nxm.connect(owner).approve(wNXM.address, AMOUNT.mul(1000)); 
  });

  describe('#deposit', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT.mul(3));
    });

    it('should give correct arNxm when nothing is staked and increase referrer stake', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);
      expect(await arNXM.balanceOf(userAddress)).to.equal(AMOUNT);
      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT);
    });
    
    it('should give correct arNxm when there are rewards in contract', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);

      // Mimicking the contract having received rewards.
      await wNXM.connect(user).transfer(arNXMVault.address, AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);

      // If X arNXM was minted and X * 2 wNXM is in the contract, each wNXM should only mint 0.5 arNXM.
      expect(await arNXM.balanceOf(userAddress)).to.equal(AMOUNT.add(AMOUNT.div(2)));
    });

    it('should give correct total assets under management', async function(){
      expect(await arNXMVault.aum()).to.equal(0);

      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);
      expect(await arNXMVault.aum()).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await wNXM.connect(user).transfer(arNXMVault.address, AMOUNT);
      expect(await arNXMVault.aum()).to.equal(AMOUNT.mul(2));
    });
  });

  describe('#restake', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);
      await arNXMVault.connect(user).approveNxmToWNXM();
      await arNXMVault.connect(owner).restake();
    });

    it('should not be able to restake before 7 days', async function(){
      await expect(arNXMVault.connect(owner).restake()).to.be.revertedWith("It has not been 7 days since the last restake.")
      await increase(86400 * 7);
      await arNXMVault.connect(owner).restake();
    });

    it('should stake all protocols correctly', async function(){
      let stake = AMOUNT.div(10).mul(9);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(stake);
    });

    it('should unstake all protocols correctly', async function(){
      // Sorta complicated way to do it but the most clear without hardcoding (divided by 10 multiplied by 9 == 90%, divided by 100 multiplied by 7 == 7% of 90%).
      let unstake = AMOUNT.div(10).mul(9).div(100).mul(7);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[1].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[3].address)).to.equal(unstake);
    });

    it('should withdraw and restake all protocols correctly', async function(){
      console.log("Last unstake request id 1:")
      let unstakeId = await nxm.pooledStaking.lastUnstakeRequestId();
      console.log(unstakeId.toString())

      console.log("Last unstake request 1:")
      let request = await nxm.pooledStaking.unstakeRequests(unstakeId);
      console.log(request.toString());

      //expect(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address)).to.equal(ether('0'));

      // Process pending unstakes
      await increase(86400 * 90);
      await nxm.pooledStaking.processPendingActions(100);

      console.log("Last unstake request id 2:")
      unstakeId = await nxm.pooledStaking.lastUnstakeRequestId();
      console.log(unstakeId.toString())

      console.log("Last unstake request 2:")
      request = await nxm.pooledStaking.unstakeRequests(unstakeId);
      console.log(request.toString());

      await arNXMVault.connect(owner).restake();

      //expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(stake);
    });

    // stake, use mockReward to give reward to users, restake, check rewards on arNXMVault and referralRewards. Also withdraw individual referrer in correct amount.
    it('should reward stakers and referrers correctly', async function(){

    });

  });

  describe('#withdraw', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT.mul(2));
      await wNXM.connect(owner).wrap(AMOUNT.mul(2));
    });

    it('should withdraw correct amount of wNXM and decrease referrer stake', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);

      // Mimicking the contract having received rewards.
      await wNXM.connect(owner).transfer(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).withdraw(AMOUNT);

      expect(await wNXM.balanceOf(userAddress)).to.equal(AMOUNT.mul(3));
      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(ether('0'))
    });

    it('should give correct total assets under management', async function(){
      expect(await arNXMVault.aum()).to.equal(0);

      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);
      expect(await arNXMVault.aum()).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await wNXM.connect(user).transfer(arNXMVault.address, AMOUNT);
      expect(await arNXMVault.aum()).to.equal(AMOUNT.mul(2));
    });
  });

  describe('#token', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(owner).wrap(AMOUNT);
    });

    it('should adjust referrer on token transfer', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress);

      await wNXM.connect(owner).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(owner).deposit(AMOUNT, userAddress);

      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT);
      expect(await referralRewards.balanceOf(userAddress)).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await arNXM.connect(owner).transfer(userAddress, AMOUNT);

      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT.mul(2));
      expect(await referralRewards.balanceOf(userAddress)).to.equal(ether('0'));
    });
  });

});
