import React from 'react';
import { Terminal, Bot, Wrench, ShieldAlert, Cpu } from 'lucide-react';

export const Ecosystem: React.FC = () => {
  return (
    <section className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-12">
          <div className="flex items-center gap-2 text-craft-accent text-xs uppercase tracking-wider mb-2">
            <Wrench className="w-4 h-4" />
            <span>Developer Surface & Autonomous Agents</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            Complete Tooling for Autonomous AI Agents
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            AgentScript gives AI agents total computational freedom — from drafting exploratory in-memory scripts to performing batch AST refactorings without risking the host system.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {/* Card 1: MCP Server */}
          <div className="p-6 rounded-xl border border-craft-800 bg-craft-900/40 hover:border-craft-700 transition-colors">
            <div className="w-10 h-10 rounded-lg bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent mb-4">
              <Bot className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">Stdlib MCP Server</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              JSON-RPC 2.0 stdio server providing structured tools for LLMs: <code className="text-craft-accent">asex_check</code>, <code className="text-craft-accent">asex_eval</code>, <code className="text-craft-accent">asex_format</code>, <code className="text-craft-accent">asex_compress_module</code>.
            </p>
            <div className="p-2.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-300">
              $ agentscript mcp
            </div>
          </div>

          {/* Card 2: In-Memory Scratchpad */}
          <div className="p-6 rounded-xl border border-craft-accent/30 bg-craft-900/60 hover:border-craft-accent transition-colors shadow-lg shadow-craft-accent/5">
            <div className="w-10 h-10 rounded-lg bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent mb-4">
              <Cpu className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-accent mb-2">Agent VFS Scratchpad</h3>
            <p className="text-xs text-craft-300 font-sans leading-relaxed mb-4">
              Agents write and run exploratory AgentScript code inside an in-memory WASI sandbox in &lt;1ms. Mass batch AST transforms and VFS file operations execute safely before commit.
            </p>
            <div className="p-2.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-accent">
              Zero host risk · &lt;1ms eval
            </div>
          </div>

          {/* Card 3: CLI Compiler & Gates */}
          <div className="p-6 rounded-xl border border-craft-800 bg-craft-900/40 hover:border-craft-700 transition-colors">
            <div className="w-10 h-10 rounded-lg bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent mb-4">
              <Terminal className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">CLI Compiler & Formatter</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              Multi-target compiler with canonical S-expression layout formatting, syntax queries via Tree-Sitter, and zero-overhead binary builds.
            </p>
            <div className="p-2.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-300">
              $ agentscript build --target wasm
            </div>
          </div>

          {/* Card 4: Differential Verifier */}
          <div className="p-6 rounded-xl border border-craft-800 bg-craft-900/40 hover:border-craft-700 transition-colors">
            <div className="w-10 h-10 rounded-lg bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent mb-4">
              <ShieldAlert className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">Differential Gate</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              Automated differential runner asserting identical bytecode execution across 6 platforms simultaneously with zero tolerance for drift.
            </p>
            <div className="p-2.5 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-300">
              0 disagreements across 135 runs
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
