pragma solidity ^0.5.17;

interface IQuotation {
    function getWithdrawableCoverNoteCoverIds(address owner) external view returns(uint256[] memory, bytes32[] memory);
}
