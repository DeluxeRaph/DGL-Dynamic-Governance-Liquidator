// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../TWAMM.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
contract TWAMMGovernance is TWAMM {
    ERC20Votes public governanceToken;
    uint256 public proposalCount;

    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100 * 10**18; // 100 tokens
    uint256 public constant VOTING_PERIOD = 7 days;

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 amount;
        uint256 duration;
        bool zeroForOne;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, uint256 amount, uint256 salesRate, uint256 duration, bool zeroForOne);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(
        IPoolManager _manager,
        uint256 _expirationInterval,
        IERC20 _underlyingToken
    ) TWAMM(_manager, _expirationInterval) {
        governanceToken = new WrappedGovernanceToken(_underlyingToken);
    }

    function createProposal(uint256 amount, uint256 salesRate, uint256 duration, bool zeroForOne) external {
        require(governanceToken.balanceOf(msg.sender) >= MIN_PROPOSAL_THRESHOLD, "Insufficient tokens to propose");

        uint256 proposalId = proposalCount;
        proposalCount++;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            amount: amount,
            duration: duration,
            zeroForOne: zeroForOne,
            votesFor: 0,
            votesAgainst: 0,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, amount, salesRate, duration, zeroForOne);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");

        uint256 votes = governanceToken.getPastVotes(msg.sender, proposal.endTime - VOTING_PERIOD);
        require(votes > 0, "No voting power");

        if (support) {
            proposal.votesFor += votes;
        } else {
            proposal.votesAgainst += votes;
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal did not pass");

        proposal.executed = true;

        
        PoolKey memory poolKey = getPoolKey();
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        State storage twamm = twammStates[poolId];
        OrderKey memory orderKey = OrderKey({
            owner: address(this),
            expiration: uint160(block.timestamp + proposal.duration),
            zeroForOne: proposal.zeroForOne
        });
        
        _submitOrder(twamm, orderKey, proposal.amount);

        emit ProposalExecuted(proposalId);
    }

    // You need to implement this function to return the correct PoolKey
function getPoolKey() internal view returns (PoolKey memory) {
    // Implementation depends on how you're storing or deriving the PoolKey
}
}

contract WrappedGovernanceToken is ERC20, ERC20Wrapper, ERC20Votes, ERC20Permit {
    constructor(IERC20 wrappedToken)
        ERC20("Wrapped Governance Token", "wGOV")
        ERC20Permit("Wrapped Governance Token")
        ERC20Wrapper(wrappedToken)
        
    {}

    // Override decimals function to resolve conflict
    function decimals() public view override(ERC20, ERC20Wrapper) returns (uint8) {
        return super.decimals();
    }

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, amount);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
    
}