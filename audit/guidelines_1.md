This document is the definitive Standard Operating Procedure (SOP) for auditing smart contracts on the Sui Blockchain. It synthesizes methodologies used by top-tier firms (OtterSec, MoveBit, Zellic) and incorporates specific requirements for DeFi and GambleFi protocols.

---

# **Sui & Move Smart Contract Security Standard (SMS-2025)**

**Version:** 1.0
**Target Framework:** Sui Move
**Role:** Senior Security Researcher

## **Introduction**
Auditing on Sui requires a fundamental shift in mindset from EVM (Account-based) to **Object-based** programming. Vulnerabilities in Move rarely stem from re-entrancy; they stem from **Object Management, Capability (Access) Control, and Type Confusion.**

This SOP guides the auditor through the entire lifecycle: **Reconnaissance → Manual "Kill Chain" Analysis → Automated Verification → Reporting.**

---

## **Phase 1: Pre-Audit Architecture & Reconnaissance**
*Do not review line-by-line code yet. Map the system first.*

### **1.1 The Object Ownership Map**
Classify every struct in the codebase into one of four categories. This dictates the attack vector.
1.  **Owned Objects:** Assets owned by a user.
    *   *Risk:* Can the protocol seize them? If transferred to the contract, are they recorded correctly?
2.  **Shared Objects:** Accessible by anyone (e.g., AMM Pools, Game State).
    *   *Risk:* Congestion (DoS), Race Conditions, MEV (Sequencing).
3.  **Immutable Objects:** Configs that cannot change.
    *   *Risk:* Can the admin un-freeze them via a backdoor?
4.  **Wrapped Objects:** Objects stored inside other objects.
    *   *Risk:* "Orphaned Data." If the parent is destroyed, is the child recovered or lost?

### **1.2 The Capability (Cap) Flow**
Identify the "Keys to the Kingdom." Trace the `init` function.
*   **One-Time Witness (OTW):** Verify the `OTW` pattern is used to mint the `Publisher` or `AdminCap`.
*   **Cap Distribution:** Where does the `AdminCap` go? Is it sent to `sender`, or is it shared?

### **1.3 Centralization & Privileged Roles Matrix**
Create a table for the final report.
| Role | Capability Name | Can Upgrade? | Can Pause? | Can Seize Funds? |
| :--- | :--- | :--- | :--- | :--- |
| **Admin** | `AdminCap` | Yes | Yes | No |
| **Operator** | `OpsCap` | No | Yes | No |

*   **Red Flag:** If a single Cap can **Upgrade Code** AND **Move User Funds**, mark as **Critical Centralization Risk**.

---

## **Phase 2: The "Kill Chain" (Vulnerability Checklist)**

### **2.1 General Move & Sui Logic Vectors**

#### **A. The "Coin Smasher" Fallacy (Partial Balances)**
*   **Concept:** A user can have ten different objects representing `Coin<SUI>`.
*   **Vulnerability:** Devs often assume `input_coin` represents the user's *entire* balance.
*   **Audit Check:**
    *   Does the function accept `coin: Coin<T>`?
    *   **Exploit:** Attacker splits 1 SUI into a 0.00001 SUI object and deposits it. If the protocol rewards are constant regardless of size, the attacker drains the rewards.
    *   **Fix:** Ensure logic checks `coin::value(&coin)` or forces a `coin::join`.

#### **B. Function Visibility (Entry vs. Public)**
*   **Vulnerability:** A developer marks a sensitive helper function (e.g., `update_accounting`) as `public`.
*   **Exploit:** While users can't call it directly (if it has non-store args), a malicious *contract* can call it, bypassing checks in the main `entry` function.
*   **Fix:** Must be `public(friend)` or private if not intended for external composition.

#### **C. Object Masquerading (Type Confusion)**
*   **Vulnerability:** Passing a fake object that mimics a system object.
*   **Audit Check:** Does the function take `Clock` or `Random` as an argument?
*   **Exploit:** Attacker creates a struct named `Clock` in their own module and passes it.
*   **Fix:** Ensure arguments are fully qualified (e.g., `sui::clock::Clock`) or checked against standard addresses.

#### **D. The "Transfer to Object" Trap**
*   **Vulnerability:** Using `transfer::public_transfer` to send an object to an Object ID.
*   **Risk:** If the receiving object does not have specific logic (Dynamic Fields) to handle incoming transfers, that asset is **locked forever**.

### **2.2 DeFi Specifics (Lending, AMMs - e.g., Scallop, NAVI)**

#### **A. Flash Loan "Hot Potato" Enforcement**
*   **Pattern:** Flash loans must return a struct with **no** `store`, `drop`, or `key` abilities.
*   **Audit Check:**
    1.  Find the Receipt struct returned by `borrow`.
    2.  Check abilities. If it has `drop`, the borrower can delete the receipt and never repay. This is **Critical**.

#### **B. Oracle Manipulation & Stale Data**
*   **Audit Check:** Inspect Pyth/Switchboard integration.
*   **Rule:** There *must* be a check for `max_age` (staleness).
*   **Math:** Ensure `(Price * Amount) / Precision`. Never `(Amount / Precision) * Price`.

#### **C. Dynamic Field Orphans**
*   **Audit Check:** Look for `object::delete`.
*   **Risk:** If a parent object is deleted, are its dynamic fields explicitly removed first? If not, they become "ghosts" (unreachable but taking up storage).

### **2.3 GambleFi Specifics (e.g., Suigar, DoubleUp)**

#### **A. Pseudo-Randomness (The Validator Prediction)**
*   **Audit Check:** **GREP** for `TxContext` or `Clock` used in modulo operations (e.g., `timestamp % 100`).
*   **Exploit:** Validators or MEV bots can predict timestamps.
*   **Mandatory:** Must use `sui::random` (VRF) or Drand (w/ verifying signature).

#### **B. Shared Object Sequencing (Front-Running)**
*   **Scenario:** A global "Game State" object is Shared.
*   **Exploit:** A user sees a winning transaction in the mempool and submits a transaction to alter the state before the winner executes.
*   **Fix:** Use "Reveal-Commit" schemes or designated "Dealer" caps.

---

## **Phase 3: Automated Verification**

*Audits are incomplete without these tools.*

1.  **Sui Move Linter:**
    *   Run: `sui move test` (warnings enabled).
    *   **Catch:** "Coin field in struct" (Anti-pattern).
2.  **Move Prover (Formal Verification):**
    *   Write `spec` blocks for invariants.
    *   *Example:* `invariant balance(pool) >= sum(user_deposits);`
3.  **Fuzz Testing:**
    *   Use `#[test]` with parameters.
    *   Feed random integers into math functions to detect panics (overflow/underflow) that standard unit tests miss.

---

## **Phase 4: The Audit Report Structure**

*Deliver the report in this exact format.*

### **1. Executive Summary**
*   **Project:** [Name]
*   **Commit Hash:** [SHA-1] (Audits are immutable for this hash only).
*   **Risk Summary:** "Protocol is mathematically sound but relies heavily on a centralized Admin Key."

### **2. Findings Schema**

> **[ID-01] Critical: Unrestricted Minting via Public Init**
>
> **Description:**
> The `init_for_testing` function is `public` and lacks `#[test_only]`.
>
> **Impact:**
> Any user can reset the global state and mint a new AdminCap.
>
> **Proof of Concept (PoC):**
> ```rust
> // Provide a working Move script that exploits the bug
> public fun exploit(ctx: &mut TxContext) { ... }
> ```
>
> **Recommendation:**
> Change visibility to `#[test_only]`.
>
> **Client Status:**
> Fixed in commit `abc123`.

---

## **Phase 5: Final Sanity Check (The "Pre-Flight")**

Before sending the report, verify:
1.  **Upgrade Policy:** Is the package `Immutable`? If not, disclose that logic can change.
2.  **Events:** Are `emit` events present for all financial movements? (Low severity if missing).
3.  **Slippage:** Are slippage parameters hardcoded (Bad) or user-defined (Good)?
4.  **Denial of Service:** Are there any loops over unbound vectors (e.g., `for user in all_users`)? This will hit gas limits and lock funds.

---

**Disclaimer:** This audit validates code logic and security best practices. It does not guarantee protection against economic collapse or private key compromise.