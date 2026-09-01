import React, { useState } from 'react';
import { Bot, Play, CheckCircle2, Terminal, RefreshCw, Coins, Code, Globe, Monitor, MessageSquare, Layers } from 'lucide-react';

interface TaskDef {
  adapter: string;
  adapterName: string;
  badge: string;
  icon: React.ReactNode;
  title: string;
  prompt: string;
  steps: {
    id: number;
    phase: string;
    action: string;
    tool: string;
    durationMs: number;
    output: string;
  }[];
}

export const AgentHarness: React.FC = () => {
  const [isRunning, setIsRunning] = useState(false);
  const [currentStepIndex, setCurrentStepIndex] = useState(-1);
  const [selectedAdapter, setSelectedAdapter] = useState<'code' | 'browser' | 'computer' | 'chat' | 'metasearch'>('code');

  const ADAPTERS: Record<string, TaskDef> = {
    code: {
      adapter: 'code',
      adapterName: 'CodeEngineAdapter',
      badge: 'Code Generation & Wasm Engine',
      icon: <Code className="w-4 h-4 text-craft-accent" />,
      title: 'Autonomous State Machine & Wasm Compiler',
      prompt: 'Synthesize closed ADT payment state machine, prove exhaustiveness statically (§9), and emit wasm32 binary.',
      steps: [
        { id: 1, phase: '1. ADT Synthesis', action: 'Defining (PaymentState) sum type with 5 cases', tool: 'asl_ast_gen', durationMs: 0.09, output: '✓ Sum type (PaymentState) generated.' },
        { id: 2, phase: '2. Exhaustive Match Check', action: 'Statically verifying transition matrix for all state pairs', tool: 'asl_check_rule9', durationMs: 0.14, output: '✓ Exhaustiveness proved: 0 unhandled transitions.' },
        { id: 3, phase: '3. Wasm Compilation', action: 'Compiling state engine to wasm32-wasip1 binary', tool: 'asl_wasm_build', durationMs: 0.38, output: '✓ Emitted 1.8KB zero-allocation Wasm binary.' },
        { id: 4, phase: '4. In-Memory Eval', action: 'Simulating 1,000 rapid event dispatches in browser memory', tool: 'asl_wasm_eval', durationMs: 0.06, output: '✓ 1,000 state transitions processed in 0.06ms.' }
      ]
    },
    browser: {
      adapter: 'browser',
      adapterName: 'BrowserAdapter',
      badge: 'Headless Browser & DOM Navigator',
      icon: <Globe className="w-4 h-4 text-craft-cyan" />,
      title: 'Autonomous Web Research & Scraping Agent',
      prompt: 'Navigate to target documentation site, extract DOM tree, filter navigational noise, and format token-compressed markdown.',
      steps: [
        { id: 1, phase: '1. DOM Navigation', action: 'Spawning headless browser viewport to https://aslang.dev', tool: 'browser_navigate', durationMs: 14.2, output: '✓ Page rendered in 14.2ms (HTTP 200).' },
        { id: 2, phase: '2. DOM Tree Pruning', action: 'Removing script/style tags and extracting semantic article node', tool: 'asl_dom_filter', durationMs: 0.22, output: '✓ 1,420 DOM nodes pruned to 8 key content nodes.' },
        { id: 3, phase: '3. Schema Extraction', action: 'Mapping extracted tables to (defschema SpecTable)', tool: 'asl_ast_gen', durationMs: 0.08, output: '✓ Schema compiled with zero type drift.' },
        { id: 4, phase: '4. RAG Markdown Compression', action: 'Compressing DOM to LLM context buffer', tool: 'asl_compress_rag', durationMs: 0.04, output: '✓ 18KB HTML compressed to 310 token markdown.' }
      ]
    },
    computer: {
      adapter: 'computer',
      adapterName: 'ComputerUseAdapter',
      badge: 'Desktop OS & Terminal Controller',
      icon: <Monitor className="w-4 h-4 text-craft-emerald" />,
      title: 'Autonomous System Tooling & Shell Controller',
      prompt: 'Inspect local environment, execute multi-target compilation pipelines, and verify build artifacts with zero human intervention.',
      steps: [
        { id: 1, phase: '1. Environment Audit', action: 'Checking rustup, clang, and node:wasi availability', tool: 'os_exec_audit', durationMs: 2.1, output: '✓ All native compilers ready.' },
        { id: 2, phase: '2. Multi-Target Build', action: 'Invoking `asl build --target wasm,ts,rs,go,py`', tool: 'asl_project_build', durationMs: 4.8, output: '✓ All 5 target binaries generated cleanly.' },
        { id: 3, phase: '3. Differential Verification', action: 'Running differential harness across all backends', tool: 'asl_differential', durationMs: 8.4, output: '✓ 0 disagreements across 135 function test cases.' },
        { id: 4, phase: '4. Receipt Generation', action: 'Creating signed build receipt with cryptographic hash', tool: 'asl_receipt_sign', durationMs: 0.12, output: '✓ Receipt @pcp:b830 emitted.' }
      ]
    },
    chat: {
      adapter: 'chat',
      adapterName: 'ChatRAGAdapter',
      badge: 'Vector Memory & Context Engine',
      icon: <MessageSquare className="w-4 h-4 text-craft-purple" />,
      title: 'Long-Term Semantic Memory & Dialogue Recall',
      prompt: 'Search in-memory vector database for past agent trajectories, compute cosine similarity, and inject relevant context.',
      steps: [
        { id: 1, phase: '1. Embedding Projection', action: 'Projecting user query into 128-dim dense vector', tool: 'asl_vec_embed', durationMs: 0.04, output: '✓ Dense vector computed in 0.04ms.' },
        { id: 2, phase: '2. Cosine Search', action: 'Executing vector top-k cosine scan across 5,000 memory entries', tool: 'asl_mem_topk', durationMs: 0.038, output: '✓ 3 matches found (similarity: 0.942, 0.915, 0.884).' },
        { id: 3, phase: '3. Trajectory Deduplication', action: 'Filtering redundant reasoning traces', tool: 'asl_dedup_wasm', durationMs: 0.02, output: '✓ Deduped 12 reasoning steps into 2 essential items.' },
        { id: 4, phase: '4. Prompt Injection', action: 'Injecting verified memory into LLM agent prompt', tool: 'asl_prompt_inject', durationMs: 0.01, output: '✓ Context cost reduced by 78%.' }
      ]
    },
    metasearch: {
      adapter: 'metasearch',
      adapterName: 'MetasearchAdapter',
      badge: 'SearXNG & Proxy Pool Rotator',
      icon: <Layers className="w-4 h-4 text-craft-amber" />,
      title: 'Decentralized SearXNG Metasearch Aggregator',
      prompt: 'Execute query across 4 SearXNG nodes, rotate degraded proxies, and compile deduplicated Wasm memory index.',
      steps: [
        { id: 1, phase: '1. Plan & Schema', action: 'Synthesizing (ProxyStatus) & (SearchResult) schemas', tool: 'asl_ast_gen', durationMs: 0.12, output: '✓ Schema (SearchResult) compiled with 0 type errors.' },
        { id: 2, phase: '2. Proxy Selection', action: 'Executing select-proxy on 4 endpoints via Wasm', tool: 'asl_wasm_eval', durationMs: 0.04, output: '✓ Selected node: https://searx.be (RTT: 32ms, status: active).' },
        { id: 3, phase: '3. Result Aggregation', action: 'Aggregating Google/Bing/arXiv and deduplicating URLs', tool: 'asl_dedup_wasm', durationMs: 0.08, output: '✓ 12 raw results deduplicated to 4 unique items.' },
        { id: 4, phase: '4. Context Injection', action: 'Formatting token-compressed RAG markdown for agent prompt', tool: 'asl_compress_rag', durationMs: 0.02, output: '✓ Context compressed by 82% (240 tokens total).' }
      ]
    }
  };

  const currentTask = ADAPTERS[selectedAdapter];

  const startAgentRun = () => {
    if (isRunning) return;
    setIsRunning(true);
    setCurrentStepIndex(0);

    const stepInterval = setInterval(() => {
      setCurrentStepIndex((prev) => {
        if (prev < currentTask.steps.length - 1) {
          return prev + 1;
        } else {
          clearInterval(stepInterval);
          setIsRunning(false);
          return prev;
        }
      });
    }, 550);
  };

  return (
    <section id="harness" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Bot className="w-3.5 h-3.5" />
              <span>Pluggable Agent Super-Harness (@genseam/asl-harness)</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              Universal Multi-Modal Agent Runtime
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              Pluggable adapter architecture for Code Generation, Browser Automation, Computer-Use (OS/Terminal), Chat RAG, and Metasearch with sub-millisecond in-memory Wasm execution.
            </p>
          </div>

          {/* Telemetry Pill */}
          <div className="p-3 rounded-xl border border-craft-700 bg-craft-900/90 flex items-center gap-4 text-xs shrink-0 shadow-lg">
            <div className="flex items-center gap-2">
              <Coins className="w-4 h-4 text-craft-accent" />
              <div>
                <div className="text-[10px] text-craft-400 uppercase">Context Economy</div>
                <div className="font-bold text-craft-accent">-78% Token Cost</div>
              </div>
            </div>
            <div className="h-6 w-[1px] bg-craft-800" />
            <div>
              <div className="text-[10px] text-craft-400 uppercase">Adapter Latency</div>
              <div className="font-bold text-craft-emerald">0.038ms / task</div>
            </div>
          </div>
        </div>

        {/* Adapter Switcher Tabs */}
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2 mb-6">
          {Object.entries(ADAPTERS).map(([key, def]) => {
            const isSelected = selectedAdapter === key;
            return (
              <button
                key={key}
                onClick={() => {
                  setSelectedAdapter(key as any);
                  setCurrentStepIndex(-1);
                }}
                className={`p-3 rounded-lg border text-left text-xs transition-all flex flex-col justify-between ${
                  isSelected
                    ? 'bg-craft-900 border-craft-accent text-craft-50 shadow-md shadow-craft-accent/5'
                    : 'bg-craft-950/60 border-craft-800 text-craft-400 hover:border-craft-700 hover:text-craft-200'
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  {def.icon}
                  <span className="font-bold">{def.adapterName}</span>
                </div>
                <div className="text-[10px] text-craft-400 truncate">{def.badge}</div>
              </button>
            );
          })}
        </div>

        {/* Harness Body */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Left Controls & Prompt */}
          <div className="lg:col-span-5 space-y-4">
            <div className="p-5 rounded-xl border border-craft-800 bg-craft-900/40 shadow-xl space-y-4">
              <div className="flex items-center justify-between">
                <span className="text-xs text-craft-400 uppercase tracking-wider font-bold">
                  Active Capability
                </span>
                <span className="px-2 py-0.5 rounded bg-craft-900 border border-craft-700 text-[10px] text-craft-accent">
                  {currentTask.badge}
                </span>
              </div>

              <div>
                <h3 className="text-sm font-bold text-craft-100">{currentTask.title}</h3>
              </div>

              {/* Task Prompt Box */}
              <div className="p-3 rounded-lg bg-craft-950 border border-craft-800 text-xs text-craft-300 font-sans leading-relaxed">
                <span className="text-craft-accent font-mono text-[10px] font-bold block mb-1">CAPABILITY OBJECTIVE</span>
                {currentTask.prompt}
              </div>

              {/* Action Button */}
              <button
                onClick={startAgentRun}
                disabled={isRunning}
                className={`w-full py-3 rounded-lg font-bold text-xs uppercase tracking-wider flex items-center justify-center gap-2 transition-all shadow-lg ${
                  isRunning
                    ? 'bg-craft-800 text-craft-400 cursor-not-allowed'
                    : 'bg-craft-accent text-craft-950 hover:bg-craft-accent/90 shadow-craft-accent/10'
                }`}
              >
                {isRunning ? (
                  <>
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    <span>Executing via {currentTask.adapterName}...</span>
                  </>
                ) : (
                  <>
                    <Play className="w-4 h-4 fill-current" />
                    <span>Run {currentTask.adapterName} Pipeline</span>
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Right Live Execution Pipeline Viewport */}
          <div className="lg:col-span-7 rounded-xl border border-craft-800 bg-craft-900/40 p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between border-b border-craft-800 pb-3 text-xs">
              <span className="flex items-center gap-2 font-bold text-craft-200">
                <Terminal className="w-4 h-4 text-craft-accent" />
                <span>Adapter Live Execution Pipeline</span>
              </span>
              <span className="px-2 py-0.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-emerald">
                {currentStepIndex >= 0 ? `Step ${Math.min(currentStepIndex + 1, currentTask.steps.length)} of ${currentTask.steps.length}` : 'Ready'}
              </span>
            </div>

            {/* Step Pipeline List */}
            <div className="space-y-3">
              {currentTask.steps.map((step, idx) => {
                const isCurrent = currentStepIndex === idx;
                const isPassed = currentStepIndex > idx;

                return (
                  <div
                    key={step.id}
                    className={`p-3.5 rounded-lg border transition-all ${
                      isCurrent
                        ? 'bg-craft-900 border-craft-accent shadow-md shadow-craft-accent/5'
                        : isPassed
                        ? 'bg-craft-950 border-craft-800/80 text-craft-300'
                        : 'bg-craft-950/40 border-craft-850 text-craft-600 opacity-60'
                    }`}
                  >
                    <div className="flex items-center justify-between text-xs mb-1.5">
                      <span className="font-bold text-craft-100 flex items-center gap-2">
                        {isPassed ? (
                          <CheckCircle2 className="w-3.5 h-3.5 text-craft-emerald" />
                        ) : isCurrent ? (
                          <RefreshCw className="w-3.5 h-3.5 text-craft-accent animate-spin" />
                        ) : (
                          <span className="w-3.5 h-3.5 rounded-full border border-craft-700 inline-block" />
                        )}
                        <span>{step.phase}</span>
                      </span>
                      <div className="flex items-center gap-2">
                        <span className="px-1.5 py-0.5 rounded bg-craft-800 text-[10px] text-craft-accent font-mono">
                          {step.tool}
                        </span>
                        <span className="text-[10px] text-craft-400 font-mono">
                          {step.durationMs}ms
                        </span>
                      </div>
                    </div>

                    <div className="text-xs text-craft-400 font-sans mb-1">
                      {step.action}
                    </div>

                    {(isPassed || isCurrent) && (
                      <div className="mt-2 p-2 rounded bg-craft-950 border border-craft-800/80 text-[11px] text-craft-emerald font-mono">
                        {step.output}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Bottom Status bar */}
            <div className="mt-4 pt-3 border-t border-craft-800 flex items-center justify-between text-xs text-craft-400 font-mono">
              <span>Adapter Status: Active</span>
              <span>100% In-Memory Determinism</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
