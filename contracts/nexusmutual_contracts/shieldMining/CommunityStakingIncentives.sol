/*
    Copyright (C) 2020 NexusMutual.io
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/
*/

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IPooledStakingv6.sol";
import "../interfaces/INXMMaster.sol";
contract CommunityStakingIncentives is ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  INXMMaster public master;
  uint public roundDuration;
  uint public roundsStartTime;
  uint public constant rewardRateScale = 1e18;

  /**
  * @dev Add rewards as a sponsor for a particular contract.
  * @param _roundDuration Duration of a reward round in seconds.
  * @param _roundsStartTime Timestamp in seconds at which rounds start. Needs to be in the future.
  * @param masterAddress NexusMutual Master contract address.
  */
  constructor(uint _roundDuration, uint _roundsStartTime, address masterAddress) public {

    require(_roundDuration > 0, "_roundDuration needs to be greater than 0");
    require(_roundsStartTime >= now, "_roundsStartTime needs to be in the future");
    roundDuration = _roundDuration;
    roundsStartTime = _roundsStartTime;
    master = INXMMaster(masterAddress);
  }

  struct RewardPool {
    uint amount;
    // rate nextRate and nextRateStartRound  may not be up to date. use _getRates to get the up to date values.
    uint rate;
    uint nextRate;
    uint nextRateStartRound;
    mapping(address => uint) lastRoundClaimed;
  }

  // stakedContractAddress => sponsorAddress => tokenAddress => RewardPool
  mapping (address => mapping (address => mapping (address => RewardPool))) rewardPools;

  event Deposited (
    address indexed stakedContract,
    address indexed sponsor,
    address tokenAddress,
    uint amount
  );

  event Withdrawn (
    address stakedContract,
    address sponsor,
    address tokenAddress,
    uint amount
  );

  event Claimed (
    address stakedContract,
    address sponsor,
    address tokenAddress,
    uint amount,
    address receiver,
    uint roundNumber
  );

  /**
  * @dev set the reward ratio as a sponsor for a particular contract and ERC20 token.
  * @param stakedContract Contract the staker has a stake on.
  * @param tokenAddress Address of the ERC20 token of the reward funds.
  * @param rate Rate between the NXM stake and the reward amount. (Scaled by 1e18)
  */
  function setRewardRate(address stakedContract, address tokenAddress, uint rate) public {

    RewardPool storage pool = rewardPools[stakedContract][msg.sender][tokenAddress];

    uint currentRound = getCurrentRound();
    uint currentRate;
    (currentRate, , ) = _getRates(pool, currentRound);
    if (currentRate == 0) {
      // set the rate for the current round
      pool.rate = rate;
      pool.nextRate = 0;
      pool.nextRateStartRound = 0;
    } else {
      // set the rate for the next round
      if (pool.rate != currentRate) {
        pool.rate = pool.nextRate;
      }
      pool.nextRate = rate;
      pool.nextRateStartRound = currentRound + 1;
    }
  }

  /**
  * @dev Add rewards as a sponsor for a particular contract.
  * @param stakedContract Contract the staker has a stake on.
  * @param tokenAddress Address of the ERC20 token of the reward funds.
  * @param amount Amount of rewards to be deposited.
  */
  function depositRewards(address stakedContract, address tokenAddress, uint amount) public {

    IERC20 erc20 = IERC20(tokenAddress);
    erc20.safeTransferFrom(msg.sender, address(this), amount);
    RewardPool storage pool = rewardPools[stakedContract][msg.sender][tokenAddress];
    pool.amount = pool.amount.add(amount);
    emit Deposited(stakedContract, msg.sender, tokenAddress, amount);
  }

  /**
  * @dev Add rewards as a sponsor for a particular contract.
  * @param stakedContract Contract the staker has a stake on.
  * @param tokenAddress Address of the ERC20 token of the reward funds.
  * @param amount Amount of rewards to be deposited.
  * @param rate Rate between the NXM stake and the reward amount. (Scaled by 1e18)
  */
  function depositRewardsAndSetRate(address stakedContract, address tokenAddress, uint amount, uint rate) external {
    depositRewards(stakedContract, tokenAddress, amount);
    setRewardRate(stakedContract, tokenAddress, rate);
  }

  /**
  * @dev Calls claimReward for each separate (stakedContract, sponsor, token) tuple specified.
  * @param stakedContracts Contracts the staker has a stake on.
  * @param sponsors Sponsors to claim rewards from.
  * @param tokenAddresses Addresses of the ERC20 token of the reward funds.
  * @return tokensRewarded Tokens rewarded by each sponsor.
  */
  function claimRewards(
    address[] calldata stakedContracts,
    address[] calldata sponsors,
    address[] calldata tokenAddresses
  ) external nonReentrant returns (uint[] memory tokensRewarded) {

    require(stakedContracts.length == sponsors.length, "stakedContracts.length != sponsors.length");
    require(stakedContracts.length == tokenAddresses.length, "stakedContracts.length != tokenAddresses.length");

    tokensRewarded = new uint[](stakedContracts.length);
    for (uint i = 0; i < stakedContracts.length; i++) {
      tokensRewarded[i] = claimReward(stakedContracts[i], sponsors[i], tokenAddresses[i]);
    }
  }

  /**
  * @dev Claims reward as a NexusMutual staker.
  * @param stakedContract contract the staker has a stake on.
  * @param sponsor Sponsor providing the reward funds.
  * @param tokenAddress address of the ERC20 token of the reward funds.
  * @return rewardAmount amount rewarded
  */
  function claimReward(
    address stakedContract,
    address sponsor,
    address tokenAddress
  ) internal returns (uint rewardAmount) {

    uint currentRound = getCurrentRound();
    RewardPool storage pool = rewardPools[stakedContract][sponsor][tokenAddress];
    uint lastRoundClaimed = pool.lastRoundClaimed[msg.sender];
    require(currentRound > lastRoundClaimed, "Already claimed this reward for this round");

    if (pool.nextRateStartRound != 0 && pool.nextRateStartRound <= currentRound) {
      pool.rate = pool.nextRate;
      pool.nextRateStartRound = 0;
      pool.nextRate = 0;
    }

    IPooledStaking pooledStaking = IPooledStaking(master.getLatestAddress("PS"));
    uint stake = pooledStaking.stakerContractStake(msg.sender, stakedContract);
    uint pendingUnstake = pooledStaking.stakerContractPendingUnstakeTotal(msg.sender, stakedContract);
    uint netStake = stake >= pendingUnstake ? stake.sub(pendingUnstake) : 0;
    rewardAmount = netStake.mul(pool.rate).div(rewardRateScale);
    uint rewardsAvailable = pool.amount;
    if (rewardAmount > rewardsAvailable) {
      rewardAmount = rewardsAvailable;
    }
    require(rewardAmount > 0, "rewardAmount needs to be greater than 0");

    pool.lastRoundClaimed[msg.sender] = currentRound;
    pool.amount = rewardsAvailable.sub(rewardAmount);

    IERC20 erc20 = IERC20(tokenAddress);
    erc20.safeTransfer(msg.sender, rewardAmount);
    emit Claimed(stakedContract, sponsor, tokenAddress, rewardAmount, msg.sender, currentRound);
  }

  /**
  * @dev Withdraw reward funds as a Sponsor for a particular staked contract.
  * @param stakedContract Contract the staker has a stake on.
  * @param tokenAddress Address of the ERC20 token of the reward funds.
  * @param amount Amount of reward funds to be withdrawn.
  */
  function withdrawRewards(address stakedContract, address tokenAddress, uint amount) external nonReentrant {
    IERC20 erc20 = IERC20(tokenAddress);
    RewardPool storage pool = rewardPools[stakedContract][msg.sender][tokenAddress];
    require(pool.amount >= amount, "Not enough tokens to withdraw");
    require(pool.rate == 0, "Reward rate is not 0");

    pool.amount = pool.amount.sub(amount);
    erc20.safeTransfer(msg.sender, amount);
    emit Withdrawn(stakedContract, msg.sender, tokenAddress, amount);
  }

  /**
  @dev Fetch the amount of available rewards for a staker for the current round from a particular reward pool.
  * @param staker whose rewards are counted.
  * @param stakedContract contract the staker has a stake on.
  * @param sponsor Sponsor providing the reward funds.
  * @param tokenAddress address of the ERC20 token of the reward funds.
  * @return rewardAmount amount of reward tokens available for this particular staker.
  */
  function getAvailableStakerReward(
    address staker,
    address stakedContract,
    address sponsor,
    address tokenAddress
  ) public view returns (uint rewardAmount) {

    uint currentRound = getCurrentRound();
    RewardPool storage pool = rewardPools[stakedContract][sponsor][tokenAddress];
    uint lastRoundClaimed = pool.lastRoundClaimed[staker];
    if (lastRoundClaimed >= currentRound) {
      return 0;
    }
    uint rate;
    (rate, , ) = _getRates(pool, currentRound);
    IPooledStaking pooledStaking = IPooledStaking(master.getLatestAddress("PS"));
    uint stake = pooledStaking.stakerContractStake(staker, stakedContract);
    uint pendingUnstake = pooledStaking.stakerContractPendingUnstakeTotal(staker, stakedContract);
    uint netStake = stake >= pendingUnstake ? stake.sub(pendingUnstake) : 0;
    rewardAmount = netStake.mul(rate).div(rewardRateScale);
    uint rewardsAvailable = pool.amount;
    if (rewardAmount > rewardsAvailable) {
      rewardAmount = rewardsAvailable;
    }
  }

  /**
  * @dev Calls claimReward for each separate (stakedContract, sponsor, token) tuple specified.
  * @param stakedContracts Contracts the staker has a stake on.
  * @param sponsors Sponsors to claim rewards from.
  * @param tokenAddresses Addresses of the ERC20 token of the reward funds.
  * @return tokensRewarded Tokens rewarded by each sponsor.
  */
  function getAvailableStakerRewards(
    address staker,
    address[] calldata stakedContracts,
    address[] calldata sponsors,
    address[] calldata tokenAddresses
  ) external view returns (uint[] memory tokensRewarded) {
    require(stakedContracts.length == sponsors.length, "stakedContracts.length != sponsors.length");
    require(stakedContracts.length == tokenAddresses.length, "stakedContracts.length != tokenAddresses.length");

    tokensRewarded = new uint[](stakedContracts.length);
    for (uint i = 0; i < stakedContracts.length; i++) {
      tokensRewarded[i] = getAvailableStakerReward(staker, stakedContracts[i], sponsors[i], tokenAddresses[i]);
    }
  }

  /**
  @dev Fetch RewardPool information
  * @param stakedContract contract a staker has a stake on.
  * @param sponsor Sponsor providing the reward funds.
  * @param tokenAddress address of the ERC20 token of the reward funds.
  * @return amount total available token amount of the RewardPool
  * @return rate rate to NXM of the RewardPool.
  * @return nextRateStartRound round number for which the next rate applies. if 0, no nextRate is set.
  * @return nextRate rate for the next round of the RewardPool. if nextRateStartRound is 0 this value is not relevant.
  */
  function getRewardPool(
    address stakedContract,
    address sponsor,
    address tokenAddress
  ) public view returns (uint amount, uint rate, uint nextRateStartRound, uint nextRate) {
    RewardPool storage pool = rewardPools[stakedContract][sponsor][tokenAddress];
    (rate, nextRateStartRound, nextRate) = _getRates(pool, getCurrentRound());
    amount = pool.amount;
  }


  /**
  @dev Fetch information for multiple RewardPools
  * @param stakedContracts contract a staker has a stake on.
  * @param sponsors Sponsor providing the reward funds.
  * @param tokenAddresses address of the ERC20 token of the reward funds.
  * @return amount total available token amount of the RewardPool
  * @return rate rate to NXM of the RewardPool.
  * @return nextRateStartRound round number for which the next rate applies. if 0, no nextRate is set.
  * @return nextRate rate for the next round of the RewardPool. if nextRateStartRound is 0 this value is not relevant.
  */
  function getRewardPools(
    address[] calldata stakedContracts,
    address[] calldata sponsors,
    address[] calldata tokenAddresses
  ) external view returns (
    uint[] memory amount,
    uint[] memory rate,
    uint[] memory nextRateStartRound,
    uint[] memory nextRate
  ) {
    require(stakedContracts.length == sponsors.length, "stakedContracts.length != sponsors.length");
    require(stakedContracts.length == tokenAddresses.length, "stakedContracts.length != tokenAddresses.length");

    amount = new uint[](stakedContracts.length);
    rate = new uint[](stakedContracts.length);
    nextRateStartRound = new uint[](stakedContracts.length);
    nextRate = new uint[](stakedContracts.length);

    for (uint i = 0; i < stakedContracts.length; i++) {
      RewardPool storage pool = rewardPools[stakedContracts[i]][sponsors[i]][tokenAddresses[i]];
      (rate[i], nextRateStartRound[i], nextRate[i]) = _getRates(pool, getCurrentRound());
      amount[i] = pool.amount;
    }
  }

  /**
  * @dev Fetch the current round number.
  */
  function getCurrentRound() public view returns (uint) {
    require(roundsStartTime <= now, "Rounds haven't started yet");
    return (now - roundsStartTime) / roundDuration + 1;
  }

  /**
  * @dev Fetch the last round in which a staker fetched his reward from a particular RewardPool.
  * @param stakedContract contract a staker has a stake on.
  * @param sponsor Sponsor providing the reward funds.
  * @param tokenAddress address of the ERC20 token of the reward funds.
  */
  function getLastRoundClaimed(
    address stakedContract,
    address sponsor,
    address tokenAddress,
    address staker
  ) external view returns (uint) {
    return rewardPools[stakedContract][sponsor][tokenAddress].lastRoundClaimed[staker];
  }

  function _getRates(RewardPool storage pool, uint currentRound) internal view returns (uint rate, uint nextRateStartRound, uint nextRate) {
    bool needsUpdate = pool.nextRateStartRound != 0 && pool.nextRateStartRound <= currentRound;
    if (needsUpdate) {
      return (pool.nextRate, 0, 0);
    }
    return (pool.rate, pool.nextRateStartRound, pool.nextRate);
  }
}
