# Phase 4: Ephemeral Bridge & Intelligence Port (`asl-bridge-ephemeral-port`)

## Goal
Implement a pure ASL AST extractor in `intel/src/extractor.asl` that parses ASL modules, extracts symbol declarations (`dfs`, `dfe`, `df`), and generates dense ASN intelligence records, eliminating the need for persistent `.js` extraction scripts.

## Work Items
1. **Pure ASL AST Extractor**:
   - `intel/src/extractor.asl`:
     - Functions to scan and index symbols, signatures, and docstrings from ASL files into standard ASN tuples `(:symbol name :kind type :doc doc)`.
2. **Unit Test Suite**:
   - `intel/tests/extractor_test.asl`:
     - Test extracting definitions from standard ASL test fixtures.
3. **Hygiene & Verification**:
   - Ensure `intel/manifest.asn` exports the new ASL extractor module.

## Acceptance Gate
```bash
node bin/asl gate intel/src/extractor.asl intel/tests/extractor_test.asl
```
Must verify cleanly with 0 errors.
