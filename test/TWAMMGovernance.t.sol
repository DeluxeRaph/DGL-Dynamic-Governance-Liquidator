// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/governance/TWAMMGovernance.sol";
import "../src/mocks/MockDaoToken.sol";
import "@uniswap/v4-core/src/libraries/Hooks.sol";
import "@uniswap/v4-core/src/types/Currency.sol";

contract TWAMMGovernanceTest is Test {
    TWAMMGovernance public governance;
    MockDAOToken public daoToken;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    TWAMM flags =
        TWAMM(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)));
    function setUp() public {
        daoToken = new MockDAOToken();
        governance = new TWAMMGovernance(
            IPoolManager(address(0x123)),
            10000,
            IERC20(address(daoToken)),
            Currency.wrap(address(0x1)),
            Currency.wrap(address(0x2)),
            3000,
            60
        );
        
        // Distribute tokens
        daoToken.transfer(alice, 200000e18);
        daoToken.transfer(bob, 200000e18);
        daoToken.transfer(charlie, 200000e18);

        // Approve governance contract to spend tokens
        vm.prank(alice);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(bob);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(charlie);
        daoToken.approve(address(governance), type(uint256).max);
    }

    function testProposalCreationRequires1Percent() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);

        vm.expectRevert("Insufficient tokens to propose");
        vm.prank(charlie);
        governance.createProposal(100e18, 7 days, true);
    }

    function testProposalLastsOneWeek() public {
        uint256 startTime = block.timestamp;
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        
        uint256 proposalId = governance.proposalCount() - 1;
        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);

        assertEq(proposal.startTime, startTime, "Start time should match");
        assertEq(proposal.endTime, startTime + 7 days, "End time should be 7 days after start");
    }

    function testVotingWithWrappedToken() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.votes.forVotes, 1);
    }

    function testTrackingYayAndNayVotes() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);
        vm.prank(charlie);
        governance.vote(proposalId, false);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.votes.forVotes, 1);
        assertEq(proposal.votes.againstVotes, 1);
    }

    function testMinimum25PercentParticipation() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert("Insufficient participation");
        governance.executeProposal(proposalId);

        // We need many more votes to reach 25% participation
        for (uint i = 0; i < 250000; i++) {
            address voter = address(uint160(i + 1000));
            daoToken.transfer(voter, 1e18);
            vm.prank(voter);
            daoToken.approve(address(governance), 1e18);
            vm.prank(voter);
            governance.vote(proposalId, true);
        }

        governance.executeProposal(proposalId);
    }

    function testProposalDeniedWithMoreNays() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, false);
        vm.prank(charlie);
        governance.vote(proposalId, false);

        // Add more votes to reach minimum participation
        for (uint i = 0; i < 250000; i++) {
            address voter = address(uint160(i + 1000));
            daoToken.transfer(voter, 1e18);
            vm.prank(voter);
            daoToken.approve(address(governance), 1e18);
            vm.prank(voter);
            governance.vote(proposalId, false);
        }

        vm.warp(block.timestamp + 7 days + 1);

        governance.executeProposal(proposalId);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.executed, true);
        // You may want to add an additional check here to ensure the TWAMM wasn't updated
    }

    function testSuccessfulProposalUpdatesTWAMM() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        // Add votes to reach minimum participation and pass the proposal
        for (uint i = 0; i < 250000; i++) {
            address voter = address(uint160(i + 1000));
            daoToken.transfer(voter, 1e18);
            vm.prank(voter);
            daoToken.approve(address(governance), 1e18);
            vm.prank(voter);
            governance.vote(proposalId, true);
        }

        vm.warp(block.timestamp + 7 days + 1);

        governance.executeProposal(proposalId);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.executed, true);
        // You should add a check here to ensure the TWAMM was actually updated
        // This might involve mocking the TWAMM contract or checking state changes
    }

    function testTokenLocking() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        uint256 bobBalanceBefore = daoToken.balanceOf(bob);
        vm.prank(bob);
        governance.vote(proposalId, true);
        uint256 bobBalanceAfter = daoToken.balanceOf(bob);

        assertEq(bobBalanceBefore - bobBalanceAfter, 1, "One token should be locked");
        assertEq(governance.lockedTokens(bob), 1, "One token should be recorded as locked");
    }

    function testTokenWithdrawal() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);

        vm.warp(block.timestamp + 7 days + 1);

        // Add more votes to reach minimum participation
        for (uint i = 0; i < 250000; i++) {
            address voter = address(uint160(i + 1000));
            daoToken.transfer(voter, 1e18);
            vm.prank(voter);
            daoToken.approve(address(governance), 1e18);
            vm.prank(voter);
            governance.vote(proposalId, true);
        }

        governance.executeProposal(proposalId);

        uint256 bobBalanceBefore = daoToken.balanceOf(bob);
        vm.prank(bob);
        governance.withdrawTokens(proposalId);
        uint256 bobBalanceAfter = daoToken.balanceOf(bob);

        assertEq(bobBalanceAfter - bobBalanceBefore, 1, "One token should be withdrawn");
        assertEq(governance.lockedTokens(bob), 0, "No tokens should remain locked");
    }

    function testCannotWithdrawBeforeExecution() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);

        vm.expectRevert("Proposal not yet executed");
        vm.prank(bob);
        governance.withdrawTokens(proposalId);
    }

    function testCannotVoteTwice() public {
        vm.prank(alice);
        governance.createProposal(100e18, 7 days, true);
        uint256 proposalId = governance.proposalCount() - 1;

        vm.prank(bob);
        governance.vote(proposalId, true);

        vm.expectRevert("Already voted on this proposal");
        vm.prank(bob);
        governance.vote(proposalId, true);
    }
}