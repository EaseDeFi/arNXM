pragma solidity ^0.6.6;

import '../general/Ownable.sol';

/**
 * @dev Simple timelock owner contract to be used until we implement a governance contract.
**/
contract TimelockOwned is Ownable {
    
    // Incremental counter of proposal IDs.
    uint256 id;
    
    // Amount of time that must pass before a proposal can be implemented.
    uint256 timelock = 2 days;
    
    struct Proposal {
        uint128 id;
        uint128 ending;
        address target;
        bytes data;
    }
    
    // Mapping of proposal ID => proposal struct.
    mapping (uint256 => Proposal) proposals;

    function implementProposal(uint256 _id)
      external
      onlyOwner
    {
        Proposal memory proposal = proposals[_id];
        require(proposal.ending != 0 && proposal.ending <= block.timestamp);
        executeProposal(proposal.target, proposal.data);
        delete proposals[_id];
    }
    
    function submitProposal(address _target, bytes calldata _data)
      external
      onlyOwner
    {
        id++;
        Proposal memory proposal = Proposal(uint128(id), uint128(block.timestamp + timelock), _target, _data);
        proposals[id] = proposal;
    }
    
    function executeProposal(address _target, bytes memory _data)
      internal
    {
        _target.call{value: 0}(_data);
    }
    
}