// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../TWAMM.sol";
import "./WrappedGovernanceToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract TWAMMGovernance {
    WrappedGovernanceToken public governanceToken;
    IERC20 public daoToken;
    uint256 public proposalCount;

    uint256 public constant PROPOSAL_THRESHOLD_PERCENTAGE = 1; // 1% of total supply
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_PARTICIPATION_PERCENTAGE = 25; // 25% of total supply
    uint256 public constant MAX_DURATION = 365 days; // Maximum duration for a proposal

    uint256 public immutable twammExpirationInterval;

    // Declare immutable variables
    Currency public immutable token0;
    Currency public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    IPoolManager public immutable manager;
    uint256 public immutable expirationInterval;
    address public immutable twamm;

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
        string description;
    }

    struct Vote {
        uint256 forVotes;
        uint256 againstVotes;
    }

    mapping(uint256 => Proposal) internal proposals;
    mapping(address => mapping(uint256 => bool)) public hasVoted;
    mapping(address => mapping(uint256 => uint256)) public lockedTokens;

    event ProposalCreated(
        uint256 indexed proposalId, address indexed proposer, uint256 amount, uint256 duration, bool zeroForOne
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
        int24 _tickSpacing,
        address _twamm
    ) {
        manager = _manager;
        expirationInterval = _expirationInterval;
        daoToken = _daoToken;
        governanceToken = new WrappedGovernanceToken(_daoToken);
        twammExpirationInterval = ITWAMM(_twamm).expirationInterval();
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        twamm = _twamm;
    }

    function createProposal(uint256 amount, uint256 duration, bool zeroForOne, string memory proposalDescription)
        external
    {
        uint256 totalSupply = daoToken.totalSupply();
        uint256 proposerBalance = daoToken.balanceOf(msg.sender);

        require(
            proposerBalance >= (totalSupply * PROPOSAL_THRESHOLD_PERCENTAGE) / 100, "Insufficient tokens to propose"
        );

        require(duration > 0 && duration <= MAX_DURATION, "Invalid duration");
        require(amount > 0, "Amount must be greater than 0");

        uint256 sellRate = amount / duration;
        require(sellRate > 0, "Sell rate too low");
        require(duration % twammExpirationInterval == 0, "Duration must be multiple of TWAMM interval");

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
            votes: Vote(0, 0),
            description: proposalDescription
        });

        emit ProposalCreated(proposalId, msg.sender, amount, duration, zeroForOne);
    }

    function vote(uint256 proposalId, bool support, uint256 voteWeight) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[msg.sender][proposalId], "Already voted on this proposal");
        require(daoToken.balanceOf(msg.sender) >= voteWeight, "Insufficient DAO tokens to vote with");
        require(voteWeight > 0, "Vote weight must be greater than zero");

        daoToken.transferFrom(msg.sender, address(this), voteWeight);
        governanceToken.mint(msg.sender, voteWeight);

        if (support) {
            proposal.votes.forVotes += voteWeight;
        } else {
            proposal.votes.againstVotes += voteWeight;
        }

        hasVoted[msg.sender][proposalId] = true;
        lockedTokens[msg.sender][proposalId] = voteWeight;

        emit Voted(proposalId, msg.sender, support);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votes.forVotes > proposal.votes.againstVotes, "Proposal denied");
        require(
            (proposal.votes.forVotes + proposal.votes.againstVotes) * 4 >= daoToken.totalSupply(),
            "Insufficient participation"
        );

        // Calculate the expiration time
        uint256 expiration = block.timestamp + proposal.duration;
        // Ensure it's on the correct interval
        expiration = expiration - (expiration % twammExpirationInterval);

        proposal.executed = true;

        // Approve TWAMM to spend tokens
        IERC20(proposal.zeroForOne ? Currency.unwrap(token0) : Currency.unwrap(token1)).approve(
            address(twamm), proposal.amount
        );

        emit ProposalExecuted(proposalId);
    }

    function withdrawTokens(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.executed, "Proposal not yet executed");
        require(hasVoted[msg.sender][proposalId], "Did not vote on this proposal");

        uint256 amount = lockedTokens[msg.sender][proposalId];
        require(amount > 0, "No tokens to withdraw");

        // Update state before external calls
        lockedTokens[msg.sender][proposalId] = 0;
        hasVoted[msg.sender][proposalId] = false;

        // Burn the governance tokens
        governanceToken.burnFrom(msg.sender, amount);

        // Transfer back the DAO tokens
        daoToken.transfer(msg.sender, amount);

        emit TokensWithdrawn(msg.sender, amount);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({currency0: token0, currency1: token1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(twamm)});
    }
}
