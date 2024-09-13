// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/TWAMM.sol";
import "../src/mocks/MockDaoToken.sol";
import "../src/governance/WrappedGovernanceToken.sol";
import {TWAMMGovernance} from "../src/governance/TWAMMGovernance.sol";
import {TWAMMQuoter} from "../src/quoter/TWAMMQuoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IQuoter} from "v4-periphery/src/interfaces/IQuoter.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract TWAMMQuoterTest is Test {
    IPoolManager poolManager;
    IQuoter quoter;
    TWAMMGovernance governance;
    WrappedGovernanceToken governanceToken;
    MockDAOToken public daoToken;
    TWAMMQuoter twammQuoter;
    TWAMM flags =
        TWAMM(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)));

    PoolKey poolKey;
    uint256 initialProposalAmount = 1e18;
    bool zeroForOne = true;

    function setUp() public {
        // Deploy mock contracts
        poolManager = IPoolManager(address(new MockPoolManager()));
        quoter = IQuoter(address(new MockQuoter()));

        // Create pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(new MockERC20("Test Token 0", "T0", 18))),
            currency1: Currency.wrap(address(new MockERC20("Test Token 1", "T1", 18))),
            fee: 3000,
            tickSpacing: 60,
            hooks: flags
        });

        // Deploy governance contract
        governance = new TWAMMGovernance(
            poolManager,
            1 weeks,
            IERC20(address(daoToken)),
            poolKey.currency0,
            poolKey.currency1,
            poolKey.fee,
            poolKey.tickSpacing
        );

        // Deploy TWAMMQuoter
        twammQuoter = new TWAMMQuoter(address(poolManager), address(governance), address(quoter), poolKey);
    }

    function testCreateGovernanceProposal() public {
        
        governanceToken.mint(address(this), 200 * 10**18); // mint to meet the proposal threshold

        governance.createProposal(initialProposalAmount, 7 days, zeroForOne);

        // Check proposal created
        TWAMMGovernance.Proposal memory proposal = governance.getProposal(0);
        assertEq(proposal.amount, initialProposalAmount, "Proposal not created correctly");
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

    function createSampleProposal() internal {
        governanceToken.mint(address(this), 200 * 10**18);  // Mint governance tokens for proposal creation

        governance.createProposal(initialProposalAmount, 7 days, zeroForOne);
    }

    event QuotedSwap(uint256 indexed proposalId, int128[] deltaAmounts, uint160 sqrtPriceX96After);
}

// Mock contracts
contract MockPoolManager {
    function initialize(PoolKey memory, uint160, bytes memory) external {}
}

contract MockQuoter {
    function quoteExactInputSingle(IQuoter.QuoteExactSingleParams memory)
        external
        pure
        returns (int128[] memory, uint160, uint32)
    {
        int128[] memory deltaAmounts = new int128[](2);
        deltaAmounts[0] = -1e18;
        deltaAmounts[1] = 9e17;
        return (deltaAmounts, 1 << 96, 1);
    }

    function quoteExactOutputSingle(IQuoter.QuoteExactSingleParams memory)
        external
        pure
        returns (int128[] memory, uint160, uint32)
    {
        int128[] memory deltaAmounts = new int128[](2);
        deltaAmounts[0] = -11e17;
        deltaAmounts[1] = 1e18;
        return (deltaAmounts, 1 << 96, 1);
    }
}

contract MockERC20 {
    constructor(string memory, string memory, uint8) {}
    function mint(address, uint256) public {}
}