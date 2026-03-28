> **🔬 Experimental** — These implementations are for illustration and benchmarking purposes only. They have not been audited and should not be used in production.

# rosetta-fe

Side-by-side implementations of common Ethereum contract patterns, with gas benchmarks. Each example contains `fe/` and `sol/` (or `js/`) subdirectories for comparison.

## Examples

**Cryptography**
- **poseidon** — Poseidon hash (T=3, BN254). In Solidity this is generated as raw bytecode by JavaScript. In Fe it's readable code.
- **verifier** — Groth16 (8-line verify function) and Plonk (SP1 v6) ZK proof verifiers
- **ec** — BN254 elliptic curve operations with G1Point operator overloading
- **merkle** — Merkle proof verification

**DeFi**
- **amm** — Constant-product AMM with effects-based storage access
- **erc20** — ERC-20 token showing StorageMap, tuple keys, per-arm effect declarations
- **math** — Uniswap V3 FullMath 512-bit mulDiv

**Contract Patterns**
- **diamond** — Compile-time facet composition. Three facets as `recv` blocks on one contract — no delegatecall, no storage collision, compiler-generated dispatch.
- **escrow** — Cross-contract typed calls. The Arbiter's capabilities are bounded by effects.

## Running

```bash
# Run all Fe tests
fe test

# Run gas benchmarks for a specific example
cd examples/poseidon
forge test --match-test testGas -vv
```

Requires [Fe](https://github.com/ethereum/fe) and [Foundry](https://book.getfoundry.sh/).
