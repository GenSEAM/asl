# Phase 1: Standalone Native AOT CLI Packager (`asl-native-standalone-cli`)

## Goal
Implement binary bundling and packaging logic in `@genseam/asl-pack` so that ASL source files can be packaged into standalone executables with the `ASLPACK!` 16-byte fixed footer and macOS ad-hoc codesign command generation.

## Work Items
1. **Packaging Manifest & Footer Formatter**:
   - Verify `pack/src/standalone.asl` calculates 16-byte fixed footer footprint (8-byte length + 8-byte magic string `ASLPACK!`).
   - Add platform detection for macOS ad-hoc AMFI code-signing (`codesign -s - --force <bin>`).
2. **Bundle Generator Bridge**:
   - In `pack/bridges/bundler.js`: support `createStandaloneBundle` appending bytecode payload and trailer.
3. **Unit Test Suite**:
   - `pack/tests/standalone.test.asl`: assert magic string equals `"ASLPACK!"`, footer size is 16, and codesign is required on macOS ARM64.

## Acceptance Gate
```bash
node asl/bin/asl test pack/tests/standalone.test.asl
```
Must pass 100% cleanly.
