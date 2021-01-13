// SPDX-License-Identifier: (c) Armor.Fi DAO, 2021

pragma solidity ^0.6.6;

import '../general/Ownable.sol';

/**
 * @dev Simple timelock owner contract to be used until we implement a governance contract.
**/
contract TimelockOwned is Ownable {
    
    // Incremental counter of proposal IDs.
    uint256 id;
    
    // Amount of time that must pass before a proposal can be implemented. Change this to 2 days before public launch.
    uint256 public timelock;
    
    struct Proposal {
        uint128 id;
        uint128 ending;
        address target;
        uint256 value;
        bytes data;
    }
    
    // Mapping of proposal ID => proposal struct.
    mapping (uint256 => Proposal) proposals;

    event ProposalSubmitted(uint256 id, address target, uint256 value, bytes data, uint256 timestamp, uint256 execTimestamp);
    event ProposalExecuted(uint256 id, address target, uint256 value, bytes data, uint256 timestamp);

    /**
     * @dev External execution.
    **/
    function implementProposal(uint256 _id)
      external
      onlyOwner
    {
        Proposal memory proposal = proposals[_id];
        require(proposal.ending != 0 && proposal.ending <= block.timestamp);
        executeProposal(proposal.target, proposal.value, proposal.data);
        emit ProposalExecuted(_id, proposal.target, proposal.value, proposal.data, block.timestamp);
        delete proposals[_id];
    }
    
    function submitProposal(address _target, uint256 _value, bytes calldata _data)
      external
      onlyOwner
    {
        id++;
        Proposal memory proposal = Proposal(uint128(id), uint128(block.timestamp + timelock), _target, _value, _data);
        proposals[id] = proposal;
        emit ProposalSubmitted(id, proposal.target, proposal.value, proposal.data, block.timestamp, uint256(proposal.ending));
    }
    
    function deleteProposal(uint256 _id)
      external
      onlyOwner
    {
        delete proposals[_id];
    }
    
    function changeTimelock(uint256 _time)
      public
    {
        require(msg.sender == address(this), "Only this contract may change timelock.");
        timelock = _time;
    }
    
    function executeProposal(address _target, uint256 _value, bytes memory _data)
      internal
    {
        (bool success, ) = _target.call{value: _value}(_data);
        require(success, "Failed to execute proposal");
    }
    
}