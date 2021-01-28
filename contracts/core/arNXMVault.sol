pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../libraries/SafeERC20.sol';
import '../interfaces/IWNXM.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/INexusMutual.sol';
import '../interfaces/IRewardManager.sol';
import '../interfaces/IShieldMining.sol';
/**
 * @title arNXM Vault
 * @dev Vault to stake wNXM in Nexus Mutual while maintaining your liquidity.
 * @author Armor.fi -- Robert M.C. Forster, Taek Lee
 * SPDX-License-Identifier: (c) Armor.Fi DAO, 2021
**/
contract arNXMVault is Ownable {
    
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    uint256 constant private DENOMINATOR = 1000;
    
    // Amount of time between 
    uint256 public restakePeriod;
    
    // Amount of time that rewards are distributed over.
    uint256 public rewardDuration;
    
    // How much to unstake each week. 10 == 1%; 1000 == 100%.
    uint256 public unstakePercent;
    
    // Amount of wNXM (in token Wei) to reserve each period.
    // Overwrites reservePercent in update.
    uint256 public reserveAmount;
    
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
    
    // Protocols being unstaked each time restake occurs.
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
    event Withdrawal(address indexed user, uint256 wAmount, uint256 timestamp);
    event Restake(uint256 withdrawn, uint256 unstaked, uint256 staked, uint256 totalAum, uint256 timestamp);
    event NxmReward(uint256 reward, uint256 timestamp, uint256 totalAum);
    
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
        unstakePercent = 100;
        adminPercent = 0;
        referPercent = 25;
        reserveAmount = 30 ether;
        pauseDuration = 10 days;
        beneficiary = msg.sender;
        restakePeriod = 3 days;
        rewardDuration = 9 days;
        
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
        
        // This amount must be determined before arNxm mint.
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
        
        emit Withdrawal(msg.sender, wNxmAmount, block.timestamp);
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
        require(lastRestake.add(restakePeriod) <= block.timestamp, "It has not been 7 days since the last restake.");
        
        // All Nexus functions.
        uint256 withdrawn = _withdrawNxm();
        _wrapNxm();
        
        uint256 staked = _stakeNxm();
        uint256 unstaked = _unstakeNxm(lastId);
        
        // Reset variables.
        lastRestake = block.timestamp;

        emit Restake(withdrawn, unstaked, staked, aum(), block.timestamp);
    }

    /**
     * @dev Split off from restake() function to enable reward fetching at any time.
    **/
    function getRewardNxm() 
      external 
      notContract 
    {
        uint256 prevAum = aum();
        uint256 rewards = _getRewardsNxm();
        if (rewards > 0) {
            _wrapNxm();
            lastRewardTimestamp = block.timestamp;

            emit NxmReward(rewards, block.timestamp, prevAum);
        } else if(lastRewardTimestamp == 0) {
            lastRewardTimestamp = block.timestamp;
        }
    }
    
    /**
     * @dev claim rewards from shield mining
     * @param _shieldMining shield mining contract address
     * @param _protocol Protocol funding the rewards.
     * @param _sponsor sponsor address who funded the shield mining
     * @param _token token address that sponsor is distributing
    **/
    function getShieldMiningRewards(address _shieldMining, address _protocol, address _sponsor, address _token) 
      external
      notContract
    {
        address[] memory protocol = new address[](1);
        protocol[0] = _protocol;
        address[] memory sponsor = new address[](1);
        sponsor[0] = _sponsor;
        address[] memory token = new address[](1);
        token[0] = _token;
        IShieldMining(_shieldMining).claimRewards(protocol, sponsor, token);
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
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        // aum() holds full reward so we sub lastReward(which needs to be distributed over time
        // and add reward that has beend distributed
        uint256 totalW = aum().add(reward).sub(lastReward);
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
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();
        
        // Find totals of both tokens.
        // aum() holds full reward so we sub lastReward(which needs to be distributed over time)
        // and add reward that has been distributed
        uint256 totalW = aum().add(reward).sub(lastReward);
        uint256 totalAr = arNxm.totalSupply();
        
        // Find exchange amount of one token, then find exchange amount for full value.
        uint256 oneAmount = ( totalW.mul(1e18) ).div(totalAr);
        wAmount = _arAmount.mul(oneAmount).div(1e18);
    }
    
    /**
     * @dev Used to determine total Assets Under Management.
     * @return aumTotal Full amount of assets under management (wNXM balance + stake deposit).
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
     * @dev Used to determine staked nxm amount in pooled staking contract.
     * @return staked staked nxm amount
    **/
    function stakedNxm()
      public
      view
    returns (uint256 staked)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        staked = pool.stakerDeposit( address(this) );
    }
    
    /**
     * @dev Used to determine distributed reward amount 
     * @return reward distributed reward amount
    **/
    function currentReward()
      external
      view
    returns (uint256 reward)
    {
        reward = _currentReward();
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
        
        // address(0) means the contract or EOA has not interacted directly with arNXM Vault.
        if ( referrers[_from] != address(0) ) rewardManager.withdraw(referrers[_from], _from, _amount);
        if ( referrers[_to] != address(0) ) rewardManager.stake(referrers[_to], _to, _amount);
    }
    
    /**
     * @dev Approve wNXM to transfer NXM from this contract.
    **/
    function approveNxmToWNXM() external {
        _approveNxm(address(wNxm));
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
        if (adminReward > 0) {
            arNxm.mint(beneficiary, adminReward);
        }
        if (referReward > 0) {
            arNxm.mint(address(this), referReward);
            rewardManager.notifyRewardAmount(referReward);
        }
        
        userReward = reward.sub(adminReward).sub(referReward);
    }

    /**
     * @dev Unstake an amount from each protocol on Nxm (takes 30 days to unstake).
     * @param lastId The ID of the last unstake request on Nexus Mutual (needed for unstaking).
     * @return unstakeAmount The amount of each token that we're unstaking.
    **/
    function _unstakeNxm(uint256 lastId)
      internal
    returns (uint256 unstakeAmount)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 stake = pool.stakerContractStake(address(this), protocols[0]);
        unstakeAmount = stake * unstakePercent / DENOMINATOR;
        // Can't unstake less than 20 NXM.
        if (unstakeAmount < 20 ether) return 0;
        
        for (uint256 i = 0; i < protocols.length; i++) {
            uint256 indUnstakeAmount = _protocolUnstakeable(protocols[i], unstakeAmount);
              
            if (indUnstakeAmount > 0) {
                amounts.push(indUnstakeAmount);
                unstakingProtocols.push(protocols[i]);
            }
          
        }
        
        pool.requestUnstake(unstakingProtocols, amounts, lastId);
        
        delete amounts;
        delete unstakingProtocols;
    }

    /**
     * @dev Returns the amount we can unstake (if we can't unstake the full amount desired).
     * @param _protocol The address of the protocol we're checking.
     * @param _unstakeAmount Amount we want to unstake.
     * @return The amount of funds that can be unstaked from this protocol if not the full amount desired.
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

        // If we do need to restake funds...
        if (reserveAmount < balance) {

            IPooledStaking pool = IPooledStaking( _getPool() );
            
            // Determine how much to stake then unwrap wNxm to be able to stake it. Can't stake less than 20 NXM.
            toStake = balance.sub(reserveAmount);
            if (toStake < 20 ether) return 0;
            
            _unwrapWNxm(toStake);
            
            if(bufferedProtocols.length == 0){
                bufferedProtocols = protocols;
            }
            for (uint256 i = 0; i < bufferedProtocols.length; i++) {
                uint256 stake = pool.stakerContractStake(address(this), bufferedProtocols[i]);
                for(uint256 j = 0; j < protocols.length; j++){
                    if(protocols[j] == bufferedProtocols[i]){
                        stake = stake.add(toStake);
                        break;
                    }
                }
                amounts.push( stake );
            }

            pool.depositAndStake(toStake, bufferedProtocols, amounts);
            // update the bufferedProtocols after deposit
            bufferedProtocols = pool.stakerContractsArray(address(this));
            delete amounts;
        }
        
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
        uint256 duration = rewardDuration;
        uint256 timeElapsed = block.timestamp.sub(lastRewardTimestamp);
        if(timeElapsed == 0){
            return 0;
        }
        
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

    /**
     * @dev Get the current NXM token address from Nexus Mutual.
     * @return nxmAddress Address of the NXM token.
    **/
    function _getNXM()
      internal
      view
    returns(address nxmAddress)
    {
        nxmAddress = nxmMaster.tokenAddress();
    }
    
    /**
     * @dev Get the current NXM token controller (for NXM actions) from Nexus Mutual.
     * @return controller Address of the token controller.
    **/
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
     * @dev rescue tokens locked in contract
     * @param token address of token to withdraw
     */
    function rescueToken(address token) 
      external 
      onlyOwner 
    {
        require(token != address(nxm) && token != address(wNxm) && token != address(arNxm), "Cannot rescue NXM-based tokens");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

    /**
     * @dev Owner may change how much of the AUM should be saved in reserve each period.
     * @param _reserveAmount The amount of wNXM (in token Wei) to reserve each period.
    **/
    function changeReserveAmount(uint256 _reserveAmount)
      external
      onlyOwner
    {
        reserveAmount = _reserveAmount;
    }
    
    /**
     * @dev Owner can change what percent of stake to unstake each week.
     * @param _unstakePercent The new percent of funds to unstake each week.
    **/
    function changeUnstakePercent(uint256 _unstakePercent)
      external
      onlyOwner
    {
        require(_unstakePercent <= 1000, "Unstake percent cannot be more than 100%.");
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
        require(_referPercent <= 500, "Cannot give referrer more than 50% of rewards.");
        referPercent = _referPercent;
    }
    
    /**
     * @dev Change the percent of rewards that are given for administration of the contract.
     * @param _adminPercent The percent of rewards to be given for administration (10 == 1%, 1000 == 100%)
    **/
    function changeAdminPercent(uint256 _adminPercent)
      external
      onlyOwner
    {
        require(_adminPercent <= 500, "Cannot give admin more than 50% of rewards.");
        adminPercent = _adminPercent;
    }

    /**
     * @dev Owner may change protocols that we stake for.
     * @param _protocols New list of protocols to stake for.
     * @param _lastId last id of ustake requests
    **/
    function changeProtocols(address[] calldata _protocols, uint256 _lastId)
      external
      onlyOwner
    {
        protocols = _protocols;
        IPooledStaking pool = IPooledStaking( _getPool() );
        bufferedProtocols = pool.stakerContractsArray(address(this));
        
        // we are going to unstake all the bufferedProtocols
        for (uint256 i = 0; i < bufferedProtocols.length; i++) {
            uint256 indUnstakeAmount = _protocolUnstakeable(bufferedProtocols[i], uint256(~0));
              
            if (indUnstakeAmount > 0) {
                amounts.push(indUnstakeAmount);
                unstakingProtocols.push(bufferedProtocols[i]);
            }
          
        }
        
        pool.requestUnstake(unstakingProtocols, amounts, _lastId);
        
        delete amounts;
        delete unstakingProtocols;
        // now we will push the new protocols to bufferedProtocols
        for (uint256 i = 0; i < _protocols.length; i++) {
            for(uint256 j = 0; j < bufferedProtocols.length; j++){
                if(_protocols[i] == bufferedProtocols[j]){
                    break;
                }
            }
            // push new protocol at the end of bufferedProtocol
            bufferedProtocols.push(_protocols[i]);
        }
    }
    
    /**
     * @dev Owner may change the amount of time required to be waited between restaking.
     * @param _restakePeriod Amount of time required between restakes (starts at 6 days or 86400 * 6).
    **/
    function changeRestakePeriod(uint256 _restakePeriod)
      external
      onlyOwner
    {
        require(_restakePeriod <= 30 days, "Restake period cannot be more than 30 days.");
        restakePeriod = _restakePeriod;
    }
    
    /**
     * @dev Owner may change the amount of time it takes to distribute rewards from Nexus.
     * @param _rewardDuration The amount of time it takes to fully distribute rewards.
    **/
    function changeRewardDuration(uint256 _rewardDuration)
      external
      onlyOwner
    {
        require(_rewardDuration <= 30 days, "Restake period cannot be more than 30 days.");
        rewardDuration = _rewardDuration;
    }
    
    /**
     * @dev Owner may change the amount of time that withdrawals are paused after a hack is confirmed.
     * @param _pauseDuration The new amount of time that withdrawals will be paused.
    **/
    function changePauseDuration(uint256 _pauseDuration)
      external
      onlyOwner
    {
        require(_pauseDuration <= 30 days, "Pause duration cannot be more than 30 days.");
        pauseDuration = _pauseDuration;
    }
    
    /**
     * @dev Change beneficiary of the administration funds.
     * @param _newBeneficiary Address of the new beneficiary to receive funds.
    **/
    function changeBeneficiary(address _newBeneficiary) 
      external 
      onlyOwner 
    {
        beneficiary = _newBeneficiary;
    }
    
    // Update addition. Proxy paranoia brought it down here.
    uint256 public lastRewardTimestamp;
    // Another paranoia    
    address[] public bufferedProtocols;
}
