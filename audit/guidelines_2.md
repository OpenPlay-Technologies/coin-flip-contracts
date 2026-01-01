
---

# ⭐ **Sui & Move Smart Contract Security Standard (SMS-2025)**  
**Version:** 1.1  
**Author Role:** Senior Security Researcher  
**Target Framework:** Sui Move  
**Purpose:** This document serves as the definitive Standard Operating Procedure (SOP) for auditing Move contracts on the Sui blockchain. It synthesizes methodologies used by top-tier firms such as OtterSec, MoveBit, and Zellic, while adding Sui-specific kill chains, DeFi/GambleFi heuristics, and formal verification practices.

---

# **0. Introduction**

Auditing Sui requires a mental shift from EVM's account-based paradigm to **Sui’s object-based execution model**.  
Most Sui vulnerabilities arise not from reentrancy but from:

- **Object lifecycle mismanagement**  
- **Capability (Cap) misuse**  
- **Type confusion**  
- **Shared-object concurrency conflicts**  

This SOP follows the complete audit lifecycle:

**Architecture Recon → Kill-Chain Analysis → Formal Verification → Reporting → Pre-Flight Checklist**

---

# **1. Pre-Audit Architecture & Reconnaissance**  
*(Do NOT read the code line-by-line yet. Map the system first.)*

## **1.1 Object Ownership Map**

Classify **every struct** into one of these categories:

| Object Type | Description | Primary Risks |
|-------------|-------------|---------------|
| **Owned Objects** | User-owned assets (Coin<T>, NFTs) | Seizure, incorrect accounting, orphaning |
| **Shared Objects** | Global mutable state | MEV, race conditions, DoS, sequencing |
| **Immutable Objects** | Configs/params that never change | Hidden backdoors enabling mutation |
| **Wrapped Objects** | Child objects stored inside others | Orphaned data on deletion |

**Checklist:**

- [ ] Can any object be unintentionally deleted?  
- [ ] Are wrapped objects destroyed before their parent?  
- [ ] Can attackers pass forged objects of the same *type name*?  
- [ ] Are object IDs ever accepted as arguments? (Red flag)

---

## **1.2 Capability (Cap) Flow Analysis**

Capabilities are **keys to the kingdom**.

Trace their lifecycle:

1. **Creation** (via OTW pattern)  
2. **Distribution**  
3. **Use**  
4. **Revocation**  
5. **Destruction**  

**Checklist:**

- [ ] Does the package use One-Time-Witness correctly?  
- [ ] Are AdminCaps stored sensibly?  
- [ ] Can a user accidentally or intentionally obtain privileged Caps?  
- [ ] Are operator or mint capabilities revocable?  
- [ ] Are revoked caps destroyed?

---

## **1.3 Privileged Roles & Centralization Matrix**

Create a table:

| Role | Capability | Upgrade Code? | Move User Funds? | Pause System? |
|------|------------|----------------|-------------------|----------------|
| Admin | `AdminCap` | Yes | Maybe | Yes |
| Operator | `OpsCap` | No | No | Yes |

**Red Flag:**  
A single Cap that can **both upgrade code AND move user funds** → **Critical Centralization Risk**.

---

## **1.4 Object Lifecycle Audit**

For each object, trace:

- Creation → Mutation → Consumption → Deletion → Storage refund

**Checklist:**

- [ ] No recycled object IDs  
- [ ] No undeleted dynamic fields  
- [ ] Storage refunds handled correctly  
- [ ] No object lost forever due to improper transfer (Transfer-to-Object trap)

---

## **1.5 Concurrency & Parallel Execution Model**

Shared object mutation introduces **non-deterministic interleavings**.

Check:

- [ ] Is the logic safe under simultaneous writes?  
- [ ] Does sequencing of two valid transactions produce different economic outcomes?  
- [ ] Can an attacker reorder transactions to manipulate state?

---

# **2. The Kill Chain (Vulnerability Checklist)**

## **2.1 General Sui Move Vectors**

### **A. The "Coin Smasher" Fallacy (Partial Balances)**

Attack vector:

- Protocol assumes a passed-in `Coin<T>` represents the user’s total balance.
- Attacker splits coin into micro-coins.

Fix:

- Force `coin::join`  
- Check `coin::value(&coin)`  

---

### **B. Function Visibility Abuse**

Ensure:

- Sensitive functions are **NOT** marked `public`.  
- Use `public(friend)` when intended.  
- Functions that bypass entry checks cannot be called by arbitrary external packages.

---

### **C. Type Confusion & Object Masquerading**

Attack:

- Attacker creates fake `Clock` or `Random` struct in their own module.

Fix:

- Fully qualify types: `0x2::clock::Clock`  
- Enforce address checking on witness objects  

---

### **D. Transfer-to-Object Trap**

If devs use:

```move
transfer::public_transfer(obj, parent_id)
```

but parent object can't receive children → object is **locked forever**.

---

### **E. Phantom Type Misuse**

Ensure:

- Token types are not swappable due to wrong phantom types  
- Oracles match their token type parameters  
- No ability leakage through phantom type misconstraints  

---

### **F. Capability Leakage / Cloning**

Check:

- Caps stored inside shared objects (Critical)  
- Public functions returning Caps  
- Caps copied or implicitly duplicated  

---

### **G. Storage Growth DoS**

Attack vectors:

- Unbounded dynamic fields  
- Unbounded vector push  
- No deletion before dropping parent

---

## **2.2 DeFi Specific Attack Vectors**

### **A. Flash Loan “Hot Potato” Enforcement**

Receipt must have **no `drop`, `store`, or `key`** abilities.

If `drop` allowed → borrower deletes receipt → no repayment.

---

### **B. Oracle Manipulation**

Check:

- Oracle freshness (`max_age`)  
- Price math ordering: `(price * amount) / precision`  
- Avoid integer truncation exploits  
- Cross-asset pricing alignment  

---

### **C. Invariant Enforcement**

Add Move Prover invariants for:

- Constant product AMM formula  
- Liquidity share calculations  
- Interest accrual monotonicity  
- Debt never decreases without repayment  

---

### **D. Liquidation Race Conditions**

Check:

- Liquidations use **fresh oracle data**  
- Liquidation and user accounting updates are atomic  
- Attackers cannot front-run interest accrual  

---

## **2.3 GambleFi Specific Attack Vectors**

### **A. Randomness Predictability**

Reject:

- `timestamp % n`  
- `ctx.sender()`  
- `clock::now_ms()`

Require:

- `sui::random` (VRF)  
- Or decentralized randomness (Drand w/ signature verification)  

---

### **B. Randomness Scaling Bias**

Modulo operations introduce bias.

Fix:

- Use rejection sampling  
- Use VRF outputs fully  

---

### **C. Shared Object Sequencing & Front-running**

Check:

- State transitions are atomic  
- Use commit–reveal when appropriate  
- Shared pool updates cannot be manipulated via timing  

---

### **D. Replay / Double-Claim Protection**

Ensure:

- Bet receipts consumed exactly once  
- Result claims cannot be replayed  
- Shared objects do not allow multiple claims per ID  

---

# **3. Automated & Formal Verification**

## **3.1 Sui Move Linter**

Run:

```bash
sui move test
```

Catch:

- Coin fields in structs  
- Abilities misuse  
- Uninitialized fields  

---

## **3.2 Move Prover**

Always add `spec` blocks for:

- Pool solvency  
- Balance conservations  
- Flash loan repayment invariants  
- No capabilities created from thin air  
- No invariant break under mutation  

---

## **3.3 Fuzz / Property Testing**

Test:

- Math edge cases  
- Overflow/underflow  
- Extreme liquidity edge conditions  
- Race-condition edge paths  

---

## **3.4 Bytecode-Level Validation**

Verify:

- Optimizer didn't change semantics  
- Dead-store elimination didn’t break invariants  
- Abilities inferred correctly  

---

## **3.5 Transaction Replay & Differential Testing**

Simulate:

- Reordering  
- Parallel races  
- Multi-step attacks  
- Compare logical model vs on-chain execution  

---

# **4. Audit Report Format**

### **1. Executive Summary**

- Project name  
- Commit hash  
- Summary of findings  
- High-level risk assessment  

---

### **2. Findings Schema**

Each finding includes:

- **ID + Severity**  
- **Description**  
- **Impact**  
- **PoC exploit code**  
- **Recommendation**  
- **Client status**  

Example:

> **[C-01] Critical: Unrestricted AdminCap Minting**  
> Description…  
> Impact…  
> PoC…  
> Fix…  

---

# **5. Pre-Flight Final Checklist**

Before finalizing the audit:

### **Upgrade & Governance**
- [ ] Is the package Immutable?  
- [ ] If upgradeable: governance clearly defined?  

### **Events**
- [ ] Every economic action emits an event?  

### **Slippage & Fee Logic**
- [ ] User-specified slippage?  
- [ ] Fees capped and invariant-safe?  

### **DoS & Gas Limits**
- [ ] No unbounded loops over dynamic structures?  

### **Centralization Review**
- [ ] No single party holds power to rug?  
- [ ] No capabilities that combine critical privileges?  

---

# **6. Red Flags List (Must Flag as Critical)**

- Public functions accept object IDs  
- Capabilities stored inside shared objects  
- Unbounded dynamic field growth  
- Flash loan receipts with `drop`  
- Missing oracle freshness checks  
- Randomness from timestamps  
- Upgradeable package with no governance  
- Math with truncation or overflow without tests  
- Type confusion via locally defined structs mimicking system ones  

---

# **END OF DOCUMENT**

This is the **final, publish-ready, professional-grade version of SMS-2025**.

If you want, I can also produce:

✅ A markdown-formatted PDF-ready version  
✅ A shorter "auditor checklist" pocket guide  
✅ A training curriculum based on this SOP  
Just tell me what you want next.