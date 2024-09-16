// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {TWAMMGovernance} from "../governance/TWAMMGovernance.sol";
import {ITWAMM} from "../interfaces/ITWAMM.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract TWAMMQuoter {
    IPoolManager public immutable poolManager;
    TWAMMGovernance public immutable governanceContract;
    ITWAMM public immutable twamm;

    // PoolKey components
    Currency public immutable currency0;
    Currency public immutable currency1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    IHooks public immutable hooks;

    uint160 constant MIN_SQRT_RATIO = 4295128739;
    uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    event QuotedSwap(uint256 indexed proposalId, int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96After);

    constructor(address _poolManager, address _governanceContract, address _twamm, PoolKey memory _poolKey) {
        poolManager = IPoolManager(_poolManager);
        governanceContract = TWAMMGovernance(_governanceContract);
        twamm = ITWAMM(_twamm);

        // Store PoolKey components
        currency0 = _poolKey.currency0;
        currency1 = _poolKey.currency1;
        fee = _poolKey.fee;
        tickSpacing = _poolKey.tickSpacing;
        hooks = _poolKey.hooks;
    }

    function getPoolKey() public view returns (PoolKey memory) {
        return PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});
    }

    function quoteProposal(uint256 proposalId)
        public
        view
        returns (int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96After)
    {
        TWAMMGovernance.Proposal memory proposal = governanceContract.getProposal(proposalId);
        require(proposal.startTime != 0, "Proposal does not exist");
        uint160 sqrtPriceLimitX96 = proposal.zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;
        PoolKey memory key = getPoolKey();
        // Call the quoteSwap function from the TWAMM contract
        return twamm.quoteSwap(key, int256(proposal.amount), proposal.zeroForOne, sqrtPriceLimitX96);
        // Remove the emit statement
    }

    function getQuoteForProposal(uint256 proposalId)
        external
        view
        returns (int256 amount0Delta, int256 amount1Delta, uint160 sqrtPriceX96After)
    {
        return quoteProposal(proposalId);
    }
}
