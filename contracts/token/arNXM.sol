pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ArmorToken is ERC20, Ownable {

    constructor() ERC20("Armor NXM", "arNXM") public {
        _mint( msg.sender, 300000 * (10 ** 18) );
    }
    
    function mint(address _to, uint256 _amount)
      external
      onlyOwner
    returns (bool)
    {
        _mint(_to, _amount);
        return true;
    }
    
    function burn(address _from, uint256 _amount)
      external
      onlyOwner
    returns (bool)
    {
        _burn(_from, _amount);
        return true;
    }

}
