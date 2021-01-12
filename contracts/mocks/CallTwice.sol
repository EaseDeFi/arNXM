pragma solidity ^0.6.0;

import "../interfaces/IRewardDistributionRecipient.sol";
import "../interfaces/IERC20.sol";
contract CallTwice {
    function execute(address recipient, address token, uint256 amount) external {
        IERC20(token).approve(recipient, amount);
        IRewardDistributionRecipient(recipient).notifyRewardAmount(amount/2);
        IRewardDistributionRecipient(recipient).notifyRewardAmount(amount/2);
    }

    function executeETH(address recipient) external payable {
        IRewardDistributionRecipient(recipient).notifyRewardAmount{value:msg.value/2}(msg.value/2);
        IRewardDistributionRecipient(recipient).notifyRewardAmount{value:msg.value/2}(msg.value/2);
    }
}
