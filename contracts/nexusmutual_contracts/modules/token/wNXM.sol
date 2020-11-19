pragma solidity 0.5.17;

import "../../library/token/ERC20/ERC20.sol";
import "../../library/token/ERC20/ERC20Detailed.sol";
import "../../library/math/SafeMath.sol";
import "../../library/math/Math.sol";
import "../../library/token/ERC20/SafeERC20.sol";
import "../../interfaces/INXM.sol";
import "../../library/ERC20Permit.sol";


contract wNXM is ERC20, ERC20Detailed, ERC20Permit {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    INXM public NXM;

    modifier notwNXM(address recipient) {
        require(recipient != address(this), "wNXM: can not send to self");
        _;
    }

    constructor(INXM _nxm) public ERC20Detailed("Wrapped NXM", "wNXM", 18) {
        NXM = _nxm;
    }

    function _transfer(address sender, address recipient, uint256 amount)
        internal
        notwNXM(recipient)
    {
        super._transfer(sender, recipient, amount);
    }

    function wrap(uint256 _amount) external {
        require(NXM.transferFrom(msg.sender, address(this), _amount), "wNXM: transferFrom failed");
        _mint(msg.sender, _amount);
    }

    function unwrap(uint256 _amount) external {
        unwrapTo(msg.sender, _amount);
    }

    function unwrapTo(address _to, uint256 _amount) public notwNXM(_to) {
        _burn(msg.sender, _amount);
        require(NXM.transfer(_to, _amount), "wNXM: transfer failed");
    }

    function canWrap(address _owner, uint256 _amount)
        external
        view
        returns (bool success, string memory reason)
    {
        if (NXM.allowance(_owner, address(this)) < _amount) {
            return (false, "insufficient allowance");
        }

        if (NXM.balanceOf(_owner) < _amount) {
            return (false, "insufficient NXM balance");
        }

        if (NXM.isLockedForMV(_owner) > now) {
            return (false, "NXM balance lockedForMv");
        }

        if (!NXM.whiteListed(address(this))) {
            return (false, "wNXM is not whitelisted");
        }

        return (true, "");
    }

    function canUnwrap(address _owner, address _recipient, uint256 _amount)
        external
        view
        returns (bool success, string memory reason)
    {
        if (balanceOf(_owner) < _amount) {
            return (false, "insufficient wNXM balance");
        }

        if (!NXM.whiteListed(_recipient)) {
            return (false, "recipient is not whitelisted");
        }

        if (NXM.isLockedForMV(address(this)) > now) {
            return (false, "wNXM is lockedForMv");
        }

        return (true, "");
    }

    /// @dev Method to claim junk and accidentally sent tokens
    function claimTokens(ERC20 _token, address payable _to, uint256 _balance) external {
        require(_to != address(0), "wNXM: can not send to zero address");

        if (_token == ERC20(address(NXM))) {
            uint256 surplusBalance = _token.balanceOf(address(this)).sub(totalSupply());
            require(surplusBalance > 0, "wNXM: there is no accidentally sent NXM");
            uint256 balance = _balance == 0 ? surplusBalance : Math.min(surplusBalance, _balance);
            _token.safeTransfer(_to, balance);
        } else if (_token == ERC20(0)) {
            // for Ether
            uint256 totalBalance = address(this).balance;
            uint256 balance = _balance == 0 ? totalBalance : Math.min(totalBalance, _balance);
            _to.transfer(balance);
        } else {
            // any other erc20
            uint256 totalBalance = _token.balanceOf(address(this));
            uint256 balance = _balance == 0 ? totalBalance : Math.min(totalBalance, _balance);
            require(balance > 0, "wNXM: trying to send 0 balance");
            _token.safeTransfer(_to, balance);
        }
    }
}
