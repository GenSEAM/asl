import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';

type Dialect = 'postgres' | 'sqlite' | 'mysql' | 'clickhouse';
type QueryPreset = 'users' | 'joins' | 'analytics';

interface QueryTemplate {
  name: string;
  description: string;
  aslQuery: string;
  table: string;
  fields: Array<{ name: string; type: string; pk: boolean }>;
}

const TEMPLATES: Record<QueryPreset, QueryTemplate> = {
  users: {
    name: '1. Filter & Pagination',
    description: 'Active users sorted by creation timestamp with parameter bindings',
    aslQuery: `(q/select ["id" "name" "email" "status"]
  (q/from "users")
  (q/where (q/and (q/eq "status" "active")
                  (q/gt "login_count" 5)))
  (q/order-by "created_at" (q/desc))
  (q/limit 25)
  (q/offset 0))`,
    table: 'users',
    fields: [
      { name: 'id', type: 'int64', pk: true },
      { name: 'name', type: 'text', pk: false },
      { name: 'email', type: 'text', pk: false },
      { name: 'status', type: 'text', pk: false },
      { name: 'login_count', type: 'int64', pk: false },
      { name: 'created_at', type: 'timestamp', pk: false },
    ],
  },
  joins: {
    name: '2. Multi-Table Join',
    description: 'Orders joined with users and amount threshold predicate',
    aslQuery: `(q/select ["u.name" "u.email" "o.order_id" "o.amount"]
  (q/from "users" :as "u")
  (q/inner-join "orders" :as "o"
    :on (q/eq "u.id" "o.user_id"))
  (q/where (q/and (q/gte "o.amount" 150.0)
                  (q/eq "o.currency" "USD")))
  (q/order-by "o.created_at" (q/desc))
  (q/limit 50))`,
    table: 'orders',
    fields: [
      { name: 'order_id', type: 'int64', pk: true },
      { name: 'user_id', type: 'int64', pk: false },
      { name: 'amount', type: 'float64', pk: false },
      { name: 'currency', type: 'text', pk: false },
      { name: 'created_at', type: 'timestamp', pk: false },
    ],
  },
  analytics: {
    name: '3. Range & Inequality',
    description: 'High-volume telemetry events with date boundaries and category matching',
    aslQuery: `(q/select ["device_id" "metric_name" "metric_val" "timestamp"]
  (q/from "device_telemetry")
  (q/where (q/and (q/gte "timestamp" "2026-09-01T00:00:00Z")
                  (q/lt "timestamp" "2026-09-03T00:00:00Z")
                  (q/eq "status" "ALERT")))
  (q/order-by "timestamp" (q/desc))
  (q/limit 100))`,
    table: 'device_telemetry',
    fields: [
      { name: 'id', type: 'int64', pk: true },
      { name: 'device_id', type: 'text', pk: false },
      { name: 'metric_name', type: 'text', pk: false },
      { name: 'metric_val', type: 'float64', pk: false },
      { name: 'status', type: 'text', pk: false },
      { name: 'timestamp', type: 'timestamp', pk: false },
    ],
  },
};

export const SqlStudio: React.FC = () => {
  const [activePreset, setActivePreset] = useState<QueryPreset>('users');
  const [activeDialect, setActiveDialect] = useState<Dialect>('postgres');
  const [activeTab, setActiveTab] = useState<'sql' | 'ddl'>('sql');

  const template = TEMPLATES[activePreset];

  // Client-side render simulation according to dialect rules
  const renderSql = (preset: QueryPreset, dialect: Dialect): { sql: string; params: Array<{ idx: number; ph: string; val: string; type: string }> } => {
    if (preset === 'users') {
      const ph1 = dialect === 'postgres' ? '$1' : '?';
      const ph2 = dialect === 'postgres' ? '$2' : '?';
      const q = dialect === 'mysql' || dialect === 'clickhouse' ? '`' : '"';
      const sql = `SELECT ${q}id${q}, ${q}name${q}, ${q}email${q}, ${q}status${q} FROM ${q}users${q} WHERE (${q}status${q} = ${ph1}) AND (${q}login_count${q} > ${ph2}) ORDER BY ${q}created_at${q} DESC LIMIT 25 OFFSET 0;`;
      return {
        sql,
        params: [
          { idx: 1, ph: ph1, val: '"active"', type: 'String' },
          { idx: 2, ph: ph2, val: '5', type: 'Int64' },
        ],
      };
    } else if (preset === 'joins') {
      const ph1 = dialect === 'postgres' ? '$1' : '?';
      const ph2 = dialect === 'postgres' ? '$2' : '?';
      const q = dialect === 'mysql' || dialect === 'clickhouse' ? '`' : '"';
      const sql = `SELECT ${q}u${q}.${q}name${q}, ${q}u${q}.${q}email${q}, ${q}o${q}.${q}order_id${q}, ${q}o${q}.${q}amount${q} FROM ${q}users${q} AS ${q}u${q} INNER JOIN ${q}orders${q} AS ${q}o${q} ON ${q}u${q}.${q}id${q} = ${q}o${q}.${q}user_id${q} WHERE (${q}o${q}.${q}amount${q} >= ${ph1}) AND (${q}o${q}.${q}currency${q} = ${ph2}) ORDER BY ${q}o${q}.${q}created_at${q} DESC LIMIT 50;`;
      return {
        sql,
        params: [
          { idx: 1, ph: ph1, val: '150.0', type: 'Float64' },
          { idx: 2, ph: ph2, val: '"USD"', type: 'String' },
        ],
      };
    } else {
      const ph1 = dialect === 'postgres' ? '$1' : '?';
      const ph2 = dialect === 'postgres' ? '$2' : '?';
      const ph3 = dialect === 'postgres' ? '$3' : '?';
      const q = dialect === 'mysql' || dialect === 'clickhouse' ? '`' : '"';
      const sql = `SELECT ${q}device_id${q}, ${q}metric_name${q}, ${q}metric_val${q}, ${q}timestamp${q} FROM ${q}device_telemetry${q} WHERE (${q}timestamp${q} >= ${ph1}) AND (${q}timestamp${q} < ${ph2}) AND (${q}status${q} = ${ph3}) ORDER BY ${q}timestamp${q} DESC LIMIT 100;`;
      return {
        sql,
        params: [
          { idx: 1, ph: ph1, val: '"2026-09-01T00:00:00Z"', type: 'Timestamp' },
          { idx: 2, ph: ph2, val: '"2026-09-03T00:00:00Z"', type: 'Timestamp' },
          { idx: 3, ph: ph3, val: '"ALERT"', type: 'String' },
        ],
      };
    }
  };

  const renderDdl = (template: QueryTemplate, dialect: Dialect): string => {
    const q = dialect === 'mysql' || dialect === 'clickhouse' ? '`' : '"';
    const lines = template.fields.map((f) => {
      let tStr = 'TEXT';
      if (f.type === 'int64') tStr = dialect === 'postgres' ? 'BIGINT' : 'INTEGER';
      else if (f.type === 'float64') tStr = dialect === 'postgres' ? 'DOUBLE PRECISION' : 'REAL';
      else if (f.type === 'timestamp') tStr = dialect === 'postgres' ? 'TIMESTAMPTZ' : 'TEXT';
      const pk = f.pk ? ' PRIMARY KEY' : ' NOT NULL';
      return `  ${q}${f.name}${q} ${tStr}${pk}`;
    });
    return `CREATE TABLE ${q}${template.table}${q} (\n${lines.join(',\n')}\n);`;
  };

  const rendered = renderSql(activePreset, activeDialect);
  const ddlSql = renderDdl(template, activeDialect);

  return (
    <Section id="sql-studio">
      <SectionHeader
        id="sql-studio-heading"
        index="05"
        eyebrow="SQL Query Studio & Parameterized Emission"
        title="Native ASL Cross-Dialect SQL AST Query Builder"
        lead="AgentScript models SQL queries directly as typechecked S-expression ASTs, emitting parameterized queries across Postgres, SQLite, MySQL, and ClickHouse with zero SQL-injection vulnerabilities."
      />

      <div className="mt-8 space-y-6">
        {/* Preset Selector */}
        <div className="flex flex-wrap items-center justify-between gap-4 p-4 rounded-xl border border-border bg-surface-elevated">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-content-muted mr-2">
              Query Template:
            </span>
            {(Object.keys(TEMPLATES) as QueryPreset[]).map((key) => {
              const active = activePreset === key;
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => setActivePreset(key)}
                  className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-colors border ${
                    active
                      ? 'bg-accent text-accent-contrast border-accent shadow-sm'
                      : 'bg-surface text-content hover:bg-surface-elevated border-border'
                  }`}
                >
                  {TEMPLATES[key].name}
                </button>
              );
            })}
          </div>

          {/* Dialect Switcher */}
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-content-muted mr-1">
              Dialect:
            </span>
            {(['postgres', 'sqlite', 'mysql', 'clickhouse'] as Dialect[]).map((d) => {
              const active = activeDialect === d;
              return (
                <button
                  key={d}
                  type="button"
                  onClick={() => setActiveDialect(d)}
                  className={`px-2.5 py-1 text-xs font-semibold rounded-md uppercase tracking-wider transition-all border ${
                    active
                      ? 'bg-code-literal text-surface border-code-literal shadow-sm'
                      : 'bg-surface text-content-muted hover:text-content border-border'
                  }`}
                >
                  {d}
                </button>
              );
            })}
          </div>
        </div>

        {/* Studio Workspace Split */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Left Column: Input ASL AST */}
          <div className="flex flex-col h-full rounded-xl border border-border bg-surface-elevated overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 border-b border-border bg-surface">
              <div className="flex items-center gap-2">
                <span className="inline-block w-2.5 h-2.5 rounded-full bg-accent" />
                <span className="text-xs font-bold uppercase tracking-wider text-content">
                  Native ASL Query AST
                </span>
              </div>
              <span className="text-2xs font-mono px-2 py-0.5 rounded bg-surface-elevated border border-border text-content-muted">
                packages/asl-sql
              </span>
            </div>

            <div className="p-4 flex-1 flex flex-col justify-between">
              <pre className="font-mono text-xs text-content leading-relaxed overflow-x-auto p-4 rounded-lg bg-surface border border-border">
                <code>{template.aslQuery}</code>
              </pre>

              <div className="mt-4 p-3 rounded-lg bg-surface border border-border flex items-center justify-between text-xs">
                <div className="flex items-center gap-2 text-content-muted">
                  <span className="text-status-pass font-bold">✓</span>
                  <span>AST Safety: Total Totality & Deterministic Parameter Extraction</span>
                </div>
                <span className="text-2xs font-semibold uppercase tracking-wider px-2 py-0.5 rounded bg-accent/10 text-accent">
                  AST Validated
                </span>
              </div>
            </div>
          </div>

          {/* Right Column: Multi-Dialect Parameterized SQL Output */}
          <div className="flex flex-col h-full rounded-xl border border-border bg-surface-elevated overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 border-b border-border bg-surface">
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setActiveTab('sql')}
                  className={`text-xs font-bold uppercase tracking-wider px-2.5 py-1 rounded transition-colors ${
                    activeTab === 'sql' ? 'bg-accent/15 text-accent' : 'text-content-muted hover:text-content'
                  }`}
                >
                  ⚡ Parameterized SQL
                </button>
                <button
                  type="button"
                  onClick={() => setActiveTab('ddl')}
                  className={`text-xs font-bold uppercase tracking-wider px-2.5 py-1 rounded transition-colors ${
                    activeTab === 'ddl' ? 'bg-accent/15 text-accent' : 'text-content-muted hover:text-content'
                  }`}
                >
                  📦 Schema DDL
                </button>
              </div>

              <div className="flex items-center gap-2">
                <span className="text-2xs font-mono uppercase px-2 py-0.5 rounded bg-code-literal/15 text-code-literal font-bold">
                  {activeDialect}
                </span>
                <span className="text-2xs font-mono px-2 py-0.5 rounded bg-status-pass/15 text-status-pass font-bold">
                  0 Injection
                </span>
              </div>
            </div>

            <div className="p-4 flex-1 flex flex-col justify-between space-y-4">
              {activeTab === 'sql' ? (
                <>
                  <pre className="font-mono text-xs text-code-literal leading-relaxed overflow-x-auto p-4 rounded-lg bg-surface border border-border whitespace-pre-wrap">
                    <code>{rendered.sql}</code>
                  </pre>

                  {/* Parameter Bindings Table */}
                  <div className="space-y-2">
                    <div className="text-xs font-bold uppercase tracking-wider text-content-muted">
                      Extracted Bound Parameters ({rendered.params.length}):
                    </div>
                    <div className="rounded-lg border border-border overflow-hidden">
                      <table className="w-full text-xs text-left">
                        <thead className="bg-surface border-b border-border text-content-muted">
                          <tr>
                            <th className="px-3 py-1.5 font-semibold">Param</th>
                            <th className="px-3 py-1.5 font-semibold">Placeholder</th>
                            <th className="px-3 py-1.5 font-semibold">Inferred Type</th>
                            <th className="px-3 py-1.5 font-semibold">Payload Value</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-border bg-surface-elevated">
                          {rendered.params.map((p) => (
                            <tr key={p.idx} className="font-mono">
                              <td className="px-3 py-1.5 text-content-muted">#{p.idx}</td>
                              <td className="px-3 py-1.5 text-accent font-bold">{p.ph}</td>
                              <td className="px-3 py-1.5 text-content-muted">{p.type}</td>
                              <td className="px-3 py-1.5 text-code-literal font-semibold">{p.val}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                </>
              ) : (
                <div className="space-y-3">
                  <div className="text-xs font-bold uppercase tracking-wider text-content-muted">
                    Auto-Generated DDL Migration ({template.table}):
                  </div>
                  <pre className="font-mono text-xs text-content leading-relaxed overflow-x-auto p-4 rounded-lg bg-surface border border-border">
                    <code>{ddlSql}</code>
                  </pre>
                  <p className="text-xs text-content-muted">
                    Derived from AgentScript module schema definitions with dialect-specific data types.
                  </p>
                </div>
              )}

              {/* CLI Command Helper */}
              <div className="mt-2 p-2.5 rounded-lg bg-surface border border-border font-mono text-2xs text-content-muted flex items-center justify-between">
                <span>$ asl sql render --dialect {activeDialect} --query '{template.aslQuery.replace(/\n\s*/g, ' ')}'</span>
                <span className="text-accent cursor-pointer hover:underline">copy</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
