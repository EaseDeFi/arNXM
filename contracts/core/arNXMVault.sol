pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../interfaces/IWNXM.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWNXM.sol';
import '../interfaces/INexusMutual.sol';
/**
 * @title arNXM Vault
 * @dev Vault to stake wNXM while maintaining your liquidity.
 * @author Armor.fi -- Robert M.C. Forster
**/
contract arNXMVault is Ownable {
    
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    // How much to unstake each week. 10 == 1%; 1000 == 100%.
    uint256 public unstakePercent;
    
    // Amount of withdrawals from the last week. Used to determine how much to keep for next week.
    uint256 public withdrawals;
    
    // Withdrawals may be paused if a hack has recently happened. Timestamp of when the pause happened.
    uint256 public withdrawalsPaused;
    
    // Amount of time withdrawals may be paused after a hack.
    uint256 public pauseDuration;
    
    // Percent over what was withdrawn last week to reserve. 10 == 1%; 1000 == 100%.
    uint256 public bufferPercent;
    
    // Address that will receive administration funds from the contract.
    address public beneficiary;
    
    // Percent of funds to be distributed for administration of the contract. 10 == 1%; 1000 == 100%.
    uint256 public adminPercent;
    
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
    
    event Deposit(address indexed user, uint256 wAmount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 arAmount, uint256 timestamp);
    event Restake(uint256 withdrawn, uint256 userReward, uint256 unstaked, uint256 staked, uint256 timestamp);
    
    /**
     * @param _protocols List of the 10 protocols we're using.
     * @param _wNxm Address of the wNxm contract.
     * @param _arNxm Address of the arNxm contract.
     * @param _nxmMaster Address of Nexus' master address (to fetch others).
    **/
    constructor(address[] memory _protocols, 
                address _wNxm, 
                address _arNxm,
                address _nxm,
                address _nxmMaster)
      public
    {
        for (uint256 i = 0; i < _protocols.length; i++) protocols.push(_protocols[i]);
        
        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        arNxm = IERC20(_arNxm);
        nxmMaster = INxmMaster(_nxmMaster);
        bufferPercent = 500;
        unstakePercent = 70;
        adminPercent = 200;
        pauseDuration = 7 days;
        beneficiary = msg.sender;
    }

    function changeBeneficiary(address _newBeneficiary) external onlyOwner {
        beneficiary = _newBeneficiary;
    }

    function approveNxmToWNXM() external {
        _approveNxm(address(wNxm));
    }
    
    /**
     * @dev Deposit wNxm to get arNxm in return.
     * @param _wAmount The amount of wNxm to stake.
    **/
    function deposit(uint256 _wAmount)
      external
    {
        // This amount must be determined before arNxm burn.
        uint256 arNxmAmount = arNxmValue(_wAmount);

        wNxm.safeTransferFrom(msg.sender, address(this), _wAmount);
        arNxm.mint(msg.sender, arNxmAmount);
        
        // Deposit does not affect the withdrawals variable.
        
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
        
        arNxm.burn(msg.sender, _arAmount);
        wNxm.safeTransfer(msg.sender, wNxmAmount);
        
        withdrawals = withdrawals.add(wNxmAmount);
        
        emit Withdrawal(msg.sender, _arAmount, block.timestamp);
    }

    /**
     * @dev Restake is to be called weekly. It unstakes 7% of what's currently staked, then restakes.
    **/
    function restake()
      external
    {
        // Check that this is only called once per week.
        require(lastRestake.add(7 days) <= block.timestamp, "It has not been 7 days since the last restake.");
        
        // All Nexus function.
        uint256 withdrawn = _withdrawNxm();
        uint256 rewards = _getRewardsNxm();
        uint256 unstaked = _unstakeNxm();
        uint256 staked = _stakeNxm();
        
        // Keep wNXM in the reserve so users can withdraw.
        _wrapNxm();
        
        // Reset variables.
        lastRestake = block.timestamp;
        withdrawals = 0;
        
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
        if(totalW == 0){
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
     * @dev Anyone may call this function to pause withdrawals for a certain amount of time.
     *      We check Nexus contracts for a recent accepted claim, then can pause to avoid further withdrawals.
     * @param _claimId The ID of the cover that has been accepted for a confirmed hack.
    **/
    function pauseWithdrawals(uint256 _claimId)
      external
    {
        IClaimsData claimsData = IClaimsData( _getClaimsData() );
        
        (/*coverId*/, uint256 status) = claimsData.getClaimStatus(_claimId);
        uint256 dateUpdate = claimsData.getClaimDateUpd(_claimId);
        
        // Status must be 14 and date update must be within the past 7 days.
        if (status == 14 && block.timestamp.sub(dateUpdate) <= 7 days) {
            
            withdrawalsPaused = block.timestamp;
            
        }
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
     * @return userReward The amount of rewards to be given to users (full reward - admin reward).
    **/
    function _getRewardsNxm()
      internal
      returns (uint256 userReward)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        // Find current reward, find user reward (transfers reward to admin within this).
        uint256 fullReward = pool.stakerReward( address(this) );
        userReward = _adminRewardsNxm(fullReward);
        
        pool.withdrawReward( address(this) );
        lastReward = userReward;
    }
    
    /**
     * @dev Find and distribute administrator rewards.
     * @param reward Full reward given from this week.
     * @return userReward Reward amount given to users (full reward - admin reward).
    **/
    function _adminRewardsNxm(uint256 reward)
      internal
    returns (uint256 userReward)
    {
        uint256 adminReward = reward.mul(adminPercent).div(1000);
        arNxm.mint(beneficiary, adminReward);
        userReward = reward.sub(adminReward);
    }

    /**
     * @dev Unstake an amount from each protocol on Nxm (takes 90 days to unstake).
     * @return unstakeAmount The amount of each token that we're unstaking.
    **/
    function _unstakeNxm()
      internal
      returns (uint256 unstakeAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), protocols[0]);
        uint256 unstakeAmount = stake * unstakePercent / 1000;
        for (uint256 i = 0; i < protocols.length; i++) {
          if(_protocolUnstakable(protocols[i])){
            amounts.push(unstakeAmount);
            unstakingProtocols.push(protocols[i]);
          }
        }
        uint256 lastId = pool.lastUnstakeRequestId();
        pool.requestUnstake(unstakingProtocols, amounts, lastId);
        delete amounts;
        delete unstakingProtocols;
    }

    function _protocolUnstakable(address _protocol) internal returns(bool) {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), _protocol);
        uint256 requested = pool.stakerContractPendingUnstakeTotal(address(this), _protocol);
        return stake > requested;
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
        uint256 toReserve = withdrawals.add( ( withdrawals.mul(bufferPercent).div(1000) ) );
       
         
        // If we do need to restake funds...
        if (toReserve < balance) {
            // Determine how much to stake then unwrap wNxm to be able to stake it.
            toStake = balance.sub(toReserve);
            _unwrapWNxm(toStake);
            for (uint256 i = 0; i < protocols.length; i++) amounts.push(toStake);
            IPooledStaking pool = IPooledStaking( _getPool() );
            pool.depositAndStake(toStake, protocols, amounts);
        }
        delete amounts;
        uint256 leftover = wNxm.balanceOf(address(this));
        IWNXM(address(wNxm)).wrap(leftover);
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
    returns(address nxm)
    {
        nxm = nxmMaster.tokenAddress();
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
        nxm.safeApprove( _to, uint256(-1) );
    }
    
    /**
     * @dev Owner may change how much to save in addition to withdrawals from the previous week.
     * @param _bufferPercent The new buffer percent to change to.
    **/
    function changeBufferPercent(uint256 _bufferPercent)
      external
      onlyOwner
    {
        bufferPercent = _bufferPercent;
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

}
