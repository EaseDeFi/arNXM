pragma solidity 0.5.17;

import "../library/token/ERC20/IERC20.sol";

contract INXM is IERC20 {
    function whiteListed(address owner) external view returns (bool);
    function isLockedForMV(address owner) external view returns (uint256);
}
