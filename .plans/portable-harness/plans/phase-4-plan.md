# Phase 4 Plan: Epistemic State & Hybrid Memory Store

## Goal
Implement a hybrid memory architecture combining pure ASL vector cosine similarity (`asl-mem/store.asl`) with structured metadata tagging, citation linking, and dual-backend persistence (IndexedDB/OPFS for browser, SQLite via `asl-sql` for Node/CLI).

## Work Items

### Item 1: Epistemic Memory Matrix in ASL
- **File**: `packages/asl-mem/src/epistemic_index.asl`
- **Specification**:
  - `dfs EpistemicRecord`: `id: Str`, `tag: Str`, `text: Str`, `vector: (List F64)`, `source-id: Str`, `timestamp: I64`, `access-count: I64`
  - `dfs MemoryQueryResult`: `record: EpistemicRecord`, `similarity: F64`
  - `rerank-by-similarity`: takes query vector, list of candidate records, and returns top-K results sorted by `cosine-similarity`.
  - `filter-by-tag`: narrows down candidates before vector calculation.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-mem/src/epistemic_index.asl`

### Item 2: Dual-Backend Persistence Bridge
- **File**: `packages/asl-harness/bridges/memory_adapter.ts`
- **Specification**:
  - `interface MemoryPersistenceDriver`:
    - `save(record: EpistemicRecord): Promise<void>`
    - `queryCandidates(tag?: string, limit?: number): Promise<EpistemicRecord[]>`
    - `delete(id: string): Promise<void>`
  - `BrowserIndexedDbDriver`: stores records and serialized float vectors in IndexedDB object store.
  - `NodeSqliteDriver`: uses SQLite with `asl-sql` DDL/DML table schema (`epistemic_memory`).
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/memory_adapter.ts`

### Item 3: Vector Memory Recall Test Suite
- **File**: `packages/asl-mem/tests/test_epistemic_memory.ts`
- **Specification**:
  - Stores 100 synthetic memory embeddings with tags and source citations.
  - Runs cosine similarity search for top-5 nearest neighbors.
  - Asserts accuracy of top-1 match and confirms persistence across store restarts.
- **Gate**: `.venv/bin/python checker/gate.py && npx tsx packages/asl-mem/tests/test_epistemic_memory.ts`
