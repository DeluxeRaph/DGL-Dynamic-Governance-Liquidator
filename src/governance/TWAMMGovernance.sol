// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../TWAMM.sol";
import {TWAMMImplementation} from "../implementation/TWAMMImplementation.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TWAMMGovernance is TWAMM {
    ERC20Votes public governanceToken;
    uint256 public proposalCount;

    uint256 public constant PROPOSAL_THRESHOLD_PERCENTAGE = 1; // 1% of total supply
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_PARTICIPATION_PERCENTAGE = 25; // 25% of total supply
    uint256 public constant MAX_DURATION = 365 days; // Maximum duration for a proposal

    TWAMM flags =
        TWAMM(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)));

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 amount;
        uint256 duration;
        bool zeroForOne;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        bool executed;
    }

    mapping(uint256 => Proposal) internal proposals;
    mapping(address => mapping(uint256 => bool)) public hasVoted;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 amount,
        uint256 duration,
        bool zeroForOne
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalFailed(uint256 indexed proposalId, string reason);

    constructor(IPoolManager _manager, uint256 _expirationInterval, IERC20 _underlyingToken)
        TWAMM(_manager, _expirationInterval)
    {
        governanceToken = new WrappedGovernanceToken(_underlyingToken);
        new TWAMMImplementation(_manager, _expirationInterval, flags);
        
    }

    function createProposal(uint256 amount, uint256 duration, bool zeroForOne) external {
        uint256 totalSupply = governanceToken.totalSupply();
        uint256 proposerBalance = governanceToken.balanceOf(msg.sender);
        
        require(
            proposerBalance >= (totalSupply * PROPOSAL_THRESHOLD_PERCENTAGE) / 100,
            "Insufficient tokens to propose"
        );

        require(duration > 0 && duration <= MAX_DURATION, "Invalid duration");
        require(amount > 0, "Amount must be greater than 0");

        uint256 sellRate = amount / duration;
        require(sellRate > 0, "Sell rate too low");

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
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, amount, duration, zeroForOne);
    }

    

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[msg.sender][proposalId], "Already voted on this proposal");

        uint256 votes = governanceToken.getPastVotes(msg.sender, proposal.startTime);
        require(votes > 0, "No voting power");

        if (support) {
            proposal.votesFor += votes;
        } else {
            proposal.votesAgainst += votes;
        }

        hasVoted[msg.sender][proposalId] = true;

        emit Voted(proposalId, msg.sender, support, votes);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 totalSupply = governanceToken.totalSupply();

        if (totalVotes < (totalSupply * MIN_PARTICIPATION_PERCENTAGE) / 100) {
            proposal.executed = true;
            emit ProposalFailed(proposalId, "Insufficient participation");
            return;
        }

        if (proposal.votesAgainst >= proposal.votesFor) {
            proposal.executed = true;
            emit ProposalFailed(proposalId, "More nays than yays");
            return;
        }

        proposal.executed = true;

        PoolKey memory poolKey = getPoolKey();
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        State storage twamm = twammStates[poolId];
        OrderKey memory orderKey = OrderKey({
            owner: address(this),
            expiration: uint160(block.timestamp + proposal.duration),
            zeroForOne: proposal.zeroForOne
        });

        uint256 sellRate = proposal.amount / proposal.duration;
        _submitOrder(twamm, orderKey, sellRate);

        emit ProposalExecuted(proposalId);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
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

    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}