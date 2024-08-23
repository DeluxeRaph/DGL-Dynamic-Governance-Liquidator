// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {TWAMM} from "../TWAMM.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract TWAMMImplementation is TWAMM {
    constructor(IPoolManager poolManager, uint256 interval, TWAMM addressToEtch) TWAMM(poolManager, interval) {
        Hooks.validateHookPermissions(addressToEtch, getHookPermissions());
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}
