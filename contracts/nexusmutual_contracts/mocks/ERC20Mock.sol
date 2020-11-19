pragma solidity ^0.5.0;

import "../library/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {

  function mintToSelf(uint256 amount) public {
    _mint(msg.sender, amount);
  }

  function mint(address account, uint256 amount) public {
    _mint(account, amount);
  }

}
