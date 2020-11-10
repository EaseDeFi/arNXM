pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/SafeERC20.sol';
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
    
    // NXM tokens.
    IERC20 public wNXM;
    IERC20 public arNXM;
    
    // NXM Master address.
    INXMMaster public nxmMaster;
    
    /**
     * @param _protocols List of the 10 protocols we're using.
     * @param _wNXM Address of the wNXM contract.
     * @param _arNXM Address of the arNXM contract.
     * @param _nxmMaster Address of Nexus' master address (to fetch others).
    **/
    constructor(address[] memory _protocols, 
                address _wNXM, 
                address _arNXM, 
                address _nxmMaster)
      public
    {
        for (uint256 i = 0; i < _protocols.length; i++) protocols.push(_protocols[i]);
        
        wNXM = IERC20(_wNXM);
        arNXM = IERC20(_arNXM);
        nxmMaster = INXMMaster(_nxmMaster);
        bufferPercent = 500;
        unstakePercent = 70;
        adminPercent = 200;
        pauseDuration = 7 days;
    }
    
    /**
     * @dev Deposit wNXM to get arNXM in return.
     * @param _wAmount The amount of wNXM to stake.
    **/
    function deposit(uint256 _wAmount)
      external
    {
        // This amount must be determined before arNXM burn.
        uint256 arNXMAmount = arNXMValue(_wAmount);

        wNXM.safeTransferFrom(msg.sender, address(this), _wAmount);
        arNXM.mint(msg.sender, arNXMAmount);
        
        // Deposit does not affect the withdrawals variable.
    }
    
    /**
     * @dev Withdraw an amount of wNXM by burning arNXM.
     * @param _arAmount The amount of arNXM to burn for the wNXM withdraw.
    **/
    function withdraw(uint256 _arAmount)
      external
    {
        require(block.timestamp.sub(withdrawalsPaused) > pauseDuration, "Withdrawals are temporarily paused.");
        
        // This amount must be determined before arNXM burn.
        uint256 wNXMAmount = wNXMValue(_arAmount);
        
        arNXM.burn(msg.sender, _arAmount);
        wNXM.safeTransfer(msg.sender, wNXMAmount);
        
        withdrawals = withdrawals.add(wNXMAmount);
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
        _withdrawNxm();
        _getRewardsNxm();
        _unstakeNxm();
        _stakeNxm();
        
        // Reset variables.
        lastRestake = block.timestamp;
        withdrawals = 0;
    }
    
    /**
     * @dev Find the arNXM value of a certain amount of wNXM.
     * @param _wAmount The amount of wNXM to check arNXM value of.
     * @return arAmount The amount of arNXM the input amount of wNXM is worth.
    **/
    function arNXMValue(uint256 _wAmount)
      public
      view
    returns (uint256 arAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
<<<<<<< HEAD:contracts/core/arNXM.sol
        
        // Get all balances of wNXM on this contract, being staked, then reward allowed to be distributed.
        uint256 balance = wNXM.balanceOf( address(this) );
=======
        uint256 balance = wNXM.balanceOf( address(this) ).sub(lastReward);
>>>>>>> 9249805525d598e404efd854c638046316968875:contracts/core/arNXMVault.sol
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNXM.totalSupply();
        
        // Find exchange amount of one token, then find exchange amount for full value.
        uint256 oneAmount = ( totalAr.mul(1e18) ).div(totalW);
        arAmount = _wAmount.mul(oneAmount).div(1e18);
    }
    
    /**
     * @dev Find the wNXM value of a certain amount of arNXM.
     * @param _arAmount The amount of arNXM to check wNXM value of.
     * @return wAmount The amount of wNXM the input amount of arNXM is worth.
    **/
    function wNXMValue(uint256 _arAmount)
      public
      view
    returns (uint256 wAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
<<<<<<< HEAD:contracts/core/arNXM.sol
        
        // Get all balances of wNXM on this contract, being staked, then reward allowed to be distributed.
        uint256 balance = wNXM.balanceOf( address(this) );
=======
        uint256 balance = wNXM.balanceOf( address(this) ).sub(lastReward);
>>>>>>> 9249805525d598e404efd854c638046316968875:contracts/core/arNXMVault.sol
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNXM.totalSupply();
        
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
     * @dev Withdraw any wNXM we can from the staking pool.
    **/
    function _withdrawNxm()
      internal
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        uint256 amount = pool.stakerMaxWithdrawable( address(this) );
        pool.withdraw(amount);
    }
    
    /**
     * @dev Withdraw any available rewards from Nexus.
    **/
    function _getRewardsNxm()
      internal
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        
        // Find current reward, find user reward (transfers reward to admin within this).
        uint256 reward = pool.stakerReward( address(this) );
        uint256 userReward = _adminRewardsNxm(reward);
        
        pool.withdrawReward( address(this) );
        lastReward = userReward;
    }
    
    function _adminRewardsNxm(uint256 reward)
      internal
    returns (uint256 userReward)
    {
        uint256 adminReward = reward.mul(adminPercent).div(1000);
        arNXM.mint(beneficiary, adminReward);
        userReward = reward.sub(adminReward);
    }

    /**
     * @dev Unstake an amount from each protocol on NXM (takes 90 days to unstake). 
    **/
    function _unstakeNxm()
      internal
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), protocols[0]);
        uint256 unstakeAmount = stake * unstakePercent / 1000;

        // Amounts must be in storage here and have unstake amounts pushed to it.
        // TODO: Better way to do this?
        for (uint256 i = 0; i < protocols.length; i++) amounts.push(unstakeAmount);

        pool.requestUnstake(protocols, amounts);
        
        delete amounts;
    }

    /**
     * @dev Stake any wNXM over the amount we need to keep in reserve (bufferPercent% more than withdrawals last week).
    **/
    function _stakeNxm()
      internal
    {
        uint256 balance = wNXM.balanceOf( address(this) );
        uint256 toReserve = withdrawals.add( ( withdrawals.mul(bufferPercent).div(1000) ) );
        
        if (toReserve < balance) {
            
            uint256 toStake = balance.sub(toReserve);
            uint256[] storage stakes;
            for (uint256 i = 0; i < protocols.length; i++) stakes.push(toStake);
        
            IPooledStaking pool = IPooledStaking( _getPool() );
            pool.depositAndStake(toStake, protocols, stakes);
        
        }
    }
    
    /**
     * @dev Calculate what the current reward is. We stream this to arNXM value to avoid dumps.
     * @return reward Amount of reward currently calculated into arNXM value.
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
