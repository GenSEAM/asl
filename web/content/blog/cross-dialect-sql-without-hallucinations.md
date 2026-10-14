# Injection-Resistant SQL by Construction: Rendering Relational S-Expressions to Postgres, SQLite, MySQL & ClickHouse
*By GenSEAM | September 2026*

When autonomous coding agents are tasked with database operations (schema changes, analytical queries, data filtering) the default industry pattern is to prompt the LLM to emit raw SQL strings:

```text
Prompt: "Fetch the top 5 highest-spending users in 2026 who signed up via organic search."
LLM Output: "SELECT u.id, u.name, SUM(o.amount) as total FROM users u JOIN orders o ON..."
```

This pattern has three structural traps:

1. **Dialect Drift:** An agent writing for SQLite emits PostgreSQL syntax (`$1` placeholders, `ILIKE`, `ARRAY[]`). An agent writing for MySQL uses `||` for concatenation, which MySQL reads as a logical OR by default.
2. **Schema Blindness:** Models invent column names or join conditions because table structures are divorced from the language's type system.
3. **SQL Injection by Construction:** Agents interpolate runtime values into query text (`f"SELECT ... WHERE id = {user_input}"`), and a value that carries a quote changes the query itself.

We have not measured how often each trap occurs; the failure modes are well known, and their rate depends on the model, the schema and the task.

Relational queries should not be manipulated as freeform prose. In AgentSlang, a query is a value of an algebraic type, and the `asl-sql` package renders it to a target dialect.

---

## 1. The Dialect Matrix `asl-sql` Knows

`asl-sql` declares four dialects in `asl/packages/asl-sql/src/core/sql.asl`: `sqlite`, `postgres`, `mysql` and `clickhouse`. The differences it encodes today, read from that source:

| Feature | PostgreSQL | SQLite | MySQL | ClickHouse |
|---|---|---|---|---|
| **Parameter placeholder** | `$1, $2` | `?` | `?` | `?` |
| **Identifier quote character** | `"` | `"` | `` ` `` | `` ` `` |
| **JSON field extract** | `col->>'key'` | `json_extract(col, '$.key')` | `JSON_UNQUOTE(JSON_EXTRACT(col, '$.key'))` | `JSONExtractString(col, 'key')` |
| **Upsert** | `ON CONFLICT (...) DO UPDATE` | `ON CONFLICT (...) DO UPDATE` | `ON DUPLICATE KEY UPDATE` | falls to the `ON CONFLICT` form, which ClickHouse does not accept |

When an autoregressive model writes SQL, it has to track the query's intent and the target engine's syntax at once. A single slip (`$1` instead of `?` on SQLite) fails at run time. When the dialect is a parameter of a renderer, the slip cannot be made by the model at all.

---

## 2. Queries as Algebraic Data (`asl-sql/core`)

`asl-sql` models an expression as the enum `SqlExpr`, whose constructors are `col`, `qualCol`, `litStr`, `litInt`, `litBool`, `litNull`, `binary`, `andExpr`, `orExpr`, `notExpr`, `arith`, `agg`, `alias`, `caseWhen`, `jsonExtract` and `rawSql`. A query is the record `SelectQuery` (columns, table, joins, optional where, group by, having, order, limit, offset). Builders such as `colExpr`, `strExpr`, `intExpr`, `makeJoin` and `makeSelect` construct them, and `renderSelect` turns a query and a dialect into a `RenderedQuery` holding the SQL text, the placeholder count and the literal parameters in traversal order.

The idea fits in a page. The sample below is self-contained and passes `asl-host check` and `asl-host test` (3 checks) on the stage-0 host:

```asl
(module probe/p12aTest :x [renderWhere runTests] :i [])

enum Dialect (sqlite) (postgres) (mysql) (clickhouse)

enum Cond (eqText column: String value: String) (gtInt column: String value: Int64)

fn quoteIdent d: Dialect name: String -> String
  (mt d ((mysql) (str "`" name "`")) ((clickhouse) (str "`" name "`")) (_ (str "\"" name "\"")))

fn placeholder d: Dialect idx: Int64 -> String
  (mt d ((postgres) (str "$" idx)) (_ "?"))

fn renderCond d: Dialect c: Cond idx: Int64 -> String
  (mt c
    ((eqText column value) (str (quoteIdent d column) " = " (placeholder d idx)))
    ((gtInt column value) (str (quoteIdent d column) " > " (placeholder d idx))))

fn renderFrom d: Dialect conds: (List Cond) idx: Int64 -> (List String)
  (mt (listHead conds)
    ((none) (list))
    ((some c) (listAppend (list (renderCond d c idx)) (renderFrom d (optionOr (listTail conds) (list)) (+ idx 1)))))

fn renderWhere d: Dialect conds: (List Cond) -> String
  (str "WHERE " (stringJoin (renderFrom d conds 1) " AND "))

fn runTests -> Bool
  (let [(conds (list (eqText "status" "x' OR 1=1 --") (gtInt "amount" 1000)))]
    (do
      (assert (= (renderWhere (postgres) conds) "WHERE \"status\" = $1 AND \"amount\" > $2") "postgres")
      (assert (= (renderWhere (mysql) conds) "WHERE `status` = ? AND `amount` > ?") "mysql")
      (refute (stringContains? (renderWhere (sqlite) conds) "OR 1=1") "value never enters the SQL text")
      true))
```

Because the query is data:
1. **Structure is explicit:** there are no unterminated quotes, missing commas or ambiguous `A AND B OR C` precedence; each node is one balanced form.
2. **Values are parameters:** a literal renders as a placeholder, and the hostile string in the test above never reaches the SQL text.
3. **The dialect is an argument:** the same condition list renders `$1` for Postgres and `?` for MySQL. A match that names each dialect without a `_` fallback is checked for exhaustiveness: leave out `clickhouse` and `asl-host check` reports `ERR_MATCH_NONEXHAUSTIVE`.

---

## 3. DDL and DML (`asl-sql/ddl`)

`asl/packages/asl-sql/src/core/ddl.asl` covers the other half: `SqlColumnType` (`colInt64`, `colFloat64`, `colText`, `colBoolean`, `colTimestamp`), `makeColumn`, `makeTable` and `renderCreateTable` for schemas, and `makeInsert`/`renderInsert`, `makeUpsert`/`renderUpsert`, `makeUpdate`/`renderUpdate` and `renderDelete` for writes. Insert and upsert render one placeholder per column for the chosen dialect.

We are building structural diffs between two table definitions that emit forward and rollback migrations; today the package renders a `CREATE TABLE` from a definition and has no diff.

---

## 4. The Injection Boundary, Stated Precisely

In traditional code, injection happens because string manipulation lets untrusted data escape literal boundaries and change the shape of the query:

```python
# The classic vulnerability pattern
cursor.execute(f"SELECT * FROM users WHERE name = '{agent_payload}'")
```

In `asl-sql`, a literal in value position (`litStr`, `litInt`, `litBool`) renders as a placeholder and travels in the parameter list, so its quotes, semicolons and `--` comments stay data. The boundary has three known gaps, and we name them rather than claim a guarantee:

1. `rawSql` (built by `rawExpr`) inserts its text unescaped; it is the escape hatch.
2. `makeUpdate` and `renderDelete` still take their WHERE clause as a string.
3. Column and table names are passed through as written; `renderSelect` does not quote identifiers yet.

Code that stays with the expression builders keeps values out of the SQL text; code that reaches for `rawSql` or string WHERE clauses is back to trusting its input.

---

## 5. Where It Runs Today

The whole package now loads on the strict stage-0 host. Measured on 2026-10-14 with `asl/host/out/asl-host check asl/packages/asl-sql/src/core/sql.asl` (exit 0) and `asl-host test` on each suite in `asl/packages/asl-sql/tests/`:

| Suite | Assertions | Refutations |
|---|---|---|
| `sqlTest.asl` | 18 | 4 |
| `ddlTest.asl` | 17 | 7 |
| `duckdbAdapterTest.asl` | 81 | 26 |
| `semanticLayerTest.asl` | 40 | 15 |

All four exit 0. These suites check the rendered text; none of them sends a query to a live database engine.

---

## 6. Summary

Treating SQL as a text-completion problem puts dialect rules, schema knowledge and escaping inside the model's sampling loop. Lifting queries and table definitions into typed S-expressions moves them into code:
* **Dialect as a parameter:** one expression renders to Postgres, SQLite, MySQL or ClickHouse placeholders and JSON paths.
* **Literals as parameters:** values stay out of the SQL text unless code opts out through `rawSql` or a string WHERE clause.
* **Checked on the host:** the sample above and the `asl-sql` suites pass on the strict stage-0 host.
