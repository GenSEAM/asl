import React from 'react';
import { Radio, Bot, Cpu, CheckCircle2, XCircle } from 'lucide-react';

export const AgentWireProtocol: React.FC = () => {
  return (
    <section id="a2a-protocol" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#04060a] transition-colors">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Radio className="w-3.5 h-3.5 animate-pulse" />
            <span>A2A (Agent-to-Agent) Wire Protocol</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            The AgP Wire Handshake.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            When agents talk to humans, natural language is essential. But when <strong>agents talk to agents</strong>, natural language is pure token waste. The moment two agents connect, they perform a 1-cycle probe and instantly switch to high-frequency typed S-expression streams.
          </p>
        </div>

        {/* Live A2A Stream Showcase (Immediate High-Impact View) */}
        <div className="rounded-[2rem] border border-craft-200 dark:border-white/[0.08] bg-craft-50/50 dark:bg-[#07090e] p-6 sm:p-8 backdrop-blur-xl shadow-xl mb-12">
          
          {/* Active Handshake Nodes Header */}
          <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-5 mb-6">
            <div className="flex items-center gap-3">
              <div className="p-2.5 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-400">
                <Bot className="w-5 h-5" />
              </div>
              <div className="text-left font-mono">
                <div className="font-bold text-sm text-craft-900 dark:text-white">agent-orchestrator</div>
                <div className="text-[10px] text-craft-500">Autonomous Planner</div>
              </div>
            </div>

            {/* Glowing Active Status Pill */}
            <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-xs font-mono text-cyan-400 font-bold">
              <span className="w-2 h-2 rounded-full bg-cyan-400" />
              <span>AgP NANO WIRE: ACTIVE</span>
            </div>

            <div className="flex items-center gap-3">
              <div className="text-right font-mono">
                <div className="font-bold text-sm text-craft-900 dark:text-white">agent-coder</div>
                <div className="text-[10px] text-craft-500">Wasm Specialist</div>
              </div>
              <div className="p-3 rounded-2xl bg-purple-500/10 border border-purple-500/30 text-craft-purple">
                <Cpu className="w-5 h-5" />
              </div>
            </div>
          </div>

          {/* Live High-Frequency Packet Stream */}
          <div className="space-y-4 font-mono text-xs text-left mb-8">
            
            {/* Step 1: 1-Cycle Discovery Probe */}
            <div className="p-4 rounded-2xl bg-white dark:bg-[#06080d] border border-cyan-500/30 text-craft-800 dark:text-craft-200">
              <div className="flex items-center justify-between text-[10px] text-cyan-500 font-bold uppercase mb-1.5">
                <span>1. Agent Discovery Probe:</span>
                <span className="text-craft-400">1-CYCLE HANDSHAKE</span>
              </div>
              <code className="text-cyan-400 font-bold text-xs sm:text-sm block">
                (?agent/probe :proto "asl/1.0" :caps [wasm schema stream]) &rarr; (!agent/ack :proto "asl/1.0" :mode :nano)
              </code>
            </div>

            {/* Step 2: Ultra-Dense Query Frame */}
            <div className="p-4 rounded-2xl bg-white dark:bg-[#06080d] border border-craft-accent/50 text-craft-800 dark:text-craft-200 shadow-sm">
              <div className="flex items-center justify-between text-[10px] text-craft-accent font-bold uppercase mb-1.5">
                <span>2. AgP Query Frame:</span>
                <span className="text-emerald-400">12 TOKENS // 0.015ms</span>
              </div>
              <code className="text-craft-accent font-bold text-xs sm:text-sm block">
                (? agent-coder fsm/build :states ["idle" "plan" "exec" "done"] :safe true)
              </code>
            </div>

            {/* Step 3: Typed Result Frame */}
            <div className="p-4 rounded-2xl bg-white dark:bg-[#06080d] border border-purple-500/40 text-craft-800 dark:text-craft-200 shadow-sm">
              <div className="flex items-center justify-between text-[10px] text-purple-400 font-bold uppercase mb-1.5">
                <span>3. AgP Response Frame:</span>
                <span className="text-emerald-400">18 TOKENS // 0.012ms</span>
              </div>
              <code className="text-purple-400 font-bold text-xs sm:text-sm block">
                (! agent-coder :ok (dfe State (:case idle []) (:case plan [(g Str)]) (:case exec [(s I64)]) (:case done [(r Str)])))
              </code>
            </div>

          </div>

          {/* Telemetry Numbers */}
          <div className="p-5 rounded-2xl bg-white dark:bg-[#06080d] border border-craft-200 dark:border-white/[0.08] grid grid-cols-1 sm:grid-cols-3 gap-4 text-center font-mono">
            <div>
              <div className="text-[10px] text-craft-500 uppercase tracking-wider">Context Savings</div>
              <div className="text-xl font-extrabold text-craft-accent mt-0.5">–88% Token Overhead</div>
            </div>
            <div>
              <div className="text-[10px] text-craft-500 uppercase tracking-wider">Wire Transport</div>
              <div className="text-xl font-extrabold text-emerald-400 mt-0.5">MCP / SSE / Sockets</div>
            </div>
            <div>
              <div className="text-[10px] text-craft-500 uppercase tracking-wider">Attention Drift</div>
              <div className="text-xl font-extrabold text-purple-400 mt-0.5">0.00% Zero Loss</div>
            </div>
          </div>

        </div>

        {/* Side-by-Side Versus Breakdown: The Old Way vs The AgP Way */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 text-left">
          
          <div className="p-6 rounded-3xl border border-rose-500/20 bg-rose-500/[0.02] dark:bg-rose-500/[0.03] backdrop-blur-xl">
            <div className="flex items-center gap-2 text-rose-500 font-mono text-xs font-bold uppercase mb-3">
              <XCircle className="w-4 h-4" />
              <span>The Old Way (Natural Language A2A)</span>
            </div>
            <p className="text-xs text-craft-600 dark:text-craft-400 leading-relaxed font-sans mb-3">
              "Hello! Could you please take this specification and generate a state machine with idle and plan states, and return it formatted in JSON?"
            </p>
            <div className="font-mono text-xs text-rose-500/80 flex items-center justify-between border-t border-rose-500/20 pt-3">
              <span>Payload: ~375 tokens</span>
              <span>Latency: ~1,400ms</span>
            </div>
          </div>

          <div className="p-6 rounded-3xl border border-craft-accent/40 bg-cyan-500/[0.03] dark:bg-cyan-500/[0.04] backdrop-blur-xl">
            <div className="flex items-center gap-2 text-craft-accent font-mono text-xs font-bold uppercase mb-3">
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
              <span>The AgP Way (Typed S-Expressions)</span>
            </div>
            <p className="text-xs text-craft-700 dark:text-craft-200 leading-relaxed font-mono mb-3">
              (? agent-coder fsm/build :states ["idle" "plan"]) &rarr; (! agent-coder :ok (dfe State ...))
            </p>
            <div className="font-mono text-xs text-emerald-400 flex items-center justify-between border-t border-craft-accent/30 pt-3">
              <span>Payload: ~30 tokens (-88%)</span>
              <span>Latency: &lt;0.015ms</span>
            </div>
          </div>

        </div>

      </div>
    </section>
  );
};
