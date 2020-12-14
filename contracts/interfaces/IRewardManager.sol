// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import './IRewardDistributionRecipient.sol';

interface IRewardManager is IRewardDistributionRecipient {
  function initialize(address _rewardToken, address _stakeManager, address _rewardDistribution) external;
  function stake(address _user, uint256 _coverPrice) external;
  function withdraw(address _user, uint256 _coverPrice) external;
  function exit(address payable _user) external;
  function getReward(address payable _user) external;
}
