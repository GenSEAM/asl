import React, { useState } from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import {
  Terminal,
  ShieldCheck,
  FileText,
  Code2,
  Copy,
  Check,
  Sparkles,
  Boxes,
  Workflow,
  Search,
  BookOpen,
  Database,
  Braces
} from 'lucide-react';

type CodeTargetLang = 'python' | 'rust' | 'typescript' | 'go';
type DataTargetFormat = 'json' | 'yaml';
type SqlDialect = 'postgres' | 'mysql' | 'sqlite' | 'mssql' | 'oracle';
type DocTab = 'cli' | 'mesh' | 'data' | 'sql' | 'syntax' | 'control' | 'stdlib';

interface PolyglotCard {
  id: string;
  title: string;
  description: string;
  asl: string;
  python: string;
  rust: string;
  typescript: string;
  go: string;
}

const SYNTAX_CARDS: PolyglotCard[] = [
  {
    id: 'schema-decl',
    title: 'Schema Declaration & Typed Records',
    description: 'Declarative immutable schemas with typed fields. Compiles into native product types across backends.',
    asl: `(dfs Token
  (:f id Str "Unique token identifier.")
  (:f exp I64 "Unix timestamp expiration."))

(df create-token [(id Str) (ttl I64)] -> Token
  :d "Construct authenticated token record."
  (Token :id id :exp (+ 1700000000 ttl)))`,
    python: `from dataclasses import dataclass

@dataclass(frozen=True)
class Token:
    """Unique token identifier."""
    id: str
    exp: int

def create_token(id: str, ttl: int) -> Token:
    """Construct authenticated token record."""
    return Token(id=id, exp=1700000000 + ttl)`,
    rust: `#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Token {
    pub id: String,
    pub exp: i64,
}

pub fn create_token(id: String, ttl: i64) -> Token {
    Token {
        id,
        exp: 1700000000 + ttl,
    }
}`,
    typescript: `export interface Token {
  readonly id: string;
  readonly exp: bigint;
}

export function createToken(id: string, ttl: bigint): Token {
  return { id, exp: 1700000000n + ttl };
}`,
    go: `package auth

type Token struct {
    ID  string \`json:"id"\`
    Exp int64  \`json:"exp"\`
}

func CreateToken(id string, ttl int64) Token {
    return Token{
        ID:  id,
        Exp: 1700000000 + ttl,
    }
}`
  },
  {
    id: 'sum-types',
    title: 'Closed Union Types (Sum Types / Enums)',
    description: 'Exhaustive sum types checked at compile time. Lowers to tagged unions, rust enums, or Go interfaces.',
    asl: `(dfe ResultStatus
  (:c ok [(val Str)] "Successful execution.")
  (:c timeout [(ms I64)] "Network timed out.")
  (:c denied [] "Access denied."))

(df status-code [(s ResultStatus)] -> I64
  :d "Map status variant to HTTP status code."
  (mt s
    ((ok _) 200)
    ((timeout _) 504)
    ((denied) 403)))`,
    python: `from typing import Union

class OkStatus:
    def __init__(self, val: str): self.val = val

class TimeoutStatus:
    def __init__(self, ms: int): self.ms = ms

class DeniedStatus: pass

ResultStatus = Union[OkStatus, TimeoutStatus, DeniedStatus]

def status_code(s: ResultStatus) -> int:
    match s:
        case OkStatus(_): return 200
        case TimeoutStatus(_): return 504
        case DeniedStatus(): return 403`,
    rust: `#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResultStatus {
    Ok(String),
    Timeout(i64),
    Denied,
}

pub fn status_code(s: &ResultStatus) -> i64 {
    match s {
        ResultStatus::Ok(_) => 200,
        ResultStatus::Timeout(_) => 504,
        ResultStatus::Denied => 403,
    }
}`,
    typescript: `export type ResultStatus =
  | { readonly kind: 'ok'; readonly val: string }
  | { readonly kind: 'timeout'; readonly ms: bigint }
  | { readonly kind: 'denied' };

export function statusCode(s: ResultStatus): number {
  switch (s.kind) {
    case 'ok': return 200;
    case 'timeout': return 504;
    case 'denied': return 403;
  }
}`,
    go: `package status

type ResultStatus interface {
    isResultStatus()
}

type OkStatus struct{ Val string }
func (OkStatus) isResultStatus() {}

type TimeoutStatus struct{ Ms int64 }
func (TimeoutStatus) isResultStatus() {}

type DeniedStatus struct{}
func (DeniedStatus) isResultStatus() {}

func StatusCode(s ResultStatus) int64 {
    switch s.(type) {
    case OkStatus:
        return 200
    case TimeoutStatus:
        return 504
    case DeniedStatus:
        return 403
    default:
        panic("unreachable")
    }
}`
  }
];

const CONTROL_CARDS: PolyglotCard[] = [
  {
    id: 'error-handling',
    title: 'Error Handling with try & Result',
    description: 'No runtime exceptions. try unwraps (ok value) or bubbles up (err reason) immediately. Lowers to ? in Rust and error guards in Go.',
    asl: `(df parse-port [(raw Str)] -> (Result I64 Str)
  :d "Parse port number with bounds verification."
  (let [(p (try (option-to-result (string-to-int64 raw) "Not an integer")))]
    (if (and (>= p 1) (<= p 65535))
      (ok p)
      (err "Port must be between 1 and 65535"))))`,
    python: `def parse_port(raw: str) -> Result[int, str]:
    try:
        p = int(raw)
    except ValueError:
        return Err("Not an integer")
    if 1 <= p <= 65535:
        return Ok(p)
    return Err("Port must be between 1 and 65535")`,
    rust: `pub fn parse_port(raw: &str) -> Result<i64, &'static str> {
    let p = raw.parse::<i64>().map_err(|_| "Not an integer")?;
    if p >= 1 && p <= 65535 {
        Ok(p)
    } else {
        Err("Port must be between 1 and 65535")
    }
}`,
    typescript: `export function parsePort(raw: string): Result<bigint, string> {
  try {
    const p = BigInt(raw);
    if (p >= 1n && p <= 65535n) {
      return { ok: true, value: p };
    }
    return { ok: false, error: "Port must be between 1 and 65535" };
  } catch {
    return { ok: false, error: "Not an integer" };
  }
}`,
    go: `package network

import (
    "errors"
    "strconv"
)

func ParsePort(raw string) (int64, error) {
    p, err := strconv.ParseInt(raw, 10, 64)
    if err != nil {
        return 0, errors.New("Not an integer")
    }
    if p >= 1 && p <= 65535 {
        return p, nil
    }
    return 0, errors.New("Port must be between 1 and 65535")
}`
  },
  {
    id: 'tail-recursion',
    title: 'Tail-Call Optimized Algorithm (Fibonacci)',
    description: 'Guaranteed TCO in ASL. Emits iterative loops or tail-optimized functions across backends without stack overflow.',
    asl: `(df fib [(n I64)] -> I64
  :d "Tail-recursive Fibonacci sequence."
  (df loop [(i I64) (a I64) (b I64)] -> I64
    (if (= i 0)
      a
      (loop (- i 1) b (+ a b))))
  (loop n 0 1))`,
    python: `def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a`,
    rust: `pub fn fib(n: i64) -> i64 {
    let (mut a, mut b) = (0i64, 1i64);
    for _ in 0..n {
        let next = a + b;
        a = b;
        b = next;
    }
    a
}`,
    typescript: `export function fib(n: bigint): bigint {
  let a = 0n;
  let b = 1n;
  for (let i = 0n; i < n; i++) {
    const next = a + b;
    a = b;
    b = next;
  }
  return a;
}`,
    go: `package algo

func Fib(n int64) int64 {
    var a, b int64 = 0, 1
    for i := int64(0); i < n; i++ {
        a, b = b, a+b
    }
    return a
}`
  }
];

interface DataComparisonCard {
  id: string;
  title: string;
  description: string;
  asl: string;
  json: string;
  yaml: string;
}

const DATA_CARDS: DataComparisonCard[] = [
  {
    id: 'tabular-matrix',
    title: 'Tabular Data Matrix Representation',
    description: 'Stores uniform record sequences as a single key vector plus compact row vectors. Saves over 65% token overhead versus verbose JSON objects.',
    asl: `([:id :name :role :level]
 [[101 "Alice" :lead 5]
  [102 "Bob"   :agent 3]
  [103 "Carol" :peer 4]])`,
    json: `[
  { "id": 101, "name": "Alice", "role": "lead", "level": 5 },
  { "id": 102, "name": "Bob", "role": "agent", "level": 3 },
  { "id": 103, "name": "Carol", "role": "peer", "level": 4 }
]`,
    yaml: `- id: 101
  name: Alice
  role: lead
  level: 5
- id: 102
  name: Bob
  role: agent
  level: 3
- id: 103
  name: Carol
  role: peer
  level: 4`
  },
  {
    id: 'constant-pool',
    title: 'Shared Value Pool Deduplication (:pool & :ref)',
    description: 'Repeated URLs, models, and endpoints declared once in a shared pool and referenced by 1-token index. Zero duplication.',
    asl: `(:pool ["https://api.genseam.org/v1/telemetry"
        "claude-3-7-sonnet-20250219"
        "asl/agent-mesh/node-alpha"]
  :events [([:node :model :target :ok]
            [[(:ref 2) (:ref 1) (:ref 0) true]
             [(:ref 2) (:ref 1) (:ref 0) false]]))`,
    json: `{
  "events": [
    {
      "node": "asl/agent-mesh/node-alpha",
      "model": "claude-3-7-sonnet-20250219",
      "target": "https://api.genseam.org/v1/telemetry",
      "ok": true
    },
    {
      "node": "asl/agent-mesh/node-alpha",
      "model": "claude-3-7-sonnet-20250219",
      "target": "https://api.genseam.org/v1/telemetry",
      "ok": false
    }
  ]
}`,
    yaml: `events:
  - node: asl/agent-mesh/node-alpha
    model: claude-3-7-sonnet-20250219
    target: https://api.genseam.org/v1/telemetry
    ok: true
  - node: asl/agent-mesh/node-alpha
    model: claude-3-7-sonnet-20250219
    target: https://api.genseam.org/v1/telemetry
    ok: false`
  },
  {
    id: 'token-traits',
    title: '1-Token Behavioral Traits & Metadata',
    description: 'Single-token keywords (:tag, :why, :use, :ref, :offload) carry zero BPE token overhead while remaining lexically distinct.',
    asl: `(:tag "d-1eed"
 :why "Eliminate BPE prefix splits and preserve single-token density"
 :use "auth/crypto"
 :offload :storage/opfs)`,
    json: `{
  "decision_tag": "d-1eed",
  "architectural_rationale": "Eliminate BPE prefix splits and preserve single-token density",
  "import_module": "auth/crypto",
  "storage_driver": "storage/opfs"
}`,
    yaml: `decision_tag: "d-1eed"
architectural_rationale: "Eliminate BPE prefix splits and preserve single-token density"
import_module: "auth/crypto"
storage_driver: "storage/opfs"`
  }
];

interface BuiltinDoc {
  name: string;
  category: 'math' | 'list' | 'string' | 'io' | 'logic';
  signature: string;
  summary: string;
}

const BUILTINS: BuiltinDoc[] = [
  { name: '+', category: 'math', signature: '(+ a b ...)', summary: 'Sums two or more integers or floats of matching type.' },
  { name: '-', category: 'math', signature: '(- a b ...)', summary: 'Subtracts subsequent numbers from the first.' },
  { name: '*', category: 'math', signature: '(* a b ...)', summary: 'Multiplies two or more numbers.' },
  { name: '/', category: 'math', signature: '(/ a b)', summary: 'Division. Rejects division by zero.' },
  { name: 'mod', category: 'math', signature: '(mod a b)', summary: 'Remainder modulo operation. Kept separate from module keyword.' },
  { name: 'list-get', category: 'list', signature: '(list-get xs idx)', summary: 'Returns (Some elem) at 0-based index, or (None) if out of bounds.' },
  { name: 'list-len', category: 'list', signature: '(list-len xs)', summary: 'Returns count of items in the list as I64.' },
  { name: 'list-map', category: 'list', signature: '(list-map xs f)', summary: 'Applies transformer function f to each element.' },
  { name: 'list-filter', category: 'list', signature: '(list-filter xs pred)', summary: 'Retains elements where pred returns true.' },
  { name: 'list-fold', category: 'list', signature: '(list-fold xs acc f)', summary: 'Reduces list with accumulator from left to right.' },
  { name: 'string-concat', category: 'string', signature: '(string-concat s1 s2 ...)', summary: 'Concatenates two or more strings.' },
  { name: 'string-to-int64', category: 'string', signature: '(string-to-int64 s)', summary: 'Parses string to (Option I64).' },
  { name: 'int64-to-string', category: 'string', signature: '(int64-to-string n)', summary: 'Converts integer to string representation.' },
  { name: 'fs-read-text', category: 'io', signature: '(fs-read-text path)', summary: 'Safely reads text file within sandboxed workspace isolate.' },
  { name: 'fs-write-text', category: 'io', signature: '(fs-write-text path text)', summary: 'Safely writes text file inside sandbox without host escape.' },
  { name: 'try', category: 'logic', signature: '(try expr)', summary: 'Unwraps (ok v) or bubbles (err e) from caller returning Result.' },
  { name: 'option-to-result', category: 'logic', signature: '(option-to-result opt err-msg)', summary: 'Converts (Some v) to (ok v) and (None) to (err err-msg).' }
];

export const DocsView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<DocTab>('cli');
  const [targetLang, setTargetLang] = useState<CodeTargetLang>('python');
  const [dataTarget, setDataTarget] = useState<DataTargetFormat>('json');
  const [sqlDialect, setSqlDialect] = useState<SqlDialect>('postgres');
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(id);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const filteredBuiltins = BUILTINS.filter(
    (b) =>
      b.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      b.summary.toLowerCase().includes(searchQuery.toLowerCase()) ||
      b.category.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="pt-28 pb-20">
      <Section id="docs" labelledBy="docs-title">
        <SectionHeader
          id="docs-title"
          index="Reference"
          eyebrow="Documentation"
          title="AgentScript Reference & Capabilities Guide"
          lead="The definitive guide to CLI toolchains, inter-agent mesh wire frames, context economy matrices, cross-dialect SQL queries, polyglot transpilation targets, and standard library functions."
        />

        {/* Machine-Readable Prompt Ingestion Banner */}
        <div className="mb-10 p-6 sm:p-8 rounded-3xl border border-signal/40 bg-gradient-to-r from-surface to-surface/70 backdrop-blur-xl shadow-e2 flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
          <div className="space-y-2 max-w-2xl">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-signal/15 text-signal font-mono text-micro uppercase font-semibold">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Prompt Ingestion Endpoints</span>
            </div>
            <h3 className="text-xl font-bold text-ink">
              Looking for raw prompt ingest cards?
            </h3>
            <p className="text-meta text-ink-2 leading-relaxed">
              Autonomous agents consume our machine-readable specifications directly. Zero markdown fluff, 100% authoritative grammar and closed vocabulary tables.
            </p>
          </div>
          <div className="flex flex-wrap gap-3">
            <a
              href="/llms.txt"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-signal text-white font-mono text-meta font-medium shadow-sm hover:opacity-90 transition-opacity"
            >
              <FileText className="w-4 h-4" />
              <span>/llms.txt</span>
            </a>
            <a
              href="/llms-full.txt"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-surface border border-line hover:border-signal/40 text-ink font-mono text-meta font-medium shadow-sm transition-all"
            >
              <Code2 className="w-4 h-4 text-signal" />
              <span>/llms-full.txt</span>
            </a>
          </div>
        </div>

        {/* Ordered Category Navigation Bar */}
        <div className="flex flex-col xl:flex-row items-stretch xl:items-center justify-between gap-4 mb-8 pb-4 border-b border-line">
          {/* Main Category Tabs */}
          <div className="grid grid-cols-2 sm:grid-cols-4 xl:flex xl:flex-wrap gap-2 flex-1 min-w-0">
            {[
              { id: 'cli', label: '1. CLI & Workflow', icon: Terminal },
              { id: 'mesh', label: '2. Agent Mesh', icon: Boxes },
              { id: 'data', label: '3. Data & Economy', icon: Database },
              { id: 'sql', label: '4. SQL & Query DSL', icon: Code2 },
              { id: 'syntax', label: '5. Syntax & Forms', icon: Braces },
              { id: 'control', label: '6. Control & Errors', icon: Workflow },
              { id: 'stdlib', label: '7. Standard Library', icon: BookOpen }
            ].map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setActiveTab(id as DocTab)}
                className={`flex items-center justify-center sm:justify-start gap-2 px-3 py-2 rounded-xl font-mono text-meta font-medium transition-all ${
                  activeTab === id
                    ? 'bg-signal text-white shadow-sm'
                    : 'bg-surface hover:bg-surface-2 text-ink-2 hover:text-ink border border-line'
                }`}
              >
                <Icon className="w-4 h-4 shrink-0" />
                <span className="truncate">{label}</span>
              </button>
            ))}
          </div>

          {/* Contextual Sub-Control Area (Stable container, never causes layout jumping) */}
          <div className="shrink-0 flex items-center justify-start sm:justify-end min-h-[44px]">
            {/* Syntax & Control: Polyglot Target Language Selector */}
            {(activeTab === 'syntax' || activeTab === 'control') && (
              <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line w-full sm:w-auto overflow-x-auto">
                <span className="text-micro font-mono uppercase text-ink-3 px-2">Target:</span>
                {(['python', 'rust', 'typescript', 'go'] as CodeTargetLang[]).map((lang) => (
                  <button
                    key={lang}
                    onClick={() => setTargetLang(lang)}
                    className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all capitalize ${
                      targetLang === lang
                        ? 'bg-signal text-white shadow-sm'
                        : 'text-ink-2 hover:text-ink'
                    }`}
                  >
                    {lang === 'typescript' ? 'TypeScript' : lang}
                  </button>
                ))}
              </div>
            )}

            {/* SQL & Query DSL: Dialect Selector */}
            {activeTab === 'sql' && (
              <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line w-full sm:w-auto overflow-x-auto">
                <span className="text-micro font-mono uppercase text-ink-3 px-2">Dialect:</span>
                {[
                  { id: 'postgres', label: 'PostgreSQL' },
                  { id: 'mysql', label: 'MySQL' },
                  { id: 'sqlite', label: 'SQLite' },
                  { id: 'mssql', label: 'MSSQL' },
                  { id: 'oracle', label: 'Oracle' }
                ].map(({ id, label }) => (
                  <button
                    key={id}
                    onClick={() => setSqlDialect(id as SqlDialect)}
                    className={`px-2.5 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                      sqlDialect === id
                        ? 'bg-signal text-white shadow-sm'
                        : 'text-ink-2 hover:text-ink'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            )}

            {/* Data & Economy: JSON / YAML Compare Selector */}
            {activeTab === 'data' && (
              <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line w-full sm:w-auto">
                <span className="text-micro font-mono uppercase text-ink-3 px-2">Compare:</span>
                {(['json', 'yaml'] as DataTargetFormat[]).map((fmt) => (
                  <button
                    key={fmt}
                    onClick={() => setDataTarget(fmt)}
                    className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all uppercase ${
                      dataTarget === fmt ? 'bg-signal text-white shadow-sm' : 'text-ink-2 hover:text-ink'
                    }`}
                  >
                    {fmt}
                  </button>
                ))}
              </div>
            )}

            {/* CLI: Status Pill */}
            {activeTab === 'cli' && (
              <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-2xl bg-ground border border-line text-micro font-mono text-ink-3">
                <ShieldCheck className="w-4 h-4 text-signal" />
                <span>Single-Pass Deterministic</span>
              </div>
            )}

            {/* Mesh: Status Pill */}
            {activeTab === 'mesh' && (
              <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-2xl bg-ground border border-line text-micro font-mono text-ink-3">
                <Boxes className="w-4 h-4 text-signal" />
                <span>SkyLoom RPC Mesh Wire</span>
              </div>
            )}

            {/* Stdlib: Builtin Counter Pill */}
            {activeTab === 'stdlib' && (
              <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-2xl bg-ground border border-line text-micro font-mono text-ink-3">
                <BookOpen className="w-4 h-4 text-signal" />
                <span>107 Pure Builtins</span>
              </div>
            )}
          </div>
        </div>

        {/* 1. CLI & Workflow */}
        {activeTab === 'cli' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-5">
              <div className="flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
                  <Terminal className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-bold text-ink text-lg">CLI Toolchain Commands</h3>
                  <p className="font-mono text-micro text-ink-3">Unified developer & autonomous agent workflow</p>
                </div>
              </div>

              <div className="space-y-3 font-mono text-meta">
                <div className="p-3.5 rounded-2xl bg-ground border border-line space-y-1">
                  <div className="text-ink font-semibold">
                    <span className="text-signal">$ </span>asl run &lt;file.asl&gt;
                  </div>
                  <p className="text-micro text-ink-3">Executes program inside the fast Wasm/native runner isolate with sandboxed I/O.</p>
                </div>
                <div className="p-3.5 rounded-2xl bg-ground border border-line space-y-1">
                  <div className="text-ink font-semibold">
                    <span className="text-signal">$ </span>asl fmt &lt;file.asl&gt;
                  </div>
                  <p className="text-micro text-ink-3">Deterministic AST formatter enforcing canonical parens and indentation.</p>
                </div>
                <div className="p-3.5 rounded-2xl bg-ground border border-line space-y-1">
                  <div className="text-ink font-semibold">
                    <span className="text-signal">$ </span>asl lint --fix
                  </div>
                  <p className="text-micro text-ink-3">Autonomous smell detector and structural AST auto-repair engine.</p>
                </div>
                <div className="p-3.5 rounded-2xl bg-ground border border-line space-y-1">
                  <div className="text-ink font-semibold">
                    <span className="text-signal">$ </span>asl topo
                  </div>
                  <p className="text-micro text-ink-3">Calculates architectural dependency DAG and detects circular imports.</p>
                </div>
                <div className="p-3.5 rounded-2xl bg-ground border border-line space-y-1">
                  <div className="text-ink font-semibold">
                    <span className="text-signal">$ </span>asl mcp
                  </div>
                  <p className="text-micro text-ink-3">Launches high-performance Model Context Protocol server for IDE agent pair-programming.</p>
                </div>
              </div>
            </div>

            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-5">
              <div className="flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
                  <ShieldCheck className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-bold text-ink text-lg">Normative Language Invariants</h3>
                  <p className="font-mono text-micro text-ink-3">Guarantees that prevent hallucination & crashes</p>
                </div>
              </div>

              <ul className="space-y-4 text-meta text-ink-2">
                <li className="flex items-start gap-3">
                  <span className="w-2 h-2 rounded-full bg-signal mt-2 shrink-0" />
                  <div>
                    <strong className="text-ink">Single-Pass LL(1) Deterministic Grammar:</strong>
                    <p className="text-meta text-ink-3 mt-0.5">
                      Balanced S-expressions eliminate parsing ambiguities and prevent syntax errors before typechecking begins.
                    </p>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-2 h-2 rounded-full bg-signal mt-2 shrink-0" />
                  <div>
                    <strong className="text-ink">Closed 107 Safe Vocabulary:</strong>
                    <p className="text-meta text-ink-3 mt-0.5">
                      No unvetted imports or random package creep. The compiler rejects any symbol not registered in the closed vocabulary.
                    </p>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-2 h-2 rounded-full bg-signal mt-2 shrink-0" />
                  <div>
                    <strong className="text-ink">Zero Indentation Hazards:</strong>
                    <p className="text-meta text-ink-3 mt-0.5">
                      Unlike Python, whitespace carries zero semantic meaning. LLM line breaks cannot alter control flow or variable scope.
                    </p>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-2 h-2 rounded-full bg-signal mt-2 shrink-0" />
                  <div>
                    <strong className="text-ink">Strict Explicit Type Conversions:</strong>
                    <p className="text-meta text-ink-3 mt-0.5">
                      Numbers never convert implicitly. Mixing I64 and F64 without explicit (float64-to-int64) is a compile-time error.
                    </p>
                  </div>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-2 h-2 rounded-full bg-signal mt-2 shrink-0" />
                  <div>
                    <strong className="text-ink">Sandbox Jailed Isolation:</strong>
                    <p className="text-meta text-ink-3 mt-0.5">
                      All filesystem and socket operations are jailed within memory or explicit workspace paths without host leaks.
                    </p>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        )}

        {/* 2. Agent Mesh (A2A) */}
        {activeTab === 'mesh' && (
          <div className="space-y-6">
            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1">
              <div className="max-w-3xl space-y-3">
                <div className="flex items-center gap-3">
                  <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
                    <Boxes className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="font-bold text-ink text-xl">Agent-to-Agent (A2A) Wire Protocol</h3>
                    <p className="font-mono text-micro text-ink-3">High-frequency S-expression RPC frames for SkyLoom mesh</p>
                  </div>
                </div>
                <p className="text-meta text-ink-2 leading-relaxed">
                  Agents coordinate using compact, single-token keyword frames. Every frame carries an immutable transaction identifier, cryptographic architectural shortcode, and machine-verifiable task intent.
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-3">
                <div className="flex items-center justify-between">
                  <h4 className="font-bold text-ink text-base">Task Dispatch Frame (:task/invoke)</h4>
                  <button
                    onClick={() =>
                      copyToClipboard(
                        `(:frame :task/invoke\n  :tx "tx-9942a"\n  :from "agent/coordinator"\n  :to "agent/sql-optimizer"\n  :payload (:query "SELECT * FROM metrics WHERE p99 > 200"\n            :timeout-ms 5000)\n  :tag "d-9942"\n  :why "Mitigate high latency spike detected in cluster.")`,
                        'mesh-invoke'
                      )
                    }
                    className="p-2 rounded-xl bg-ground hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                  >
                    {copiedKey === 'mesh-invoke' ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                  </button>
                </div>
                <pre className="p-4 rounded-2xl bg-ground border border-line text-purple-300 font-mono text-meta overflow-x-auto leading-relaxed">
{`(:frame :task/invoke
  :tx "tx-9942a"
  :from "agent/coordinator"
  :to "agent/sql-optimizer"
  :payload (:query "SELECT * FROM metrics WHERE p99 > 200"
            :timeout-ms 5000)
  :tag "d-9942"
  :why "Mitigate high latency spike detected in cluster.")`}
                </pre>
              </div>

              <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-3">
                <div className="flex items-center justify-between">
                  <h4 className="font-bold text-ink text-base">Execution Result Frame (:task/complete)</h4>
                  <button
                    onClick={() =>
                      copyToClipboard(
                        `(:frame :task/complete\n  :tx "tx-9942a"\n  :status :ok\n  :result (:scanned 42000 :optimized-ms 1.8)\n  :memory-ref "mem://indexes/p99-idx-01")`,
                        'mesh-complete'
                      )
                    }
                    className="p-2 rounded-xl bg-ground hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                  >
                    {copiedKey === 'mesh-complete' ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                  </button>
                </div>
                <pre className="p-4 rounded-2xl bg-ground border border-line text-purple-300 font-mono text-meta overflow-x-auto leading-relaxed">
{`(:frame :task/complete
  :tx "tx-9942a"
  :status :ok
  :result (:scanned 42000 :optimized-ms 1.8)
  :memory-ref "mem://indexes/p99-idx-01")`}
                </pre>
              </div>
            </div>
          </div>
        )}

        {/* 3. Data & Economy (Side-by-Side: ASL vs JSON/YAML) */}
        {activeTab === 'data' && (
          <div className="space-y-6">
            {DATA_CARDS.map((card) => {
              const targetCode = dataTarget === 'json' ? card.json : card.yaml;
              return (
                <div key={card.id} className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
                  <div className="space-y-1">
                    <h3 className="font-bold text-ink text-lg">{card.title}</h3>
                    <p className="text-meta text-ink-2 leading-relaxed">{card.description}</p>
                  </div>

                  {/* Side-by-side: ASL vs JSON/YAML */}
                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    {/* Left: ASL Source */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-signal px-2 py-0.5 rounded bg-signal/10 border border-signal/20">
                          ASL
                        </span>
                        <button
                          onClick={() => copyToClipboard(card.asl, `${card.id}-asl`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title="Copy ASL"
                        >
                          {copiedKey === `${card.id}-asl` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-purple-300 leading-relaxed overflow-x-auto whitespace-pre">
                        {card.asl}
                      </pre>
                    </div>

                    {/* Right: Compare (JSON / YAML) */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-ink-2 px-2 py-0.5 rounded bg-surface border border-line">
                          {dataTarget}
                        </span>
                        <button
                          onClick={() => copyToClipboard(targetCode, `${card.id}-target`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title={`Copy ${dataTarget.toUpperCase()}`}
                        >
                          {copiedKey === `${card.id}-target` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-ink-2 leading-relaxed overflow-x-auto whitespace-pre">
                        {targetCode}
                      </pre>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* 4. SQL & Query DSL (Side-by-Side: ASL vs SQL Dialects) */}
        {activeTab === 'sql' && (
          <div className="space-y-6">
            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
              <div className="space-y-2 max-w-2xl">
                <div className="flex items-center gap-3">
                  <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
                    <Code2 className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="font-bold text-ink text-xl">Cross-Dialect SQL Generation</h3>
                    <p className="font-mono text-micro text-ink-3">Side-by-side ASL query lowering to target database engines</p>
                  </div>
                </div>
                <p className="text-meta text-ink-2 leading-relaxed">
                  Write type-safe S-expression queries once. ASL compiles dialect-specific quoting, date arithmetic, placeholder bindings, and pagination rules automatically.
                </p>
              </div>

              {/* SQL Dialect Selector */}
              <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line shrink-0 overflow-x-auto">
                <span className="text-micro font-mono uppercase text-ink-3 px-2">Dialect:</span>
                {[
                  { id: 'postgres', label: 'PostgreSQL' },
                  { id: 'mysql', label: 'MySQL' },
                  { id: 'sqlite', label: 'SQLite' },
                  { id: 'mssql', label: 'MSSQL (T-SQL)' },
                  { id: 'oracle', label: 'Oracle' }
                ].map(({ id, label }) => (
                  <button
                    key={id}
                    onClick={() => setSqlDialect(id as SqlDialect)}
                    className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                      sqlDialect === id
                        ? 'bg-signal text-white shadow-sm'
                        : 'text-ink-2 hover:text-ink'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            {/* Side-by-side: ASL Query vs Target SQL Dialect */}
            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
              <div className="space-y-1">
                <h4 className="font-bold text-ink text-lg">Active Admin Telemetry Query</h4>
                <p className="text-meta text-ink-2">
                  Demonstrates case-insensitive matching, native relative date arithmetic, descending ordering, and pagination across dialects.
                </p>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                {/* Left: ASL S-Expression Query */}
                <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-micro uppercase font-bold text-signal px-2 py-0.5 rounded bg-signal/10 border border-signal/20">
                      ASL Query
                    </span>
                    <button
                      onClick={() =>
                        copyToClipboard(
                          `(q/select ["id" "name" "email" "status"]\n  (q/from "users")\n  (q/where (q/and (q/ilike "name" "%admin%")\n                  (q/gte "created_at" (q/date-sub (q/now) 7 :days))\n                  (q/eq "status" "ACTIVE")))\n  (q/order-by "created_at" (q/desc))\n  (q/limit 25)\n  (q/offset 50))`,
                          'sql-asl'
                        )
                      }
                      className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                      title="Copy ASL Query"
                    >
                      {copiedKey === 'sql-asl' ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  <pre className="font-mono text-meta text-purple-300 leading-relaxed overflow-x-auto whitespace-pre">
{`(q/select ["id" "name" "email" "status"]
  (q/from "users")
  (q/where (q/and (q/ilike "name" "%admin%")
                  (q/gte "created_at" (q/date-sub (q/now) 7 :days))
                  (q/eq "status" "ACTIVE")))
  (q/order-by "created_at" (q/desc))
  (q/limit 25)
  (q/offset 50))`}
                  </pre>
                </div>

                {/* Right: Dialect-Specific Generated SQL */}
                <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-micro uppercase font-bold text-ink-2 px-2 py-0.5 rounded bg-surface border border-line">
                      {sqlDialect.toUpperCase()} Dialect
                    </span>
                    <button
                      onClick={() => {
                        const dialectMap: Record<SqlDialect, string> = {
                          postgres: `SELECT "id", "name", "email", "status"\nFROM "users"\nWHERE ("name" ILIKE $1)\n  AND ("created_at" >= NOW() - INTERVAL '7 days')\n  AND ("status" = $2)\nORDER BY "created_at" DESC\nLIMIT 25 OFFSET 50;`,
                          mysql: `SELECT \`id\`, \`name\`, \`email\`, \`status\`\nFROM \`users\`\nWHERE (\`name\` LIKE ?)\n  AND (\`created_at\` >= DATE_SUB(NOW(), INTERVAL 7 DAY))\n  AND (\`status\` = ?)\nORDER BY \`created_at\` DESC\nLIMIT 50, 25;`,
                          sqlite: `SELECT "id", "name", "email", "status"\nFROM "users"\nWHERE ("name" LIKE ?1)\n  AND ("created_at" >= datetime('now', '-7 days'))\n  AND ("status" = ?2)\nORDER BY "created_at" DESC\nLIMIT 25 OFFSET 50;`,
                          mssql: `SELECT [id], [name], [email], [status]\nFROM [users]\nWHERE ([name] LIKE @p1)\n  AND ([created_at] >= DATEADD(day, -7, GETDATE()))\n  AND ([status] = @p2)\nORDER BY [created_at] DESC\nOFFSET 50 ROWS FETCH NEXT 25 ROWS ONLY;`,
                          oracle: `SELECT "id", "name", "email", "status"\nFROM "users"\nWHERE (UPPER("name") LIKE UPPER(:1))\n  AND ("created_at" >= SYSDATE - 7)\n  AND ("status" = :2)\nORDER BY "created_at" DESC\nOFFSET 50 ROWS FETCH NEXT 25 ROWS ONLY;`
                        };
                        copyToClipboard(dialectMap[sqlDialect], 'sql-dialect');
                      }}
                      className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                      title="Copy Generated SQL"
                    >
                      {copiedKey === 'sql-dialect' ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  <pre className="font-mono text-meta text-ink-2 leading-relaxed overflow-x-auto whitespace-pre">
                    {sqlDialect === 'postgres' &&
`SELECT "id", "name", "email", "status"
FROM "users"
WHERE ("name" ILIKE $1)
  AND ("created_at" >= NOW() - INTERVAL '7 days')
  AND ("status" = $2)
ORDER BY "created_at" DESC
LIMIT 25 OFFSET 50;`}
                    {sqlDialect === 'mysql' &&
`SELECT \`id\`, \`name\`, \`email\`, \`status\`
FROM \`users\`
WHERE (\`name\` LIKE ?)
  AND (\`created_at\` >= DATE_SUB(NOW(), INTERVAL 7 DAY))
  AND (\`status\` = ?)
ORDER BY \`created_at\` DESC
LIMIT 50, 25;`}
                    {sqlDialect === 'sqlite' &&
`SELECT "id", "name", "email", "status"
FROM "users"
WHERE ("name" LIKE ?1)
  AND ("created_at" >= datetime('now', '-7 days'))
  AND ("status" = ?2)
ORDER BY "created_at" DESC
LIMIT 25 OFFSET 50;`}
                    {sqlDialect === 'mssql' &&
`SELECT [id], [name], [email], [status]
FROM [users]
WHERE ([name] LIKE @p1)
  AND ([created_at] >= DATEADD(day, -7, GETDATE()))
  AND ([status] = @p2)
ORDER BY [created_at] DESC
OFFSET 50 ROWS FETCH NEXT 25 ROWS ONLY;`}
                    {sqlDialect === 'oracle' &&
`SELECT "id", "name", "email", "status"
FROM "users"
WHERE (UPPER("name") LIKE UPPER(:1))
  AND ("created_at" >= SYSDATE - 7)
  AND ("status" = :2)
ORDER BY "created_at" DESC
OFFSET 50 ROWS FETCH NEXT 25 ROWS ONLY;`}
                  </pre>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* 5. Syntax & Forms (Side-by-Side: ASL vs Target Language) */}
        {activeTab === 'syntax' && (
          <div className="space-y-6">
            {SYNTAX_CARDS.map((card) => {
              const targetCode = card[targetLang];
              return (
                <div key={card.id} className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
                  <div className="space-y-1">
                    <h3 className="font-bold text-ink text-lg">{card.title}</h3>
                    <p className="text-meta text-ink-2 leading-relaxed">{card.description}</p>
                  </div>

                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    {/* Left: ASL Source */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-signal px-2 py-0.5 rounded bg-signal/10 border border-signal/20">
                          ASL
                        </span>
                        <button
                          onClick={() => copyToClipboard(card.asl, `${card.id}-asl`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title="Copy ASL"
                        >
                          {copiedKey === `${card.id}-asl` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-purple-300 leading-relaxed overflow-x-auto whitespace-pre">
                        {card.asl}
                      </pre>
                    </div>

                    {/* Right: Target Language */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-ink-2 px-2 py-0.5 rounded bg-surface border border-line capitalize">
                          {targetLang}
                        </span>
                        <button
                          onClick={() => copyToClipboard(targetCode, `${card.id}-target`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title={`Copy ${targetLang}`}
                        >
                          {copiedKey === `${card.id}-target` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-ink-2 leading-relaxed overflow-x-auto whitespace-pre">
                        {targetCode}
                      </pre>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* 6. Control & Errors (Side-by-Side: ASL vs Target Language) */}
        {activeTab === 'control' && (
          <div className="space-y-6">
            {CONTROL_CARDS.map((card) => {
              const targetCode = card[targetLang];
              return (
                <div key={card.id} className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
                  <div className="space-y-1">
                    <h3 className="font-bold text-ink text-lg">{card.title}</h3>
                    <p className="text-meta text-ink-2 leading-relaxed">{card.description}</p>
                  </div>

                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    {/* Left: ASL Source */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-signal px-2 py-0.5 rounded bg-signal/10 border border-signal/20">
                          ASL
                        </span>
                        <button
                          onClick={() => copyToClipboard(card.asl, `${card.id}-asl`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title="Copy ASL"
                        >
                          {copiedKey === `${card.id}-asl` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-purple-300 leading-relaxed overflow-x-auto whitespace-pre">
                        {card.asl}
                      </pre>
                    </div>

                    {/* Right: Target Language */}
                    <div className="rounded-2xl bg-ground border border-line p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="font-mono text-micro uppercase font-bold text-ink-2 px-2 py-0.5 rounded bg-surface border border-line capitalize">
                          {targetLang}
                        </span>
                        <button
                          onClick={() => copyToClipboard(targetCode, `${card.id}-target`)}
                          className="p-1.5 rounded-lg bg-surface hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                          title={`Copy ${targetLang}`}
                        >
                          {copiedKey === `${card.id}-target` ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
                        </button>
                      </div>
                      <pre className="font-mono text-meta text-ink-2 leading-relaxed overflow-x-auto whitespace-pre">
                        {targetCode}
                      </pre>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* 7. Standard Library */}
        {activeTab === 'stdlib' && (
          <div className="space-y-6">
            <div className="relative max-w-md">
              <Search className="w-4 h-4 text-ink-3 absolute left-3.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search builtins (+, mod, list-get, string-concat)..."
                className="w-full pl-10 pr-4 py-2.5 rounded-2xl bg-surface border border-line focus:border-signal outline-none font-mono text-meta text-ink transition-colors"
              />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredBuiltins.map((b) => (
                <div
                  key={b.name}
                  className="p-4 rounded-2xl border border-line bg-surface shadow-e1 hover:border-signal/40 transition-all flex flex-col justify-between space-y-2"
                >
                  <div>
                    <div className="flex items-center justify-between">
                      <span className="font-mono font-bold text-signal text-base">{b.name}</span>
                      <span className="text-micro font-mono uppercase px-2 py-0.5 rounded bg-purple-500/10 text-purple-400 border border-purple-500/20">
                        {b.category}
                      </span>
                    </div>
                    <code className="block font-mono text-micro text-ink mt-1 bg-ground p-1.5 rounded-lg border border-line overflow-x-auto">
                      {b.signature}
                    </code>
                    <p className="text-meta text-ink-2 mt-2 leading-relaxed">{b.summary}</p>
                  </div>
                </div>
              ))}
            </div>

            {filteredBuiltins.length === 0 && (
              <div className="p-8 text-center text-ink-3 font-mono text-meta border border-line rounded-2xl">
                No builtins match query "{searchQuery}".
              </div>
            )}
          </div>
        )}
      </Section>
    </div>
  );
};
