pragma solidity ^0.6.6;

/**
 * @dev Quick interface for the Nexus Mutual contract to work with the Armor Contracts.
 * SPDX-License-Identifier: (c) Armor.Fi, 2021
 **/

// to get nexus mutual contract address
interface INxmMaster {
    function tokenAddress() external view returns(address);
    function owner() external view returns(address);
    function pauseTime() external view returns(uint);
    function masterInitialized() external view returns(bool);
    function isPause() external view returns(bool check);
    function isMember(address _add) external view returns(bool);
    function getLatestAddress(bytes2 _contractName) external view returns(address payable contractAddress);
}

interface IPooledStaking {
    function lastUnstakeRequestId() external view returns(uint256);
    function stakerDeposit(address user) external view returns (uint256);
    function stakerMaxWithdrawable(address user) external view returns (uint256);
    function withdrawReward(address user) external;
    function requestUnstake(address[] calldata protocols, uint256[] calldata amounts, uint256 insertAfter) external;
    function depositAndStake(uint256 deposit, address[] calldata protocols, uint256[] calldata amounts) external;
    function stakerContractCount(address staker) external view returns(uint256);
    function stakerContractAtIndex(address staker, uint contractIndex) external view returns (address);
    function stakerContractStake(address staker, address protocol) external view returns (uint256);
    function stakerContractsArray(address staker) external view returns (address[] memory);
    function stakerContractPendingUnstakeTotal(address staker, address protocol) external view returns(uint256);
    function withdraw(uint256 amount) external;
    function stakerReward(address staker) external view returns (uint256);
}

interface IClaimsData {
    function getClaimStatusNumber(uint256 claimId) external view returns (uint256, uint256);
    function getClaimDateUpd(uint256 claimId) external view returns (uint256);
}

interface INXMPool {
    function buyNXM(uint minTokensOut) external payable;
}
