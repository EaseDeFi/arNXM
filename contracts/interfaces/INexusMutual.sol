pragma solidity ^0.6.6;

/**
 * @dev Quick interface for the Nexus Mutual contract to work with the Armor Contracts.
 **/

// to get nexus mutual contract address
interface INXMMaster {
    function tokenAddress() external view returns(address);
    function owner() external view returns(address);
    function pauseTime() external view returns(uint);
    function masterInitialized() external view returns(bool);
    function isPause() external view returns(bool check);
    function isMember(address _add) external view returns(bool);
    function getLatestAddress(bytes2 _contractName) external view returns(address payable contractAddress);
}

interface IPooledStaking {
    function stakerDeposit(address user) external view returns (uint256);
    function stakerMaxWithdrawable(address user) external view returns (uint256);
    function withdrawReward(address user) external;
    function requestUnstake(address[] calldata protocols, uint256[] calldata amounts) external;
    function depositAndStake(uint256 deposit, address[] calldata protocols, uint256[] calldata amounts) external;
    function stakerContractStake(address staker, address protocol) external view returns (uint256);
    function withdraw(uint256 amount) external;
}

