// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TWAMMGovernance} from "../src/governance/TWAMMGovernance.sol";
import {TWAMMQuoter} from "../src/quoter/TWAMMQuoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IQuoter} from "v4-periphery/src/interfaces/IQuoter.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract TWAMMQuoterTest is Test, Deployers {
    using PoolKey for PoolKey;

    IPoolManager poolManager;
    IQuoter quoter;
    TWAMMGovernance governance;
    TWAMMQuoter twammQuoter;

    PoolKey poolKey;
    uint256 initialProposalAmount = 1e18;
    bool zeroForOne = true;

    function setUp() public {
        // Initialize pool manager, deploy quoter, governance, and TWAMMQuoter
        poolManager = Deployers.deployFreshManagerAndRouters();
        quoter = Deployers.deployQuoter(address(poolManager));
        governance = new TWAMMGovernance(poolManager, 1 weeks, Deployers.deployTestToken("Governance Token", "GT", 18));

        twammQuoter = new TWAMMQuoter(address(poolManager), address(governance), address(quoter));

        // Create pool for the quoter to interact with
        poolKey = PoolKey({
            currency0: Deployers.deployTestToken("Test Token 0", "T0", 18),
            currency1: Deployers.deployTestToken("Test Token 1", "T1", 18),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        poolManager.initialize(poolKey, TickMath.getSqrtRatioAtTick(0), "");
    }

    function testCreateGovernanceProposal() public {
        // Mint governance tokens and create a proposal
        ERC20Votes governanceToken = ERC20Votes(address(governance.governanceToken()));
        governanceToken.mint(address(this), 200 * 10**18); // mint to meet the proposal threshold

        governance.createProposal(initialProposalAmount, 1e18, 7 days, zeroForOne);

        // Check proposal created
        (,, uint256 amount,,,) = governance.proposals(0);
        assertEq(amount, initialProposalAmount, "Proposal not created correctly");
    }

    function testQuoteProposalExactInput() public {
        // Create a proposal
        createSampleProposal();

        // Get quote for the created proposal
        (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) = twammQuoter.getQuoteForProposal(0, true);

        // Log results for visual verification
        emit log_int(int256(deltaAmounts[1]));  // Expected output amount
        emit log_uint(sqrtPriceX96After);       // Expected price after swap

        // Check if event emitted correctly
        vm.expectEmit(true, true, true, true);
        emit QuotedSwap(0, deltaAmounts, sqrtPriceX96After);
        twammQuoter.getQuoteForProposal(0, true);
    }

    function testQuoteProposalExactOutput() public {
        // Create a proposal
        createSampleProposal();

        // Get quote for exact output of the created proposal
        (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) = twammQuoter.getQuoteForProposal(0, false);

        // Log results for visual verification
        emit log_int(int256(deltaAmounts[0]));  // Expected input amount
        emit log_uint(sqrtPriceX96After);       // Expected price after swap

        // Check if event emitted correctly
        vm.expectEmit(true, true, true, true);
        emit QuotedSwap(0, deltaAmounts, sqrtPriceX96After);
        twammQuoter.getQuoteForProposal(0, false);
    }

    function testExecuteProposal() public {
        // Create a proposal and get quote for it
        createSampleProposal();
        (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) = twammQuoter.getQuoteForProposal(0, true);

        // Execute the proposal after the voting period
        vm.warp(block.timestamp + 8 days);  // Move forward in time to ensure voting period has ended
        governance.executeProposal(0);

        // Check proposal was executed
        (, , , , , , , bool executed) = governance.proposals(0);
        assertTrue(executed, "Proposal not executed properly");
    }

    function testQuoterOffChainEvaluation() public {
        // Create a proposal
        createSampleProposal();

        // Simulate off-chain evaluation of the quote
        (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) = twammQuoter.getQuoteForProposal(0, true);
        emit log_int(int256(deltaAmounts[1]));  // Log output amount
        emit log_uint(sqrtPriceX96After);       // Log sqrt price after swap

        // Compare the off-chain result with actual execution on-chain
        BalanceDelta swapDelta = swap(poolKey, zeroForOne, -int256(uint256(initialProposalAmount)), "");
        assertEq(deltaAmounts[1], -swapDelta.amount1(), "Off-chain quote does not match on-chain execution");

        // Test if the quoter contract's event gets emitted correctly for off-chain quotes
        vm.expectEmit(true, true, true, true);
        emit QuotedSwap(0, deltaAmounts, sqrtPriceX96After);
        twammQuoter.getQuoteForProposal(0, true);
    }

    function createSampleProposal() internal {
        ERC20Votes governanceToken = ERC20Votes(address(governance.governanceToken()));
        governanceToken.mint(address(this), 200 * 10**18);  // Mint governance tokens for proposal creation

        governance.createProposal(initialProposalAmount, 1e18, 7 days, zeroForOne);
    }

    event QuotedSwap(uint256 indexed proposalId, int128[] deltaAmounts, uint160 sqrtPriceX96After);
}
