import React, { useState } from 'react';
import { Radio, Bot, Cpu } from 'lucide-react';

export const AgentWireProtocol: React.FC = () => {
  const [protocolMode, setProtocolMode] = useState<'verbose' | 'handshake' | 'agp'>('agp');

  return (
    <section id="a2a-protocol" className="relative py-28 border-b border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-950 transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Radio className="w-3.5 h-3.5 animate-pulse" />
            <span>A2A (Agent-to-Agent) Wire Protocol</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.035em] text-craft-900 dark:text-craft-50 font-sans leading-tight">
            The AgP Wire Handshake.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
            When agents talk to humans, natural language is essential. But when <strong>agents talk to agents</strong>, natural language is pure token waste. With <strong>AgP (Agentic Programming)</strong>, agents recognize each other and instantly switch to high-frequency typed S-expression streams.
          </p>
        </div>

        {/* Interactive Mode Selector Tabs */}
        <div className="flex justify-center mb-8">
          <div className="p-1.5 rounded-2xl bg-craft-100 dark:bg-craft-900 border border-craft-200 dark:border-craft-800 flex gap-2 font-mono text-xs">
            <button
              onClick={() => setProtocolMode('verbose')}
              className={`px-4 py-2 rounded-xl transition-all ${
                protocolMode === 'verbose'
                  ? 'bg-white dark:bg-craft-800 text-rose-500 font-bold shadow-sm'
                  : 'text-craft-500 hover:text-craft-800 dark:hover:text-craft-200'
              }`}
            >
              1. Verbose Natural Language (Old Way)
            </button>
            <button
              onClick={() => setProtocolMode('handshake')}
              className={`px-4 py-2 rounded-xl transition-all ${
                protocolMode === 'handshake'
                  ? 'bg-white dark:bg-craft-800 text-amber-500 font-bold shadow-sm'
                  : 'text-craft-500 hover:text-craft-800 dark:hover:text-craft-200'
              }`}
            >
              2. Agent Discovery Probe (?agent/probe)
            </button>
            <button
              onClick={() => setProtocolMode('agp')}
              className={`px-4 py-2 rounded-xl transition-all ${
                protocolMode === 'agp'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-glow-sm'
                  : 'text-craft-500 hover:text-craft-800 dark:hover:text-craft-200'
              }`}
            >
              3. AgP Nano Stream (-88% Tokens)
            </button>
          </div>
        </div>

        {/* The Live Interactive A2A Communication Simulator */}
        <div className="max-w-4xl mx-auto rounded-3xl border border-craft-200 dark:border-craft-800 bg-craft-50/70 dark:bg-craft-900/60 p-6 sm:p-8 backdrop-blur-2xl shadow-2xl">
          
          {/* Agent Nodes Header */}
          <div className="flex items-center justify-between border-b border-craft-200 dark:border-craft-800/80 pb-4 mb-6">
            <div className="flex items-center gap-3">
              <div className="p-2.5 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-craft-cyan">
                <Bot className="w-5 h-5" />
              </div>
              <div className="text-left font-mono">
                <div className="font-bold text-sm text-craft-900 dark:text-craft-100">agent-orchestrator</div>
                <div className="text-[10px] text-craft-500">Autonomous Planner Node</div>
              </div>
            </div>

            <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 text-[11px] font-mono">
              <span className="w-2 h-2 rounded-full bg-craft-emerald animate-ping" />
              <span className="text-craft-800 dark:text-craft-200">A2A Wire: <strong>Connected</strong></span>
            </div>

            <div className="flex items-center gap-3">
              <div className="text-right font-mono">
                <div className="font-bold text-sm text-craft-900 dark:text-craft-100">agent-coder</div>
                <div className="text-[10px] text-craft-500">Wasm Synthesis Specialist</div>
              </div>
              <div className="p-2.5 rounded-xl bg-purple-500/10 border border-purple-500/30 text-craft-purple">
                <Cpu className="w-5 h-5" />
              </div>
            </div>
          </div>

          {/* Conversation Stream based on Mode */}
          <div className="space-y-4 font-mono text-xs text-left mb-6 min-h-[220px] flex flex-col justify-center">
            
            {protocolMode === 'verbose' && (
              <div className="space-y-3 animate-fadeIn">
                <div className="p-4 rounded-2xl bg-white dark:bg-craft-950 border border-rose-500/30 text-craft-800 dark:text-craft-200">
                  <div className="text-rose-500 font-bold mb-1 text-[10px] uppercase">agent-orchestrator &rarr; agent-coder:</div>
                  <p className="font-sans leading-relaxed">
                    "Hello agent-coder! I am currently orchestrating a multi-step user workflow. Could you please take this specification, create an exhaustive Finite State Machine schema with 'idle', 'planning', 'executing', and 'finished' states, and return it back to me wrapped inside a JSON response with schema validation?"
                  </p>
                  <div className="mt-2 text-[10px] text-rose-500 font-mono">Payload: ~165 tokens • Latency: ~1,200ms</div>
                </div>

                <div className="p-4 rounded-2xl bg-white dark:bg-craft-950 border border-rose-500/30 text-craft-800 dark:text-craft-200">
                  <div className="text-purple-500 font-bold mb-1 text-[10px] uppercase">agent-coder &rarr; agent-orchestrator:</div>
                  <p className="font-sans leading-relaxed">
                    "Certainly! Here is the JSON schema you requested. I have structured the states and included validation fields. Please let me know if you would like me to modify any parameters or generate additional test fixtures."
                  </p>
                  <div className="mt-2 text-[10px] text-rose-500 font-mono">Payload: ~210 tokens • Latency: ~1,400ms</div>
                </div>
              </div>
            )}

            {protocolMode === 'handshake' && (
              <div className="space-y-3 animate-fadeIn">
                <div className="p-4 rounded-2xl bg-amber-500/10 border border-amber-500/40 text-craft-800 dark:text-craft-200">
                  <div className="text-amber-500 font-bold mb-1 text-[10px] uppercase">Agent Discovery Probe:</div>
                  <code className="text-amber-500 font-bold text-sm block">
                    (?agent/probe :proto "asl/1.0" :caps [wasm schema stream])
                  </code>
                  <p className="text-[11px] text-craft-500 font-sans mt-1">
                    Orchestrator detects recipient is an autonomous agent and offers high-speed protocol switch.
                  </p>
                </div>

                <div className="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/40 text-craft-800 dark:text-craft-200">
                  <div className="text-emerald-500 font-bold mb-1 text-[10px] uppercase">Protocol Ack & Frequency Shift:</div>
                  <code className="text-emerald-500 font-bold text-sm block">
                    (!agent/ack :proto "asl/1.0" :mode :nano)
                  </code>
                  <p className="text-[11px] text-craft-500 font-sans mt-1">
                    Specialist accepts. Both agents drop natural language conversational bloat instantly.
                  </p>
                </div>
              </div>
            )}

            {protocolMode === 'agp' && (
              <div className="space-y-3 animate-fadeIn">
                <div className="p-4 rounded-2xl bg-white dark:bg-craft-950 border border-craft-accent/50 shadow-glow-sm text-craft-800 dark:text-craft-200">
                  <div className="text-craft-accent font-bold mb-1 text-[10px] uppercase flex items-center justify-between">
                    <span>AgP Query Frame:</span>
                    <span className="text-craft-emerald text-[10px]">12 TOKENS // 0.015ms</span>
                  </div>
                  <code className="text-craft-accent font-bold text-sm block">
                    (? agent-coder fsm/build :states ["idle" "plan" "exec" "done"] :safe true)
                  </code>
                </div>

                <div className="p-4 rounded-2xl bg-white dark:bg-craft-950 border border-purple-500/50 shadow-glow-sm text-craft-800 dark:text-craft-200">
                  <div className="text-purple-500 font-bold mb-1 text-[10px] uppercase flex items-center justify-between">
                    <span>AgP Response Frame:</span>
                    <span className="text-craft-emerald text-[10px]">18 TOKENS // 0.012ms</span>
                  </div>
                  <code className="text-purple-400 font-bold text-sm block">
                    (! agent-coder :ok (dfe State (:case idle []) (:case plan [(g Str)]) (:case exec [(s I64)]) (:case done [(r Str)])))
                  </code>
                </div>
              </div>
            )}

          </div>

          {/* Protocol Telemetry Metrics Footer */}
          <div className="p-4 rounded-2xl bg-white dark:bg-craft-950 border border-craft-200 dark:border-craft-800/80 grid grid-cols-1 sm:grid-cols-3 gap-4 text-center font-mono">
            <div>
              <div className="text-[10px] text-craft-500 uppercase">Context Reduction</div>
              <div className="text-lg font-extrabold text-craft-accent">-88% Token Load</div>
            </div>
            <div>
              <div className="text-[10px] text-craft-500 uppercase">Wire Transport</div>
              <div className="text-lg font-extrabold text-craft-emerald">MCP / SSE / Unix Sockets</div>
            </div>
            <div>
              <div className="text-[10px] text-craft-500 uppercase">Attention Drift</div>
              <div className="text-lg font-extrabold text-purple-400">0.00% Zero Loss</div>
            </div>
          </div>

        </div>

      </div>
    </section>
  );
};
