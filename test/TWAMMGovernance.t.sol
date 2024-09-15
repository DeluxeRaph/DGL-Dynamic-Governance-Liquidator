// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/governance/TWAMMGovernance.sol";
import "../src/mocks/MockDaoToken.sol";
import "../src/mocks/MockERC20.sol";
import "../src/governance/WrappedGovernanceToken.sol";
import {TWAMM} from "../src/TWAMM.sol";
import {TWAMMImplementation} from "../src/implementation/TWAMMImplementation.sol";
import "@uniswap/v4-core/src/libraries/Hooks.sol";
import "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Vm} from "forge-std/Vm.sol";

contract TWAMMGovernanceTest is Test, Deployers {
    TWAMMGovernance public governance;
    TWAMMImplementation public twammImpl;
    address public twamm;
    PoolKey public poolKey;
    PoolId public poolId;
    MockDAOToken public daoToken;
    WrappedGovernanceToken public governanceToken;
    MockERC20 public token0;
    MockERC20 public token1;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public ed = address(0x4);

    function setUp() public {
        // Initialize the manager and routers
        deployFreshManagerAndRouters();
        // 'manager' is initialized in 'Deployers' and accessible here

        // Deploy currencies
        (currency0, currency1) = deployMintAndApprove2Currencies();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // Set up the TWAMM hook
        twamm =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG));

        // Deploy the TWAMMImplementation contract
        twammImpl = new TWAMMImplementation(manager, 10000, TWAMM(twamm));

        // Etch the code of the implementation into the twamm address
        (, bytes32[] memory writes) = vm.accesses(address(twammImpl));
        vm.etch(twamm, address(twammImpl).code);

        // Copy storage values
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(twamm, slot, vm.load(address(twammImpl), slot));
            }
        }

        // Initialize the pool with the TWAMM hook
        (poolKey, poolId) = initPool(
            currency0,
            currency1,
            IHooks(twamm), // Cast twamm to IHooks
            3000,
            60,
            1 << 96,
            bytes("")
        );
        // Add liquidity to the pool
        token0.mint(address(this), 100 ether);
        token1.mint(address(this), 100 ether);
        token0.approve(address(modifyLiquidityRouter), 100 ether);
        token1.approve(address(modifyLiquidityRouter), 100 ether);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether, 0), bytes("")
        );

        // Deploy DAO token and governance token
        daoToken = new MockDAOToken();
        governanceToken = new WrappedGovernanceToken(IERC20(address(daoToken)));

        // Deploy the governance contract using 'manager' and 'twamm'
        governance =
            new TWAMMGovernance(manager, 10000, IERC20(address(daoToken)), currency0, currency1, 3000, 60, twamm);

        // Distribute tokens to test addresses
        daoToken.mint(alice, 200000e18);
        daoToken.mint(bob, 200000e18);
        daoToken.mint(charlie, 200000e18);
        daoToken.mint(ed, 200000);

        // Approve governance contract to spend tokens
        vm.prank(alice);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(bob);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(charlie);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(ed);
        daoToken.approve(address(governance), type(uint256).max);
    }

    // helper function to convert to valid proposal duration
    function getValidProposalDuration() public view returns (uint256) {
        uint256 twammInterval = ITWAMM(twamm).expirationInterval();
        uint256 proposalDuration = 7 days;
        // Ensure proposalDuration is a multiple of twammInterval
        return proposalDuration - (proposalDuration % twammInterval) + twammInterval;
    }

    function testProposalCreationRequires1Percent() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");

        vm.expectRevert("Insufficient tokens to propose");
        vm.prank(ed);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
    }

    function testProposalLastsOneWeek() public {
        uint256 validDuration = getValidProposalDuration();
        uint256 startTime = block.timestamp;
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");

        uint256 proposalId = governance.proposalCount() - 1;
        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);

        assertEq(proposal.startTime, startTime, "Start time should match");
        assertEq(proposal.endTime, startTime + 7 days, "End time should be 7 days after start");
    }

    function testVotingWithWrappedToken() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.votes.forVotes, 1e18);
    }

    function testTrackingYayAndNayVotes() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);
        vm.prank(charlie);
        governance.vote(proposalId, false, 1e18);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.votes.forVotes, 1e18);
        assertEq(proposal.votes.againstVotes, 1e18);
    }

    function testMinimum25PercentParticipation() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);

        vm.warp(block.timestamp + validDuration + 1);

        vm.expectRevert("Insufficient participation");
        governance.executeProposal(proposalId);
    }

    function testProposalDeniedWithMoreNays() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, false, 1e18);
        vm.prank(charlie);
        governance.vote(proposalId, false, 1e18);

        vm.warp(block.timestamp + validDuration + 1);

        vm.expectRevert("Proposal denied");
        governance.executeProposal(proposalId);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.executed, false);
    }

function testSuccessfulProposalUpdatesTWAMM() public {
    uint256 validDuration = getValidProposalDuration();
    uint256 totalSupply = daoToken.totalSupply();
    uint256 requiredParticipation = (totalSupply * 25) / 100; // 25% of total supply

    vm.prank(alice);
    governance.createProposal(100e18, validDuration, true, "Test proposal");
    uint256 proposalId = governance.proposalCount() - 1;

    // Vote with enough tokens to meet the participation threshold
    vm.prank(alice);
    governance.vote(proposalId, true, requiredParticipation / 3);
    vm.prank(bob);
    governance.vote(proposalId, true, requiredParticipation / 3);
    vm.prank(charlie);
    governance.vote(proposalId, true, requiredParticipation / 3);

    vm.warp(block.timestamp + validDuration + 1);

    // Mock the TWAMM contract to expect a call to submitOrder
    bytes32 mockOrderId = bytes32(uint256(1));
    vm.mockCall(address(twamm), abi.encodeWithSelector(ITWAMM.submitOrder.selector), abi.encode(mockOrderId));

    governance.executeProposal(proposalId);

    TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
    assertEq(proposal.executed, true, "Proposal should be marked as executed");
}

    function testTokenLocking() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        uint256 bobBalanceBefore = daoToken.balanceOf(bob);
        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);
        uint256 bobBalanceAfter = daoToken.balanceOf(bob);

        assertEq(bobBalanceBefore - bobBalanceAfter, 1e18, "1e18 tokens should be locked");
        assertEq(governance.lockedTokens(bob, proposalId), 1e18, "1e18 tokens should be recorded as locked");
    }

    function testTokenWithdrawal() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 150000e18);
        vm.prank(charlie);
        governance.vote(proposalId, true, 150000e18);
        vm.prank(alice);
        governance.vote(proposalId, true, 150000e18);

        vm.warp(block.timestamp + validDuration + 1);

        // Mock the TWAMM contract to expect a call to submitOrder
        bytes32 mockOrderId = bytes32(uint256(1)); // Example mock order ID
        vm.mockCall(address(twamm), abi.encodeWithSelector(ITWAMM.submitOrder.selector), abi.encode(mockOrderId));

        governance.executeProposal(proposalId);

        uint256 bobBalanceBefore = daoToken.balanceOf(bob);
        vm.prank(bob);
        governance.withdrawTokens(proposalId);
        uint256 bobBalanceAfter = daoToken.balanceOf(bob);

        assertEq(bobBalanceAfter - bobBalanceBefore, 150000e18, "tokens should be withdrawn");
        assertEq(governance.lockedTokens(bob, proposalId), 0, "No tokens should remain locked");
    }

    function testCannotWithdrawBeforeExecution() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);

        vm.expectRevert("Proposal not yet executed");
        vm.prank(bob);
        governance.withdrawTokens(proposalId);
    }

    function testCannotVoteTwice() public {
        uint256 validDuration = getValidProposalDuration();
        vm.prank(alice);
        governance.createProposal(100e18, validDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);

        vm.expectRevert("Already voted on this proposal");
        vm.prank(bob);
        governance.vote(proposalId, true, 1e18);
    }
}
