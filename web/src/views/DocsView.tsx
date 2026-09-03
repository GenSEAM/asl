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

interface CodeSnippetProps {
  title: string;
  description: string;
  nanoCode: string;
  verboseCode: string;
  category: string;
}

const SNIPPETS: CodeSnippetProps[] = [
  {
    category: 'syntax',
    title: 'Module Declaration & Type Exports',
    description: 'Every file is a self-contained module. By default, declarations are private unless explicitly exported in :x / :export.',
    nanoCode: `(module auth/crypto
  :d "Cryptographic tokens and salted hashes."
  :x [hash-password verify-token Token]
  :i [(sys/time :a time)
      (data/json :a json)])

(dfs Token
  (:f id Str "Unique token identifier.")
  (:f exp I64 "Unix timestamp expiration."))`,
    verboseCode: `(module auth/crypto
  :doc "Cryptographic tokens and salted hashes."
  :export [hash-password verify-token Token]
  :import [(sys/time :as time)
           (data/json :as json)])

(defschema Token
  (:field id Str "Unique token identifier.")
  (:field exp I64 "Unix timestamp expiration."))`
  },
  {
    category: 'syntax',
    title: 'Closed Union Types (Enums)',
    description: 'Enums describe sum types. Pattern matchers enforce exhaustive checking so unhandled variants are rejected at compile time.',
    nanoCode: `(dfe ResultStatus
  (:c ok [(val Str)] "Successful execution.")
  (:c timeout [(ms I64)] "Network timed out.")
  (:c denied [] "Access denied."))

(df status-code [(s ResultStatus)] -> I64
  :d "Map status variant to HTTP status code."
  (mt s
    ((ok _) 200)
    ((timeout _) 504)
    ((denied) 403)))`,
    verboseCode: `(defenum ResultStatus
  (:case ok [(val Str)] "Successful execution.")
  (:case timeout [(ms I64)] "Network timed out.")
  (:case denied [] "Access denied."))

(defun status-code [(s ResultStatus)] -> I64
  :doc "Map status variant to HTTP status code."
  (match s
    ((ok _) 200)
    ((timeout _) 504)
    ((denied) 403)))`
  },
  {
    category: 'control',
    title: 'Error Bubbling with try & Result',
    description: 'try unwraps (ok value) or bubbles up (err reason) immediately from functions returning Result. No exceptions, no hidden throws.',
    nanoCode: `(df parse-port [(raw Str)] -> (Result I64 Str)
  :d "Parse port number with bounds verification."
  (let [(p (try (option-to-result (string-to-int64 raw) "Not an integer")))]
    (if (and (>= p 1) (<= p 65535))
      (ok p)
      (err "Port must be between 1 and 65535"))))`,
    verboseCode: `(defun parse-port [(raw Str)] -> (Result I64 Str)
  :doc "Parse port number with bounds verification."
  (let [(p (try (option-to-result (string-to-int64 raw) "Not an integer")))]
    (if (and (>= p 1) (<= p 65535))
      (ok p)
      (err "Port must be between 1 and 65535"))))`
  },
  {
    category: 'control',
    title: 'Pattern Matching with Guards & Destructuring',
    description: 'Deconstruct lists, options, records, and tuples with concise, expressive pattern arms.',
    nanoCode: `(df inspect-queue [(items (List I64))] -> Str
  :d "Classify incoming queue workload."
  (mt items
    (() "Queue is empty")
    ((cons x ()) (string-concat "Single item: " (int64-to-string x)))
    ((cons x rest) (string-concat "Batch with head: " (int64-to-string x)))))`,
    verboseCode: `(defun inspect-queue [(items (List I64))] -> Str
  :doc "Classify incoming queue workload."
  (match items
    (() "Queue is empty")
    ((cons x ()) (string-concat "Single item: " (int64-to-string x)))
    ((cons x rest) (string-concat "Batch with head: " (int64-to-string x)))))`
  },
  {
    category: 'data',
    title: 'Context Economy: Tabular Matrices',
    description: 'Represent tabular lists of uniform records as a single key vector plus compact row vectors, saving over 65% token overhead.',
    nanoCode: `([:id :name :role :level]
 [[101 "Alice" :lead 5]
  [102 "Bob"   :agent 3]
  [103 "Carol" :peer 4]])`,
    verboseCode: `(list
  (User :id 101 :name "Alice" :role :lead :level 5)
  (User :id 102 :name "Bob"   :role :agent :level 3)
  (User :id 103 :name "Carol" :role :peer  :level 4))`
  },
  {
    category: 'data',
    title: 'Constant Pool Deduplication (:pool & :ref)',
    description: 'Declare repeated long URLs, schemas, or models once in a shared constant pool, referencing them by single-token index.',
    nanoCode: `(:pool ["https://api.genseam.org/v1/telemetry"
        "claude-3-7-sonnet-20250219"
        "asl/agent-mesh/node-alpha"]
  :events [([:node :model :target :ok]
            [[(:ref 2) (:ref 1) (:ref 0) true]
             [(:ref 2) (:ref 1) (:ref 0) false]]))`,
    verboseCode: `(:events [([:node :model :target :ok]
           [["asl/agent-mesh/node-alpha" "claude-3-7-sonnet-20250219" "https://api.genseam.org/v1/telemetry" true]
            ["asl/agent-mesh/node-alpha" "claude-3-7-sonnet-20250219" "https://api.genseam.org/v1/telemetry" false]]))`
  },
  {
    category: 'mesh',
    title: 'Agent-to-Agent (A2A) Task Frame',
    description: 'Standardized inter-agent wire protocol frame for zero-latency, type-checked task distribution.',
    nanoCode: `(:frame :task/invoke
  :tx "tx-9942a"
  :from "agent/coordinator"
  :to "agent/sql-optimizer"
  :payload (:query "SELECT * FROM metrics WHERE p99 > 200"
            :timeout-ms 5000)
  :tag "d-9942"
  :why "Mitigate high latency spike detected in cluster.")`,
    verboseCode: `(:frame :task/invoke
  :transaction-id "tx-9942a"
  :source-agent "agent/coordinator"
  :target-agent "agent/sql-optimizer"
  :payload (:query "SELECT * FROM metrics WHERE p99 > 200"
            :timeout-ms 5000)
  :tag "d-9942"
  :rationale "Mitigate high latency spike detected in cluster.")`
  },
  {
    category: 'data',
    title: 'Record Construction & Field Access',
    description: 'Records are immutable product types. Construct with keyword arguments and read fields with (.-field record).',
    nanoCode: `(dfs Coord
  (:f x F64 "X coordinate.")
  (:f y F64 "Y coordinate."))

(df translate [(p Coord) (dx F64) (dy F64)] -> Coord
  :d "Move point by delta vector."
  (Coord :x (+ (.-x p) dx)
         :y (+ (.-y p) dy)))`,
    verboseCode: `(defschema Coord
  (:field x F64 "X coordinate.")
  (:field y F64 "Y coordinate."))

(defun translate [(p Coord) (dx F64) (dy F64)] -> Coord
  :doc "Move point by delta vector."
  (Coord :x (+ (.-x p) dx)
         :y (+ (.-y p) dy)))`
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
  { name: '/', category: 'math', signature: '(/ a b)', summary: 'Integer or floating-point division.' },
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
  const [activeTab, setActiveTab] = useState<'syntax' | 'data' | 'control' | 'mesh' | 'stdlib' | 'cli'>('syntax');
  const [useNano, setUseNano] = useState<boolean>(true);
  const [copiedIndex, setCopiedIndex] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedIndex(id);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  const filteredSnippets = SNIPPETS.filter((s) => s.category === activeTab);

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
          lead="The definitive guide to AgentScript syntax, token economy matrices, control flow idioms, inter-agent mesh wire protocols, and CLI toolchain."
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

        {/* Category Navigation Bar & Projection Switch */}
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 mb-8 pb-4 border-b border-line">
          <div className="flex flex-wrap gap-2">
            {[
              { id: 'syntax', label: 'Syntax & Forms', icon: Braces },
              { id: 'data', label: 'Data & Economy', icon: Database },
              { id: 'control', label: 'Control & Errors', icon: Workflow },
              { id: 'mesh', label: 'Agent Mesh (A2A)', icon: Boxes },
              { id: 'stdlib', label: 'Standard Library', icon: BookOpen },
              { id: 'cli', label: 'CLI & Workflow', icon: Terminal }
            ].map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setActiveTab(id as any)}
                className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl font-mono text-meta font-medium transition-all ${
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

          {/* Nano vs Verbose Toggle */}
          {activeTab !== 'stdlib' && activeTab !== 'cli' && (
            <div className="flex items-center gap-2 bg-ground p-1.5 rounded-2xl border border-line shrink-0">
              <span className="text-micro font-mono uppercase text-ink-3 px-2">Projection:</span>
              <button
                onClick={() => setUseNano(true)}
                className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                  useNano
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-2 hover:text-ink'
                }`}
              >
                Nano
              </button>
              <button
                onClick={() => setUseNano(false)}
                className={`px-3 py-1 rounded-xl text-micro font-mono font-semibold transition-all ${
                  !useNano
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-2 hover:text-ink'
                }`}
              >
                Verbose
              </button>
            </div>
          )}
        </div>

        {/* Tab Content: Code Snippets (Syntax, Data, Control, Mesh) */}
        {activeTab !== 'stdlib' && activeTab !== 'cli' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {filteredSnippets.map((snippet, idx) => {
              const code = useNano ? snippet.nanoCode : snippet.verboseCode;
              const snippetId = `${activeTab}-${idx}`;
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
                      <div className="absolute top-2 right-2 text-micro uppercase font-semibold text-ink-3 px-2 py-0.5 rounded bg-surface/50">
                        {useNano ? 'nano' : 'verbose'}
                      </div>
                      <pre className="text-purple-300 dark:text-purple-200 leading-relaxed whitespace-pre font-mono">
                        {code}
                      </pre>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Tab Content: Standard Library Explorer */}
        {activeTab === 'stdlib' && (
          <div className="space-y-6">
            {/* Search Box */}
            <div className="relative max-w-md">
              <Search className="w-4 h-4 text-ink-3 absolute left-3.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search builtins (+, list-get, string-concat)..."
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

        {/* Tab Content: CLI Toolchain & Invariants */}
        {activeTab === 'cli' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-5">
              <div className="flex items-center gap-3">
                <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
                  <Terminal className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-bold text-ink text-lg">CLI Toolchain Commands</h3>
                  <p className="font-mono text-micro text-ink-3">Unified developer & agent workflow</p>
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
      </Section>
    </div>
  );
};
