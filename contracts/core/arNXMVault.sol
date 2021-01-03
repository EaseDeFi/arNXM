pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../interfaces/IWNXM.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/INexusMutual.sol';
import '../interfaces/IRewardManager.sol';

/**
 * @title arNXM Vault
 * @dev Vault to stake wNXM while maintaining your liquidity.
 * @author Armor.fi -- Robert M.C. Forster, Taek Lee
**/
contract arNXMVault is Ownable {
    
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    uint256 constant private DENOMINATOR = 1000;
    
    // How much to unstake each week. 10 == 1%; 1000 == 100%.
    uint256 public unstakePercent;
    
    // Total amount of assets under management.
    //uint256 public aumTotal;
    
    // Percent of the AUM total that we should keep in reserve. 10 == 1%; 1000 == 100%.
    uint256 public reservePercent;
    
    // Withdrawals may be paused if a hack has recently happened. Timestamp of when the pause happened.
    uint256 public withdrawalsPaused;
    
    // Amount of time withdrawals may be paused after a hack.
    uint256 public pauseDuration;
    
    // Address that will receive administration funds from the contract.
    address public beneficiary;
    
    // Percent of funds to be distributed for administration of the contract. 10 == 1%; 1000 == 100%.
    uint256 public adminPercent;
    
    // Percent of staking rewards that referrers get.
    uint256 public referPercent;
    
    // Timestamp of when the last restake took place--7 days between each.
    uint256 public lastRestake;
    
    // The amount of the last reward.
    uint256 public lastReward;
    
    // Uniswap, Maker, Compound, Aave, Curve, Synthetix, Yearn, RenVM, Balancer, dForce.
    address[] public protocols;
    
    // Amount to unstake each time.
    uint256[] private amounts;
    
    address[] private unstakingProtocols;

    // Nxm tokens.
    IERC20 public wNxm;
    IERC20 public nxm;
    IERC20 public arNxm;
    
    // Nxm Master address.
    INxmMaster public nxmMaster;
    
    // Reward manager for referrers.
    IRewardManager public rewardManager;
    
    // Referral => referrer
    mapping (address => address) public referrers;
    
    event Deposit(address indexed user, uint256 wAmount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 arAmount, uint256 timestamp);
    event Restake(uint256 withdrawn, uint256 userReward, uint256 unstaked, uint256 staked, uint256 timestamp);
    
    // Avoid composability issues for liquidation.
    modifier notContract {
        require(msg.sender == tx.origin, "Sender must be an EOA.");
        _;
    }
    
    /**
     * @param _protocols List of the 10 protocols we're using.
     * @param _wNxm Address of the wNxm contract.
     * @param _arNxm Address of the arNxm contract.
     * @param _nxmMaster Address of Nexus' master address (to fetch others).
     * @param _rewardManager Address of the ReferralRewards smart contract.
    **/
    function initialize(address[] memory _protocols, 
                address _wNxm, 
                address _arNxm,
                address _nxm,
                address _nxmMaster,
                address _rewardManager)
      public
    {
        require(address(arNxm) == address(0), "Contract has already been initialized.");
        
        for (uint256 i = 0; i < _protocols.length; i++) protocols.push(_protocols[i]);
        
        Ownable.initializeOwnable();
        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        arNxm = IERC20(_arNxm);
        nxmMaster = INxmMaster(_nxmMaster);
        rewardManager = IRewardManager(_rewardManager);
        unstakePercent = 70;
        adminPercent = 0;
        referPercent = 50;
        reservePercent = 100;
        pauseDuration = 7 days;
        beneficiary = msg.sender;
        
        // Approve to send funds to reward manager.
        arNxm.approve( _rewardManager, uint256(-1) );
    }
    
    /**
     * @dev Deposit wNxm to get arNxm in return.
     * @param _wAmount The amount of wNxm to stake.
     * @param _referrer The address that referred this user.
    **/
    function deposit(uint256 _wAmount, address _referrer)
      external
    {
        if ( referrers[msg.sender] == address(0) ) {
            referrers[msg.sender] = _referrer != address(0) ? _referrer : beneficiary;
        }
        
        // This amount must be determined before arNxm burn.
        uint256 arNxmAmount = arNxmValue(_wAmount);

        wNxm.safeTransferFrom(msg.sender, address(this), _wAmount);
        // Mint also increases sender's referral balance through alertTransfer.
        arNxm.mint(msg.sender, arNxmAmount);
        
        emit Deposit(msg.sender, _wAmount, block.timestamp);
    }
    
    /**
     * @dev Withdraw an amount of wNxm by burning arNxm.
     * @param _arAmount The amount of arNxm to burn for the wNxm withdraw.
    **/
    function withdraw(uint256 _arAmount)
      external
    {
        require(block.timestamp.sub(withdrawalsPaused) > pauseDuration, "Withdrawals are temporarily paused.");

        // This amount must be determined before arNxm burn.
        uint256 wNxmAmount = wNxmValue(_arAmount);
        
        // Burn also decreases sender's referral balance through alertTransfer.
        arNxm.burn(msg.sender, _arAmount);
        wNxm.safeTransfer(msg.sender, wNxmAmount);
        
        emit Withdrawal(msg.sender, _arAmount, block.timestamp);
    }

    /**
     * @dev Restake is to be called weekly. It unstakes 7% of what's currently staked, then restakes.
     * @param lastId Frontend must submit last ID because it doesn't work direct from Nexus Mutual.
    **/
    function restake(uint256 lastId)
      external
      notContract
    {
        // Check that this is only called once per week.
        require(lastRestake.add(7 days) <= block.timestamp, "It has not been 7 days since the last restake.");
        
        // All Nexus functions.
        uint256 withdrawn = _withdrawNxm();
        uint256 rewards = _getRewardsNxm();
        _wrapNxm();
        
        uint256 staked = _stakeNxm();
        uint256 unstaked = _unstakeNxm(lastId);
        
        // Reset variables.
        lastRestake = block.timestamp;

        emit Restake(withdrawn, rewards, unstaked, staked, block.timestamp);
    }
    
    /**
     * @dev Find the arNxm value of a certain amount of wNxm.
     * @param _wAmount The amount of wNxm to check arNxm value of.
     * @return arAmount The amount of arNxm the input amount of wNxm is worth.
    **/
    function arNxmValue(uint256 _wAmount)
      public
      view
    returns (uint256 arAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        // Get all balances of wNxm on this contract, being staked, then reward allowed to be distributed.
        uint256 balance = wNxm.balanceOf( address(this) );
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNxm.totalSupply();
        
        // Find exchange amount of one token, then find exchange amount for full value.
        if (totalW == 0) {
            arAmount = _wAmount;
        } else {
            uint256 oneAmount = ( totalAr.mul(1e18) ).div(totalW);
            arAmount = _wAmount.mul(oneAmount).div(1e18);
        }
    }
    
    /**
     * @dev Find the wNxm value of a certain amount of arNxm.
     * @param _arAmount The amount of arNxm to check wNxm value of.
     * @return wAmount The amount of wNxm the input amount of arNxm is worth.
    **/
    function wNxmValue(uint256 _arAmount)
      public
      view
    returns (uint256 wAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        // Get all balances of wNxm on this contract, being staked, then reward allowed to be distributed.
        uint256 balance = wNxm.balanceOf( address(this) );
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNxm.totalSupply();
        
        // Find exchange amount of one token, then find exchange amount for full value.
        uint256 oneAmount = ( totalW.mul(1e18) ).div(totalAr);
        wAmount = _arAmount.mul(oneAmount).div(1e18);
    }
    
    /**
     * @dev Used to determine total Assets Under Management.
    **/
    function aum()
      public
      view
    returns (uint256 aumTotal)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 balance = wNxm.balanceOf( address(this) );
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        aumTotal = balance.add(stakeDeposit);
    }
    
    /**
     * @dev Anyone may call this function to pause withdrawals for a certain amount of time.
     *      We check Nexus contracts for a recent accepted claim, then can pause to avoid further withdrawals.
     * @param _claimId The ID of the cover that has been accepted for a confirmed hack.
    **/
    function pauseWithdrawals(uint256 _claimId)
      external
    {
        IClaimsData claimsData = IClaimsData( _getClaimsData() );
        
        (/*coverId*/, uint256 status) = claimsData.getClaimStatusNumber(_claimId);
        uint256 dateUpdate = claimsData.getClaimDateUpd(_claimId);
        
        // Status must be 14 and date update must be within the past 7 days.
        if (status == 14 && block.timestamp.sub(dateUpdate) <= 7 days) {
            withdrawalsPaused = block.timestamp;
        }
    }
    
    /**
     * @dev When arNXM tokens are transferred, the referrer stakes must be adjusted on RewardManager.
     *      This is taken care of by a "_beforeTokenTransfer" function on the arNXM ERC20.
     * @param _from The user that tokens are being transferred from.
     * @param _to The user that tokens are being transferred to.
     * @param _amount The amount of tokens that are being transferred.
    **/
    function alertTransfer(address _from, address _to, uint256 _amount)
      external
    {
        require(msg.sender == address(arNxm), "Sender must be the token contract.");
        
        // address(0) protection is for mints and burns.
        if ( referrers[_from] != address(0) ) rewardManager.withdraw(referrers[_from], _from, _amount);
        if ( referrers[_to] != address(0) ) rewardManager.stake(referrers[_to], _to, _amount);
    }
    
    /**
     * @dev Withdraw any wNxm we can from the staking pool.
     * @return amount The amount of funds that are being withdrawn.
    **/
    function _withdrawNxm()
      internal
      returns (uint256 amount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        amount = pool.stakerMaxWithdrawable( address(this) );
        pool.withdraw(amount);
    }
    
    /**
     * @dev Withdraw any available rewards from Nexus.
     * @return finalReward The amount of rewards to be given to users (full reward - admin reward - referral reward).
    **/
    function _getRewardsNxm()
      internal
      returns (uint256 finalReward)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        // Find current reward, find user reward (transfers reward to admin within this).
        uint256 fullReward = pool.stakerReward( address(this) );
        finalReward = _feeRewardsNxm(fullReward);
        
        pool.withdrawReward( address(this) );
        lastReward = finalReward;
    }
    
    /**
     * @dev Find and distribute administrator rewards.
     * @param reward Full reward given from this week.
     * @return userReward Reward amount given to users (full reward - admin reward).
    **/
    function _feeRewardsNxm(uint256 reward)
      internal
    returns (uint256 userReward)
    {
        // Find both rewards before minting any.
        uint256 adminReward = arNxmValue( reward.mul(adminPercent).div(DENOMINATOR) );
        uint256 referReward = arNxmValue( reward.mul(referPercent).div(DENOMINATOR) );

        // Mint to beneficary then this address (to then transfer to rewardManager).
        if (adminReward > 0) arNxm.mint(beneficiary, adminReward);
        if (referReward > 0) {
            arNxm.mint(address(this), referReward);
            rewardManager.notifyRewardAmount(referReward);
        }
        
        userReward = reward.sub(adminReward).sub(referReward);
    }

    /**
     * @dev Unstake an amount from each protocol on Nxm (takes 90 days to unstake).
     * @return unstakeAmount The amount of each token that we're unstaking.
    **/
    function _unstakeNxm(uint256 lastId)
      internal
      returns (uint256 unstakeAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), protocols[0]);
        unstakeAmount = stake * unstakePercent / DENOMINATOR;
        
        for (uint256 i = 0; i < protocols.length; i++) {
            uint256 indUnstakeAmount = _protocolUnstakeable(protocols[i], unstakeAmount);
              
            if (indUnstakeAmount > 0) {
                amounts.push(indUnstakeAmount);
                unstakingProtocols.push(protocols[i]);
            }
          
        }
        
        // This isn't working from Nexus. When pending actions are cleared, it continues from a blank unstake request which you cannot add to.
        // uint256 lastId = pool.lastUnstakeRequestId();
        pool.requestUnstake(unstakingProtocols, amounts, lastId);
        
        delete amounts;
        delete unstakingProtocols;
    }

    /**
     * @dev Returns the amount we can unstake (if we can't unstake the full amount desired).
     * @param _protocol The address of the protocol we're checking.
     * @param _unstakeAmount Amount we want to unstake.
    **/
    function _protocolUnstakeable(address _protocol, uint256 _unstakeAmount) 
      internal 
      view
    returns (uint256) {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), _protocol);
        uint256 requested = pool.stakerContractPendingUnstakeTotal(address(this), _protocol);
        uint256 available = stake - requested;
        
        // available <= stake is underflow protection.
        return available >= _unstakeAmount && available <= stake ? _unstakeAmount : available;
    }

    /**
     * @dev Stake any wNxm over the amount we need to keep in reserve (bufferPercent% more than withdrawals last week).
     * @return toStake Amount of token that we will be staking. 
    **/
    function _stakeNxm()
      internal
      returns (uint256 toStake)
    {
        _approveNxm(_getTokenController());
        uint256 balance = wNxm.balanceOf( address(this) );
        uint256 toReserve = aum() * reservePercent / DENOMINATOR;
        
        // If we do need to restake funds...
        if (toReserve < balance) {

            IPooledStaking pool = IPooledStaking( _getPool() );
            // Determine how much to stake then unwrap wNxm to be able to stake it.
            toStake = balance.sub(toReserve);
            _unwrapWNxm(toStake);
            
            for (uint256 i = 0; i < protocols.length; i++) {
                uint256 stake = pool.stakerContractStake(address(this), protocols[i]);
                amounts.push( toStake.add(stake) );
            }

            pool.depositAndStake(toStake, protocols, amounts);
            
        }
        
        delete amounts;
    }
    
    /**
     * @dev Calculate what the current reward is. We stream this to arNxm value to avoid dumps.
     * @return reward Amount of reward currently calculated into arNxm value.
    **/
    function _currentReward()
      internal
      view
    returns (uint256 reward)
    {
        uint256 duration = 7 days;
        uint256 timeElapsed = block.timestamp.sub(lastRestake);
        
        // Full reward is added to the balance if it's been more than the disbursement duration.
        if (timeElapsed >= duration) {
            
            reward = lastReward;
        
        // Otherwise, disburse amounts linearly over duration.
        } else {
            
            // 1e18 just for a buffer.
            uint256 portion = ( duration.mul(1e18) ).div(timeElapsed);
            reward = ( lastReward.mul(1e18) ).div(portion);
            
        }
    }
    
    /**
     * @dev Wrap Nxm tokens to be able to be withdrawn as wNxm.
    **/
    function _wrapNxm()
      internal
    {
        // Wrap our full NXM balance.
        uint256 amount = nxm.balanceOf( address(this) );
        IWNXM(address(wNxm)).wrap(amount);
    }
    
    /**
     * @dev Unwrap wNxm tokens to be able to be used within the Nexus Mutual system.
     * @param _amount Amount of wNxm tokens to be unwrapped.
    **/
    function _unwrapWNxm(uint256 _amount)
      internal
    {
        IWNXM(address(wNxm)).unwrap(_amount);
    }
    
    /**
     * @dev Get current address of the Nexus staking pool.
     * @return pool Address of the Nexus staking pool contract.
    **/
    function _getPool()
      internal
      view
    returns (address pool)
    {
        pool = nxmMaster.getLatestAddress("PS");
    }

    function _getNXM()
      internal
      view
    returns(address nxmAddress)
    {
        nxmAddress = nxmMaster.tokenAddress();
    }
    
    function _getTokenController()
      internal
      view
    returns(address controller)
    {
        controller = nxmMaster.getLatestAddress("TC");
    }

    /**
     * @dev Get current address of the Nexus Claims Data contract.
     * @return claimsData Address of the Nexus Claims Data contract.
    **/
    function _getClaimsData()
      internal
      view
    returns (address claimsData)
    {
        claimsData = nxmMaster.getLatestAddress("CD");
    }
    
    /**
     * @dev Approve wNxm contract to be able to transferFrom Nxm from this contract.
    **/
    function _approveNxm(address _to)
      internal
    {
        nxm.approve( _to, uint256(-1) );
    }
    
    /**
     * @dev Owner may change how much of the AUM should be saved in reserve each week.
     * @param _reservePercent The new reserve percent to change to.
    **/
    function changeReservePercent(uint256 _reservePercent)
      external
      onlyOwner
    {
        require(_reservePercent <= 1000);
        reservePercent = _reservePercent;
    }
    
    /**
     * @dev Owner can change what percent of stake to unstake each week.
     * @param _unstakePercent The new percent of funds to unstake each week.
    **/
    function changeUnstakePercent(uint256 _unstakePercent)
      external
      onlyOwner
    {
        require(_unstakePercent <= 100);
        unstakePercent = _unstakePercent;
    }
    
    /**
     * @dev Owner may change the percent of insurance fees referrers receive.
     * @param _referPercent The percent of fees referrers receive. 50 == 5%.
    **/
    function changeReferPercent(uint256 _referPercent)
      external
      onlyOwner
    {
        require(_referPercent <= 1000, "Cannot give more than 100% of fees.");
        referPercent = _referPercent;
    }
    
    /**
     * @dev Owner may change protocols that we stake for.
     * @param _protocols New list of protocols to stake for.
    **/
    function changeProtocols(address[] calldata _protocols)
      external
      onlyOwner
    {
        protocols = _protocols;
    }
    
    /**
     * @dev Owner may change the amount of time that withdrawals are paused after a hack is confirmed.
     * @param _pauseDuration The new amount of time that withdrawals will be paused.
    **/
    function changePauseDuration(uint256 _pauseDuration)
      external
      onlyOwner
    {
        pauseDuration = _pauseDuration;
    }
    
    /**
     * @dev Change the percent of rewards that are given for administration of the contract.
     * @param _adminPercent The percent of rewards to be given for administration (10 == 1%, 1000 == 100%)
    **/
    function changeAdminPercent(uint256 _adminPercent)
      external
      onlyOwner
    {
        require(_adminPercent <= 1000);
        adminPercent = _adminPercent;
    }
    
    /**
     * @dev Change beneficiary of the administration funds.
     * @param _newBeneficiary Address of the new beneficiary to receive funds.
    **/
    function changeBeneficiary(address _newBeneficiary) external onlyOwner {
        beneficiary = _newBeneficiary;
    }

    /**
     * @dev Approve wNXM to transfer NXM from this contract.
    **/
    function approveNxmToWNXM() external {
        _approveNxm(address(wNxm));
    }

}
