// SPDX-License-Identifier: (c) Armor.Fi DAO, 2021

pragma solidity ^0.6.0;

interface IShieldMining {
  function claimRewards(
    address[] calldata stakedContracts,
    address[] calldata sponsors,
    address[] calldata tokenAddresses
  ) external returns (uint[] memory tokensRewarded);
}
