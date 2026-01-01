# 🪙 Coin Flip - OpenPlay Game Contract

A provably fair coin flip game built on the [Sui blockchain](https://sui.io/) using the [OpenPlay Core](https://github.com/OpenPlay-Technologies/openplay-core) framework.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](package/)
[![Tests](https://img.shields.io/badge/tests-12%2F12%20passing-brightgreen)](package/tests/)
[![Security Audit](https://img.shields.io/badge/audit-passed-brightgreen)](audit/SECURITY_AUDIT_REPORT_OPUS4.5.md)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## Overview

Coin Flip is a simple yet secure gambling game where players bet on the outcome of a virtual coin flip. The game uses Sui's native VRF (Verifiable Random Function) for cryptographically secure randomness, ensuring provably fair outcomes.

### Key Features

- 🎲 **Provably Fair** - Uses `sui::random` VRF for cryptographically secure randomness
- 🔒 **Immutable Deployment** - Package is deployed as immutable (non-upgradeable)
- ⚙️ **Configurable Parameters** - House edge, payout factor, and stake limits via ParameterStore
- 🏦 **OpenPlay Integration** - Seamless integration with OpenPlay houses for liquidity
- 📊 **Full Transparency** - Events emitted for all game actions
- ✅ **Security Audited** - Passed comprehensive security audit

---

## Game Mechanics

### How It Works

The Coin Flip game implements a simple yet provably fair gambling mechanism:

1. **Bet Placement**: A player chooses either "Head" or "Tail" and stakes a SUI amount within the configured limits (`min_stake` to `max_stake`).

2. **Randomness Generation**: The game uses Sui's native VRF (Verifiable Random Function) via `sui::random::RandomGenerator` to generate a cryptographically secure random number between 0 and 10,000. This ensures that:
   - Outcomes cannot be predicted by validators or MEV bots
   - The randomness is verifiable on-chain
   - No manipulation is possible

3. **Outcome Determination**: The random number determines the result:
   - If `random_value < house_edge_bps`: Result is "HouseBias" (house wins)
   - Else if `random_value % 2 == 0`: Result is "Head"
   - Else: Result is "Tail"

4. **Settlement**: The game immediately settles:
   - **Win**: If player's prediction matches the result, they receive `stake × payout_factor` (typically 2x their stake)
   - **Loss**: If prediction doesn't match, the stake goes to the house

### Payout Structure

| Outcome | Result | Explanation |
|---------|--------|-------------|
| **Win** | Stake × Payout Factor | Player correctly predicted Head or Tail |
| **Lose** | Stake forfeited | Player's prediction didn't match the result |
| **House Bias** | Stake forfeited | Special outcome within house edge range (house always wins) |

### Game Parameters

All game parameters are stored in an immutable `ParameterStore` from OpenPlay Core, ensuring they cannot be changed after game creation:

| Parameter | Description | Purpose |
|-----------|-------------|---------|
| `min_stake` | Minimum bet amount | Prevents dust attacks and ensures minimum transaction value |
| `max_stake` | Maximum bet amount | Limits exposure and prevents single large bets |
| `house_edge_bps` | House advantage (basis points) | Defines the percentage of outcomes where house wins (0-9,999 bps = 0-99.99%) |
| `payout_factor_bps` | Win multiplier (basis points) | Defines payout ratio (20,000 bps = 2x multiplier) |

### Security Flow

The game implements a critical security pattern to prevent house bankruptcy:

1. **Funds Verification**: Before generating randomness, the game checks that the house has sufficient funds to cover the maximum possible payout (`stake × payout_factor`)
2. **Randomness Generation**: Only after confirming sufficient funds, the random outcome is generated
3. **Transaction Submission**: The game submits transactions (`bet` and optionally `win`) to the house for settlement

This order prevents scenarios where a winning outcome is generated but the house cannot pay, which could lead to failed transactions or house bankruptcy.

---

## Architecture

The Coin Flip game is built on Sui's object-centric model and integrates with the OpenPlay Core framework for liquidity management and settlement.

### Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Coin Flip Game                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │    Game     │    │   Context   │    │   ParameterStore    │ │
│  │  (Shared)   │───▶│  (Per-User) │    │    (Immutable)      │ │
│  └──────┬──────┘    └─────────────┘    └─────────────────────┘ │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────┐                                                │
│  │ CoinFlipCap │  Admin capability for game creation            │
│  │  (Owned)    │                                                │
│  └─────────────┘                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       OpenPlay Core                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────┐  ┌────────────────┐  ┌─────────────────────────┐│
│  │   House   │  │ BalanceManager │  │        Registry         ││
│  │ (Shared)  │  │   (Shared)     │  │        (Shared)         ││
│  └───────────┘  └────────────────┘  └─────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Sui Framework                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────┐  ┌────────────────┐                              │
│  │  Random   │  │     Clock      │                              │
│  │   (VRF)   │  │                │                              │
│  └───────────┘  └────────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

#### Game (`game.move`)

The main `Game` struct is a **shared object** that manages the game state:

- **Shared Object**: Accessible by all users, enabling concurrent gameplay
- **Context Storage**: Maintains a `Table<ID, CoinFlipContext>` mapping each player's `BalanceManager` ID to their game context
- **Parameter Validation**: Stores `param_store_id` to ensure the correct immutable ParameterStore is used

The game implements a single entry function `interact()` that:
1. Validates the bet amount and prediction
2. Checks house has sufficient funds (before RNG)
3. Generates random outcome using Sui VRF
4. Calculates win/loss and creates transactions
5. Submits transactions to the house for settlement

#### Context (`context.move`)

`CoinFlipContext` implements a state machine tracking each player's game state:

- **States**: `New` → `Initialized` (bet placed) → `Settled` (outcome determined)
- **Data**: Stores stake amount, prediction, result, win amount, and current status
- **Validation**: Enforces valid state transitions (prevents double-betting, double-settling)

The state machine ensures:
- Players cannot bet twice without settling
- Outcomes cannot be settled multiple times
- Game flow follows the correct sequence

#### ParameterStore

Game parameters are stored in an immutable `ParameterStore` from OpenPlay Core:

- **Immutable**: Once frozen, parameters cannot be changed
- **Validation**: Game asserts `param_store.id() == self.param_store_id` before reading any parameter
- **Security**: Prevents parameter swapping attacks or post-deployment modifications

#### Integration with OpenPlay Core

The game integrates with three core components:

1. **House**: Manages liquidity, processes transactions, and handles fee distribution
   - Game borrows a `HouseTransactionCap` to authorize transaction submission
   - House verifies sufficient funds before allowing gameplay
   - Settlement happens atomically in the same transaction

2. **BalanceManager**: Manages player funds
   - Players deposit SUI into their BalanceManager
   - Game deducts bets and credits wins through the BalanceManager
   - Uses `PlayCap` for delegated access control

3. **Registry**: Protocol-level registry for version control
   - Ensures game package version is allowed
   - Can pause gameplay if needed (but never locks user funds)

### Transaction Flow

When a player places a bet, the following happens atomically in a single Programmable Transaction Block:

1. **Entry Point**: `game::interact()` is called with all required objects
2. **Authorization**: Game borrows `HouseTransactionCap` from the house
3. **Funds Check**: House verifies it has sufficient funds for max payout
4. **Randomness**: Sui VRF generates cryptographically secure random number
5. **Outcome**: Game determines result (Head/Tail/HouseBias)
6. **Transactions**: Game creates `bet` transaction and optionally `win` transaction
7. **Settlement**: House processes transactions, updating player balance and house vault
8. **Event**: `InteractedWithGame` event is emitted with all relevant data

This atomic flow prevents "free roll" attacks where players could withdraw funds after seeing outcomes.

---

## Project Structure

```
coin-flip-contracts/
├── package/                    # Move package
│   ├── sources/               # Source files
│   │   ├── game.move          # Main game logic and interaction handling
│   │   ├── context.move       # Game state machine and context management
│   │   └── constants.move     # Game constants (outcomes, parameters, etc.)
│   ├── tests/                 # Test files
│   │   ├── game_tests.move    # Unit tests for game logic
│   │   ├── context_tests.move # State machine transition tests
│   │   ├── e2e_tests.move     # End-to-end integration tests
│   │   └── test_utils.move    # Test helper functions
│   ├── Move.toml              # Package manifest and dependencies
│   └── Move.lock              # Dependency lock file
│
├── scripts/                   # Deployment and management scripts
│   ├── deploy-package.sh      # Publishes package and makes it immutable
│   ├── create-game.sh         # Creates game instances with parameters
│   └── claim-fees.sh          # Claims collected fees from fee collectors
│
├── outputs/                   # Deployment outputs and state
│   └── testnet/               # Testnet-specific outputs
│       ├── latest_coin_flip.env  # Latest deployment environment variables
│       └── versions.txt          # Package version history
│
├── audit/                     # Security documentation
│   ├── SECURITY_AUDIT_REPORT_OPUS4.5.md      # Comprehensive security audit
│   ├── GAME_WHITELISTING_CHECKLIST.md        # Whitelisting verification checklist
│   ├── game-whitelisting.md                  # Whitelisting guide
│   └── guidelines_*.md                       # Audit methodology guidelines
│
└── README.md                  # This file
```

### Source Files

- **`game.move`**: Contains the main `Game` struct and `interact()` entry function. Handles bet validation, randomness generation, outcome determination, and transaction creation. Also includes admin functions for game creation.

- **`context.move`**: Implements `CoinFlipContext` state machine that tracks each player's game state. Enforces valid state transitions (New → Initialized → Settled) and prevents invalid operations like double-betting.

- **`constants.move`**: Defines all game constants including outcome strings ("Head", "Tail", "HouseBias"), parameter names, and maximum allowed values for house edge and payout factors.

### Test Files

The test suite includes 12 tests covering:
- Win and lose flows
- House bias scenarios
- Invalid state transitions
- Invalid predictions and results
- Parameter validation (minimum stake enforcement)

---

## Security

### Audit Status

This project has been audited. See the full reports:

- 📋 [Security Audit Report](audit/SECURITY_AUDIT_REPORT_OPUS4.5.md)
- ✅ [Game Whitelisting Checklist](audit/GAME_WHITELISTING_CHECKLIST.md)

### Audit Summary

| Severity | Count | Status |
|----------|-------|--------|
| 🔴 Critical | 0 | - |
| 🟠 High | 0 | - |
| 🟡 Medium | 2 | All Resolved |
| 🔵 Low | 3 | 1 Non-Issue |

**Overall Risk Assessment: LOW**

### Security Features

- ✅ **Immutable Package** - Cannot be upgraded after deployment
- ✅ **VRF Randomness** - Cryptographically secure, unpredictable outcomes
- ✅ **Frozen Parameters** - Game parameters cannot be changed after creation
- ✅ **Funds Check Before RNG** - House funds verified before randomness generation
- ✅ **Atomic Transactions** - No "free roll" attacks possible
- ✅ **Gas-Safe Design** - Win path costs more gas than lose path

---

## Dependencies

| Dependency | Version | Description |
|------------|---------|-------------|
| [Sui Framework](https://github.com/MystenLabs/sui) | mainnet-v1.61.2 | Core Sui framework |
| [OpenPlay Core](https://github.com/OpenPlay-Technologies/openplay-core) | v3.1 | OpenPlay protocol core |

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Links

- 🌐 [OpenPlay Website](https://openplay.tech)
- 📦 [OpenPlay Core](https://github.com/OpenPlay-Technologies/openplay-core)
- 📚 [Sui Documentation](https://docs.sui.io)
- 💬 [Discord Community](https://discord.gg/openplay)

---

<p align="center">
  Built with ❤️ by <a href="https://openplay.tech">OpenPlay Technologies</a>
</p>

