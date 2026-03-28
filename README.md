> **🔬 Experimental** — These implementations are for illustration and benchmarking purposes only. They have not been audited and should not be used in production.

# rosetta-fe

Side-by-side Solidity and Fe implementations of common Ethereum contract patterns, with gas benchmarks.

## Modules

**Cryptography**
- **poseidon** — Poseidon hash (T=3, BN254). In Solidity this is generated as raw bytecode by JavaScript. In Fe it's readable code.
- **verifier** — Groth16 (8-line verify function) and Plonk (SP1 v6) ZK proof verifiers
- **ec** — BN254 elliptic curve operations with G1Point operator overloading
- **merkle** — Merkle proof verification

**DeFi**
- **amm** — Constant-product AMM with effects-based storage access
- **erc20** — ERC-20 token showing StorageMap, tuple keys, per-arm effect declarations
- **math** — Uniswap V3 FullMath (512-bit mulDiv), Aave WadRayMath, Morpho MathLib

**Contract Patterns**
- **diamond** — Compile-time facet composition. Three facets (token/governance/admin) as `recv` blocks on one contract — no delegatecall, no storage collision, compiler-generated dispatch.
- **escrow** — Cross-contract typed calls. The Arbiter contract's capabilities are bounded by effects — it can only make calls, not access storage.

## Running

```bash
# Fe tests (27 tests across all modules)
fe test

# Foundry gas benchmarks (Fe vs Solidity, side by side)
cd bench
forge test --match-test testGas -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).
