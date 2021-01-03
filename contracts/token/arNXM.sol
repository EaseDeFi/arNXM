pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IarNXMVault.sol";

contract ArNXMToken is ERC20 {

    // Vault is needed so that we can adjust referrer balances when a token is transferred.
    IarNXMVault public arNXMVault;

    constructor(address _arNXMVault) ERC20("Armor NXM", "arNXM") public {
        arNXMVault = IarNXMVault(_arNXMVault);
    }
    
    /**
     * @dev Only arNXMVault is allowed to mint and burn tokens.
    **/
    modifier onlyArNxm {
        require(msg.sender == address(arNXMVault), "Sender is not arNXM Vault.");
        _;
    }
    
    function mint(address _to, uint256 _amount)
      external
      onlyArNxm
    returns (bool)
    {
        _mint(_to, _amount);
        return true;
    }
    
    function burn(address _from, uint256 _amount)
      external
      onlyArNxm
    returns (bool)
    {
        _burn(_from, _amount);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        arNXMVault.alertTransfer(from, to, amount);
    }

}
