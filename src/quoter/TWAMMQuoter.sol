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

    PoolKey public poolKey;

    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    event QuotedSwap(uint256 indexed proposalId, int128[] deltaAmounts, uint160 sqrtPriceX96After);

    constructor(address _poolManager, address _governanceContract, address _quoter, PoolKey memory _poolKey) {
        poolManager = IPoolManager(_poolManager);
        governanceContract = TWAMMGovernance(_governanceContract);
        quoter = IQuoter(_quoter);
        poolKey = _poolKey;
    }

    function quoteProposalExactInput(uint256 proposalId) public returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        TWAMMGovernance.Proposal memory proposal = governanceContract.getProposal(proposalId);
        
        
        uint160 MAX_SLIPPAGE = proposal.zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;

        (deltaAmounts, sqrtPriceX96After,) = quoter.quoteExactInputSingle(
            IQuoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: proposal.zeroForOne,
                exactAmount: uint128(proposal.amount),
                sqrtPriceLimitX96: MAX_SLIPPAGE,
                hookData: ""
            })
        );

        emit QuotedSwap(proposalId, deltaAmounts, sqrtPriceX96After);
    }

    function quoteProposalExactOutput(uint256 proposalId) public returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        TWAMMGovernance.Proposal memory proposal = governanceContract.getProposal(proposalId);

        uint160 MAX_SLIPPAGE = proposal.zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;

        (deltaAmounts, sqrtPriceX96After,) = quoter.quoteExactOutputSingle(
            IQuoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: proposal.zeroForOne,
                exactAmount: uint128(proposal.amount),
                sqrtPriceLimitX96: MAX_SLIPPAGE,
                hookData: ""
            })
        );

        emit QuotedSwap(proposalId, deltaAmounts, sqrtPriceX96After);
    }

    function getQuoteForProposal(uint256 proposalId, bool exactInput) external returns (int128[] memory deltaAmounts, uint160 sqrtPriceX96After) {
        if (exactInput) {
            return quoteProposalExactInput(proposalId);
        } else {
            return quoteProposalExactOutput(proposalId);
        }
    }
}