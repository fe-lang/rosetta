# Evolutions

Possible directions for Fe, grounded in what we've learned from rosetta-fe. Sorted by level of involvement (least to most).

## 1. Typed Fixed-Point Arithmetic Library

`FixedPoint<D>` with Add/Sub and scale-specific mul/div.

**Works today.** Already tested: `FixedPoint<18>` with taylor expansion and ERC-4626 share math. Const-generic Add/Sub impl compiles and runs.

**What's needed:** Nothing — just packaging and documentation. Could live in core.

**Risk:** Low. Pure library work. The only question is whether `const fn` can compute `10^D` to make the impl fully generic (currently needs per-scale impl blocks for mul/div).

## 2. Transcript Type with Method Chaining

Replace raw mstore/mload buffer management in the Plonk verifier with a `Transcript` struct supporting `.write_u256(x).write_g1(p).squeeze()`.

**Works today.** Tested with SHA256 squeeze and chained challenge derivation.

**What's needed:** Refactor plonk.fe to use it. Drop-in replacement for `fs_new`/`fs_write`/`fs_squeeze`.

**Risk:** Low. Same memory layout, same algorithm. Just cleaner notation. Could improve gas slightly if the compiler optimizes Copy struct passing better than the current function-threading pattern.

## 3. G1Point Operator Traits + Const-Generic Pairing

`G1Point + G1Point` for EC add, `.scale(s)` for EC mul, `pairing_check<N>(pairs)` for N-pair pairing.

**Partially works.** G1Point with Add works at small scale. Const-generic pairing needs testing.

**What's needed:** Add `impl Add for G1Point` to ec/bn254.fe (done in sketch). Write `pairing_check<const N: usize>`. Refactor Groth16 and Plonk pairing calls.

**Risk:** Low-medium. The G1Point Add might hit the same sonatina#227 crash at scale (many EC operations in a loop). The pairing function does `N * 192` in an alloc call — needs testing whether const arithmetic in expressions works.

## 4. SHA256 in std

Wrap the SHA256 precompile (address 0x02) as `std::evm::crypto::sha256(ptr, len)`.

**Works today** (added locally, not upstreamed).

**What's needed:** PR to Fe repo adding `ingots/std/src/evm/crypto.fe`. Minimal change.

**Risk:** Very low. One function, one staticcall. The scoping question (under `std::evm`) is correct since it's EVM-specific.

## 5. Generic Merkle Verifier

`PairHasher` trait with Keccak and Poseidon impls. `verify<H: PairHasher, const DEPTH: usize>` works for any hash at any depth.

**What's needed:** Define the trait, implement for keccak (trivial), implement for Poseidon (calls poseidon::hash). Refactor merkle module.

**Risk:** Medium. The Poseidon impl would import from another ingot (cross-ingot dependency). The trait dispatch might hit sonatina#227 if the hash function is complex. Keccak-only version should work immediately.

## 6. Typed Token Amounts

`Amount<const TOKEN: usize>` prevents mixing token A and B amounts at compile time.

**Works today** in isolation. Tested.

**What's needed:** Integrate into the AMM contract. Replace `u256` reserves with `Amount<0>` and `Amount<1>`.

**Risk:** Medium. The contract's `msg` ABI encoding needs to accept/return `u256` externally while using `Amount<T>` internally. The boundary between typed internal logic and untyped ABI is where complexity lives. Might need explicit wrap/unwrap at the contract boundary.

## 7. Fp Field Type for Crypto

`Fp` with `Add`/`Mul` traits using addmod/mulmod internally. Would clean up Poseidon (eliminate `PRIME` parameter noise) and Plonk (infix notation for field math).

**Blocked by sonatina#227.** Works at small scale, crashes at Poseidon scale.

**What's needed:** Sean fixes the stack object allocation bug. Then: define Fp, implement Add/Mul, refactor Poseidon and Plonk field arithmetic.

**Risk:** Medium. Even after the crash is fixed, gas performance is unknown — the compiler needs to optimize away the wrapper overhead to match raw addmod/mulmod. If the Fp calls aren't inlined, gas regresses.

## 8. Lazy Calldata Array

`CalldataArray<const N: usize>` that reads elements from calldata on demand instead of copying the entire array to memory.

**What's needed:** Define the type with `get(index)` method. Implement `Seq` trait for `for x in` iteration. Integrate with ABI decoder (Grant's PR #1322 provides the foundation).

**Risk:** Medium-high. Requires coordination with Grant's calldata decode work. The `Seq` implementation needs to satisfy Fe's iteration contract. Gas savings are significant (~5,900 for Merkle) but only if the compiler doesn't re-materialize the array.

## 9. Byte Buffer for Precompile Inputs

A write-only buffer type for constructing inputs to SHA256, ecPairing, etc. without manual mstore offset arithmetic.

**What's needed:** Design the API (fixed-size vs growable, typed vs raw bytes). Implement using mstore internally. Replace the 40-line mstore sequences in Plonk's `hash_fr` and Groth16's pairing setup.

**Risk:** Medium-high. The API design is the hard part — too low-level and it's just mstore with extra steps, too high-level and it adds overhead. Needs to work with Fe's memory model. The `hash_fr` DST string ("BSB22-Plonk") needs byte-level writes which requires either `[u8; N]` runtime support or `String::as_bytes()` (currently missing in sonatina).

## 10. Const-Generic ZK Verifier Library

A single `verify<V: VerificationScheme, const N: usize>` that works for Groth16 and Plonk (and future schemes). Verification keys describe circuits, schemes describe math.

**What's needed:** Design the `VerificationScheme` trait abstraction. Factor out shared patterns (EC MSM, pairing, Fiat-Shamir). Parameterize by number of public inputs, number of gates, etc.

**Risk:** High. The abstraction might not fit — Groth16 and Plonk have different enough structures that a shared trait could be forced. Const-generic `[G1Point; N + 1]` for IC arrays needs const arithmetic in types (may not work yet). The payoff is real but the design work is substantial.

## 11. Const Fn Round Constant Generation

Poseidon's 400 lines of hardcoded constants derived at compile time from the field prime and security level via `const fn`.

**What's needed:** Implement the Grain LFSR in Fe's `const fn` subset. This means: const fn loops, const fn bitwise operations on u256, const fn array construction. Then `const PARAMS: PoseidonParams<3, 8, 57> = generate_params()`.

**Risk:** High. Fe's `const fn` evaluator would need to handle hundreds of iterations of complex bitwise math. May hit evaluation limits. The LFSR algorithm is fiddly to get right even in a normal language. But the result would be extraordinary — the first smart contract language where a cryptographic hash function's security parameters are compiler-verified.

## 12. Effect-Based Access Control

Contract functions require capabilities via effects: `uses (admin: AdminRole)`. The type system enforces access control.

**What's needed:** Design the capability model. How are capabilities created? How do they compose? How do they interact with the existing `Ctx` effect (which provides `caller()`)?

**Risk:** High. This is language design territory. Getting the semantics right is critical — too permissive and it's just a pattern, too restrictive and it's unusable. Interacts with the orphan rule / effects discussion. Needs careful thought about what "capability" means in a smart contract context where msg.sender is the ultimate authority.

## 13. Compile-Time Circuit Description

The polynomial evaluation phase in Plonk described as `const fn` data, evaluated generically by the verifier. New circuits = new const data, not new verifier code.

**What's needed:** Represent gate constraints as const fn data structures. Implement polynomial evaluation as a generic function parameterized by the circuit description. The circuit description would come from snark-verifier or gnark tooling.

**Risk:** Very high. This is research-grade work. The circuit description format needs to be general enough for real circuits but structured enough for the compiler to optimize. Polynomial evaluation involves variable-length sums that depend on the circuit — hard to express with fixed-size const generics. May need dependent types or more powerful const fn than Fe currently has.
