// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import './IRewardDistributionRecipient.sol';

interface IRewardManager is IRewardDistributionRecipient {
  function initialize(address _rewardToken, address _stakeController) external;
  function stake(address _user, address _referral, uint256 _coverPrice) external;
  function withdraw(address _user, address _referral, uint256 _coverPrice) external;
  function getReward(address payable _user) external;
}
