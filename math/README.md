# DeFi Math

Side-by-side implementations of assembly-heavy DeFi math libraries.

## FullMath (Uniswap V3)

512-bit `mulDiv` — the most-used math primitive in DeFi. The Solidity version is ~100 lines of inline assembly for something Fe handles with native arithmetic.

**Solidity**: `unchecked` blocks, inline assembly for `mul`, `mulmod`, `div`, `sub`, `lt`, `gt` — because Solidity can't express 256-bit wrapping arithmetic safely without it.

**Fe**: Same algorithm, plain arithmetic. Fe's u256 ops compile directly to EVM opcodes (ADD, MUL, SUB wrap natively). `mulmod` available via `std::evm::ops`.

### Source
- Solidity reference: `bench/src/SolidityFullMath.sol` (adapted from [Uniswap V3](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol))
- Fe implementation: `fe/src/full_math.fe`

### Running
```bash
cd bench
FE_SONA_OPT_LEVEL=2 forge test --ffi --offline -vvv
```
