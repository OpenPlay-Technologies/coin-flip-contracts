# Game Whitelisting Checklist: Coin Flip

---

## Overview

| **Attribute** | **Details** |
|---------------|-------------|
| **Game Name** | Coin Flip |
| **Package** | coin_flip |
| **Package Version** | 3 |
| **Verification Date** | January 1, 2026 |
| **Verifier** | Automated Security Analysis (Claude Opus 4.5) |
| **Verification Standard** | OpenPlay Game Whitelisting Guide v3.1 |
| **Related Audit** | [SECURITY_AUDIT_REPORT_OPUS4.5.md](./SECURITY_AUDIT_REPORT_OPUS4.5.md) |

### Summary

| Category | Status | Notes |
|----------|--------|-------|
| 🔒 **Mandatory Checks (1-7)** | ✅ All Passed | All mandatory security checks pass |
| 📋 **Additional Checks (8-16)** | ✅ Most Pass | Some require operational verification |
| 🎯 **Overall Verdict** | ✅ **SAFE TO WHITELIST** | Pending on-chain verification |

---

## Table of Contents

1. [Mandatory Checks](#mandatory-checks)
   - [1. Package Immutability](#1-package-immutability-)
   - [2. Game Logic Verification](#2-game-logic-verification-)
   - [3. Sufficient Funds Check](#3-sufficient-funds-check-)
   - [4. Immutable Parameter Store](#4-immutable-parameter-store-)
   - [5. Admin Cap Restrictions](#5-admin-cap-restrictions-)
   - [6. Resource Attack Prevention](#6-resource-attack-prevention-)
   - [7. Atomic Transaction Flow](#7-atomic-transaction-flow--free-roll-protection-)
2. [Additional Security Recommendations](#additional-security-recommendations)
3. [Final Whitelisting Checklist](#final-whitelisting-checklist)
4. [Verification Evidence](#verification-evidence)

---

## Mandatory Checks

### 1. Package Immutability ✅

**Requirement**: The game package must be **immutable** (not upgradeable).

**Status**: ✅ **PASS** (via deployment script analysis)

**Evidence**:

The deployment script (`scripts/deploy-package.sh`) explicitly makes the package immutable:

```bash
# Lines 231-240: Make package immutable by destroying upgrade capability
print_status "Making package immutable by destroying upgrade capability..."
IMMUTABLE_OUTPUT=$(sui client call \
    --package 0x2 \
    --module 'package' \
    --function 'make_immutable' \
    --args "$COIN_FLIP_UPGRADE_CAP" \
    --json)
```

**Verification Checklist**:
- [x] Deployment script calls `sui::package::make_immutable`
- [x] Upgrade capability is destroyed during deployment
- [x] Script saves `IMMUTABLE_TX_DIGEST` for verification
- [ ] **On-chain verification required**: Verify package is immutable on Sui explorer using the package ID

**Notes**: Final on-chain verification should be performed by house operator before whitelisting.

---

### 2. Game Logic Verification ✅

**Requirement**: The game logic must correctly implement the stated game rules.

**Status**: ✅ **PASS**

**Game Rules Analysis**:

| Rule | Implementation | Status |
|------|----------------|--------|
| **50/50 coin flip** | Head or Tail outcome with house edge | ✅ |
| **House edge** | Applied via `house_edge_bps` parameter | ✅ |
| **Payout calculation** | `stake * payout_factor` (typically 2x) | ✅ |
| **Win condition** | `prediction == result` | ✅ |

**Randomness**:
- [x] Uses `sui::random::Random` (VRF) - cryptographically secure
- [x] No timestamp-based randomness
- [x] No predictable seed values

```move
// game.move:117 - Correct VRF usage
let mut random_generator = random.new_generator(ctx);

// game.move:204 - Random outcome generation
let x = rand.generate_u64_in_range(0, 10_000);
```

**Win Calculation**:
```move
// game.move:216-218 - Correct win calculation
payout = int_mul(stake, payout_factor);  // stake * 2x (typically)
interaction.transactions.push_back(win_checked(payout));
```

**Bet Validation**:
```move
// game.move:252-257 - Proper validation
assert!(stake >= self.min_stake(param_store), EUnsupportedStake);
assert!(stake <= self.max_stake(param_store), EUnsupportedStake);
assert!(prediction == head_result() || prediction == tail_result(), EUnsupportedPrediction);
```

**Verification Checklist**:
- [x] Randomness uses Sui VRF (`sui::random`)
- [x] No hardcoded outcomes
- [x] No predictable randomness patterns
- [x] Win calculations are mathematically correct
- [x] House edge correctly applied
- [x] Bet amount validation implemented
- [x] Prediction validation implemented
- [x] No admin functions that can manipulate outcomes

---

### 3. Sufficient Funds Check ✅

**Requirement**: Games must check house has sufficient funds **BEFORE** using RNG.

**Status**: ✅ **PASS**

**Evidence** - Correct order in `interact` function:

```move
// game.move:103-118 - CORRECT ORDER

// STEP 1: Get payout factor (line 107)
let payout_factor = self.payout_factor(param_store);

// STEP 2: Check sufficient funds BEFORE RNG (line 108)
house.ensure_sufficient_funds(registry, max_payout(payout_factor, stake), ctx);

// ... interaction setup ...

// STEP 3: Generate random AFTER funds check (line 117)
let mut random_generator = random.new_generator(ctx);
```

**Flow Diagram**:
```
1. ✅ Validate bet amount
2. ✅ Calculate max payout: stake * payout_factor
3. ✅ Check house.ensure_sufficient_funds(max_payout) 
4. ✅ Generate random outcome (RNG)
5. ✅ Calculate actual win
6. ✅ Submit transactions
```

**Verification Checklist**:
- [x] `ensure_sufficient_funds` called before RNG
- [x] Max payout calculated correctly (`stake * payout_factor`)
- [x] Uses `house.ensure_sufficient_funds()` from OpenPlay Core
- [x] Funds check uses actual max payout (not just stake)

---

### 4. Immutable Parameter Store ✅

**Requirement**: All game parameters must be in an immutable `ParameterStore` with proper validation.

**Status**: ✅ **PASS**

**Implementation Analysis**:

**4.1 Uses OpenPlay Core ParameterStore**:
```move
// game.move:19
use openplay_core::parameter_store::{Self, ParameterStore};
```

**4.2 Stores param_store_id in Game struct**:
```move
// game.move:41-45
public struct Game has key {
    id: UID,
    param_store_id: ID,  // ✅ Stored for validation
    contexts: Table<ID, CoinFlipContext>,
}
```

**4.3 Has assertion function**:
```move
// game.move:296-299
public fun assert_param_store(self: &Game, param_store: &ParameterStore) {
    let param_store_id = self.param_store_id;
    assert!(param_store_id == param_store.id(), EInvalidParamStore);
}
```

**4.4 All parameter reads call assertion**:
```move
// game.move:270-289 - All functions call assert_param_store first
public fun payout_factor(self: &Game, param_store: &ParameterStore): UQ32_32 {
    self.assert_param_store(param_store);  // ✅ Validation
    *param_store.borrow<String, u64>(payout_factor_bps_param_name())
    // ...
}

public fun house_edge_bps(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);  // ✅ Validation
    *param_store.borrow<String, u64>(house_edge_bps_param_name())
}

public fun min_stake(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);  // ✅ Validation
    *param_store.borrow<String, u64>(min_stake_param_name())
}

public fun max_stake(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);  // ✅ Validation
    *param_store.borrow<String, u64>(max_stake_param_name())
}
```

**4.5 All parameters in ParameterStore (none hardcoded)**:

| Parameter | In ParameterStore | Location |
|-----------|-------------------|----------|
| `min_stake` | ✅ | game.move:164 |
| `max_stake` | ✅ | game.move:165 |
| `house_edge_bps` | ✅ | game.move:166 |
| `payout_factor_bps` | ✅ | game.move:167 |

**4.6 ParameterStore frozen during deployment**:
```bash
# scripts/create-game.sh:347 - Freezes ParameterStore
--move-call $CORE_PACKAGE_ID::parameter_store::freeze_ createGameOutput.1 \
```

**Verification Checklist**:
- [x] Uses `openplay_core::parameter_store::ParameterStore`
- [x] Stores `param_store_id` in Game struct
- [x] Has `assert_param_store()` validation function
- [x] All parameter read functions call assertion before reading
- [x] ALL outcome-affecting parameters in ParameterStore (none hardcoded)
- [x] Deployment script freezes ParameterStore
- [x] No parameters stored in mutable fields
- [x] No admin functions that can modify parameters

---

### 5. Admin Cap Restrictions ✅

**Requirement**: Admin capabilities must NOT have powers to change game logic or outcomes.

**Status**: ✅ **PASS**

**CoinFlipCap Analysis**:

```move
// game.move:46-48
public struct CoinFlipCap has key, store {
    id: UID,
}
```

**Functions Requiring CoinFlipCap**:

| Function | Purpose | Can Change Outcomes? |
|----------|---------|---------------------|
| `admin_create` | Create new game instance | ❌ No |

```move
// game.move:147-179 - Only admin function
public fun admin_create(
    _cap: &CoinFlipCap,  // Only used for authorization
    registry: &mut Registry,
    min_stake: u64,
    max_stake: u64,
    house_edge_bps: u64,
    payout_factor_bps: u64,
    ctx: &mut TxContext,
): (Game, ParameterStore, GameStatistics) {
    // Creates new game - cannot modify existing games
}
```

**Verification Checklist**:
- [x] Admin cap only allows game creation
- [x] No admin functions to change game outcomes
- [x] No admin functions to modify parameters (ParameterStore is frozen)
- [x] No admin functions to bypass bet validation
- [x] No admin functions to manipulate randomness
- [x] No admin functions to submit transactions directly
- [x] Admin cap cannot change house edge or payouts post-creation

---

### 6. Resource Attack Prevention ✅

**Requirement**: Win path must consume MORE gas than lose path.

**Status**: ✅ **PASS**

**Transaction Analysis**:

```move
// game.move:198-221

match (interaction.interact_type) {
    InteractionType::PLACE_BET { stake, prediction } => {
        // ALWAYS: Place bet transaction
        interaction.transactions.push_back(bet_checked(stake));  // 1 transaction
        context.bet(stake, prediction);
        
        // Generate result
        let x = rand.generate_u64_in_range(0, 10_000);
        // ... outcome determination ...
        
        if (prediction == result) {
            // WIN PATH: Additional win transaction
            payout = int_mul(stake, payout_factor);
            interaction.transactions.push_back(win_checked(payout));  // +1 transaction
            context.settle_win(result, payout);
        } else {
            // LOSE PATH: No additional transactions
            context.settle_loss(result);
        };
    },
};
```

**Gas Comparison**:

| Path | Transactions | Operations | Gas Cost |
|------|-------------|------------|----------|
| **Win** | `bet` + `win` | 2 transactions + settle_win | **Higher** ✅ |
| **Lose** | `bet` only | 1 transaction + settle_loss | Lower |

**Verification Checklist**:
- [x] Win path includes both `bet` and `win` transactions (more gas)
- [x] Lose path only includes `bet` transaction (less gas)
- [x] No expensive computations only in lose path
- [x] Win path creates more operations than lose path
- [x] State updates (context) are comparable between paths

**Additional Resources**:
- [x] Objects created: Same for both paths (context update only)
- [x] Events emitted: Same for both paths (`InteractedWithGame`)
- [x] UIDs: No new UIDs in either path

---

### 7. Atomic Transaction Flow ("Free Roll" Protection) ✅

**Requirement**: Funds must be locked in the same transaction as outcome generation.

**Status**: ✅ **PASS**

**Flow Analysis**:

The entire game flow happens in a single entry function:

```move
// game.move:89-139 - Single atomic entry function
entry fun interact(
    self: &mut Game,
    registry: &Registry,
    param_store: &ParameterStore,
    game_stats: &mut GameStatistics,
    balance_manager: &mut BalanceManager,  // Funds locked here
    house: &mut House,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    prediction: String,
    random: &Random,
    ctx: &mut TxContext,
) {
    // All of these happen atomically in ONE transaction:
    // 1. Borrow tx cap
    // 2. Check sufficient funds
    // 3. Generate random outcome
    // 4. Calculate win/loss
    // 5. Process transactions (bet + optional win)
    // 6. Emit event
}
```

**Atomic Execution Proof**:

1. **Single PTB**: All operations in one Programmable Transaction Block
2. **Immediate Settlement**: `house.tx_admin_process_transactions_v2()` settles immediately
3. **No Async State**: No pending game state between transactions
4. **Fund Locking**: BalanceManager funds consumed in same tx as outcome

**Verification Checklist**:
- [x] Bet transaction submitted in same PTB as RNG/outcome
- [x] No multi-step game flow requiring separate transactions
- [x] Funds processed immediately (no escrow needed for single-step game)
- [x] User cannot withdraw funds while game is "in progress"
- [x] No off-chain state that could be exploited

---

## Additional Security Recommendations

### 8. Maximum Payout Limits ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Maximum payout defined | ✅ | `max_stake * payout_factor` |
| Payout limits enforced | ✅ | `house.ensure_sufficient_funds()` |
| Limits in ParameterStore | ✅ | `max_stake`, `payout_factor_bps` |

### 9. Reentrancy Protection ✅

| Check | Status | Evidence |
|-------|--------|----------|
| No external calls re-entering | ✅ | Sui's transaction model prevents |
| Proper state management | ✅ | State updated atomically |
| Uses Sui's transaction model | ✅ | Single entry function |

### 10. Event Emission ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Events for all actions | ✅ | `InteractedWithGame` event |
| Events include amounts | ✅ | `old_balance`, `new_balance` |
| Events include outcomes | ✅ | `context` (includes result) |
| Events include player | ✅ | `balance_manager_id` |

```move
// game.move:134-139
emit(InteractedWithGame {
    old_balance,
    new_balance,
    context: *self.get_context(balance_manager),
    balance_manager_id: balance_manager.id(),
})
```

### 11. Error Handling ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Proper error codes | ✅ | 7 distinct error codes |
| Clear error semantics | ✅ | Descriptive constant names |
| No inconsistent states | ✅ | Atomic transactions |

```move
// game.move:30-36 - Error codes
const EUnsupportedHouseEdge: u64 = 1;
const EUnsupportedPayoutFactor: u64 = 2;
const EUnsupportedStake: u64 = 3;
const EUnsupportedPrediction: u64 = 4;
const EUnsupportedAction: u64 = 5;
const EInvalidParamStore: u64 = 9;
const EMinStakeBelowMinTransaction: u64 = 10;
```

### 12. Gas Efficiency ✅

| Check | Status | Evidence |
|-------|--------|----------|
| No unbounded loops | ✅ | Single-step game |
| Efficient data structures | ✅ | Table for contexts |
| Minimal on-chain storage | ✅ | Only necessary state |

### 13. Code Auditing ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Security audit completed | ✅ | [SECURITY_AUDIT_REPORT_OPUS4.5.md](./SECURITY_AUDIT_REPORT_OPUS4.5.md) |
| Critical issues resolved | ✅ | M-02 fixed, M-01 mitigated by design |
| Test coverage | ✅ | 12/12 tests passing |

### 14. Testing and Simulation ✅

| Check | Status | Evidence |
|-------|--------|----------|
| Unit tests | ✅ | 12 tests in test suite |
| Win flow tested | ✅ | `success_win_flow`, `success_flow_win` |
| Lose flow tested | ✅ | `success_lose_flow`, `success_flow_lose` |
| House bias tested | ✅ | `success_house_bias_flow` |
| Edge cases tested | ✅ | Invalid state transitions, predictions |
| Validation tested | ✅ | `fail_min_stake_below_min_transaction_amount` |

### 15. Reputation and Track Record ⚠️

| Check | Status | Notes |
|-------|--------|-------|
| Developer history | ⚠️ | Requires manual verification |
| Game performance | ⚠️ | New game - no track record |
| Community feedback | ⚠️ | Requires manual verification |

### 16. Rate Limiting and Circuit Breakers ⚠️

| Check | Status | Notes |
|-------|--------|-------|
| Max transactions per epoch | ⚠️ | Handled at house level |
| Automatic pausing | ⚠️ | Via registry version control |
| Monitoring systems | ⚠️ | Requires operational setup |

---

## Final Whitelisting Checklist

### Package Verification

- [x] Package is immutable (deployment script destroys upgrade cap)
- [x] Package ID can be verified on-chain
- [ ] **Manual**: Verify package immutability on Sui explorer before whitelisting

### Game Logic Verification

- [x] Game logic correctly implements stated rules (50/50 coin flip with house edge)
- [x] House edge is correctly calculated and applied
- [x] Randomness uses Sui's on-chain VRF (`sui::random`)
- [x] No hardcoded outcomes or predictable randomness
- [x] Win calculations are mathematically correct
- [x] Bet validation is properly implemented

### Funds and Safety Checks

- [x] Sufficient funds check happens **BEFORE** RNG
- [x] Maximum payout is enforced
- [x] Payout limits are reasonable (configurable via ParameterStore)
- [x] Games handle insufficient funds gracefully (house assertion)

### Parameter Store

- [x] Game uses `openplay_core::parameter_store::ParameterStore`
- [x] Game stores `param_store_id` in its main struct
- [x] Game has assertion function validating `param_store.id() == self.param_store_id`
- [x] All parameter read functions call the assertion before reading
- [x] ALL parameters affecting outcomes/rules are in ParameterStore (none hardcoded)
- [x] Parameters are read from ParameterStore (not hardcoded)
- [x] No parameters stored in mutable fields
- [x] Deployment script freezes ParameterStore

### Admin Capabilities

- [x] Admin caps have no power to change game logic
- [x] Admin caps cannot modify parameters (ParameterStore is frozen)
- [x] Admin caps cannot manipulate outcomes
- [x] Admin caps cannot bypass validation

### Resource Attack Prevention

- [x] Win path consumes more gas than lose path
- [x] Win transactions include both bet and win (more operations)
- [x] Lose transactions only include bet (fewer operations)
- [x] No expensive computations only in lose path
- [x] Other resources (objects, events, UIDs) are balanced or favor win path

### Atomic Transaction Flow

- [x] All game logic in single atomic entry function
- [x] Funds processed in same transaction as outcome
- [x] No multi-step flows that could be exploited
- [x] "Free roll" attack not possible

### Additional Security

- [x] Transaction validation is proper
- [x] Reentrancy protection via Sui's model
- [x] Events are emitted for transparency
- [x] Error handling is robust
- [x] Code is gas-efficient
- [x] Security audit completed
- [x] Extensive testing performed
- [ ] **Manual**: Verify developer reputation
- [ ] **Manual**: Set up monitoring systems

---

## Verification Evidence

### Files Reviewed

| File | Lines | Description |
|------|-------|-------------|
| `package/sources/game.move` | 306 | Main game logic |
| `package/sources/context.move` | 127 | Game context state machine |
| `package/sources/constants.move` | 66 | Game constants |
| `package/tests/*.move` | ~250 | Test coverage |
| `scripts/deploy-package.sh` | 296 | Deployment (immutability) |
| `scripts/create-game.sh` | 432 | Game creation (freeze) |

### Test Results

```
Test result: OK. Total tests: 12; passed: 12; failed: 0
```

### Security Audit

See: [SECURITY_AUDIT_REPORT_OPUS4.5.md](./SECURITY_AUDIT_REPORT_OPUS4.5.md)

- Critical Issues: 0
- High Issues: 0
- Medium Issues: 2 (1 Mitigated by Design, 1 Fixed)
- Low Issues: 3 (1 Non-Issue)
- Overall Risk: **LOW**

---

## Conclusion

### Verdict: ✅ **SAFE TO WHITELIST**

The Coin Flip game passes all mandatory security checks required for whitelisting on OpenPlay houses.

**Before Whitelisting**:
1. ✅ Verify package is immutable on Sui explorer
2. ✅ Verify game instance ID matches verified code
3. ✅ Verify ParameterStore ID is frozen
4. ✅ Assign appropriate fee collector

**Whitelisting Command**:
```move
house.admin_add_tx_allowed_with_collector(game_id, fee_collector)
```

---

**Report Generated**: January 1, 2026
**Verification Standard**: OpenPlay Game Whitelisting Guide v3.1

---

*End of Checklist*

