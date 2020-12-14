// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

interface IRewardDistributionRecipient {
    function notifyRewardAmount(uint256 reward) payable external;
    function setRewardDistribution(address rewardDistribution) external;
}
