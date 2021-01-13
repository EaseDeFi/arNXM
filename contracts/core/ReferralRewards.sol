pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../general/SafeERC20.sol';
import '../general/BalanceWrapper.sol';
import '../libraries/Math.sol';
import '../libraries/SafeMath.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IRewardManager.sol';

/**
 * @dev This contract is used to distribute rewards to referrers of users of the arNXMVault contract.
 *      It exists because we want the reward to be taken from rewards gained from staking, and those
 *      are not rewarded on an individual basis but to the arNXMVault contract as a whole. This means
 *      we can only reward the referrers as a pool as well, so we're using the SNX scheme to 
 *      reward a group of referrers all at once.
 *  SPDX-License-Identifier: (c) Armor.Fi, 2021
**/
contract ReferralRewards is BalanceWrapper, Ownable, IRewardManager {
    using SafeERC20 for IERC20;

    // Reward token is 0 if Ether is the reward.
    IERC20 public rewardToken;
    address public stakeController;

    // Duration is 1 to distribute nearly instantly.
    uint256 public constant DURATION = 1;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event BalanceAdded(address indexed user, address indexed referral, uint256 amount);
    event BalanceWithdrawn(address indexed user, address indexed referral, uint256 amount);
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

    modifier onlyStakeController {
        require(msg.sender == stakeController, "Caller is not stake controller.");
        _;
    }

    function initialize(address _rewardToken, address _stakeController)
      external
      override
    {
        Ownable.initializeOwnable();
        require(address(stakeController) == address(0), "Contract is already initialized.");
        stakeController = _stakeController;
        rewardToken = IERC20(_rewardToken);
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
    function stake(address user, address referral, uint256 amount) external override onlyStakeController updateReward(user) {
        _addStake(user, amount);
        emit BalanceAdded(user, referral, amount);
    }

    function withdraw(address user, address referral, uint256 amount) public override onlyStakeController updateReward(user) {
        _removeStake(user, amount);
        emit BalanceWithdrawn(user, referral, amount);
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
        onlyStakeController
        updateReward(address(0))
    {
        //this will make sure tokens are in the reward pool
        if ( address(rewardToken) == address(0) ) {
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
