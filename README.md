# DGL: Dynamic Governance Liquidator

### Authers
- Raphael Nembhard: Github - DeluxeRaph // Telegram - @VillageFarmerr
- Benjamin Scheinberg: Github - theSchein // Telegram - @schein_berg

## Introduction

DGL (Dynamic Governance Liquidator) is a comprehensive solution tailored for DAOs to manage their governance tokens more effectively and transparently. Built atop the Uniswap v4 protocol, DGL integrates the Time-Weighted Average Market Maker (**TWAMM**), allowing DAOs to dynamically buy or sell governance tokens over extended periods to minimize market impact and mitigate frontrunning risks. Furthermore, DGL embeds governance-specific logic, enabling the liquidation process to be governed by the DAO's voting and participation mechanisms.

## Problem

DAOs often face the challenge of managing large token orders for treasury rebalancing, funding, or operational liquidity. Large on-chain transactions expose these orders to significant **market impact** and **frontrunning** attacks, resulting in undesirable price slippage and inefficient token allocation. Such inefficiencies hinder the DAO's ability to manage its treasury effectively.

## Solution

DGL solves this problem by leveraging Uniswap v4's **TWAMM** technology and extending it with governance-based logic. The solution enables DAOs to:

- **Market Buys/Sells**: Execute large token orders gradually over time, reducing market impact and improving price efficiency.
- **Governance-Driven Liquidation**: Incorporate weighted governance voting mechanisms to influence when and how tokens are liquidated based on the DAO’s strategic objectives.

## Features

- **TWAMM Integration**: Splits large orders into smaller, continuous swaps over a specified time interval, smoothing out price fluctuations and protecting against frontrunning.
- **Governance-Specific Logic**: Integrates a governance voting system that determines how and when liquidations occur, adding an additional layer of control for DAOs.
- **Frontrunning Protection**: By executing TWAMM orders as the first pool action in a block, it prevents frontrunners from front-running or sandwiching the order, ensuring optimal execution for DAOs.
- **Yield and Liquidity Options**: Optionally integrate liquidity provision or yield strategies for tokens locked during governance processes.

## Technical Details

DGL is built upon Uniswap v4's **TWAMM** functionality, enhanced with governance-related smart contracts to tailor the liquidation process according to DAO-defined rules. The core components are:

- **TWAMM Hook**: A smart contract that schedules and manages time-weighted orders, allowing large trades to be executed over long intervals. This minimizes price impact and ensures better execution pricing.
- **Governance Integration**: A custom governance module that controls when and how orders are submitted based on governance vote outcomes. The voting power determines the size and nature of orders, adding decentralization to treasury management.
- **Token Wrapping for Voting**: Users lock governance tokens in the contract and receive **wrapped governance tokens**, which can be paired with other assets (such as ETH or USDC) to provide liquidity and earn yield while voting.
- **Order Execution and Settlement**: Governance orders are executed over time using TWAMM, and at the conclusion of the order, tokens are either released back to voters or sent for settlement based on the voting outcome.

### Contract Architecture

The contract architecture is composed of the following modules:

1. **TWAMMGovernance Contract**:
   - Handles the governance logic and integrates with TWAMM for long-term order execution.
   - Manages token locking, wrapped token issuance, and voting for DAO participants.
   - Supports the creation of proposals that define token orders (buy/sell) and controls the execution based on voting outcomes.

2. **TWAMM Hook**:
   - This hook connects the DGL system to Uniswap v4’s liquidity pools, allowing token swaps to occur over a defined period.
   - Orders submitted by the governance contract are split into smaller trades, distributed evenly over the duration of the proposal.

3. **WrappedGovernanceToken Contract**:
   - Manages the wrapping and unwrapping of governance tokens. Users deposit their governance tokens and receive a wrapped version, which is used in voting and liquidity provisioning.
   - This wrapped token can be paired with stable assets such as **USDC** or **ETH** to earn yield while waiting for the proposal execution.

4. **Order Execution and Liquidation**:
   - Upon successful proposal execution, the TWAMM order is created and managed by the hook, gradually executing the trade to ensure minimal price slippage.
   - Governance logic dictates when and how liquidations occur, ensuring the DAO's strategic interests are upheld.

### Process Flow

1. **Proposal Creation**:
   - DAO members submit a proposal to liquidate governance tokens (buy or sell) over a specific duration. The proposal defines the token pair (e.g., governance token/ETH), the amount, and the duration.
   
2. **Voting**:
   - DAO members lock their governance tokens, receive wrapped governance tokens, and cast votes on the proposal. Votes can be weighted based on the number of tokens staked or other DAO-defined rules.

3. **TWAMM Execution**:
   - If the proposal passes, TWAMM splits the trade into smaller time-weighted transactions, minimizing market impact. These swaps are automatically executed at regular intervals, ensuring an efficient market presence.

4. **Settlement and Yield**:
   - Once the trade completes, tokens are either distributed back to participants or used to fulfill the proposal's objective (e.g., selling for treasury management or liquidity provisioning).
   - Locked tokens may also be paired with assets like ETH or USDC in a Uniswap liquidity pool.
   - Redistribution fee of swaps to voter's

## Usage

To integrate DGL into your DAO's governance and treasury management process:

1. **Install Dependencies**:
   - Ensure Uniswap v4 and TWAMM-related contracts are available in your environment.
   - Install OpenZeppelin libraries for governance and token standards.

2. **Deploy Contracts**:
   - Deploy the `TWAMMGovernance`, `WrappedGovernanceToken`, and `TWAMM Hook` contracts.
   - Set up the token pairings (e.g., governance token/ETH) using the **Uniswap v4 PoolManager**.

3. **Configure Governance Rules**:
   - Customize governance rules (e.g., proposal threshold, voting period, participation percentage) to suit the DAO’s needs.

4. **Submit and Vote on Orders**:
   - DAO members can propose large token orders and vote using their wrapped tokens.
   - Once a proposal is approved, the TWAMM hook will execute the order over time, ensuring minimal market disruption.

## Contribution

We welcome contributions from the community to improve DGL's functionality. Whether it's proposing new features, improving efficiency, or enhancing governance integrations, we encourage you to open issues or submit pull requests.

## License

DGL is licensed under the MIT License. See the LICENSE file for more details.
