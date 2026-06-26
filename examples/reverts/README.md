# Revert output

This example demonstrates Fe contract reverts that Foundry decodes like standard Solidity payloads:

- checked arithmetic overflow emits `Panic(0x11)`, displayed as `panic: arithmetic underflow or overflow (0x11)`
- `assert!(false)` emits `Panic(0x01)`, displayed as `panic: assertion failed (0x01)`
- `assert!(false, "boom")` emits `Error(string)`, displayed as `boom`

Run:

```bash
FE_BIN="$HOME/code/fe/master/target/release/fe" forge test -vv
```

To see Foundry's decoded failure output directly, run the opt-in display tests. These intentionally fail:

```bash
FE_BIN="$HOME/code/fe/master/target/release/fe" forge test --match-test test_display --no-match-test '^$' -vvv
```
