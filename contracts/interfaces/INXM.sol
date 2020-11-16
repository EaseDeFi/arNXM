pragma solidity ^0.6.6;

import '../interfaces/IERC20.sol';

interface IwNXM is IERC20 {
    function wrap(uint256 _amount) external;
    function unwrap(uint256 _amount) external;
}