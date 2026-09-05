# Phase 3 Plan: Arbitrum Stylus Wasm ABI Target (`wasm-stylus-target`)

## Objective
Generate EVM-compatible Arbitrum Stylus WebAssembly interfaces:
- Declare standard Stylus entrypoint `user_entrypoint(len: usize) -> usize`.
- Map ASL contract methods to 4-byte EVM function selectors (`keccak256("transfer(address,uint256)")`).
- Provide calldata decoder and returndata encoder in pure ASL.

## Work Items

### Item 1: Stylus ABI Generator (`stylus_abi.asl`)
- **Target**: `asl/packages/asl-contracts/src/stylus_abi.asl`
- **Details**:
  - `FunctionSelector`: 4-byte hex prefix for EVM dispatch.
  - `CalldataDecoder`: Extracts typed arguments from raw hex/bytes.
  - `StylusExport`: Generates Wasm component bindings for Arbitrum Stylus VM.
- **Gate**: `asl check asl/packages/asl-contracts/src/stylus_abi.asl`

### Item 2: Stylus Interface Test Suite (`stylus_test.asl`)
- **Target**: `asl/packages/asl-contracts/tests/stylus_test.asl`
- **Details**: Verify function selector calculation, calldata unpacking, and ABI dispatch.
- **Gate**: `PATH="$PWD/asl:$PATH" asl test asl/packages/asl-contracts/tests/stylus_test.asl`

## Acceptance Criteria
- EVM function selectors match standard Ethereum ABI.
- Calldata parsing functions correctly without memory leaks or buffer overflows.
