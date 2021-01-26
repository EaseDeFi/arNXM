import { ethers } from "hardhat";
import { constants, providers, Contract, Signer, BigNumber } from "ethers";
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

describe('ReferralRewards', function(){
  let referralRewards : Contract;
  let owner : Signer;
  let user : Signer;
  let referral : Signer;
  let stakeController: Signer;
  let rewardToken: Contract;
  let amount = ether("1");
  beforeEach(async function(){
    let signers = await ethers.getSigners();
    owner = signers[0];
    user = signers[1];
    referral = signers[2];
    stakeController = signers[3];
    const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
    const ReferralRewards = await ethers.getContractFactory('ReferralRewards');

    rewardToken = await ERC20Mock.deploy();
    await rewardToken.connect(owner).mint(owner.getAddress(),amount.mul(BigNumber.from(1000)));
    referralRewards = await ReferralRewards.deploy();
    await referralRewards.connect(owner).initialize(rewardToken.address, stakeController.getAddress());
  });

  describe('#initialize()', function(){
    it('should fail if already initialized', async function(){
      await expect(referralRewards.connect(owner).initialize(rewardToken.address, stakeController.getAddress())).to.be.revertedWith("already initialized");
    });
  });

  describe('#stake()', function(){
    it('should fail if msg.sender is not stakeManager', async function(){
      await expect(referralRewards.connect(user).stake(user.getAddress(), referral.getAddress(), amount)).to.be.revertedWith("Caller is not stake controller.");
    });

    it('should update user\'s reward', async function(){
      await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
    });

    it('should increase totalSupply', async function(){
      const totalSupply = await referralRewards.totalSupply();
      await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
      expect(await referralRewards.totalSupply()).to.be.equal(totalSupply.add(amount));
    });
    
    it('should increase balance', async function(){
      const balance = await referralRewards.balanceOf(user.getAddress());
      await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
      expect(await referralRewards.balanceOf(user.getAddress())).to.be.equal(balance.add(amount));
    });
  });
  
  describe('#withdraw()', function(){
    beforeEach(async function(){
      await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
    });
    it('should fail if msg.sender is not stakeManager', async function(){
      await expect(referralRewards.connect(user).withdraw(user.getAddress(), referral.getAddress(), amount)).to.be.revertedWith("Caller is not stake controller.");
    });

    it('should update user\'s reward', async function(){
      await referralRewards.connect(stakeController).withdraw(user.getAddress(), referral.getAddress(), amount);
    });

    it('should decrease totalSupply', async function(){
      const totalSupply = await referralRewards.totalSupply();
      await referralRewards.connect(stakeController).withdraw(user.getAddress(), referral.getAddress(), amount);
      expect(await referralRewards.totalSupply()).to.be.equal(totalSupply.sub(amount));
    });
    
    it('should decrease balance', async function(){
      const balance = await referralRewards.balanceOf(user.getAddress());
      await referralRewards.connect(stakeController).withdraw(user.getAddress(), referral.getAddress(), amount);
      expect(await referralRewards.balanceOf(user.getAddress())).to.be.equal(balance.sub(amount));
    });
  });

  describe('ERC20', function() {
    describe('#getReward()', function(){
      beforeEach(async function(){
        await rewardToken.connect(owner).transfer(stakeController.getAddress(), amount);
        await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
        await rewardToken.connect(stakeController).approve(referralRewards.address, amount);
        await referralRewards.connect(stakeController).notifyRewardAmount(amount);
      });

      it("should do nothing if user does not have any reward", async function(){
        await referralRewards.connect(stakeController).getReward(owner.getAddress());
      });

      it("should payout the reward if user has reward", async function(){
        await increase(1);
        await mine();
        const earned = await referralRewards.earned(user.getAddress());
        const balance = await rewardToken.balanceOf(user.getAddress());
        await referralRewards.connect(stakeController).getReward(user.getAddress());
        expect(await rewardToken.balanceOf(user.getAddress())).to.be.equal(balance.add(earned));
      });
    });

    describe('#notifyRewardAmount()', function(){
      beforeEach(async function(){
        await rewardToken.connect(owner).transfer(stakeController.getAddress(), amount);
        await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
        await rewardToken.connect(stakeController).approve(referralRewards.address, amount);
      });

      it("should fail if msg.sender is not stakeController", async function(){
        await expect(referralRewards.connect(user).notifyRewardAmount(amount)).to.be.revertedWith("Caller is not stake controller.");
      });

      it("should fail if msg.value is not zero", async function(){
        await expect(referralRewards.connect(stakeController).notifyRewardAmount(amount, {value:1})).to.be.revertedWith("Do not send ETH");
      });

      it("should be able to handle multiple notification in one block", async function(){
        const CallerFactory = await ethers.getContractFactory("CallTwice");
        const caller = await CallerFactory.deploy();
        const ReferralRewards = await ethers.getContractFactory("ReferralRewards");
        const temp = await ReferralRewards.deploy();
        await temp.connect(owner).initialize(rewardToken.address, caller.address);
        await rewardToken.mint(caller.address, amount);
        await caller.execute(temp.address,rewardToken.address, amount);
      });
    });
  });
  describe('ETH', function() {
    beforeEach(async function(){
      const ReferralRewards = await ethers.getContractFactory("ReferralRewards");
      referralRewards = await ReferralRewards.deploy();
      await referralRewards.connect(owner).initialize(constants.AddressZero, stakeController.getAddress());
    });
    describe('#getReward()', function(){
      beforeEach(async function(){
        await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
        await referralRewards.connect(stakeController).notifyRewardAmount(amount, {value:amount});
      });

      it("should do nothing if user does not have any reward", async function(){
        await referralRewards.connect(stakeController).getReward(owner.getAddress());
      });

      it("should payout the reward if user has reward", async function(){
        await increase(1);
        await mine();
        const earned = await referralRewards.earned(user.getAddress());
        const balance = await user.getBalance();
        await referralRewards.connect(stakeController).getReward(user.getAddress());
        expect(await user.getBalance()).to.be.equal(balance.add(earned));
      });
    });

    describe('#notifyRewardAmount()', function(){
      beforeEach(async function(){
        await referralRewards.connect(stakeController).stake(user.getAddress(), referral.getAddress(), amount);
      });

      it("should fail if msg.sender is not stakeController", async function(){
        await expect(referralRewards.connect(user).notifyRewardAmount(amount, {value:amount})).to.be.revertedWith("Caller is not stake controller.");
      });

      it("should fail if msg.value does not match amount", async function(){
        await expect(referralRewards.connect(stakeController).notifyRewardAmount(amount, {value:1})).to.be.revertedWith("Correct reward was not sent.");
      });

      it("should be able to handle multiple notification in one block", async function(){
        const CallerFactory = await ethers.getContractFactory("CallTwice");
        const caller = await CallerFactory.deploy();
        const ReferralRewards = await ethers.getContractFactory("ReferralRewards");
        const temp = await ReferralRewards.deploy();
        await temp.connect(owner).initialize(constants.AddressZero, caller.address);
        await caller.executeETH(temp.address);
      });
    });
  });
});
