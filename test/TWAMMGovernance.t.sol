// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/governance/TWAMMGovernance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDAOToken is ERC20 {
    constructor() ERC20("Mock DAO Token", "MDT") {
        _mint(msg.sender, 1000000e18); // Mint 1 million tokens
    }
}

contract TWAMMGovernanceTest is Test {
    TWAMMGovernance public governance;
    MockDAOToken public daoToken;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    address constant HOOK_ADDRESS = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

    function setUp() public {
        daoToken = new MockDAOToken();
        governance = new TWAMMGovernance(IPoolManager(address(0x123)), 10000, IERC20(address(daoToken)));

        // (, bytes32[] memory writes) = vm.accesses(address(governance));
        // vm.etch(address(governance), address(governance).code);
        // // for each storage key that was written during the hook implementation, copy the value over
        // unchecked {
        //     for (uint256 i = 0; i < writes.length; i++) {
        //         bytes32 slot = writes[i];
        //         vm.store(address(governance), slot, vm.load(address(governance), slot));
        //     }
        // }
        
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
        // Get the proposal as a single struct
        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);

        // Now we can access the struct fields directly
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
        assertEq(proposal.votesFor, 200000e18);
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
        assertEq(proposal.votesFor, 200000e18);
        assertEq(proposal.votesAgainst, 200000e18);
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

        vm.prank(charlie);
        governance.vote(proposalId, false);

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

        vm.prank(bob);
        governance.vote(proposalId, true);
        vm.prank(charlie);
        governance.vote(proposalId, true);

        vm.warp(block.timestamp + 7 days + 1);

        governance.executeProposal(proposalId);

        TWAMMGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.executed, true);
        // You should add a check here to ensure the TWAMM was actually updated
        // This might involve mocking the TWAMM contract or checking state changes
    }
}