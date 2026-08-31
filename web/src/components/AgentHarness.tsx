import React, { useState } from 'react';
import { Bot, Play, CheckCircle2, Terminal, RefreshCw, Coins } from 'lucide-react';

export const AgentHarness: React.FC = () => {
  const [isRunning, setIsRunning] = useState(false);
  const [currentStepIndex, setCurrentStepIndex] = useState(-1);
  const [selectedTask, setSelectedTask] = useState('metasearch');

  const TASKS = {
    metasearch: {
      title: 'Decentralized SearXNG Metasearch & Proxy Health Check',
      prompt: 'Execute query across 4 SearXNG nodes, rotate degraded proxies, and compile deduplicated Wasm memory index.',
      steps: [
        { id: 1, phase: '1. Plan & Schema', action: 'Synthesizing (ProxyStatus) & (SearchResult) schemas', tool: 'asl_ast_gen', durationMs: 0.12, output: '✓ Schema (SearchResult) compiled with 0 type errors.' },
        { id: 2, phase: '2. Proxy Selection', action: 'Executing select-proxy on 4 endpoints via Wasm', tool: 'asl_wasm_eval', durationMs: 0.04, output: '✓ Selected node: https://searx.be (RTT: 32ms, status: active).' },
        { id: 3, phase: '3. Result Aggregation', action: 'Aggregating Google/Bing/arXiv and deduplicating URLs', tool: 'asl_dedup_wasm', durationMs: 0.08, output: '✓ 12 raw results deduplicated to 4 unique items.' },
        { id: 4, phase: '4. Context Injection', action: 'Formatting token-compressed RAG markdown for agent prompt', tool: 'asl_compress_rag', durationMs: 0.02, output: '✓ Context compressed by 82% (240 tokens total).' }
      ]
    },
    fsm: {
      title: 'Autonomous Payment & Order State Machine',
      prompt: 'Generate mathematically closed state machine with exhaustive pattern matching and effect isolation.',
      steps: [
        { id: 1, phase: '1. ADT Definition', action: 'Defining (PaymentState) sum type with 5 cases', tool: 'asl_ast_gen', durationMs: 0.09, output: '✓ Sum type (PaymentState) validated.' },
        { id: 2, phase: '2. Exhaustive Check', action: 'Statically verifying transition matrix for all state pairs', tool: 'asl_check_rule9', durationMs: 0.14, output: '✓ Exhaustiveness proved: 0 unhandled states.' },
        { id: 3, phase: '3. Wasm Compilation', action: 'Compiling state engine to wasm32-wasip1 binary', tool: 'asl_wasm_build', durationMs: 0.38, output: '✓ Emitted 1.8KB optimized Wasm binary.' },
        { id: 4, phase: '4. In-Memory Sandbox', action: 'Simulating 1,000 rapid event dispatches in browser memory', tool: 'asl_wasm_eval', durationMs: 0.06, output: '✓ 1,000 state transitions processed in 0.06ms.' }
      ]
    }
  };

  const currentTask = TASKS[selectedTask as keyof typeof TASKS];

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
    }, 600);
  };

  return (
    <section id="harness" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Bot className="w-3.5 h-3.5" />
              <span>Native Agent Super-Harness</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              In-Browser Autonomous Agent Execution Sandbox
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              Watch autonomous agents generate, verify, and execute native ASL WebAssembly tools entirely inside your browser with sub-millisecond latency.
            </p>
          </div>

          {/* Token Economics Telemetry Pill */}
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
              <div className="text-[10px] text-craft-400 uppercase">Execution Latency</div>
              <div className="font-bold text-craft-emerald">0.038ms / task</div>
            </div>
          </div>
        </div>

        {/* Harness Sandbox Body */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Left Controls & Prompt */}
          <div className="lg:col-span-5 space-y-4">
            <div className="p-5 rounded-xl border border-craft-800 bg-craft-900/40 shadow-xl space-y-4">
              <div className="text-xs text-craft-400 uppercase tracking-wider font-bold">
                Select Agent Objective
              </div>

              <div className="space-y-2">
                <button
                  onClick={() => { setSelectedTask('metasearch'); setCurrentStepIndex(-1); }}
                  className={`w-full text-left p-3 rounded-lg border text-xs transition-all ${
                    selectedTask === 'metasearch'
                      ? 'bg-craft-900 border-craft-accent text-craft-50'
                      : 'bg-craft-950/60 border-craft-800 text-craft-400 hover:border-craft-700'
                  }`}
                >
                  <div className="font-bold text-craft-200">SearXNG Metasearch & Proxy Pool</div>
                  <div className="text-[11px] text-craft-400 font-sans mt-1">Multi-engine search with RAG context compression</div>
                </button>

                <button
                  onClick={() => { setSelectedTask('fsm'); setCurrentStepIndex(-1); }}
                  className={`w-full text-left p-3 rounded-lg border text-xs transition-all ${
                    selectedTask === 'fsm'
                      ? 'bg-craft-900 border-craft-accent text-craft-50'
                      : 'bg-craft-950/60 border-craft-800 text-craft-400 hover:border-craft-700'
                  }`}
                >
                  <div className="font-bold text-craft-200">Exhaustive State Machine Generator</div>
                  <div className="text-[11px] text-craft-400 font-sans mt-1">Mathematical payment state transitions with 0 invalid bugs</div>
                </button>
              </div>

              {/* Task Prompt Box */}
              <div className="p-3 rounded-lg bg-craft-950 border border-craft-800 text-xs text-craft-300 font-sans leading-relaxed">
                <span className="text-craft-accent font-mono text-[10px] font-bold block mb-1">GOAL PROMPT</span>
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
                    <span>Executing in In-Memory Wasm...</span>
                  </>
                ) : (
                  <>
                    <Play className="w-4 h-4 fill-current" />
                    <span>Launch Agent Execution Cycle</span>
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
                <span>Autonomous Agent Live Execution Stream</span>
              </span>
              <span className="px-2 py-0.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-emerald">
                {currentStepIndex >= 0 ? `Step ${Math.min(currentStepIndex + 1, currentTask.steps.length)} of 4` : 'Ready'}
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
              <span>Memory Footprint: 64KB Wasm Page</span>
              <span>100% In-Memory Determinism</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
