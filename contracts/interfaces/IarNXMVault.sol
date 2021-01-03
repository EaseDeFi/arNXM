// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

interface IarNXMVault {
  function alertTransfer(address _from, address _to, uint256 _amount) external;
}
