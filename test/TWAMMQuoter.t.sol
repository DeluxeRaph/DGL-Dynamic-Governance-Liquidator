// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/quoter/TWAMMQuoter.sol";
import "../src/TWAMM.sol";
import "../src/governance/TWAMMGovernance.sol";
import "../src/mocks/MockERC20.sol";
import "../src/implementation/TWAMMImplementation.sol";
import "@uniswap/v4-core/src/libraries/Hooks.sol";
import "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

contract TWAMMQuoterTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    TWAMMQuoter public quoter;
    TWAMMGovernance public governance;
    TWAMMImplementation public twammImpl;
    address public twamm;
    PoolKey public poolKey;
    PoolId public poolId;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public daoToken;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Initialize the manager and routers
        deployFreshManagerAndRouters();

        // Deploy currencies
        (currency0, currency1) = deployMintAndApprove2Currencies();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // Set up the TWAMM hook
        twamm = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG));

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
        (poolKey, poolId) = initPool(currency0, currency1, IHooks(twamm), 3000, 60, 1 << 96, bytes(""));

        // Add liquidity to the pool
        token0.mint(address(this), 100 ether);
        token1.mint(address(this), 100 ether);
        token0.approve(address(modifyLiquidityRouter), 100 ether);
        token1.approve(address(modifyLiquidityRouter), 100 ether);
        modifyLiquidityRouter.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether, 0), bytes(""));

        // Deploy DAO token
        daoToken = new MockERC20("DAO Token", "DAO", 18);

        // Deploy the governance contract
        governance = new TWAMMGovernance(manager, 10000, IERC20(address(daoToken)), currency0, currency1, 3000, 60, twamm);

        // Deploy the quoter contract
        quoter = new TWAMMQuoter(address(manager), address(governance), twamm, poolKey);

        // Distribute tokens to test addresses
        daoToken.mint(alice, 200000e18);
        daoToken.mint(bob, 200000e18);

        // Approve governance contract to spend tokens
        vm.prank(alice);
        daoToken.approve(address(governance), type(uint256).max);
        vm.prank(bob);
        daoToken.approve(address(governance), type(uint256).max);
    }

    function testQuoterSetup() public {
        assertEq(address(quoter.poolManager()), address(manager), "Pool manager address mismatch");
        assertEq(address(quoter.governanceContract()), address(governance), "Governance contract address mismatch");
        assertEq(address(quoter.twamm()), twamm, "TWAMM address mismatch");
        assertEq(Currency.unwrap(quoter.currency0()), Currency.unwrap(poolKey.currency0), "Currency0 mismatch");
        assertEq(Currency.unwrap(quoter.currency1()), Currency.unwrap(poolKey.currency1), "Currency1 mismatch");
        assertEq(quoter.fee(), poolKey.fee, "Fee mismatch");
        assertEq(quoter.tickSpacing(), poolKey.tickSpacing, "Tick spacing mismatch");
        assertEq(address(quoter.hooks()), address(poolKey.hooks), "Hooks address mismatch");
    }

    function testQuoteProposal() public {
    // Create a proposal
    uint256 proposalAmount = 1 ether;
    uint256 proposalDuration = TWAMM(twamm).expirationInterval();
    vm.prank(alice);
    governance.createProposal(proposalAmount, proposalDuration, true, "Test proposal");
    uint256 proposalId = governance.proposalCount() - 1;

    // Get quote for the proposal
    (int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96After) = quoter.getQuoteForProposal(proposalId);

    // Log the values for debugging
    console.log("amount0Delta:", amount0Delta);
    console.log("amount1Delta:", amount1Delta);
    console.log("sqrtPriceX96After:", sqrtPriceX96After);

    // Check that the quote is not zero and within reasonable bounds
    assertTrue(amount0Delta != 0 || amount1Delta != 0, "Quote should not be zero");
    assertTrue(sqrtPriceX96After != 0, "SqrtPriceX96After should not be zero");
    assertTrue(amount0Delta > -1e27 && amount0Delta < 1e27, "amount0Delta out of reasonable bounds");
    assertTrue(amount1Delta > -1e27 && amount1Delta < 1e27, "amount1Delta out of reasonable bounds");
}

    function testQuoteProposalWithNoLiquidity() public {
        // Remove all liquidity from the pool
        modifyLiquidityRouter.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, -10 ether, 0), bytes(""));

        // Create a proposal
        uint256 proposalAmount = 1 ether;
        uint256 proposalDuration = TWAMM(twamm).expirationInterval();
        vm.prank(alice);
        governance.createProposal(proposalAmount, proposalDuration, true, "Test proposal");
        uint256 proposalId = governance.proposalCount() - 1;

        // Attempt to get quote for the proposal
        vm.expectRevert(); // Expect revert due to lack of liquidity
        quoter.getQuoteForProposal(proposalId);
    }

    function testQuoteMultipleProposals() public {
    // Create multiple proposals
    uint256 proposalAmount = 1 ether;
    uint256 proposalDuration = TWAMM(twamm).expirationInterval();
    vm.startPrank(alice);
    governance.createProposal(proposalAmount, proposalDuration, true, "Proposal 1");
    governance.createProposal(proposalAmount, proposalDuration, false, "Proposal 2");
    vm.stopPrank();

    uint256 proposalId1 = governance.proposalCount() - 2;
    uint256 proposalId2 = governance.proposalCount() - 1;

    // Get quotes for both proposals
    (int256 amount0Delta1, int256 amount1Delta1, uint160 sqrtPriceX96After1) = quoter.getQuoteForProposal(proposalId1);
    (int256 amount0Delta2, int256 amount1Delta2, uint160 sqrtPriceX96After2) = quoter.getQuoteForProposal(proposalId2);

    // Log the values for debugging
    console.log("Proposal 1 - amount0Delta:", amount0Delta1);
    console.log("Proposal 1 - amount1Delta:", amount1Delta1);
    console.log("Proposal 1 - sqrtPriceX96After:", sqrtPriceX96After1);
    console.log("Proposal 2 - amount0Delta:", amount0Delta2);
    console.log("Proposal 2 - amount1Delta:", amount1Delta2);
    console.log("Proposal 2 - sqrtPriceX96After:", sqrtPriceX96After2);

    // Check that the quotes are different and within reasonable bounds
    assertTrue(amount0Delta1 != amount0Delta2 || amount1Delta1 != amount1Delta2, "Quotes should be different");
    assertTrue(sqrtPriceX96After1 != sqrtPriceX96After2, "SqrtPriceX96After should be different");
    assertTrue(amount0Delta1 > -1e27 && amount0Delta1 < 1e27, "amount0Delta1 out of reasonable bounds");
    assertTrue(amount1Delta1 > -1e27 && amount1Delta1 < 1e27, "amount1Delta1 out of reasonable bounds");
    assertTrue(amount0Delta2 > -1e27 && amount0Delta2 < 1e27, "amount0Delta2 out of reasonable bounds");
    assertTrue(amount1Delta2 > -1e27 && amount1Delta2 < 1e27, "amount1Delta2 out of reasonable bounds");
    }

    function testQuoteNonExistentProposal() public {
        uint256 nonExistentProposalId = 9999;

        vm.expectRevert(); // Expect revert when quoting a non-existent proposal
        quoter.getQuoteForProposal(nonExistentProposalId);
    }
}