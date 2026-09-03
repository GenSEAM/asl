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

type LanguageTarget = 'nano' | 'verbose' | 'python' | 'rust' | 'typescript';
type SqlTarget = 'asl' | 'sql' | 'python' | 'rust' | 'typescript';
type DocTab = 'cli' | 'mesh' | 'stdlib' | 'data' | 'syntax' | 'control' | 'sql';

interface PolyglotSnippet {
  title: string;
  description: string;
  category: 'syntax' | 'control';
  nano: string;
  verbose: string;
  python: string;
  rust: string;
  typescript: string;
}

const POLYGLOT_SNIPPETS: PolyglotSnippet[] = [
  {
    category: 'syntax',
    title: 'Schema Declaration & Immutable Product Types',
    description: 'Structured records with typed fields. Transpiles to frozen dataclasses in Python, serde structs in Rust, and read-only interfaces in TypeScript.',
    nano: `(dfs Token
  (:f id Str "Unique token identifier.")
  (:f exp I64 "Unix timestamp expiration."))

(df create-token [(id Str) (ttl I64)] -> Token
  :d "Construct authenticated token record."
  (Token :id id :exp (+ 1700000000 ttl)))`,
    verbose: `(defschema Token
  (:field id Str "Unique token identifier.")
  (:field exp I64 "Unix timestamp expiration."))

(defun create-token [(id Str) (ttl I64)] -> Token
  :doc "Construct authenticated token record."
  (Token :id id :exp (+ 1700000000 ttl)))`,
    python: `@dataclass(frozen=True)
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
}`
  },
  {
    category: 'syntax',
    title: 'Closed Union Types (Sum Types / Enums)',
    description: 'Exhaustive variants checked at compile time. Lowers to tagged unions in TypeScript, native enums in Rust, and variant classes in Python.',
    nano: `(dfe ResultStatus
  (:c ok [(val Str)] "Successful execution.")
  (:c timeout [(ms I64)] "Network timed out.")
  (:c denied [] "Access denied."))

(df status-code [(s ResultStatus)] -> I64
  :d "Map status variant to HTTP status code."
  (mt s
    ((ok _) 200)
    ((timeout _) 504)
    ((denied) 403)))`,
    verbose: `(defenum ResultStatus
  (:case ok [(val Str)] "Successful execution.")
  (:case timeout [(ms I64)] "Network timed out.")
  (:case denied [] "Access denied."))

(defun status-code [(s ResultStatus)] -> I64
  :doc "Map status variant to HTTP status code."
  (match s
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
}`
  },
  {
    category: 'control',
    title: 'Error Bubbling with try & Result',
    description: 'Zero exceptions. `try` unpacks `(ok value)` or bubbles `(err reason)` early. Lowers to `?` in Rust, explicit guards in Python and TypeScript.',
    nano: `(df parse-port [(raw Str)] -> (Result I64 Str)
  :d "Parse port number with bounds verification."
  (let [(p (try (option-to-result (string-to-int64 raw) "Not an integer")))]
    (if (and (>= p 1) (<= p 65535))
      (ok p)
      (err "Port must be between 1 and 65535"))))`,
    verbose: `(defun parse-port [(raw Str)] -> (Result I64 Str)
  :doc "Parse port number with bounds verification."
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
}`
  },
  {
    category: 'control',
    title: 'Tail-Call Recursive Algorithm (Fibonacci)',
    description: 'Guaranteed tail-call optimization in ASL. Emits iterative loops or tail-optimized functions across backends.',
    nano: `(df fib [(n I64)] -> I64
  :d "Tail-recursive Fibonacci sequence."
  (df loop [(i I64) (a I64) (b I64)] -> I64
    (if (= i 0)
      a
      (loop (- i 1) b (+ a b))))
  (loop n 0 1))`,
    verbose: `(defun fib [(n I64)] -> I64
  :doc "Tail-recursive Fibonacci sequence."
  (defun loop [(i I64) (a I64) (b I64)] -> I64
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
}`
  }
];

interface DataSnippet {
  title: string;
  description: string;
  nano: string;
  verbose: string;
}

const DATA_SNIPPETS: DataSnippet[] = [
  {
    title: 'Context Economy: Tabular Matrices',
    description: 'Store uniform record sequences as a single key vector plus compact row vectors, saving over 65% token overhead.',
    nano: `([:id :name :role :level]
 [[101 "Alice" :lead 5]
  [102 "Bob"   :agent 3]
  [103 "Carol" :peer 4]])`,
    verbose: `(list
  (User :id 101 :name "Alice" :role :lead :level 5)
  (User :id 102 :name "Bob"   :role :agent :level 3)
  (User :id 103 :name "Carol" :role :peer  :level 4))`
  },
  {
    title: 'Constant Pool Deduplication (:pool & :ref)',
    description: 'Declare repeated long URLs, schemas, or models once in a shared constant pool, referencing them by single-token index.',
    nano: `(:pool ["https://api.genseam.org/v1/telemetry"
        "claude-3-7-sonnet-20250219"
        "asl/agent-mesh/node-alpha"]
  :events [([:node :model :target :ok]
            [[(:ref 2) (:ref 1) (:ref 0) true]
             [(:ref 2) (:ref 1) (:ref 0) false]]))`,
    verbose: `(:events [([:node :model :target :ok]
           [["asl/agent-mesh/node-alpha" "claude-3-7-sonnet-20250219" "https://api.genseam.org/v1/telemetry" true]
            ["asl/agent-mesh/node-alpha" "claude-3-7-sonnet-20250219" "https://api.genseam.org/v1/telemetry" false]]))`
  },
  {
    title: '1-Token Behavioral Traits & Metadata',
    description: 'Single-token keywords (:tag, :why, :use, :ref, :offload) carry zero BPE token overhead while remaining lexically distinct.',
    nano: `(:tag "d-1eed"
 :why "Eliminate BPE prefix splits and preserve single-token density"
 :use "auth/crypto"
 :offload :storage/opfs)`,
    verbose: `(:decision-tag "d-1eed"
 :architectural-rationale "Eliminate BPE prefix splits and preserve single-token density"
 :import-module "auth/crypto"
 :storage-driver :storage/opfs)`
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
  const [langTarget, setLangTarget] = useState<LanguageTarget>('nano');
  const [sqlTarget, setSqlTarget] = useState<SqlTarget>('asl');
  const [useDataNano, setUseDataNano] = useState<boolean>(true);
  const [copiedIndex, setCopiedIndex] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedIndex(id);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  const filteredPolyglot = POLYGLOT_SNIPPETS.filter((s) => s.category === activeTab);

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
          lead="The definitive guide to CLI toolchains, inter-agent mesh wire frames, standard library functions, context economy matrices, polyglot transpilation targets, and SQL queries."
        />

        {/* Dual Audience Banner */}
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
        <div className="flex flex-col lg:flex-row items-start lg:items-center justify-between gap-4 mb-8 pb-4 border-b border-line">
          <div className="flex flex-wrap gap-2">
            {[
              { id: 'cli', label: '1. CLI & Workflow', icon: Terminal },
              { id: 'mesh', label: '2. Agent Mesh (A2A)', icon: Boxes },
              { id: 'stdlib', label: '3. Standard Library', icon: BookOpen },
              { id: 'data', label: '4. Data & Economy', icon: Database },
              { id: 'syntax', label: '5. Syntax & Forms', icon: Braces },
              { id: 'control', label: '6. Control & Errors', icon: Workflow },
              { id: 'sql', label: '7. SQL & Query DSL', icon: Code2 }
            ].map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setActiveTab(id as DocTab)}
                className={`inline-flex items-center gap-2 px-3.5 py-2 rounded-xl font-mono text-meta font-medium transition-all ${
                  activeTab === id
                    ? 'bg-signal text-white shadow-sm'
                    : 'bg-surface hover:bg-surface-2 text-ink-2 hover:text-ink border border-line'
                }`}
              >
                <Icon className="w-4 h-4" />
                <span>{label}</span>
              </button>
            ))}
          </div>

          {/* Polyglot Target Language Selector for Syntax & Control */}
          {(activeTab === 'syntax' || activeTab === 'control') && (
            <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line shrink-0 overflow-x-auto">
              <span className="text-micro font-mono uppercase text-ink-3 px-2">Target:</span>
              {(['nano', 'verbose', 'python', 'rust', 'typescript'] as LanguageTarget[]).map((lang) => (
                <button
                  key={lang}
                  onClick={() => setLangTarget(lang)}
                  className={`px-2.5 py-1 rounded-xl text-micro font-mono font-semibold transition-all capitalize ${
                    langTarget === lang
                      ? 'bg-signal text-white shadow-sm'
                      : 'text-ink-2 hover:text-ink'
                  }`}
                >
                  {lang === 'nano' ? 'ASL Nano' : lang === 'verbose' ? 'ASL Verbose' : lang}
                </button>
              ))}
            </div>
          )}

          {/* Nano / Verbose Toggle for Data & Economy */}
          {activeTab === 'data' && (
            <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line shrink-0">
              <span className="text-micro font-mono uppercase text-ink-3 px-2">Projection:</span>
              <button
                onClick={() => setUseDataNano(true)}
                className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                  useDataNano ? 'bg-signal text-white shadow-sm' : 'text-ink-2 hover:text-ink'
                }`}
              >
                Nano
              </button>
              <button
                onClick={() => setUseDataNano(false)}
                className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                  !useDataNano ? 'bg-signal text-white shadow-sm' : 'text-ink-2 hover:text-ink'
                }`}
              >
                Verbose
              </button>
            </div>
          )}
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
                    <span className="text-signal">$ </span>asl transcode &lt;file.asl&gt; --to nano|verbose
                  </div>
                  <p className="text-micro text-ink-3">Dual-projection lossless transcoder between human-readable and token-dense formats.</p>
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
                    {copiedIndex === 'mesh-invoke' ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
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
                    {copiedIndex === 'mesh-complete' ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
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

        {/* 3. Standard Library */}
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

        {/* 4. Data & Economy */}
        {activeTab === 'data' && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {DATA_SNIPPETS.map((snippet, idx) => {
              const code = useDataNano ? snippet.nano : snippet.verbose;
              const snippetId = `data-${idx}`;
              const isCopied = copiedIndex === snippetId;

              return (
                <div
                  key={snippet.title}
                  className="p-6 rounded-3xl border border-line bg-surface shadow-e1 flex flex-col justify-between hover:border-signal/30 transition-all space-y-4"
                >
                  <div className="space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-bold text-ink text-base">{snippet.title}</h3>
                      <button
                        onClick={() => copyToClipboard(code, snippetId)}
                        className="p-1.5 rounded-xl bg-ground hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all shrink-0"
                      >
                        {isCopied ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                      </button>
                    </div>
                    <p className="text-meta text-ink-2 leading-relaxed">{snippet.description}</p>
                  </div>

                  <div className="rounded-2xl bg-ground border border-line p-3.5 font-mono text-meta overflow-x-auto">
                    <pre className="text-purple-300 dark:text-purple-200 leading-relaxed whitespace-pre font-mono">
                      {code}
                    </pre>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* 5. Syntax & Forms & 6. Control & Errors (Polyglot Lowering) */}
        {(activeTab === 'syntax' || activeTab === 'control') && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {filteredPolyglot.map((snippet, idx) => {
              const code = snippet[langTarget];
              const snippetId = `${activeTab}-${idx}-${langTarget}`;
              const isCopied = copiedIndex === snippetId;

              return (
                <div
                  key={snippet.title}
                  className="p-6 rounded-3xl border border-line bg-surface shadow-e1 flex flex-col justify-between hover:border-signal/30 transition-all"
                >
                  <div className="space-y-3">
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <h3 className="font-bold text-ink text-base sm:text-lg">{snippet.title}</h3>
                        <p className="text-meta text-ink-2 mt-1 leading-relaxed">{snippet.description}</p>
                      </div>
                      <button
                        onClick={() => copyToClipboard(code, snippetId)}
                        className="p-2 rounded-xl bg-ground hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all shrink-0"
                        title="Copy code"
                      >
                        {isCopied ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                      </button>
                    </div>

                    <div className="relative rounded-2xl bg-ground border border-line p-4 font-mono text-meta overflow-x-auto">
                      <div className="absolute top-2 right-2 text-micro uppercase font-semibold text-signal px-2 py-0.5 rounded bg-signal/10 border border-signal/20">
                        {langTarget === 'nano' ? 'asl-nano' : langTarget === 'verbose' ? 'asl-verbose' : langTarget}
                      </div>
                      <pre className="text-purple-300 dark:text-purple-200 leading-relaxed whitespace-pre font-mono pt-4">
                        {code}
                      </pre>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* 7. SQL & Query DSL */}
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
                    <p className="font-mono text-micro text-ink-3">ASL S-expression queries transpiled to target SQL and native database clients</p>
                  </div>
                </div>
                <p className="text-meta text-ink-2 leading-relaxed">
                  Write queries once in type-safe AgentScript S-expressions. The compiler optimizes predicate logic, parameter bindings, and emits production-ready SQL and client code.
                </p>
              </div>

              {/* Target Selector */}
              <div className="flex items-center gap-1.5 bg-ground p-1.5 rounded-2xl border border-line shrink-0 overflow-x-auto">
                <span className="text-micro font-mono uppercase text-ink-3 px-2">Target:</span>
                {[
                  { id: 'asl', label: 'ASL Query' },
                  { id: 'sql', label: 'Standard SQL' },
                  { id: 'python', label: 'Python (psycopg2)' },
                  { id: 'rust', label: 'Rust (sqlx)' },
                  { id: 'typescript', label: 'TypeScript (Kysely)' }
                ].map(({ id, label }) => (
                  <button
                    key={id}
                    onClick={() => setSqlTarget(id as SqlTarget)}
                    className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                      sqlTarget === id
                        ? 'bg-signal text-white shadow-sm'
                        : 'text-ink-2 hover:text-ink'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            {/* SQL Query Example Box */}
            <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-bold text-ink text-lg">Active High-Priority Users Query</h4>
                  <p className="text-meta text-ink-2">Multi-predicate filter, descending timestamp ordering, and pagination.</p>
                </div>
                <button
                  onClick={() => {
                    const codeMap = {
                      asl: `(q/select ["id" "name" "email" "status"]\n  (q/from "users")\n  (q/where (q/and (q/eq "status" "active")\n                  (q/gt "login_count" 5)))\n  (q/order-by "created_at" (q/desc))\n  (q/limit 25)\n  (q/offset 0))`,
                      sql: `SELECT "id", "name", "email", "status"\nFROM "users"\nWHERE ("status" = $1) AND ("login_count" > $2)\nORDER BY "created_at" DESC\nLIMIT 25 OFFSET 0;`,
                      python: `cursor.execute(\n    """\n    SELECT id, name, email, status\n    FROM users\n    WHERE status = %s AND login_count > %s\n    ORDER BY created_at DESC\n    LIMIT 25 OFFSET 0;\n    """,\n    ("active", 5)\n)\nactive_users = [User(*row) for row in cursor.fetchall()]`,
                      rust: `let users = sqlx::query_as!(\n    User,\n    r#"\n    SELECT id, name, email, status\n    FROM users\n    WHERE status = $1 AND login_count > $2\n    ORDER BY created_at DESC\n    LIMIT 25 OFFSET 0\n    "#,\n    "active", 5i64\n).fetch_all(&pool).await?;`,
                      typescript: `const users = await db.selectFrom('users')\n  .select(['id', 'name', 'email', 'status'])\n  .where('status', '=', 'active')\n  .where('login_count', '>', 5)\n  .orderBy('created_at', 'desc')\n  .limit(25)\n  .offset(0)\n  .execute();`
                    };
                    copyToClipboard(codeMap[sqlTarget], 'sql-copy');
                  }}
                  className="p-2 rounded-xl bg-ground hover:bg-surface-2 border border-line text-ink-2 hover:text-ink transition-all"
                >
                  {copiedIndex === 'sql-copy' ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                </button>
              </div>

              <div className="rounded-2xl bg-ground border border-line p-5 font-mono text-meta overflow-x-auto">
                <pre className="text-purple-300 dark:text-purple-200 leading-relaxed whitespace-pre font-mono">
                  {sqlTarget === 'asl' &&
`(q/select ["id" "name" "email" "status"]
  (q/from "users")
  (q/where (q/and (q/eq "status" "active")
                  (q/gt "login_count" 5)))
  (q/order-by "created_at" (q/desc))
  (q/limit 25)
  (q/offset 0))`}
                  {sqlTarget === 'sql' &&
`-- Generated parameterized SQL (PostgreSQL dialect)
SELECT "id", "name", "email", "status"
FROM "users"
WHERE ("status" = $1) AND ("login_count" > $2)
ORDER BY "created_at" DESC
LIMIT 25 OFFSET 0;

-- Parameters:
--   $1 = 'active' (String)
--   $2 = 5 (Int64)`}
                  {sqlTarget === 'python' &&
`# Python Client Integration (psycopg2 / asyncpg)
cursor.execute(
    """
    SELECT id, name, email, status
    FROM users
    WHERE status = %s AND login_count > %s
    ORDER BY created_at DESC
    LIMIT 25 OFFSET 0;
    """,
    ("active", 5)
)
active_users = [User(*row) for row in cursor.fetchall()]`}
                  {sqlTarget === 'rust' &&
`// Rust Client Integration (sqlx async connection pool)
let users = sqlx::query_as!(
    User,
    r#"
    SELECT id, name, email, status
    FROM users
    WHERE status = $1 AND login_count > $2
    ORDER BY created_at DESC
    LIMIT 25 OFFSET 0
    "#,
    "active",
    5i64
).fetch_all(&pool).await?;`}
                  {sqlTarget === 'typescript' &&
`// TypeScript Client Integration (Kysely Type-Safe Query Builder)
const users = await db.selectFrom('users')
  .select(['id', 'name', 'email', 'status'])
  .where('status', '=', 'active')
  .where('login_count', '>', 5)
  .orderBy('created_at', 'desc')
  .limit(25)
  .offset(0)
  .execute();`}
                </pre>
              </div>
            </div>
          </div>
        )}
      </Section>
    </div>
  );
};
