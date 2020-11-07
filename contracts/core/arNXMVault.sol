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
    
    // How much to unstake each week.
    uint256 public unstakePercent;
    
    // Amount of withdrawals from the last week. Used to determine how much to keep for next week.
    uint256 public withdrawals;
    
    // Percent over what was withdrawn last week to reserve.
    uint256 public bufferPercent;
    
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
     * @param _bufferPercent The percent extra to keep over withdrawals from the previous week.
    **/
    constructor(address[] memory _protocols, 
                address _wNXM, 
                address _arNXM, 
                address _nxmMaster,
                uint256 _bufferPercent,
                uint256 _unstakePercent)
      public
    {
        for (uint256 i = 0; i < _protocols.length; i++) protocols.push(_protocols[i]);
        
        wNXM = IERC20(_wNXM);
        arNXM = IERC20(_arNXM);
        nxmMaster = INXMMaster(_nxmMaster);
        bufferPercent = _bufferPercent;
        unstakePercent = _unstakePercent;
    }
    
    /**
     * @dev Deposit wNXM to get arNXM in return.
     * @param _wAmount The amount of wNXM to stake.
    **/
    function deposit(uint256 _wAmount)
      external
    {
        wNXM.safeTransferFrom(msg.sender, address(this), _wAmount);
        uint256 arNXMAmount = arNXMValue(_wAmount);
        arNXM.mint(msg.sender, arNXMAmount);
    }
    
    /**
     * @dev Withdraw an amount of wNXM by burning arNXM.
     * @param _arAmount The amount of arNXM to burn for the wNXM withdraw.
    **/
    function withdraw(uint256 _arAmount)
      external
    {
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
        
        _withdrawNxm();
        _getRewardsNxm();
        _unstakeNxm();
        _stakeNxm();
        
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
        uint256 balance = wNXM.balanceOf( address(this) ).sub(lastReward);
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNXM.totalSupply();
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
        uint256 balance = wNXM.balanceOf( address(this) ).sub(lastReward);
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        uint256 reward = _currentReward();
        uint256 totalW = balance.add(stakeDeposit).add(reward);
        uint256 totalAr = arNXM.totalSupply();
        uint256 oneAmount = ( totalW.mul(1e18) ).div(totalAr);
        wAmount = _arAmount.mul(oneAmount).div(1e18);
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
        pool.withdrawReward( address(this) );
    }

    /**
     * @dev Unstake an amount from each protocol on NXM (takes 90 days to unstake). 
    **/
    function _unstakeNxm()
      internal
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), protocols[0]);
        uint256 unstakeAmount = stake * unstakePercent / 100;

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
        uint256 toReserve = withdrawals.add( ( withdrawals.mul(bufferPercent).div(100) ) );
        
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
        
        if (timeElapsed >= duration) {
            
            reward = lastReward;
            
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
     * @dev Owner may change how much to save in addition to withdrawals from last week.
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
    function changeProtocol(address[] calldata _protocols)
      external
      onlyOwner
    {
        protocols = _protocols;
    }
    
}
