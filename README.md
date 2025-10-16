# Superfluid Staking Contract

A smart contract system that enables token staking with streaming rewards powered by the Superfluid Protocol.

## Overview

This project implements a staking mechanism where users can:
- Stake ERC20 tokens
- Earn rewards that are distributed continuously using Superfluid streams
- Claim accumulated rewards at any time
- Unstake their tokens with full flexibility

## Key Features

- **Continuous Reward Distribution**: Utilizes Superfluid's streaming capability to distribute rewards in real-time
- **Scalable Architecture**: Uses a separate claim contract for each staker to manage rewards efficiently
- **Owner Controls**: Allows the contract owner to:
  - Supply reward tokens
  - Set distribution duration
  - Perform emergency withdrawals if needed
- **Flexible Staking**: Users can stake and unstake any amount at any time
- **Scaler**: A scaling factor is used to ensure that the flow rate per unit is always significantly larger than 1, minimizing the impact of integer division and ensuring that the accumulated remainder over a year is less than 0.001% of the total supply of the reward token. For more details, see [SCALER.md](SCALER.md).

## Technical Stack

- **Framework**: Foundry
- **Language**: Solidity ^0.8.0
- **Dependencies**:
  - OpenZeppelin Contracts (v5)
  - Superfluid Protocol
  - Forge Standard Library

## Installation

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

3. Install dependencies:
```bash
forge install
```

## Usage

### Build
```bash
forge build
```

### Test
```bash
forge test
```

## Contract Architecture

### Main Contracts

1. **SuperfluidStaking.sol**
   - Main staking contract
   - Handles stake/unstake operations
   - Manages reward distribution
   - Controls fund supply

2. **ClaimContract.sol**
   - Individual contract for each staker
   - Manages reward claims
   - Handles reward withdrawals

## Testing

The project includes comprehensive tests covering:
- Staking functionality
- Reward distribution
- Multiple staker scenarios
- Emergency procedures
- Access control

Run specific tests:
```bash
forge test --match-test testStake -vvv
```

## Security

- Access control implemented using OpenZeppelin's `Ownable`
- Emergency withdrawal function for contract owner
- Individual claim contracts to isolate user rewards
- Comprehensive require statements for input validation

## License

MIT
