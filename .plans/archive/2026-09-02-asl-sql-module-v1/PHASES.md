# Phases — asl-sql-module-v1

Native AgentScript Cross-Dialect SQL AST Query Builder, Parameterized Emission & DDL Module (`packages/asl-sql`).

## Phase List

- [ ] **Phase 1**: Native ASL SQL AST Modeling & Dialect Enums (`packages/asl-sql/src/core/sql.asl`)
  - Criterion: `.venv/bin/python agentscript check packages/asl-sql/src/core/sql.asl` passes with 0 diagnostics.
- [ ] **Phase 2**: Multi-Dialect Parameterized SQL Emission & Placeholder Adapter (`packages/asl-sql/src/core/render.asl`)
  - Criterion: `.venv/bin/python agentscript check packages/asl-sql/src/core/render.asl` passes with 0 diagnostics, emitting `$n` for Postgres, `?` for SQLite.
- [ ] **Phase 3**: DML Operations & Schema-Driven DDL Migration Generator (`packages/asl-sql/src/core/ddl.asl`)
  - Criterion: `.venv/bin/python agentscript check packages/asl-sql/src/core/ddl.asl` passes with 0 diagnostics, generating typed `CREATE TABLE` and parameterized `INSERT`/`UPDATE`.
- [ ] **Phase 4**: CLI Integration (`asl sql render`) & Comprehensive Test Suite (`tools/tests/test_sql.py`)
  - Criterion: `.venv/bin/python -m pytest tools/tests/test_sql.py -q` passes 100%.
- [ ] **Phase 5**: Interactive SQL Studio in Web Showcase (`web/src/components/SqlStudio.tsx`) & 7-Gate Verification
  - Criterion: `node web/scripts/check-tokens.mjs` and `cd web && npm run build` pass; all 7 pre-commit gates pass cleanly.

## Out of Scope
- Direct socket TCP network connections to live database servers (this module is a pure AST query builder and serializer; network execution is left to host drivers).
