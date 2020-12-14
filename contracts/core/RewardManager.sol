// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../general/SafeERC20.sol';
import '../general/BalanceWrapper.sol';
import '../libraries/Math.sol';
import '../libraries/SafeMath.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IRewardManager.sol';

/**
 * @dev RewardManager is nearly the exact same contract as Utilization Farm.
 *      Only difference is the initialize function instead of constructor.
**/

/**
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

contract RewardManager is BalanceWrapper, Ownable, IRewardManager{
    using SafeERC20 for IERC20;

    // Reward token is 0 if Ether is the reward.
    IERC20 public rewardToken;
    address public stakeController;
    address public rewardDistribution;
    uint256 public constant DURATION = 7 days;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event BalanceAdded(address indexed user, uint256 amount);
    event BalanceWithdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyRewardDistribution() {
        require(msg.sender == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function initialize(address _rewardToken, address _stakeController, address _rewardDistribution)
      external
      override
    {
        Ownable.initialize();
        require(address(stakeController) == address(0), "Contract is already initialized.");
        stakeController = _stakeController;
        rewardToken = IERC20(_rewardToken);
        rewardDistribution = _rewardDistribution;
    }
    
    function setRewardDistribution(address _rewardDistribution)
        external
        override
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(address user, uint256 amount) external override updateReward(user) {
        require(msg.sender == stakeController, "Caller is not the stake controller.");
        _addStake(user, amount);
        emit BalanceAdded(user, amount);
    }

    function withdraw(address user, uint256 amount) public override updateReward(user) {
        require(msg.sender == stakeController, "Caller is not the stake controller.");
        _removeStake(user, amount);
        emit BalanceWithdrawn(user, amount);
    }

    function exit(address payable user) external override {
        withdraw(user, balanceOf(user));
        getReward(user);
    }

    function getReward(address payable user) public override updateReward(user) {
        uint256 reward = earned(user);
        if (reward > 0) {
            rewards[user] = 0;
            
            if ( address(rewardToken) == address(0) ) user.transfer(reward);
            else rewardToken.safeTransfer(user, reward);
            
            emit RewardPaid(user, reward);
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        payable
        override
        onlyRewardDistribution
        updateReward(address(0))
    {
        //this will make sure tokens are in the reward pool
        if ( address(rewardToken) == address(0) ){
            require(msg.value == reward, "Correct reward was not sent.");
        }
        else {
            require(msg.value == 0, "Do not send ETH");
            rewardToken.safeTransferFrom(msg.sender, address(this), reward);
        }
        
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }
}
