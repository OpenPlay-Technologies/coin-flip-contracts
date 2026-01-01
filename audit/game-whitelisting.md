# Game Whitelisting Guide

## Overview

Game whitelisting is a critical security process that ensures only safe, verified games can process transactions on OpenPlay houses. This document outlines the verification requirements and best practices for house operators when whitelisting games.

**Key Principle**: A game should only be whitelisted after thorough off-chain verification confirms it is safe to use. Once whitelisted, a game instance can submit transactions to the house, so verification is essential to protect house funds and stakers.

## Whitelisting Process

### Current Implementation (v3.1)

In OpenPlay v3.1, game whitelisting is combined with fee collector assignment:

1. **Fee Collector Creation**: House admin creates a fee collector via `house.admin_create_fee_collector()`
2. **Game Package Deployment**: Developer deploys a game package to Sui (must be immutable)
3. **Game Instance Creation**: Developer creates a game instance with specific parameters
4. **Off-Chain Verification**: House operator verifies the game meets all security requirements
5. **Whitelisting with Fee Collector**: House operator calls `house.admin_add_tx_allowed_with_collector(game_id, fee_collector)` to whitelist the instance AND assign it to a fee collector

**Important**: 
- Whitelisting is done per **game instance** (identified by `game_id`), not per package
- Each game MUST be assigned to a fee collector when whitelisted
- Multiple games can share the same fee collector
- Fees are calculated from GGR (Gross Gaming Revenue) at epoch end, not per-transaction

### Future Standard Procedure

A standardized verification procedure will be developed to ensure consistent security across all houses. This document outlines the current requirements and will be updated as the standard procedure is formalized.

## Mandatory Security Checks

The following checks are **mandatory** before whitelisting any game:

### 1. Package Immutability ✅

**Requirement**: The game package must be **immutable** (not upgradeable).

**Why**: If a package is upgradeable, a malicious developer could upgrade it after whitelisting to change game logic and submit fraudulent transactions.

**How to Verify**:
- Check the package's `Move.toml` - it should NOT have an upgrade policy or upgrade capability
- Verify on-chain that the package is immutable using Sui explorer
- Confirm the package ID matches the one you're verifying

**Risk if Skipped**: Game logic could be changed post-whitelisting, allowing fraudulent transactions that drain house funds.

### 2. Game Logic Verification ✅

**Requirement**: The game logic must be verified to correctly implement the stated game rules.

**Why**: Incorrect or malicious game logic could allow games to:
- Submit invalid transactions (e.g., wins without bets)
- Manipulate outcomes
- Bypass house edge calculations
- Drain house funds

**How to Verify**:
- **Code Review**: Thoroughly review the game's Move source code
- **Logic Verification**: Verify that:
  - Bets are properly validated (amount, limits, etc.)
  - Wins are calculated correctly based on game rules
  - House edge is correctly applied
  - Random number generation uses Sui's on-chain randomness (VRF)
  - No backdoors or admin functions that can manipulate outcomes
- **Test Coverage**: Review test cases to ensure edge cases are covered
- **Mathematical Verification**: For games with probabilities, verify the math matches stated odds

**What to Look For**:
- ✅ Proper use of `sui::random` for randomness
- ✅ Transaction validation (bet amounts, limits)
- ✅ Correct win calculations
- ✅ No admin functions that can change game outcomes
- ✅ Proper error handling
- ❌ Hardcoded outcomes or predictable randomness
- ❌ Admin functions that can manipulate results
- ❌ Missing validation on bet amounts or limits

**Risk if Skipped**: Games could submit fraudulent transactions, manipulate outcomes, or drain house funds.

### 3. Sufficient Funds Check ✅

**Requirement**: Games must check that the house has sufficient funds to payout the maximum possible win **before** using randomness (RNG).

**Why**: If RNG is used before checking funds, a game could:
- Generate a winning outcome
- Discover the house can't pay
- Still submit the win transaction, causing the house to fail or go bankrupt

**How to Verify**:
- Review game code to ensure the flow is:
  1. Validate bet amount
  2. **Check house has sufficient funds for max payout**
  3. Generate random outcome (RNG)
  4. Calculate win amount
  5. Submit transactions
- Verify the check uses `house.ensure_sufficient_funds()` or `house.house_balance()` to verify available funds
- Ensure the check happens before any randomness is generated

**Example Correct Flow**:
```move
// 1. Validate bet
assert!(bet_amount >= min_bet && bet_amount <= max_bet, EInvalidBet);

// 2. Check sufficient funds BEFORE RNG
let max_payout = calculate_max_payout(bet_amount);
house.ensure_sufficient_funds(max_payout);  // Uses house_balance

// 3. Generate random outcome
let random_value = sui::random::random(ctx);
let outcome = determine_outcome(random_value, bet_amount);

// 4. Calculate win
let win_amount = calculate_win(outcome, bet_amount);

// 5. Submit transactions
house.tx_admin_process_transactions_v2(...);
```

**Risk if Skipped**: House could be forced into bankruptcy by games submitting wins when insufficient funds exist.

### 4. Immutable Parameter Store ✅

**Requirement**: All game-specific parameters that affect outcomes or rules must be stored in an **immutable ParameterStore** from OpenPlay Core, and the game must assert that the correct ParameterStore is being used.

**Why**: If parameters can be changed after whitelisting, a malicious developer could:
- Increase max bet to drain house funds
- Change house edge to favor players
- Modify limits to bypass safety checks
- Swap ParameterStore objects to use different parameters

**How to Verify**:
- Confirm the game uses `openplay_core::parameter_store::ParameterStore`
- **ParameterStore is guaranteed frozen**: Since ParameterStore is from OpenPlay Core and must be shared to be used, it is automatically frozen (immutable) - this is enforced by Sui's object model
- Check that **ALL** game-specific parameters affecting outcomes or rules are stored in the ParameterStore:
  - Minimum bet amount
  - Maximum bet amount
  - Maximum payout/win amount
  - House edge percentage
  - Success rates / probabilities
  - Payout factors / multipliers
  - Step limits or game progression rules
  - Any other parameters that affect game outcomes or rules
- Verify the game stores the `param_store_id` in its struct (e.g., `Game.param_store_id`)
- **Critical**: Verify the game has an assertion function (e.g., `assert_param_store()`) that checks `param_store.id() == self.param_store_id` before reading any parameters
- Confirm all parameter reads go through functions that call this assertion
- Verify parameters are read from the ParameterStore, not hardcoded

**What to Check**:
- ✅ Game uses `openplay_core::parameter_store::ParameterStore`
- ✅ Game stores `param_store_id` in its main struct
- ✅ Game has an assertion function that validates `param_store.id() == self.param_store_id`
- ✅ All parameter read functions call this assertion before reading
- ✅ ALL parameters affecting outcomes/rules are in ParameterStore (none hardcoded)
- ✅ ParameterStore is created and frozen during game initialization
- ❌ Parameters stored in mutable fields
- ❌ Parameters that can be changed via admin functions
- ❌ Missing param_store_id validation
- ❌ Hardcoded parameters that should be in ParameterStore

**Example Correct Implementation**:
```move
public struct Game has key {
    id: UID,
    param_store_id: ID,  // Store the ID
    // ... other fields
}

fun assert_param_store(self: &Game, param_store: &ParameterStore) {
    assert!(self.param_store_id == param_store.id(), EInvalidParamStore);
}

public fun min_stake(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);  // Assert before reading
    *param_store.borrow<String, u64>(min_stake_param_name())
}
```

**Risk if Skipped**: Game parameters could be changed post-whitelisting, or a different ParameterStore could be passed to manipulate outcomes, allowing manipulation of bet limits, payouts, or house edge.

### 5. Admin Cap Restrictions ✅

**Requirement**: Any admin capabilities in the game must **not** have powers that can change game logic, outcomes, or critical parameters.

**Why**: Admin capabilities with too much power could allow:
- Manipulation of game outcomes
- Changing of parameters
- Bypassing of safety checks
- Fraudulent transaction submission

**How to Verify**:
- Review all admin functions in the game
- Verify admin functions are limited to:
  - ✅ Fee collection (if applicable)
  - ✅ Statistics viewing
  - ✅ Non-critical configuration
- Ensure admin functions **cannot**:
  - ❌ Change game outcomes
  - ❌ Modify parameters (if ParameterStore is used)
  - ❌ Bypass bet validation
  - ❌ Manipulate randomness
  - ❌ Submit transactions directly
  - ❌ Change house edge or payout calculations

**What to Look For**:
- Admin functions should be read-only or limited to non-critical operations
- No admin functions that can influence game outcomes
- No admin functions that can modify frozen ParameterStore
- Admin caps should not grant transaction submission rights

**Risk if Skipped**: Malicious developers or compromised admin keys could manipulate games to drain house funds.

### 6. Resource Attack Prevention ✅

**Requirement**: The win path (happy path) must consume **more gas** than the lose path (unhappy path) to prevent gas-based resource attacks.

**Why**: If the lose path consumes more gas than the win path, an attacker could:
- Set a gas budget sufficient only for the win path
- Call the game function repeatedly
- If they win: transaction succeeds
- If they lose: transaction reverts (out of gas) without paying
- This effectively allows them to only accept wins, breaking the game's economics

**How OpenPlay Core Protects**: The core package already handles this by making win transactions consume more operations than bet-only transactions. When a game submits transactions:
- **Bet-only (loss)**: Single `bet()` transaction - lower gas cost
- **Bet + Win**: Both `bet()` and `win()` transactions - higher gas cost

This ensures the win path always costs more gas than the lose path.

**How to Verify**:
- Verify the game's logic flow ensures wins require more operations than losses
- Check that win transactions include both bet and win (higher gas)
- Verify that loss transactions only include bet (lower gas)
- Ensure no expensive computations happen only in the lose path
- Profile transaction gas costs to confirm win path > lose path

**What to Check**:
- ✅ Win path includes both bet and win transactions (more gas)
- ✅ Lose path only includes bet transaction (less gas)
- ✅ No expensive computations only in lose path
- ✅ Gas profiling confirms win path costs more
- ❌ Expensive operations only in lose path
- ❌ Win path is cheaper than lose path

**Example Correct Implementation**:
```move
// Win path: bet + win = more gas
if (player_wins) {
    transactions.push_back(bet(amount));
    transactions.push_back(win(payout));  // Additional transaction = more gas
} else {
    // Lose path: only bet = less gas
    transactions.push_back(bet(amount));
}
```

**Example Vulnerable Implementation**:
```move
// VULNERABLE - Do not use!
if (player_wins) {
    transactions.push_back(bet(amount));
    transactions.push_back(win(payout));
} else {
    transactions.push_back(bet(amount));
    // Expensive computation only in lose path
    expensive_computation();  // Makes lose path cost more gas!
}
```

**Additional Resource Considerations**:
Beyond gas, also verify games don't have resource attacks on:
- Number of new objects created (win vs lose)
- Number of objects used (win vs lose)
- Number of events emitted (win vs lose)
- Number of UIDs generated/deleted (win vs lose)

**Risk if Skipped**: Attackers could exploit gas budgets to only accept wins, breaking game economics and draining house funds.

## Additional Security Recommendations

Beyond the mandatory checks, consider these additional security measures:

### 7. Atomic Transaction Flow ("Free Roll" Protection) ✅

**Requirement**: Games must enforce an atomic transaction flow where funds are locked (bet placed) in the same transaction block as the game initiation or outcome generation.

**Why**: If a game allows a user to "start" a game without locking funds, the user could:
1. Start the game (e.g., deal cards off-chain)
2. See the result
3. If they lose, withdraw all funds from their `BalanceManager`
4. When the game tries to settle the loss, the transaction fails (insufficient funds)
5. The user effectively plays risk-free ("Free Roll")

**How to Verify**:
- **Atomic Execution**: Verify that the bet transaction (`house.process_transactions`) happens in the same Programmable Transaction Block (PTB) as the game logic/RNG.
- **Fund Locking**: If the game is asynchronous (e.g., requires user input), verify that funds are escrowed or locked at the start of the game, preventing withdrawal during the active game state.
- **Balance Checks**: Ensure the game checks for sufficient funds *and* consumes them (or locks them) before any outcome is revealed.

**What to Look For**:
- ✅ Bet transaction submitted in the same PTB as RNG/outcome
- ✅ Funds locked/escrowed for multi-step games
- ❌ Game reveals outcome before funds are secured
- ❌ User can withdraw funds while game is "in progress"

**Risk if Skipped**: Users can abuse the system to avoid paying for losses, bankrupting the house or playing risk-free.

### 8. Maximum Payout Limits

**Recommendation**: Verify games enforce reasonable maximum payout limits.

**Checks**:
- Maximum payout is defined and enforced
- Payout limits are reasonable relative to house size
- Limits cannot be exceeded even with edge cases
- Limits are stored in immutable ParameterStore

### 9. Reentrancy Protection

**Recommendation**: Verify games are protected against reentrancy attacks.

**Checks**:
- No external calls that could re-enter game functions
- Proper state management to prevent double-processing
- Use of Sui's transaction model (which helps prevent reentrancy)

### 10. Event Emission

**Recommendation**: Verify games emit proper events for transparency.

**Checks**:
- Games emit events for all critical actions (bets, wins, outcomes)
- Events include all relevant data (amounts, outcomes, player addresses)
- Events are emitted before state changes
- Events can be used for off-chain monitoring and auditing

### 11. Error Handling

**Recommendation**: Verify games handle errors gracefully.

**Checks**:
- Proper error codes for different failure scenarios
- Errors don't leave game in inconsistent state
- Failed transactions don't cause fund loss
- Clear error messages for debugging

### 12. Gas Efficiency

**Recommendation**: Verify games are gas-efficient to prevent DoS attacks.

**Checks**:
- No unbounded loops
- Efficient data structures
- Minimal on-chain storage
- Reasonable gas costs per transaction

### 13. Code Auditing

**Recommendation**: Have games audited by security professionals before whitelisting.

**Checks**:
- Third-party security audit report
- Review of audit findings and fixes
- Verification that critical issues are resolved
- Consider using audited game packages when available

### 14. Testing and Simulation

**Recommendation**: Test games extensively before whitelisting.

**Checks**:
- Run games in testnet environment
- Test edge cases (min bets, max bets, boundary conditions)
- Simulate high-volume scenarios
- Test failure cases (insufficient funds, invalid inputs)
- Verify mathematical correctness with simulations

### 15. Reputation and Track Record

**Recommendation**: Consider the developer's reputation and the game's track record.

**Checks**:
- Developer's history with other houses
- Game's performance on other houses (if applicable)
- Community feedback and reviews
- Any past security incidents

### 16. Rate Limiting and Circuit Breakers

**Recommendation**: Consider implementing rate limiting or circuit breakers for games.

**Checks**:
- Maximum transactions per epoch
- Maximum bet volume per game
- Automatic pausing if anomalies detected
- Monitoring and alerting systems

## Whitelisting Checklist

Use this checklist when verifying a game for whitelisting:

### Package Verification
- [ ] Package is immutable (not upgradeable)
- [ ] Package ID matches the one being verified
- [ ] Package is deployed on the correct network (mainnet/testnet)

### Game Logic Verification
- [ ] Game logic correctly implements stated rules
- [ ] House edge is correctly calculated and applied
- [ ] Randomness uses Sui's on-chain VRF
- [ ] No hardcoded outcomes or predictable randomness
- [ ] Win calculations are mathematically correct
- [ ] Bet validation is properly implemented

### Funds and Safety Checks
- [ ] Sufficient funds check happens **before** RNG
- [ ] Maximum payout is enforced
- [ ] Payout limits are reasonable for house size
- [ ] Games handle insufficient funds gracefully

### Parameter Store
- [ ] Game uses `openplay_core::parameter_store::ParameterStore`
- [ ] Game stores `param_store_id` in its main struct
- [ ] Game has assertion function validating `param_store.id() == self.param_store_id`
- [ ] All parameter read functions call the assertion before reading
- [ ] ALL parameters affecting outcomes/rules are in ParameterStore (none hardcoded)
- [ ] Parameters are read from ParameterStore (not hardcoded)
- [ ] No parameters stored in mutable fields

### Admin Capabilities
- [ ] Admin caps have no power to change game logic
- [ ] Admin caps cannot modify parameters
- [ ] Admin caps cannot manipulate outcomes
- [ ] Admin caps cannot bypass validation

### Resource Attack Prevention
- [ ] Win path consumes more gas than lose path
- [ ] Win transactions include both bet and win (more operations)
- [ ] Lose transactions only include bet (fewer operations)
- [ ] No expensive computations only in lose path
- [ ] Gas profiling confirms win path > lose path
- [ ] Other resources (objects, events, UIDs) also checked

### Additional Security
- [ ] Transaction validation is proper
- [ ] Reentrancy protection is in place
- [ ] Events are emitted for transparency
- [ ] Error handling is robust
- [ ] Code is gas-efficient
- [ ] Security audit completed (recommended)
- [ ] Extensive testing performed
- [ ] Developer reputation verified

## Whitelisting Best Practices

### For House Operators

1. **Never Whitelist Without Verification**: Always complete all mandatory checks before whitelisting
2. **Start Small**: Whitelist games with small bet limits initially, increase after monitoring
3. **Monitor Closely**: Watch game performance and transaction patterns after whitelisting
4. **Set Appropriate Fees**: Configure game fees that align with risk and value
5. **Regular Reviews**: Periodically review whitelisted games for continued safety
6. **Revoke When Needed**: Don't hesitate to revoke games that show suspicious behavior
7. **Document Decisions**: Keep records of why games were whitelisted or rejected
8. **Community Input**: Consider community feedback when evaluating games

### For Game Developers

1. **Follow Best Practices**: Implement all security requirements from the start
2. **Use ParameterStore**: Store ALL parameters affecting outcomes/rules in `openplay_core::parameter_store::ParameterStore` (guaranteed frozen when shared)
3. **Assert ParameterStore**: Always validate that the correct ParameterStore is used by asserting `param_store.id() == self.param_store_id` before reading any parameters
4. **Check Funds First**: Always verify sufficient funds before using RNG
5. **Limit Admin Powers**: Keep admin capabilities minimal and non-critical
6. **Emit Events**: Provide transparency through comprehensive event emission
7. **Get Audited**: Consider professional security audits before submission
8. **Test Thoroughly**: Extensive testing builds trust with house operators
9. **Document Your Game**: Clear documentation helps operators verify your game

## Revoking Games

If a whitelisted game shows suspicious behavior or security issues:

1. **Immediate Revocation**: Call `house.admin_revoke_tx_allowed(game_id)` to immediately stop the game and unassign its fee collector
2. **Investigation**: Investigate the issue thoroughly
3. **Communication**: Inform stakers and players if necessary
4. **Documentation**: Document the issue and resolution
5. **Prevention**: Update verification procedures to prevent similar issues

**Note**: Revoking a game stops it from processing new transactions, but does not affect:
- Existing transactions that are already processed
- Player funds (they remain in Balance Managers)
- Staker funds (they remain in the house)

## Future Standard Procedure

A standardized verification procedure will be developed to ensure consistent security across all houses. This will include:

- **Standardized Checklist**: Formal checklist with required and recommended checks
- **Verification Templates**: Templates for documenting verification results
- **Automated Tools**: Tools to help verify common security requirements
- **Certification Program**: Potential certification for verified games
- **Community Standards**: Community-agreed standards for game security

This document will be updated as the standard procedure is formalized.

## Examples

### Example 1: Coin Flip Game

**Verification Steps**:
1. ✅ Package is immutable
2. ✅ Logic: 50/50 chance, correct win calculation (bet * 2 * (1 - house_edge))
3. ✅ Funds check: Verifies `house.ensure_sufficient_funds(bet * 2)` before RNG
4. ✅ Parameters: Min bet, max bet, house edge in ParameterStore from OpenPlay Core
5. ✅ ParameterStore validation: Game asserts `param_store.id() == self.param_store_id` before reading
6. ✅ Admin cap: Only allows fee collection, no game logic changes
7. ✅ Resource attacks: Win path (bet + win) costs more gas than lose path (bet only)

**Whitelisting**: Use `house.admin_add_tx_allowed_with_collector(game_id, fee_collector)` to whitelist and assign fee collector

**Result**: ✅ Safe to whitelist

### Example 2: Dice Game (Rejected)

**Issues Found**:
1. ❌ Package is upgradeable (can be changed post-whitelisting)
2. ❌ No funds check before RNG
3. ❌ Parameters stored in mutable fields (can be changed)
4. ❌ Missing ParameterStore validation (no assertion that correct ParameterStore is used)
5. ❌ Admin cap can modify house edge
6. ❌ Resource attack: Lose path has expensive computation, making it cost more gas than win path

**Result**: ❌ **NOT SAFE** - Do not whitelist

### Example 3: Game with Incomplete ParameterStore (Rejected)

**Issues Found**:
1. ✅ Package is immutable
2. ✅ Logic is correct
3. ✅ Funds check before RNG
4. ❌ Some parameters in ParameterStore, but payout multipliers are hardcoded
5. ❌ Missing ParameterStore ID validation - could accept wrong ParameterStore

**Result**: ❌ **NOT SAFE** - All outcome-affecting parameters must be in ParameterStore, and validation must be present

## Related Documentation

- [Vision Document](./vision.md) - Overview of OpenPlay
- [Balance System](./balances.md) - Understanding house funds
- [Security Audit](./../audit/SECURITY_AUDIT_REPORT_OPUS_4.5.md) - Protocol security analysis
- [Parameter Store Module](../package/sources/parameter_store.move) - Parameter storage implementation

## Summary

Game whitelisting is a critical security process that protects house funds and stakers. Always:

- ✅ Verify package immutability
- ✅ Verify game logic correctness
- ✅ Verify sufficient funds check before RNG
- ✅ Verify ALL outcome-affecting parameters are in ParameterStore from OpenPlay Core
- ✅ Verify ParameterStore ID assertion (`param_store.id() == self.param_store_id`) is enforced
- ✅ Verify admin cap restrictions
- ✅ Verify resource attack prevention (win path costs more gas than lose path)
- ✅ Follow additional security recommendations
- ✅ Use the whitelisting checklist
- ✅ Monitor games after whitelisting
- ✅ Revoke games if issues are found

**Key Points**:
- ParameterStore from OpenPlay Core is **guaranteed frozen** when shared (enforced by Sui's object model)
- **ALL** game-specific parameters affecting outcomes or rules must be in ParameterStore
- Games **must** assert the correct ParameterStore is being used to prevent parameter swapping attacks
- **Win path must cost more gas** than lose path to prevent gas-based resource attacks (OpenPlay Core handles this via bet+win vs bet-only transactions)

**Remember**: It's better to be cautious and thorough than to risk house funds and staker trust.
