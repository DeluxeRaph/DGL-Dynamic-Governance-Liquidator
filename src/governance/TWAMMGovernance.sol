// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../TWAMM.sol";
import "./WrappedGovernanceToken.sol";
import {TWAMMImplementation} from "../implementation/TWAMMImplementation.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TWAMMGovernance is TWAMM {
    WrappedGovernanceToken public governanceToken;
    IERC20 public daoToken;
    uint256 public proposalCount;

    uint256 public constant PROPOSAL_THRESHOLD_PERCENTAGE = 1; // 1% of total supply
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_PARTICIPATION_PERCENTAGE = 25; // 25% of total supply
    uint256 public constant MAX_DURATION = 365 days; // Maximum duration for a proposal

    // Declare immutable variables
    Currency public immutable token0;
    Currency public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    TWAMM flags =
        TWAMM(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)));

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 amount;
        uint256 duration;
        bool zeroForOne;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        Vote votes;
    }

    struct Vote {
        uint256 forVotes;
        uint256 againstVotes;
    }

    mapping(uint256 => Proposal) internal proposals;
    mapping(address => mapping(uint256 => bool)) public hasVoted;
    mapping(address => uint256) public lockedTokens;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 amount,
        uint256 duration,
        bool zeroForOne
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalFailed(uint256 indexed proposalId, string reason);
    event TokensWithdrawn(address indexed user, uint256 amount);

    constructor(
        IPoolManager _manager,
        uint256 _expirationInterval,
        IERC20 _daoToken,
        Currency _token0,
        Currency _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) TWAMM(_manager, _expirationInterval) {
        daoToken = _daoToken;
        governanceToken = new WrappedGovernanceToken(_daoToken);
        new TWAMMImplementation(_manager, _expirationInterval, flags);
        
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    function createProposal(uint256 amount, uint256 duration, bool zeroForOne) external {
        uint256 totalSupply = daoToken.totalSupply();
        uint256 proposerBalance = daoToken.balanceOf(msg.sender);
        
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
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false,
            votes: Vote(0, 0)
        });

        emit ProposalCreated(proposalId, msg.sender, amount, duration, zeroForOne);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[msg.sender][proposalId], "Already voted on this proposal");
        require(daoToken.balanceOf(msg.sender) > 0, "No DAO tokens to vote with");

        uint256 voteWeight = 1; // Each vote counts as 1

        daoToken.transferFrom(msg.sender, address(this), voteWeight);
        governanceToken.mint(msg.sender, voteWeight);

        if (support) {
            proposal.votes.forVotes += voteWeight;
        } else {
            proposal.votes.againstVotes += voteWeight;
        }

        hasVoted[msg.sender][proposalId] = true;
        lockedTokens[msg.sender] += voteWeight;

        emit Voted(proposalId, msg.sender, support);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");

        uint256 totalVotes = proposal.votes.forVotes + proposal.votes.againstVotes;
        uint256 totalSupply = daoToken.totalSupply();

        if (totalVotes < (totalSupply * MIN_PARTICIPATION_PERCENTAGE) / 100) {
            proposal.executed = true;
            emit ProposalFailed(proposalId, "Insufficient participation");
            return;
        }

        if (proposal.votes.againstVotes >= proposal.votes.forVotes) {
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

    function withdrawTokens(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.executed, "Proposal not yet executed");
        require(hasVoted[msg.sender][proposalId], "Did not vote on this proposal");

        uint256 amount = 1; // Each vote locked 1 token
        lockedTokens[msg.sender] -= amount;
        hasVoted[msg.sender][proposalId] = false;

        governanceToken.burnFrom(msg.sender, amount);
        daoToken.transfer(msg.sender, amount);

        emit TokensWithdrawn(msg.sender, amount);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: token0,
            currency1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: flags
        });
    }
}