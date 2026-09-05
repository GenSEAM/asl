# Gap Review: Phase 3 (asl-native-compiler-wire)

**Verdict**: `APPROVE`
**Lenses**:
1. **Completeness**: Target selection must default to Rust/Wasm when unspecified, and cleanly dispatch to `emit-c` when target is `c-embedded`.
2. **Invariants**: Diagnostic records must adhere to `ty/Diagnostic` schema.
3. **Anti-Overengineering**: Keep pipeline linear: parse -> check -> emit.
