// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDAOToken is ERC20 {
    constructor() ERC20("Mock DAO Token", "MDT") {
        _mint(msg.sender, 1000000e18); // Mint 1 million tokens
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
