import React, { useState, useMemo } from 'react';
import {
  Cpu,
  Zap,
  Terminal,
  Eye,
  Globe2,
  Database,
  Radio,
  Boxes,
  Copy,
  Check,
  Search,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Code2
} from 'lucide-react';

export interface PackageSpec {
  id: string;
  name: string;
  stage: 'Stage 1: Core' | 'Stage 2: Harness' | 'Stage 3: Visual';
  stageNum: 1 | 2 | 3;
  status: 'Stable' | 'Active' | 'Preview';
  tagline: string;
  description: string;
  icon: React.ComponentType<{ className?: string }>;
  metrics: { label: string; value: string }[];
  highlights: string[];
  interfaces: string[];
  installCmd: string;
  codeSnippet: {
    lang: string;
    filename: string;
    code: string;
  };
}

export const PACKAGES: PackageSpec[] = [
  {
    id: '@genseam/asl-codec',
    name: 'asl-codec',
    stage: 'Stage 1: Core',
    stageNum: 1,
    status: 'Stable',
    tagline: 'Universal ASN codec with 57%–65% token compaction over JSON',
    description: 'Universal AgentScript Notation (ASN) reader, writer, and algebraic serializer. Slashes LLM token consumption by eliminating punctuation deadweight (braces, quotes, colons) and hoisting tabular schemas into single positional headers.',
    icon: Database,
    metrics: [
      { label: 'Token Compaction', value: '57%–65% vs JSON' },
      { label: '100-Row Dataset', value: '1,601 vs 3,802 tokens' },
      { label: 'Syntax Overhead', value: '0 Braces / Quotes' },
      { label: 'Grammar', value: 'Single-Pass LL(1)' },
    ],
    highlights: [
      'Hoists repetitive schema keys once into header vector',
      'Encodes tabular batches as compact positional value tuples',
      'Isomorphic transcode between human ASL and compact ASN',
      'Single-pass LL(1) parse eliminates syntax repair loops',
    ],
    interfaces: ['(asn/encode)', '(asn/decode)', '(asn/encode-table)', '(asn/validate)'],
    installCmd: 'asl pkg add @genseam/asl-codec',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'data/exchange.asl',
      code: `(module data/exchange
  :d "Universal ASN tabular serialization with hoisted schema."
  :i [(asl-codec/asn :a asn)])

;; Hoists schema keys once; streams 57% fewer tokens than JSON
(asn/encode-table
  [:id :sku :qty :status]
  [[101 "A-44" 5 "shipped"]
   [102 "B-12" 1 "pending"]
   [103 "C-99" 12 "delivered"]])`,
    },
  },
  {
    id: '@genseam/asl-sh',
    name: 'asl-sh',
    stage: 'Stage 1: Core',
    stageNum: 1,
    status: 'Stable',
    tagline: 'Process guard, streaming reducer with window retention and middle eviction',
    description: 'High-assurance process execution toolkit with structured pipelines and typed channel redirection. Features a pure streaming reducer with head/tail window retention, middle eviction markers, consecutive duplicate suppression, ANSI stripping, and zero shell injection vulnerabilities.',
    icon: Terminal,
    metrics: [
      { label: 'Shell Injections', value: '0 Vectors' },
      { label: 'Window Retention', value: '500h / 1500t' },
      { label: 'Middle Eviction', value: 'Automatic Markers' },
      { label: 'Dedup Suppression', value: '100% Repeats' },
    ],
    highlights: [
      'Direct execve/posix_spawn invocation preventing shell injection bugs',
      'Head/tail retention windowing prevents context window exhaustion',
      'Evicts middle noise with "... [N lines evicted from buffer] ..."',
      'Automated semantic test and compiler diagnostic extraction',
    ],
    interfaces: ['(proc/cmd)', '(proc/exec!)', '(reducer/reduce-stream)', '(reducer/default-config)'],
    installCmd: 'asl pkg add @genseam/asl-sh',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'admin/pipeline.asl',
      code: `(module admin/pipeline
  :d "Run compiler tasks with head/tail retention windowing."
  :i [(asl-sh/process :a proc)
      (asl-sh/reducer :a reducer)])

;; Direct posix_spawn execution streamed into windowing reducer
(let [(cmd (proc/cmd "cargo" ["test" "--all"]))
      (stream (proc/exec-stream! cmd))]
  (reducer/reduce-stream stream
    (reducer/ReductionConfig :head-limit 500 :tail-limit 1500 :dedup-repeats true)))`,
    },
  },
  {
    id: '@genseam/asl-agent-core',
    name: 'asl-agent-core',
    stage: 'Stage 2: Harness',
    stageNum: 2,
    status: 'Active',
    tagline: 'Onion middleware pipeline, capability negotiator',
    description: 'The composable execution engine for autonomous agents. Houses a modular onion middleware pipeline supporting pre-call, post-call, filter, mutate, and audit hooks with topological DAG ordering, dynamic capability negotiation, and structured tool dispatch.',
    icon: Cpu,
    metrics: [
      { label: 'Dispatch Latency', value: '<0.05ms' },
      { label: 'Ordering Engine', value: 'Topological DAG' },
      { label: 'Middleware Hooks', value: '5 Extension Types' },
      { label: 'Permission Gates', value: 'Zero-Prompt' },
    ],
    highlights: [
      'Topological DAG ordering ensures correct hook execution order',
      'Pre-call, post-call, filter, mutate, and audit middleware hooks',
      'Dynamic capability negotiator enforcing strict permission boundaries',
      'Unified tool registry with formal parameter schemas and event bus',
    ],
    interfaces: ['(OnionPipeline)', '(dispatch-tool-call)', '(make-middleware)', '(AgentRegistry)'],
    installCmd: 'asl pkg add @genseam/asl-agent-core',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'agent/supervisor.asl',
      code: `(module agent/supervisor
  :d "Onion middleware dispatch with topological DAG ordering."
  :i [(asl-agent-core/onion :a onion)
      (asl-agent-core/core :a core)])

;; Register security and telemetry hooks with topological dependencies
(let [(auth-mw  (onion/make-middleware "auth" "Capability Gate" onion/kind-filter 10 [] []))
      (audit-mw (onion/make-middleware "audit" "Telemetry Logger" onion/kind-audit 20 ["auth"] []))
      (pipeline (onion/make-pipeline [auth-mw audit-mw]))]
  (onion/dispatch-tool-call pipeline context tool-call))`,
    },
  },
  {
    id: '@genseam/asl-shrody',
    name: 'asl-shrody',
    stage: 'Stage 2: Harness',
    stageNum: 2,
    status: 'Active',
    tagline: 'Sandboxed voice & ReAct agent core, <100ms launch, zero-prompt capability permissions',
    description: 'High-velocity ReAct agent runtime engineered for instant voice and autonomous workflows. Launches in under 100ms with a strict <=24MB RSS ceiling, zero permission prompts for authorized workspace paths, and conversational barge-in latency under 5ms.',
    icon: Zap,
    metrics: [
      { label: 'Cold Start', value: '<100ms' },
      { label: 'RSS Ceiling', value: '<=24MB' },
      { label: 'Barge-In Latency', value: '<5ms' },
      { label: 'Permission Prompts', value: '0 Prompts' },
    ],
    highlights: [
      'Sub-100ms launch speed vs ~2,480ms legacy Node/Transformers',
      '<=24MB RSS peak memory ceiling under concurrent errand load',
      'Zero-prompt declarative capability permissions with path jailing',
      'Instant conversational barge-in cutoff (<5ms) for natural speech',
    ],
    interfaces: ['(execute-react-loop)', '(triage-intent)', '(workspace-jail)', '(barge-in-cutoff)'],
    installCmd: 'asl pkg add @genseam/asl-shrody',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'voice/assistant.asl',
      code: `(module voice/assistant
  :d "Low-latency voice assistant with instant barge-in cutoff."
  :i [(asl-shrody/agent :a shrody)
      (asl-shrody/policy :a policy)])

;; Jailed ReAct loop with <100ms launch and zero permission prompts
(shrody/execute-react-loop
  :intent (shrody/triage-intent user-speech-frame)
  :policy (policy/workspace-jail "/workspace" :allow-read-only ["/tmp"])
  :barge-in-ms 5)`,
    },
  },
  {
    id: '@genseam/asl-agent-bus',
    name: 'asl-agent-bus',
    stage: 'Stage 2: Harness',
    stageNum: 2,
    status: 'Active',
    tagline: 'High-frequency in-memory Unix socket & SSE A2A mesh bus',
    description: 'Sub-millisecond inter-agent communication mesh with Model Context Protocol (MCP) bridge. Subagents stay warm in-memory, listening on local Unix domain sockets and Server-Sent Events (SSE) streams, exchanging compact ASL frames at <0.04ms latency with zero cold-start delay.',
    icon: Radio,
    metrics: [
      { label: 'Socket Latency', value: '<0.04ms' },
      { label: 'Cold Start Delay', value: '0ms (Warm)' },
      { label: 'Wire Reduction', value: '-78% vs Chat' },
      { label: 'Transports', value: 'Unix Socket, SSE, MCP' },
    ],
    highlights: [
      'Sub-millisecond IPC over in-memory Unix domain sockets and SSE',
      'Zero cold-start delay: subagents stay warm and resident in-memory',
      'Out-of-the-box Model Context Protocol (MCP) JSON-RPC bridge',
      'Replaces conversational chat bloat with typed S-expression frames',
    ],
    interfaces: ['asl bus serve', 'asl bus send', '(bus/publish!)', '(bus/subscribe!)'],
    installCmd: 'asl pkg add @genseam/asl-agent-bus',
    codeSnippet: {
      lang: 'bash',
      filename: 'terminal / bash',
      code: `# Launch local agent bus daemon listening on Unix domain socket
asl bus serve --socket /tmp/asl-bus.sock --port 8765

# Broadcast structured machine frame to warm subagent (<0.04ms latency)
asl bus send agent-coder "(? task/exec :target \"core/asn\")"`,
    },
  },
  {
    id: '@genseam/asl-mem',
    name: 'asl-mem',
    stage: 'Stage 2: Harness',
    stageNum: 2,
    status: 'Active',
    tagline: 'Hierarchical memory matrix & Wasm vector store',
    description: 'Zero-server in-memory vector database and cosine similarity search engine executing inside a 64KB WebAssembly page. Provides sub-0.05ms semantic vector recall, local working memory, session history, and hierarchical knowledge base recall without external database servers.',
    icon: Boxes,
    metrics: [
      { label: 'Wasm Footprint', value: '64KB Page' },
      { label: 'Search Latency', value: '0.038ms (5k vectors)' },
      { label: 'External Servers', value: '0 Required' },
      { label: 'Algorithm', value: 'SIMD Cosine KNN' },
    ],
    highlights: [
      '64KB WebAssembly memory page footprint for extreme portability',
      '0.038ms cosine similarity search across high-dimensional embeddings',
      'Hierarchical tiers: working context, session recall, persistent ledger',
      'Runs identically in-browser, inside edge workers, or on native CLI',
    ],
    interfaces: ['(vmem/init-store)', '(vmem/insert!)', '(vmem/knn-search)', '(vmem/persist)'],
    installCmd: 'asl pkg add @genseam/asl-mem',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'memory/recall.asl',
      code: `(module memory/recall
  :d "Sub-0.05ms local vector recall inside 64KB WebAssembly."
  :i [(asl-mem/vector :a vmem)])

;; Initialize local vector store and query top-k nearest neighbors
(let [(store (vmem/init-store :dim 384 :metric :cosine))]
  (vmem/insert! store "chunk-91" query-vector)
  (vmem/knn-search store query-vector :top-k 5))`,
    },
  },
  {
    id: '@genseam/asl-vdom',
    name: 'asl-vdom',
    stage: 'Stage 3: Visual',
    stageNum: 3,
    status: 'Preview',
    tagline: 'Dual perception AXTree + D2Snap DOM downsampler, TSX declarative UI dialect',
    description: 'Declarative S-expression Virtual DOM renderer and dual perception compaction bridge. Compresses browser DOM and CDP accessibility trees by >=75% for LLMs via D2Snap downsampling, and compiles declarative UI trees into React 19 TSX, Vue 3 render functions, or native Wasm DOM patches.',
    icon: Eye,
    metrics: [
      { label: 'Prompt Reduction', value: '>=75%' },
      { label: 'Target Dialects', value: 'React 19 TSX, Vue 3, Wasm' },
      { label: 'Perception Modes', value: 'AXTree + D2Snap' },
      { label: 'Diffing', value: 'Surgical Mutation Ops' },
    ],
    highlights: [
      'Dual perception downsampling eliminates invisible DOM overhead',
      '>=75% prompt token reduction over verbose browser HTML',
      'Declarative UI dialect compiling directly to modern React 19 TSX',
      'S-expression virtual DOM diffing with surgical patch generation',
    ],
    interfaces: ['(vdom/render)', '(html/div)', '(perception/compact-axtree)', '(vdom/diff)'],
    installCmd: 'asl pkg add @genseam/asl-vdom',
    codeSnippet: {
      lang: 'agentscript',
      filename: 'ui/card.asl',
      code: `(module ui/metrics-card
  :d "Declarative TSX component with compact perception."
  :i [(asl-vdom/html :a h)
      (asl-vdom/perception :a perc)])

;; Declarative UI dialect transpiled directly to React 19 TSX
(df render-card [(title Str) (count I64)] -> h/VNode
  (h/div :class "rounded-2xl border border-line bg-surface p-4"
    [(h/span :class "font-mono text-micro text-signal" title)
     (h/h3 :class "text-h2 font-bold text-ink" (string-from-int64 count))]))`,
    },
  },
  {
    id: '@genseam/asl-browser-plugin',
    name: 'asl-browser-plugin',
    stage: 'Stage 3: Visual',
    stageNum: 3,
    status: 'Preview',
    tagline: 'In-tab agent copilot with in-memory WASI preview1 runner & A2A mesh framing',
    description: 'Cross-browser Manifest V3 extension providing autonomous in-tab execution. Houses an in-memory WASI preview1 runner inside the background service worker, live DOM tree extraction into compact ASL S-expression frames saving 78% tokens, and sub-millisecond A2A mesh communication.',
    icon: Globe2,
    metrics: [
      { label: 'Extension Standard', value: 'Manifest V3' },
      { label: 'Runner Latency', value: '<0.05ms (WASI)' },
      { label: 'DOM Token Savings', value: '78% Compaction' },
      { label: 'Compatibility', value: 'Chrome, Edge, Firefox, Safari' },
    ],
    highlights: [
      'In-memory WASI preview1 execution in browser background service worker',
      'Live DOM compaction saving 78% prompt tokens vs raw HTML',
      'Zero remote DevTools/Selenium protocol latency and flakiness',
      'Direct A2A mesh wire framing for swarm orchestration',
    ],
    interfaces: ['WasiPreview1Runner', 'DomExtractor.extractAslFrame', 'A2AMeshClient'],
    installCmd: 'asl pkg add @genseam/asl-browser-plugin',
    codeSnippet: {
      lang: 'typescript',
      filename: 'background/copilot.ts',
      code: `import { WasiPreview1Runner, DomExtractor } from '@genseam/asl-browser-plugin';

// Run ASL Wasm preview1 directly inside browser service worker
const runner = new WasiPreview1Runner({ wasmModule: compiledAslBytes });
const compactFrame = await DomExtractor.extractAslFrame(activeTabId);

// Stream compact S-expression frame to agent mesh bus
await runner.dispatchA2AFrame(compactFrame);`,
    },
  },
];

export const UnifiedPackageMatrix: React.FC = () => {
  const [selectedStage, setSelectedStage] = useState<number | 'all'>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [expandedCodeId, setExpandedCodeId] = useState<string | null>(null);
  const [copiedCodeId, setCopiedCodeId] = useState<string | null>(null);

  const filteredPackages = useMemo(() => {
    return PACKAGES.filter((pkg) => {
      const matchesStage = selectedStage === 'all' || pkg.stageNum === selectedStage;
      if (!matchesStage) return false;
      if (!searchQuery.trim()) return true;

      const q = searchQuery.toLowerCase();
      return (
        pkg.id.toLowerCase().includes(q) ||
        pkg.name.toLowerCase().includes(q) ||
        pkg.tagline.toLowerCase().includes(q) ||
        pkg.description.toLowerCase().includes(q) ||
        pkg.highlights.some((h) => h.toLowerCase().includes(q)) ||
        pkg.interfaces.some((i) => i.toLowerCase().includes(q))
      );
    });
  }, [selectedStage, searchQuery]);

  const copyInstallCmd = (pkgId: string, cmd: string) => {
    navigator.clipboard.writeText(cmd);
    setCopiedId(pkgId);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const copyCode = (pkgId: string, code: string) => {
    navigator.clipboard.writeText(code);
    setCopiedCodeId(pkgId);
    setTimeout(() => setCopiedCodeId(null), 2000);
  };

  const toggleExpand = (id: string) => {
    setExpandedCodeId((prev) => (prev === id ? null : id));
  };

  return (
    <div className="space-y-10">
      {/* Ecosystem Summary Stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1">
          <span className="font-mono text-micro uppercase text-ink-3">Unified Packages</span>
          <p className="mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono">08</p>
          <span className="text-meta text-signal font-mono mt-1 inline-block">Stages 1–3 Complete</span>
        </div>
        <div className="p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1">
          <span className="font-mono text-micro uppercase text-ink-3">Token Compaction</span>
          <p className="mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono">57%–78%</p>
          <span className="text-meta text-emerald-400 font-mono mt-1 inline-block">Over Verbose JSON</span>
        </div>
        <div className="p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1">
          <span className="font-mono text-micro uppercase text-ink-3">IPC Mesh Latency</span>
          <p className="mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono">&lt;0.04ms</p>
          <span className="text-meta text-signal font-mono mt-1 inline-block">Warm Socket / SSE</span>
        </div>
        <div className="p-4 sm:p-5 rounded-2xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1">
          <span className="font-mono text-micro uppercase text-ink-3">Process Safety</span>
          <p className="mt-1 text-2xl sm:text-3xl font-bold text-ink font-mono">0 Leaks</p>
          <span className="text-meta text-emerald-400 font-mono mt-1 inline-block">Jailed Sandboxing</span>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 p-3 sm:p-4 rounded-2xl border border-line bg-surface/90 backdrop-blur-xl shadow-e1">
        {/* Stage Filter Buttons */}
        <div className="flex flex-wrap items-center gap-1.5 sm:gap-2">
          <button
            type="button"
            onClick={() => setSelectedStage('all')}
            className={`px-3 py-1.5 rounded-xl font-mono text-micro transition-all ${
              selectedStage === 'all'
                ? 'bg-signal text-white font-semibold shadow-sm'
                : 'bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60'
            }`}
          >
            All Packages (8)
          </button>
          <button
            type="button"
            onClick={() => setSelectedStage(1)}
            className={`px-3 py-1.5 rounded-xl font-mono text-micro transition-all ${
              selectedStage === 1
                ? 'bg-signal text-white font-semibold shadow-sm'
                : 'bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60'
            }`}
          >
            Stage 1: Core (2)
          </button>
          <button
            type="button"
            onClick={() => setSelectedStage(2)}
            className={`px-3 py-1.5 rounded-xl font-mono text-micro transition-all ${
              selectedStage === 2
                ? 'bg-signal text-white font-semibold shadow-sm'
                : 'bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60'
            }`}
          >
            Stage 2: Harness (4)
          </button>
          <button
            type="button"
            onClick={() => setSelectedStage(3)}
            className={`px-3 py-1.5 rounded-xl font-mono text-micro transition-all ${
              selectedStage === 3
                ? 'bg-signal text-white font-semibold shadow-sm'
                : 'bg-inset text-ink-2 hover:text-ink hover:bg-surface border border-line/60'
            }`}
          >
            Stage 3: Visual (2)
          </button>
        </div>

        {/* Search Input */}
        <div className="relative flex-1 max-w-md">
          <Search className="w-4 h-4 text-ink-3 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search packages, APIs, or metrics..."
            className="w-full pl-9 pr-4 py-1.5 rounded-xl bg-inset border border-line font-mono text-meta text-ink placeholder:text-ink-3 focus:outline-none focus:border-signal/60 transition-colors"
          />
        </div>
      </div>

      {/* Packages Grid */}
      {filteredPackages.length === 0 ? (
        <div className="p-12 text-center rounded-3xl border border-line bg-surface/50 font-mono text-meta text-ink-3">
          No packages found matching "{searchQuery}".
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {filteredPackages.map((pkg) => {
            const isCopied = copiedId === pkg.id;
            const isCodeExpanded = expandedCodeId === pkg.id;
            const isCodeCopied = copiedCodeId === pkg.id;

            return (
              <div
                key={pkg.id}
                className="group p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between space-y-6"
              >
                <div className="space-y-4">
                  {/* Card Header */}
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex items-center gap-3.5">
                      <div className="w-11 h-11 rounded-2xl bg-inset border border-line flex items-center justify-center text-signal group-hover:scale-105 transition-transform shrink-0">
                        <pkg.icon className="w-5 h-5" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-meta font-bold text-ink">{pkg.id}</span>
                        </div>
                        <p className="font-mono text-micro text-signal uppercase mt-0.5">{pkg.tagline}</p>
                      </div>
                    </div>

                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                      <span
                        className={`px-2.5 py-0.5 rounded-full font-mono text-[10px] uppercase font-semibold border ${
                          pkg.stageNum === 1
                            ? 'bg-blue-500/10 text-blue-400 border-blue-500/30'
                            : pkg.stageNum === 2
                            ? 'bg-purple-500/10 text-signal border-signal/30'
                            : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                        }`}
                      >
                        {pkg.stage}
                      </span>
                      <span className="flex items-center gap-1 font-mono text-[10px] uppercase text-ink-3">
                        <span
                          className={`w-1.5 h-1.5 rounded-full ${
                            pkg.status === 'Stable'
                              ? 'bg-emerald-400'
                              : pkg.status === 'Active'
                              ? 'bg-purple-400'
                              : 'bg-amber-400'
                          }`}
                        />
                        {pkg.status}
                      </span>
                    </div>
                  </div>

                  {/* Description */}
                  <p className="text-meta text-ink-2 leading-relaxed">{pkg.description}</p>

                  {/* Highlights Bullet List */}
                  <ul className="space-y-1.5 pt-2 border-t border-line/60">
                    {pkg.highlights.map((h, i) => (
                      <li key={i} className="flex items-start gap-2 text-meta text-ink-2">
                        <CheckCircle2 className="w-3.5 h-3.5 text-signal mt-0.5 shrink-0" />
                        <span>{h}</span>
                      </li>
                    ))}
                  </ul>

                  {/* Performance Metrics Pills */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2">
                    {pkg.metrics.map((m, i) => (
                      <div key={i} className="p-2 rounded-xl bg-ground border border-line text-center">
                        <span className="block font-mono text-[9px] uppercase text-ink-3 leading-tight">
                          {m.label}
                        </span>
                        <span className="block font-mono text-micro font-semibold text-ink mt-0.5">
                          {m.value}
                        </span>
                      </div>
                    ))}
                  </div>

                  {/* Interfaces & Primitives */}
                  <div className="pt-2">
                    <span className="font-mono text-[10px] uppercase text-ink-3 block mb-1.5">
                      Exported Primitives & Interfaces:
                    </span>
                    <div className="flex flex-wrap gap-1.5">
                      {pkg.interfaces.map((iface, i) => (
                        <code
                          key={i}
                          className="px-2 py-0.5 rounded-md bg-inset border border-line font-mono text-micro text-purple-300"
                        >
                          {iface}
                        </code>
                      ))}
                    </div>
                  </div>

                  {/* Expandable Code Preview */}
                  {isCodeExpanded && (
                    <div className="mt-4 pt-3 border-t border-line/60 space-y-2 animate-fade-in">
                      <div className="flex items-center justify-between font-mono text-micro text-ink-3">
                        <span className="flex items-center gap-1.5 text-signal font-semibold">
                          <Code2 className="w-3.5 h-3.5" />
                          {pkg.codeSnippet.filename}
                        </span>
                        <button
                          type="button"
                          onClick={() => copyCode(pkg.id, pkg.codeSnippet.code)}
                          className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-inset border border-line hover:text-ink text-ink-3 transition-colors"
                        >
                          {isCodeCopied ? (
                            <>
                              <Check className="w-3 h-3 text-emerald-400" />
                              <span className="text-emerald-400">Copied</span>
                            </>
                          ) : (
                            <>
                              <Copy className="w-3 h-3" />
                              <span>Copy Code</span>
                            </>
                          )}
                        </button>
                      </div>
                      <div className="p-3.5 rounded-2xl bg-ground border border-line font-mono text-micro text-ink-2 overflow-x-auto leading-relaxed shadow-inner">
                        <pre>{pkg.codeSnippet.code}</pre>
                      </div>
                    </div>
                  )}
                </div>

                {/* Card Footer: Install Command & Inspect Toggle */}
                <div className="pt-4 border-t border-line/60 flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
                  {/* Install Line */}
                  <div className="flex-1 flex items-center justify-between px-3 py-1.5 rounded-xl bg-ground border border-line font-mono text-micro text-ink-3">
                    <span className="truncate text-ink-2">
                      <span className="text-signal font-semibold">$ </span>
                      {pkg.installCmd}
                    </span>
                    <button
                      type="button"
                      onClick={() => copyInstallCmd(pkg.id, pkg.installCmd)}
                      title="Copy install command"
                      className="ml-2 p-1 rounded hover:bg-surface text-ink-3 hover:text-ink transition-colors shrink-0"
                    >
                      {isCopied ? (
                        <Check className="w-3.5 h-3.5 text-emerald-400" />
                      ) : (
                        <Copy className="w-3.5 h-3.5" />
                      )}
                    </button>
                  </div>

                  {/* Toggle Code / Details */}
                  <button
                    type="button"
                    onClick={() => toggleExpand(pkg.id)}
                    className="inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-inset border border-line hover:border-signal/40 font-mono text-micro text-ink font-medium transition-colors shrink-0"
                  >
                    <span>{isCodeExpanded ? 'Hide Code' : 'Inspect Code'}</span>
                    {isCodeExpanded ? (
                      <ChevronUp className="w-3.5 h-3.5 text-signal" />
                    ) : (
                      <ChevronDown className="w-3.5 h-3.5 text-signal" />
                    )}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
