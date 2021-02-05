import { ethers } from "hardhat";
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
}

async function mine() {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  await (signer.provider as providers.JsonRpcProvider).send("evm_mine", []);
}

async function getTimestamp() {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  let number = await (signer.provider as providers.JsonRpcProvider).getBlockNumber();
  let block = await (signer.provider as providers.JsonRpcProvider).getBlock(number);
  return block.timestamp;
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
    
    // For proxy
    await arNXMVault.connect(owner).changeProtocols(protocolsAddress,[100,100,100,100],[],0);
    await arNXMVault.connect(owner).changeBucketSize(2);
    
    await referralRewards.initialize(arNXM.address, arNXMVault.address);
    await nxm.registerUser(userAddress);
    await nxm.registerUser(wNXM.address);
    await nxm.registerUser(arNXMVault.address);
    await nxm.nxm.connect(owner).transfer(userAddress, AMOUNT.mul(1000)); 
    await nxm.nxm.connect(user).approve(wNXM.address, AMOUNT.mul(1000));
    await nxm.nxm.connect(owner).approve(wNXM.address, AMOUNT.mul(1000));
  });

  describe('Shield mining rewards', function(){
    let shieldReward: Contract;
    let shieldMining: Contract;
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      await arNXMVault.connect(owner).restake(await getIndex());

      const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
      shieldReward = await ERC20Mock.deploy();

      const ShieldMining = await ethers.getContractFactory("CommunityStakingIncentives");
      const startTime = await getTimestamp();
      shieldMining = await ShieldMining.deploy(86400*7, startTime + 10 ,nxm.master.address); 
    });

    it("should be able to withdraw the mining rewards", async function(){
      await increase(100);
      await shieldReward.connect(owner).mintToSelf(ether("10"));
      await shieldReward.connect(owner).approve(shieldMining.address, ether("10"));
      await shieldMining.depositRewardsAndSetRate(protocols[0].address, shieldReward.address, ether("10"), ether("1"));
      await increase(1000);
      await arNXMVault.connect(owner).getShieldMiningRewards(shieldMining.address, protocols[0].address, owner.getAddress(), shieldReward.address);
      const balance = await shieldReward.balanceOf(arNXMVault.address);
      expect(balance).to.not.equal(0);
    });
  });

  describe('#deposit', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT.mul(3));
    });

    it('should give correct arNxm when nothing is staked and increase referrer stake', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      expect(await arNXM.balanceOf(userAddress)).to.equal(AMOUNT);
      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT);
    });
    
    it('should give correct arNxm when there are rewards in contract', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);

      // Mimicking the contract having received rewards.
      await nxm.nxm.connect(user).transfer(arNXMVault.address, AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);

      // If X arNXM was minted and X * 2 wNXM is in the contract, each wNXM should only mint 0.5 arNXM.
      expect(await arNXM.balanceOf(userAddress)).to.equal(AMOUNT.add(AMOUNT.div(2)));
    });

    it('should give correct total assets under management', async function(){
      expect(await arNXMVault.aum()).to.equal(0);

      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      expect(await arNXMVault.aum()).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await nxm.nxm.connect(user).transfer(arNXMVault.address, AMOUNT);
      expect(await arNXMVault.aum()).to.equal(AMOUNT.mul(2));
    });
  });

  // This block used for restake to find next index we can unstake after.
  async function getIndex() {
    let index = 0;
    while (true) {
      let request = await nxm.pooledStaking.unstakeRequests(index)
      if (request.next > 0) index = request.next;
      else break;
    }
    return index;
  }

  describe('#restake', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT.mul(2));
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT.mul(2));
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      await arNXMVault.connect(owner).restake(await getIndex());
    });

    it('should not be able to restake before 3 days', async function(){
      await expect(arNXMVault.connect(owner).restake(await getIndex())).to.be.revertedWith("It has not been enough time since the last restake.")
      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
    });

    it('should stake all protocols correctly through rotations', async function(){
      let stake = AMOUNT.sub(ether("30"));
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(0);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(0);

      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());

      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(stake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(stake.add(ether("30")));
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(stake.add(ether("30")));
    });

    it('should unstake all protocols correctly through rotations', async function(){
      // Unstaking 10% of what's staked
      let unstake = AMOUNT.sub(ether("30")).div(100).mul(10);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(0);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(0);

      await arNXMVault.connect(owner).restake(await getIndex());
      await increase(86400 * 3);

      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(unstake);

      let unstakeTwo = unstake.add(AMOUNT.sub(unstake).div(100).mul(10));
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(unstakeTwo);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(unstakeTwo);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(unstake);

      await arNXMVault.connect(owner).restake(await getIndex());
      await increase(86400 * 3);

      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[0].address)).to.equal(unstakeTwo);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[1].address)).to.equal(unstakeTwo);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[2].address)).to.equal(unstakeTwo);
      expect(await nxm.pooledStaking.stakerContractStake(arNXMVault.address, protocols[3].address)).to.equal(unstakeTwo);
      console.log("#1 start");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[1].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(0);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[3].address)).to.equal(0);

      console.log("#1 done");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));

      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT.sub(ether("30")), ownerAddress, false);
      console.log("#2 start");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));
      let withdrawable = await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address);
      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());

      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[1].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(unstake);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[3].address)).to.equal(unstake);
      console.log("#2 done");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));

      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT.sub(ether("30")), ownerAddress, false);
      withdrawable = await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address);
      console.log("#3 start");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));
      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
      unstakeTwo = unstake.add(AMOUNT.sub(ether("30")).add(withdrawable).div(10));
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstakeTwo);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[1].address)).to.equal(unstakeTwo);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(unstake);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[3].address)).to.equal(unstake);
      console.log("#3 done");
      console.log("Balance : " + await nxm.nxm.balanceOf(arNXMVault.address));

      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT.sub(ether("30")), ownerAddress, false);
      await increase(86400 * 3);
      withdrawable = await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address);
      let unstakeThree = unstake.add(AMOUNT.sub(ether("30")).add(withdrawable).div(10));
      await arNXMVault.connect(owner).restake(await getIndex());
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstakeTwo);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[1].address)).to.equal(unstakeTwo);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(unstakeThree);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[3].address)).to.equal(unstakeThree);
    });

    it('should withdraw and restake all protocols correctly', async function(){
      await increase(86400 * 3);
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT.sub(ether("30")), ownerAddress, false);
      let withdrawable = await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address);
      await arNXMVault.connect(owner).restake(await getIndex());

      await increase(86400 * 3);
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT.sub(ether("30")), ownerAddress, false);
      withdrawable = withdrawable.add(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address));
      await arNXMVault.connect(owner).restake(await getIndex());

      // TODO: this is all messed up cause of rotation

      // 10% of AMOUNT + 10% of AMOUNT - 10%
      let unstakeOne = AMOUNT.div(10);
      let unstakeTwo = AMOUNT.sub(unstakeOne).div(10);
      expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstakeOne.add(unstakeTwo));
      expect(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address)).to.equal(ether('0'));
      unstakeOne = AMOUNT.sub(ether("30")).div(10);
      unstakeTwo = unstakeOne.add(withdrawable.add(AMOUNT).sub(ether("30")).div(10));
      console.log(unstakeTwo.toString());
      console.log(withdrawable.toString());
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(unstakeTwo);
      //expect(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address)).to.equal(ether('0'));

      // Process pending unstakes
      await increase(86400 * 90);
      await nxm.pooledStaking.processPendingActions(100);
      //expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[0].address)).to.equal(ether('0'));
      //expect(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address)).to.equal(ether('291'));
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      let contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400 * 3);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await arNXMVault.connect(owner).changeCheckpointAndStart(2,2);
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      contracts = await nxm.pooledStaking.stakerContractsArray(arNXMVault.address);
      contracts.forEach( async (x) => {
        console.log(x);
        console.log((await nxm.pooledStaking.stakerContractStake(arNXMVault.address, x)).toString());
        console.log((await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, x)).toString());
      });
      await increase(86400* 30);
      await arNXMVault.connect(owner).changeCheckpointAndStart(0,0);
      console.log(0);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      await increase(86400* 30);
      //await arNXMVault.connect(owner).changeCheckpointAndStart(0,2);
      console.log(0);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
      await increase(86400* 30);
      //await arNXMVault.connect(owner).changeCheckpointAndStart(0,0);
      console.log(0);
      await nxm.pooledStaking.processPendingActions(100);
      await arNXMVault.connect(owner).ownerRestake(await getIndex());
     // expect(await nxm.pooledStaking.stakerMaxWithdrawable(arNXMVault.address)).to.equal(ether('0'));
     // expect(await nxm.pooledStaking.stakerContractPendingUnstakeTotal(arNXMVault.address, protocols[2].address)).to.equal(ether('97'));
    });
  });

  // TODO: Add checkpoint test
  // TODO: Add NXM deposit test

  describe('#getRewardNxm()', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      await arNXMVault.connect(owner).restake(await getIndex());
    });

    it('should just update the lastRewardTime when no rewards and lastRewardTime is not set', async function(){
      const prev = await arNXMVault.lastRewardTimestamp();
      expect(prev).to.equal(0);
      await arNXMVault.connect(owner).getRewardNxm();
      const after = await arNXMVault.lastRewardTimestamp();
      expect(after).to.not.equal(0);
    });

    it('should distribute through duration', async function(){
      await nxm.nxm.connect(owner).transfer(nxm.pooledStaking.address, AMOUNT);

      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
      expect(await nxm.nxm.balanceOf(arNXMVault.address)).to.equal(ether("30"));

      await nxm.pooledStaking.connect(owner).mockReward(arNXMVault.address, AMOUNT);

      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
      await increase(86400 * 1);
      await arNXMVault.connect(owner).getRewardNxm();
      const lastReward = await arNXMVault.lastReward();

      expect(await arNXMVault.currentReward()).to.equal(0);
      await increase(86400 * 1);
      await mine();
      expect(await arNXMVault.currentReward()).to.equal(lastReward.div(9));
      await increase(86400 * 1);
      await mine();
      expect(await arNXMVault.currentReward()).to.equal(lastReward.div(9).mul(2));
    });

    it('should reward referrers correctly', async function() {
      await nxm.nxm.connect(owner).transfer(nxm.pooledStaking.address, AMOUNT);

      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
      expect(await nxm.nxm.balanceOf(arNXMVault.address)).to.equal(ether("30"));

      await nxm.pooledStaking.connect(owner).mockReward(arNXMVault.address, AMOUNT);

      await increase(86400 * 3);
      await arNXMVault.connect(owner).restake(await getIndex());
      await arNXMVault.connect(owner).getRewardNxm();

      expect(await nxm.nxm.balanceOf(arNXMVault.address)).to.equal(AMOUNT.add(ether("30")));
      // 2.5% goes to referrers
      expect(await arNXM.balanceOf(referralRewards.address)).to.equal(AMOUNT.div(40));
      
      await increase(86400);
      await referralRewards.connect(owner).getReward(ownerAddress);
      expect(await arNXM.balanceOf(ownerAddress)).to.equal(AMOUNT.div(40));
    });
  });

  describe('#withdraw', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT.mul(2));
      await wNXM.connect(owner).wrap(AMOUNT.mul(2));
    });

    it('should withdraw correct amount of wNXM and decrease referrer stake', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);

      // Mimicking the contract having received rewards.
      await nxm.nxm.connect(owner).transfer(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).withdraw(AMOUNT);

      expect(await wNXM.balanceOf(userAddress)).to.equal(AMOUNT.mul(3));
      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(ether('0'))
    });

    it('should give correct total assets under management', async function(){
      expect(await arNXMVault.aum()).to.equal(0);

      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);
      expect(await arNXMVault.aum()).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await nxm.nxm.connect(user).transfer(arNXMVault.address, AMOUNT);
      expect(await arNXMVault.aum()).to.equal(AMOUNT.mul(2));
    });
  });

  describe('#pausing', function(){

    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);

      let timestamp = await getTimestamp();
      await nxm.claimsData.connect(owner).setClaimdateTest(1,timestamp);
      await nxm.claimsData.connect(owner).setClaimStatusTest(1,14);
      await arNXMVault.connect(user).pauseWithdrawals(1);
    });

    it('should pause if claim has recently happened', async function(){
      await expect(arNXMVault.connect(user).withdraw(AMOUNT)).to.be.revertedWith("Withdrawals are temporarily paused.");
    });

    it('should unpause after 10 days', async function(){
      await increase(86400 * 10 + 1);
      await arNXMVault.connect(user).withdraw(AMOUNT);
    });

    it('should not be able to pause again after 10 days', async function(){
      await increase(86400 * 10 + 1);
      await arNXMVault.connect(user).pauseWithdrawals(1);
      await arNXMVault.connect(user).withdraw(AMOUNT);
    });

  });

  describe('#token', function(){
    beforeEach(async function(){
      await wNXM.connect(user).wrap(AMOUNT);
      await wNXM.connect(owner).wrap(AMOUNT);
    });

    it('should adjust referrer on token transfer', async function(){
      await wNXM.connect(user).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(user).deposit(AMOUNT, ownerAddress, false);

      await wNXM.connect(owner).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(owner).deposit(AMOUNT, userAddress, false);

      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT);
      expect(await referralRewards.balanceOf(userAddress)).to.equal(AMOUNT);

      // Mimicking the contract having received rewards.
      await arNXM.connect(owner).transfer(userAddress, AMOUNT);

      expect(await referralRewards.balanceOf(ownerAddress)).to.equal(AMOUNT.mul(2));
      expect(await referralRewards.balanceOf(userAddress)).to.equal(ether('0'));
    });

    it("ERROR",async function(){
      await wNXM.connect(owner).approve(arNXMVault.address, AMOUNT);
      await arNXMVault.connect(owner).deposit(AMOUNT, userAddress, false);
      // fisrt send to user without referrer
      await arNXM.connect(owner).transfer(userAddress, AMOUNT);
      // then register referrer
      await wNXM.connect(user).approve(arNXMVault.address, 1);
      await arNXMVault.connect(user).deposit(1, ownerAddress, false);
      // Mimicking the contract having received rewards.
      await arNXM.connect(user).transfer(ownerAddress, AMOUNT);
    });

  });

});
