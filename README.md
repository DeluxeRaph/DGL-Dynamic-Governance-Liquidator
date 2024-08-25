# DGL: Dynamic Governance Liquidator

## Introduction

DGL (Dynamic Governance Liquidator) is a tool designed for DAOs to manage their governance tokens more effectively. Built on top of the Uniswap v4 protocol, DGL leverages the Time-Weighted Average Market Maker (TWAMM) hook to allow DAOs to buy or sell their governance tokens over time, minimizing market impact and protecting against frontrunning.

## Problem

DAOs often need to buy or sell large quantities of their governance tokens to manage their treasuries. Executing large trades on-chain can significantly impact the market price and expose the transaction to frontrunning, leading to suboptimal execution and potential loss of value.

## Solution

DGL solves this problem by integrating the TWAMM hook with additional governance-related functionalities. It enables DAOs to:

- **Market Sell/Buys**: Execute large orders over time, minimizing market impact and reducing the risk of frontrunning.
- **Governance Features**: Incorporate governance-specific logic, such as weighted voting, to tailor the liquidation process according to the DAO's rules.

## Features

- **TWAMM Integration**: Utilize the TWAMM hook to split large orders into smaller, time-weighted swaps, ensuring better execution prices.
- **Governance-Specific Logic**: Implement custom governance rules that influence how and when tokens are liquidated.
- **Frontrunning Protection**: Orders executed through TWAMM are always processed as the first pool action in a block, preventing frontrunners from exploiting the transaction.

## Technical Details

DGL is built on the open-source TWAMM contract from Uniswap v4, with added governance features to suit the needs of DAOs. The core functionality relies on the following key components:

- **TWAMM Hook**: A custom hook that allows DAOs to execute large token orders over time, reducing price impact and protecting against frontrunning.
- **Governance Logic**: Smart contracts that manage the rules and processes for how governance tokens are bought or sold within the DAO.

### Contract Architecture

The contract architecture follows the standard Uniswap v4 setup, with additional layers to support DAO-specific governance features. The TWAMM orders are processed in the following steps:

1. **Order Submission**: DAOs submit an order specifying the amount of tokens to sell or buy, and the duration over which the order should be executed.
2. **TWAMM Execution**: The TWAMM hook splits the order into smaller chunks, which are executed over time, minimizing the market impact.
3. **Governance Integration**: The order execution is influenced by governance rules, ensuring that the liquidation aligns with the DAO's objectives.

## Usage

To integrate DGL into your DAO's treasury management strategy, follow these steps:

1. **Install Dependencies**: Ensure that your environment is set up with the necessary Uniswap v4 and TWAMM contracts.
2. **Deploy Contracts**: Deploy the DGL contracts, including the TWAMM hook and any governance-related smart contracts.
3. **Configure Governance Rules**: Set up the governance logic to dictate how the TWAMM orders should be managed.
4. **Submit Orders**: Use the DGL interface to submit buy or sell orders for your DAO's governance tokens.

forge build 

forge test 

## Contribution

We welcome contributions from the community to improve DGL. Please feel free to open issues or submit pull requests.

## License

DGL is licensed under the MIT License. See the LICENSE file for more details.
