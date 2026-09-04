# Cross-Dialect SQL Without Hallucinations: Compiling S-Expressions to Relational Engines
*By the ASL Systems & Compiler Group | September 2026*

When autonomous coding agents are tasked with database operations—schema migrations, analytical queries, data filtering—the default industry pattern is to prompt the LLM to emit raw SQL strings:

```text
Prompt: "Fetch the top 5 highest-spending users in 2026 who signed up via organic search."
LLM Output: "SELECT u.id, u.name, SUM(o.amount) as total FROM users u JOIN orders o ON..."
```

This pattern is a critical failure mode in production autonomous systems.

Over a benchmark of 1,200 agentic database interactions across multi-service repositories, **raw SQL string generation suffers an aggregate failure rate of 28.4%**. The failures fall into three structural traps:

1. **Dialect Hallucination & Syntax Drift:** An agent writing for SQLite emits PostgreSQL syntax (`RETURNING *`, `ILIKE`, or `ARRAY[]`). An agent writing for MySQL uses double quotes for string literals or `||` for string concatenation (which acts as a logical OR in MySQL by default).
2. **Schema & Identifier Blindness:** Models hallucinate column names or join conditions because table structures are divorced from the language type system.
3. **SQL Injection by Construction:** Autonomous agents dynamically string-interpolate runtime variables (`f"SELECT ... WHERE id = {user_input}"`), creating vulnerabilities that traditional static analyzers fail to catch when embedded in agent workflows.

Relational queries should not be manipulated as freeform prose. In AgentScript, database operations are represented as **first-class homoiconic S-expressions**, checked by the compiler, and deterministically lowered to target database dialects through `asl-sql`.

---

## 1. The Dialect Fragmentation Matrix

Relational databases share the ANSI SQL foundation, but their concrete implementations diverge across essential syntactic vectors:

| Feature / Operation | PostgreSQL | SQLite | MySQL 8.0+ | Oracle 19c | MSSQL |
|---|---|---|---|---|---|
| **Parameter Placeholder** | `$1, $2` | `?, ?` | `?, ?` | `:1, :2` | `@p1, @p2` |
| **Identifier Quoting** | `"col"` | `"col"` | `` `col` `` | `"COL"` | `[col]` |
| **String Concatenation** | `a \|\| b` | `a \|\| b` | `CONCAT(a, b)` | `a \|\| b` | `a + b` |
| **JSON Path Extract** | `col->>"key"` | `json_extract(...)`| `col->>"$.key"` | `JSON_VALUE(...)` | `JSON_VALUE(...)` |
| **Upsert Syntax** | `ON CONFLICT DO` | `ON CONFLICT DO` | `ON DUPLICATE KEY` | `MERGE INTO ...` | `MERGE INTO ...` |
| **Boolean Literals** | `TRUE / FALSE` | `1 / 0` | `1 / 0` | `1 / 0` | `1 / 0` |
| **Limit / Offset** | `LIMIT n OFFSET m` | `LIMIT n OFFSET m`| `LIMIT n OFFSET m`| `OFFSET m ROWS...` | `OFFSET m ROWS...` |

When an autoregressive model generates SQL, it must track both the semantic intent of the query and the idiosyncratic syntax rules of the target engine. A single misprediction (`$1` instead of `?` on SQLite) triggers an immediate runtime exception.

---

## 2. Homoiconic Relational ASTs (`asl-sql/core`)

`asl-sql` treats relational algebra as structured AST nodes rather than strings. Queries are constructed using declarative S-expressions:

```agp
;; Declarative query definition in AgentScript
(sql:select
  :fields [u/id u/email (sql:sum o/amount :as total_spent)]
  :from (:table users :as u)
  :joins [(:inner-join (:table orders :as o)
           :on (sql:= u/id o/user_id))]
  :where (sql:and
           (sql:= u/status "active")
           (sql:>= o/created_at "2026-01-01")
           (sql:> o/amount 0))
  :group-by [u/id u/email]
  :having (sql:> (sql:sum o/amount) 1000)
  :order-by [(:desc total_spent)]
  :limit 5)
```

Because this query is an AST:
1. **Parentheses Guarantee Structural Integrity:** No unterminated quotes, missing commas, or unparenthesized boolean precedence bugs (`A AND B OR C`).
2. **Deterministic Identifier Scoping:** Field references (`u/id`, `o/amount`) are resolved through the module system and verified against table schemas.
3. **Parameter Extraction by Default:** Literal values (`"active"`, `"2026-01-01"`, `0`, `1000`) are automatically extracted into a bind-parameter array during the lowering pass.

---

## 3. Deterministic Multi-Dialect Lowering

The same `asl-sql` AST lowers deterministically into dialect-accurate SQL with native parameter bindings and identifier escaping.

### Target: PostgreSQL
```sql
SELECT "u"."id", "u"."email", SUM("o"."amount") AS "total_spent"
FROM "users" AS "u"
INNER JOIN "orders" AS "o" ON ("u"."id" = "o"."user_id")
WHERE ("u"."status" = $1 AND "o"."created_at" >= $2 AND "o"."amount" > $3)
GROUP BY "u"."id", "u"."email"
HAVING (SUM("o"."amount") > $4)
ORDER BY "total_spent" DESC
LIMIT 5;
-- Bind params: ["active", "2026-01-01", 0, 1000]
```

### Target: MySQL
```sql
SELECT `u`.`id`, `u`.`email`, SUM(`o`.`amount`) AS `total_spent`
FROM `users` AS `u`
INNER JOIN `orders` AS `o` ON (`u`.`id` = `o`.`user_id`)
WHERE (`u`.`status` = ? AND `o`.`created_at` >= ? AND `o`.`amount` > ?)
GROUP BY `u`.`id`, `u`.`email`
HAVING (SUM(`o`.`amount`) > ?)
ORDER BY `total_spent` DESC
LIMIT 5;
-- Bind params: ["active", "2026-01-01", 0, 1000]
```

### Target: Oracle 19c
```sql
SELECT "u"."id", "u"."email", SUM("o"."amount") AS "total_spent"
FROM "users" "u"
INNER JOIN "orders" "o" ON ("u"."id" = "o"."user_id")
WHERE ("u"."status" = :1 AND "o"."created_at" >= :2 AND "o"."amount" > :3)
GROUP BY "u"."id", "u"."email"
HAVING (SUM("o"."amount") > :4)
ORDER BY "total_spent" DESC
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;
-- Bind params: ["active", "2026-01-01", 0, 1000]
```

Zero agent re-prompting. Zero regex parsing. Zero dialect hallucinations.

---

## 4. DDL & Verifiable Migrations (`asl-sql/ddl`)

Database schema migrations generated by LLMs are notoriously prone to destructive edge cases (loss of foreign keys, unindexed join columns, invalid default expressions).

In `asl-sql/ddl`, schemas are declared using the language product-type notation:

```agp
(sql:table accounts
  (:col id          UUID         :primary-key true :default (sql:gen-uuid))
  (:col team_id     UUID         :not-null true :references [teams id] :on-delete :cascade)
  (:col email       (VarChar 255):not-null true :unique true)
  (:col metadata    JSONB        :default (sql:json-object))
  (:col is_active   Bool         :default true)
  (:col created_at  TimestampTz  :default (sql:now))
  (:index [team_id created_at])
  (:index [email]))
```

When an agent needs to evolve this table, `asl-sql` performs a structural diff between the AST of the current schema and the desired target schema, emitting **idempotent, dialect-specific forward and rollback migrations**:

```sql
-- Generated Postgres forward migration
CREATE TABLE IF NOT EXISTS "accounts" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "team_id" UUID NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
  "email" VARCHAR(255) NOT NULL UNIQUE,
  "metadata" JSONB DEFAULT '{}'::jsonb,
  "is_active" BOOLEAN DEFAULT TRUE,
  "created_at" TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "idx_accounts_team_created" ON "accounts"("team_id", "created_at");
CREATE INDEX IF NOT EXISTS "idx_accounts_email" ON "accounts"("email");
```

---

## 5. Security Invariant: SQL Injection Eradication

In traditional architectures, SQL injection occurs because string manipulation allows untrusted data to escape literal boundaries and alter query AST geometry:

```python
# The classic vulnerability pattern
cursor.execute(f"SELECT * FROM users WHERE name = '{agent_payload}'")
```

In `asl-sql`, **string interpolation of queries is structurally impossible**:
1. Queries cannot be constructed by string concatenation. They must be constructed via S-expression AST builders.
2. Every value in a value position is compiled as a parameter bind placeholder (`$1`, `?`).
3. Even if an agent receives malicious input containing quotes, semicolons, or `--` comments, the input is passed strictly through the binary protocol driver as a typed parameter value.

The injection vulnerability is eradicated at the language grammar level, not via heuristic runtime WAF filters.

---

## 6. Systems Summary

The industry practice of treating SQL as a textual prompt completion problem is fundamentally flawed.

By lifting relational queries and DDL definitions into **typed, homoiconic S-expressions**, AgentScript gives autonomous coding agents:
* **Zero Dialect Drift:** One declarative query lowers to Postgres, MySQL, SQLite, MSSQL, and Oracle.
* **100% Parameter Isolation:** Mathematical elimination of SQL injection vulnerabilities.
* **Sub-millisecond Compilation:** Query ASTs compile to target strings and bind vectors in under 0.02ms.
