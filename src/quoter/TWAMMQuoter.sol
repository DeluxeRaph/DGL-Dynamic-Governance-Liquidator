// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IQuoter} from "v4-periphery/src/interfaces/IQuoter.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {TWAMMGovernance} from "../governance/TWAMMGovernance.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TWAMMQuoter {
    IQuoter public quoter;
    IPoolManager public poolManager;
    TWAMMGovernance public governanceContract;

    event QuotedSwap(uint256 indexed proposalId, int128[] deltaAmounts, uint160 sqrtPriceX96After);

    constructor(address _poolManager, address _governanceContract, address _quoter) {
        poolManager = IPoolManager(_poolManager);
        governanceContract = TWAMMGovernance(_governanceContract);
        quoter = IQuoter(_quoter);
    }

    /// @notice Quotes the exact input for a given proposal before execution
    /// @param proposalId The ID of the governance proposal
    /// @return deltaAmounts The token amounts resulting from the quote
    /// @return sqrtPriceX96After The price after the swap
    function quoteProposalExactInput(uint256 proposalId) external returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        TWAMMGovernance.Proposal memory proposal = governanceContract.proposals(proposalId);
        
        PoolKey memory key = governanceContract.getPoolKey();
        uint160 MAX_SLIPPAGE = proposal.zeroForOne ? TickMath.MIN_SQRT_RATIO : TickMath.MAX_SQRT_RATIO;
        bytes memory hookData;

        // Quote the swap based on the proposal amount (input)
        (deltaAmounts, sqrtPriceX96After,) = quoter.quoteExactInputSingle(
            IQuoter.QuoteExactSingleParams(
                key,
                proposal.zeroForOne,
                address(this),
                uint128(proposal.amount),
                MAX_SLIPPAGE,
                hookData
            )
        );

        emit QuotedSwap(proposalId, deltaAmounts, sqrtPriceX96After);
    }

    /// @notice Quotes the exact output for a given proposal before execution
    /// @param proposalId The ID of the governance proposal
    /// @return deltaAmounts The token amounts resulting from the quote
    /// @return sqrtPriceX96After The price after the swap
    function quoteProposalExactOutput(uint256 proposalId) external returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        TWAMMGovernance.Proposal memory proposal = governanceContract.proposals(proposalId);

        PoolKey memory key = governanceContract.getPoolKey();
        uint160 MAX_SLIPPAGE = proposal.zeroForOne ? TickMath.MIN_SQRT_RATIO : TickMath.MAX_SQRT_RATIO;
        bytes memory hookData;

        // Quote the swap based on the proposal amount (output)
        (deltaAmounts, sqrtPriceX96After,) = quoter.quoteExactOutputSingle(
            IQuoter.QuoteExactSingleParams(
                key,
                proposal.zeroForOne,
                address(this),
                uint128(proposal.amount),
                MAX_SLIPPAGE,
                hookData
            )
        );

        emit QuotedSwap(proposalId, deltaAmounts, sqrtPriceX96After);
    }

    /// @notice Helper function to fetch the quote and return it for evaluation.
    /// Can be called off-chain to simulate the effect of the proposal before it is executed.
    function getQuoteForProposal(uint256 proposalId, bool exactInput) external returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        if (exactInput) {
            return quoteProposalExactInput(proposalId);
        } else {
            return quoteProposalExactOutput(proposalId);
        }
    }
}
