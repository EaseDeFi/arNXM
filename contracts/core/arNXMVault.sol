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
 * @dev Vault to stake wNXM or NXM in Nexus Mutual while maintaining your liquidity.
 *      This is V2 which replaces V1 behind a proxy. Updated variables at the bottom.
 * @author Armor.fi -- Robert M.C. Forster, Taek Lee
 * SPDX-License-Identifier: (c) Armor.Fi DAO, 2021
**/

contract arNXMVault is Ownable {

    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint256 constant private DENOMINATOR = 1000;

    // Amount of time between
    uint256 private ____deprecated____0;

    // Amount of time that rewards are distributed over.
    uint256 public rewardDuration;

    // This used to be unstake percent but has now been deprecated in favor of individual unstakes.
    // Paranoia results in this not being replaced but rather deprecated and new variables placed at the bottom.
    uint256 private ____deprecated____1;

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

    // Protocols being actively used in staking or unstaking.
    address[] private activeProtocols;

    struct WithdrawalRequest {
        uint48 requestTime;
        uint104 nAmount;
        uint104 arAmount;
    }

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

    event Deposit(address indexed user, uint256 nAmount, uint256 arAmount, uint256 timestamp);
    event WithdrawRequested(address indexed user, uint256 arAmount, uint256 nAmount, uint256 requestTime, uint256 withdrawTime);
    event Withdrawal(address indexed user, uint256 nAmount, uint256 arAmount, uint256 timestamp);
    event Restake(uint256 withdrawn, uint256 unstaked, uint256 staked, uint256 totalAum, uint256 timestamp);
    event NxmReward(uint256 reward, uint256 timestamp, uint256 totalAum);

    // Avoid composability issues for liquidation.
    modifier notContract {
        require(msg.sender == tx.origin, "Sender must be an EOA.");
        _;
    }

    // Functions as re-entrancy protection and more.
    // Mapping down below with other update variables.
    modifier oncePerTx {
        require(block.timestamp > lastCall[tx.origin], "May only call this contract once per transaction.");
        lastCall[tx.origin] = block.timestamp;
        _;
    }

    /**
     * @param _wNxm Address of the wNxm contract.
     * @param _arNxm Address of the arNxm contract.
     * @param _nxmMaster Address of Nexus' master address (to fetch others).
     * @param _rewardManager Address of the ReferralRewards smart contract.
    **/
    function initialize(
        address _wNxm,
        address _arNxm,
        address _nxm,
        address _nxmMaster,
        address _rewardManager
    )
      public
    {
        require(address(arNxm) == address(0), "Contract has already been initialized.");

        Ownable.initializeOwnable();
        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        arNxm = IERC20(_arNxm);
        nxmMaster = INxmMaster(_nxmMaster);
        rewardManager = IRewardManager(_rewardManager);
        // unstakePercent = 100;
        adminPercent = 0;
        referPercent = 25;
        reserveAmount = 30 ether;
        pauseDuration = 10 days;
        beneficiary = msg.sender;
        // restakePeriod = 3 days;
        rewardDuration = 9 days;

        // Approve to wrap and send funds to reward manager.
        arNxm.approve( _rewardManager, uint256(-1) );
    }

    /**
     * @dev Deposit wNxm or NXM to get arNxm in return.
     * @param _nAmount The amount of NXM to stake.
     * @param _referrer The address that referred this user.
     * @param _isNxm True if the token is NXM, false if the token is wNXM.
    **/
    function deposit(uint256 _nAmount, address _referrer, bool _isNxm)
      external
      oncePerTx
    {
        if ( referrers[msg.sender] == address(0) ) {
            referrers[msg.sender] = _referrer != address(0) ? _referrer : beneficiary;
            address refToSet = _referrer != address(0) ? _referrer : beneficiary;
            referrers[msg.sender] = refToSet;

            // A wallet with a previous arNXM balance would be able to subtract referral weight that it never added.
            uint256 prevBal = arNxm.balanceOf(msg.sender);
            if (prevBal > 0) rewardManager.stake(refToSet, msg.sender, prevBal);
        }

        // This amount must be determined before arNxm mint.
        uint256 arAmount = arNxmValue(_nAmount);

        if (_isNxm) {
            nxm.safeTransferFrom(msg.sender, address(this), _nAmount);
        } else {
            wNxm.safeTransferFrom(msg.sender, address(this), _nAmount);
            _unwrapWnxm(_nAmount);
        }

        // Mint also increases sender's referral balance through alertTransfer.
        arNxm.mint(msg.sender, arAmount);

        emit Deposit(msg.sender, _nAmount, arAmount, block.timestamp);
    }

    /**
     * @dev Withdraw an amount of wNxm or NXM by burning arNxm.
     * @param _arAmount The amount of arNxm to burn for the wNxm withdraw.
     * @param _payFee Flag to pay fee to withdraw without delay.
    **/
    function withdraw(uint256 _arAmount, bool _payFee)
      external
      oncePerTx
    {
        require(block.timestamp.sub(withdrawalsPaused) > pauseDuration, "Withdrawals are temporarily paused.");

        // This amount must be determined before arNxm burn.
        uint256 nAmount = nxmValue(_arAmount);
        require(totalPending.add(nAmount) <= nxm.balanceOf(address(this)), "Not enough NXM available for witthdrawal.");

        if (_payFee) {
            uint256 fee = nAmount.mul(withdrawFee).div(1000);
            uint256 disbursement = nAmount.sub(fee);

            // Burn also decreases sender's referral balance through alertTransfer.
            arNxm.burn(msg.sender, _arAmount);
            _wrapNxm(disbursement);
            wNxm.safeTransfer(msg.sender, disbursement);

            emit Withdrawal(msg.sender, nAmount, _arAmount, block.timestamp);
        } else {
            totalPending = totalPending.add(nAmount);
            arNxm.safeTransferFrom(msg.sender, address(this), _arAmount);
            WithdrawalRequest memory prevWithdrawal = withdrawals[msg.sender];
            withdrawals[msg.sender] = WithdrawalRequest(
                uint48(block.timestamp),
                prevWithdrawal.nAmount + uint104(nAmount),
                prevWithdrawal.arAmount + uint104(_arAmount)
            );

            emit WithdrawRequested(msg.sender, _arAmount, nAmount, block.timestamp, block.timestamp.add(withdrawDelay));
        }
    }

    /**
     * @dev Withdraw from request
    **/
    function withdrawFinalize()
      external
      oncePerTx
    {
        WithdrawalRequest memory withdrawal = withdrawals[msg.sender];
        uint256 nAmount = uint256(withdrawal.nAmount);
        uint256 arAmount = uint256(withdrawal.arAmount);
        uint256 requestTime = uint256(withdrawal.requestTime);

        require(block.timestamp.sub(withdrawalsPaused) > pauseDuration, "Withdrawals are temporarily paused.");
        require(requestTime.add(withdrawDelay) <= block.timestamp, "Not ready to withdraw");
        require(nAmount > 0, "No pending amount to withdraw");

        // Burn also decreases sender's referral balance through alertTransfer.
        arNxm.burn(address(this), arAmount);
        _wrapNxm(nAmount);
        wNxm.safeTransfer(msg.sender, nAmount);
        delete withdrawals[msg.sender];
        totalPending = totalPending.sub(nAmount);

        emit Withdrawal(msg.sender, nAmount, arAmount, block.timestamp);
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
            lastRewardTimestamp = block.timestamp;
            emit NxmReward(rewards, block.timestamp, prevAum);
        } else if(lastRewardTimestamp == 0) {
            lastRewardTimestamp = block.timestamp;
        }
    }

    /**
     * @dev claim rewards from shield mining
     * @param _shieldMining shield mining contract address
     * @param _protocols Protocol funding the rewards.
     * @param _sponsors sponsor address who funded the shield mining
     * @param _tokens token address that sponsor is distributing
    **/
    function getShieldMiningRewards(address _shieldMining, address[] calldata _protocols, address[] calldata _sponsors, address[] calldata _tokens)
      external
      notContract
    {
        IShieldMining(_shieldMining).claimRewards(_protocols, _sponsors, _tokens);
    }

    /**
     * @dev Find the arNxm value of a certain amount of wNxm.
     * @param _nAmount The amount of NXM to check arNxm value of.
     * @return arAmount The amount of arNxm the input amount of wNxm is worth.
    **/
    function arNxmValue(uint256 _nAmount)
      public
      view
    returns (uint256 arAmount)
    {
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();

        // aum() holds full reward so we sub lastReward (which needs to be distributed over time)
        // and add reward that has been distributed
        uint256 totalN = aum().add(reward).sub(lastReward);
        uint256 totalAr = arNxm.totalSupply();

        // Find exchange amount of one token, then find exchange amount for full value.
        if (totalN == 0) {
            arAmount = _nAmount;
        } else {
            uint256 oneAmount = ( totalAr.mul(1e18) ).div(totalN);
            arAmount = _nAmount.mul(oneAmount).div(1e18);
        }
    }

    /**
     * @dev Find the wNxm value of a certain amount of arNxm.
     * @param _arAmount The amount of arNxm to check wNxm value of.
     * @return nAmount The amount of wNxm the input amount of arNxm is worth.
    **/
    function nxmValue(uint256 _arAmount)
      public
      view
    returns (uint256 nAmount)
    {
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();

        // aum() holds full reward so we sub lastReward (which needs to be distributed over time)
        // and add reward that has been distributed
        uint256 totalN = aum().add(reward).sub(lastReward);
        uint256 totalAr = arNxm.totalSupply();

        // Find exchange amount of one token, then find exchange amount for full value.
        uint256 oneAmount = ( totalN.mul(1e18) ).div(totalAr);
        nAmount = _arAmount.mul(oneAmount).div(1e18);
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
        uint256 balance = nxm.balanceOf( address(this) );
        uint256 stakeDeposit = pool.stakerDeposit( address(this) );
        aumTotal = balance.add(stakeDeposit);
    }

    /**
     * @dev Used to determine staked nxm amount in pooled staking contract.
     * @return staked Staked nxm amount.
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
     * @dev Used to withdraw nxm from staking pool
    **/
    function withdrawNxm()
      external
      onlyOwner
    {
        _withdrawNxm();
    }

    /**
     * @dev Used to unwrap wnxm tokens to nxm
    **/
    function unwrapWnxm()
      external
    {
        uint256 balance = wNxm.balanceOf(address(this));
        _unwrapWnxm(balance);
    }

    /**
     * @dev Used to stake nxm tokens to stake pool. it is determined manually
    **/
    function stakeNxm(address[] calldata _protocols, uint256[] calldata _stakeAmounts) external onlyOwner{
        _stakeNxm(_protocols, _stakeAmounts);
    }

    /**
     * @dev Used to unstake nxm tokens from stake pool. it is determined manually
    **/
    function unstakeNxm(uint256 _lastId, address[] calldata _protocols, uint256[] calldata _unstakeAmounts) external onlyOwner{
        _unstakeNxm(_lastId, _protocols, _unstakeAmounts);
    }
    
    /**
     * @dev Withdraw any Nxm we can from the staking pool.
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
     * @dev Stake any wNxm over the amount we need to keep in reserve (bufferPercent% more than withdrawals last week).
     * @param _protocols List of protocols to stake in (NOT list of all protocols).
     * @param _stakeAmounts List of amounts to stake in each relevant protocol--this is only ADDITIONAL stake rather than full stake.
     * @return toStake Amount of token that we will be staking.
     **/
    function _stakeNxm(address[] memory _protocols, uint256[] memory _stakeAmounts)
      internal
      returns (uint256 toStake)
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        uint256 balance = nxm.balanceOf( address(this) );
        // If we do need to restake funds...
        // toStake == additional stake on top of old ones
        if (reserveAmount.add(totalPending) > balance) {
            toStake = 0;
        } else {
            toStake = balance.sub(reserveAmount.add(totalPending));
            _approveNxm(_getTokenController(), toStake);
        }

        // get current data from pooled staking
        address[] memory currentProtocols = pool.stakerContractsArray(address(this));
        // this will be used to calculate the remaining exposure
        for (uint256 i = 0; i < currentProtocols.length; i++) {
            amounts.push(pool.stakerContractStake(address(this), currentProtocols[i]));
            activeProtocols.push(currentProtocols[i]);
        }

        // push additional stake data
        for(uint256 i = 0; i < _protocols.length; i++) {
            address protocol = _protocols[i];
            uint256 curIndex = _addressArrayFind(currentProtocols, protocol);
            if(curIndex == type(uint256).max) {
                activeProtocols.push(protocol);
                amounts.push(_stakeAmounts[i]);
            } else {
                amounts[curIndex] += _stakeAmounts[i];
            }
        }
        // now calculate the new staking protocols
        pool.depositAndStake(toStake, activeProtocols, amounts);
        delete activeProtocols;
        delete amounts;
    }

    /**
     * @dev Unstake an amount from each protocol on Nxm (takes 30 days to unstake).
     * @param _lastId The ID of the last unstake request on Nexus Mutual (needed for unstaking).
    **/
    function _unstakeNxm(uint256 _lastId, address[] memory _protocols, uint256[] memory _amounts)
      internal
    {
        IPooledStaking pool = IPooledStaking( _getPool() );
        pool.requestUnstake(_protocols, _amounts, _lastId);
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

        // Scenario in which all staked has already been requested to be unstaked.
        if (requested >= stake) {
            return 0;
        }

        uint256 available = stake - requested;

        return _unstakeAmount <= available ? _unstakeAmount : available;
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
    function _wrapNxm(uint256 _amount)
      internal
    {
        _approveNxm(address(wNxm), _amount);
        IWNXM(address(wNxm)).wrap(_amount);
    }

    /**
     * @dev Unwrap wNxm tokens to be able to be used within the Nexus Mutual system.
     * @param _amount Amount of wNxm tokens to be unwrapped.
    **/
    function _unwrapWnxm(uint256 _amount)
      internal
    {
        IWNXM(address(wNxm)).unwrap(_amount);
    }

    /**
     * @dev Approve wNxm contract to be able to transferFrom Nxm from this contract.
    **/
    function _approveNxm(address _to, uint256 _amount)
      internal
    {
        nxm.approve( _to, _amount );
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

    function _addressArrayFind(address[] memory arr, address elem) internal pure returns(uint256 index) {
        for(uint256 i = 0; i<arr.length; i++) {
            if(arr[i] == elem) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /*---- Ownable functions ----*/

    /**
     * @dev pull nxm from arNFT and wrap it to wnxm
    **/
    function pullNXM(address _from, uint256 _amount, address _to)
      external
      onlyOwner
    {
        nxm.transferFrom(_from, address(this), _amount);
        _wrapNxm(_amount);
        wNxm.transfer(_to, _amount);
    }

    /**
     * @dev Buy NXM direct from Nexus Mutual. Used by ExchangeManager.
     * @param _minNxm Minimum amount of NXM tokens to receive in return for the Ether.
    **/
    function buyNxmWithEther(uint256 _minNxm)
      external
      payable
    {
        require(msg.sender == 0x1337DEF157EfdeF167a81B3baB95385Ce5A14477, "Sender must be ExchangeManager.");
        INXMPool pool = INXMPool(nxmMaster.getLatestAddress("P1"));
        pool.buyNXM{value:address(this).balance}(_minNxm);
    }

    /**
     * @dev Vote on Nexus Mutual governance proposals using tokens.
     * @param _proposalId ID of the proposal to vote on.
     * @param _solutionChosen Side of the proposal we're voting for (0 for no, 1 for yes).
    **/
    function submitVote(uint256 _proposalId, uint256 _solutionChosen)
      external
      onlyOwner
    {
        address gov = nxmMaster.getLatestAddress("GV");
        IGovernance(gov).submitVote(_proposalId, _solutionChosen);
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

    /*---- Admin functions ----*/

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
     * @dev Owner may change the withdraw fee.
     * @param _withdrawFee The fee of withdraw.
    **/
    function changeWithdrawFee(uint256 _withdrawFee)
      external
      onlyOwner
    {
        require(_withdrawFee <= DENOMINATOR, "Cannot take more than 100% of withdraw");
        withdrawFee = _withdrawFee;
    }

    /**
     * @dev Owner may change the withdraw delay.
     * @param _withdrawDelay Withdraw delay.
    **/
    function changeWithdrawDelay(uint256 _withdrawDelay)
      external
      onlyOwner
    {
        withdrawDelay = _withdrawDelay;
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
     * @dev Owner may change the amount of time it takes to distribute rewards from Nexus.
     * @param _rewardDuration The amount of time it takes to fully distribute rewards.
    **/
    function changeRewardDuration(uint256 _rewardDuration)
      external
      onlyOwner
    {
        require(_rewardDuration <= 30 days, "Reward duration cannot be more than 30 days.");
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

    //// Update addition. Proxy paranoia brought it down here. ////

    uint256 public lastRewardTimestamp;

    //// Second update additions. ////

    // Protocol that the next restaking will begin on.
    uint256 private ____deprecated____2;

    // Checkpoint in case we want to cut off certain buckets (where we begin the rotations).
    // To bar protocols from being staked/unstaked, move them to before checkpointProtocol.
    uint256 private ____deprecated____3;

    // Number of protocols to stake each time.
    uint256 private ____deprecated____4;

    // Individual percent to unstake.
    uint256[] private ____deprecated____5;

    // Last time an EOA has called this contract.
    mapping (address => uint256) public lastCall;

    ///// Third update additions. /////

    // Withdraw fee to withdraw immediately.
    uint256 public withdrawFee;

    // Delay to withdraw
    uint256 public withdrawDelay;

    // Total amount of withdrawals pending.
    uint256 public totalPending;

    mapping (address => WithdrawalRequest) public withdrawals;

}
