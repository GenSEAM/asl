import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { Terminal, ShieldCheck, FileText, Code2 } from 'lucide-react';

export const DocsView: React.FC = () => (
  <div className="pt-28 pb-20">
    <Section id="docs" labelledBy="docs-title">
      <SectionHeader
        id="docs-title"
        index="Reference"
        eyebrow="Documentation"
        title="AgentScript Architecture & Toolchain Reference"
        lead="Comprehensive guides, CLI commands, and formal language semantics designed for humans to architect and autonomous agents to execute."
      />

      {/* Dual Audience Banner */}
      <div className="mb-12 p-6 sm:p-8 rounded-3xl border border-signal/40 bg-gradient-to-r from-surface to-surface/70 backdrop-blur-xl shadow-e2 flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
        <div className="space-y-2 max-w-2xl">
          <span className="font-mono text-micro uppercase text-signal font-semibold">
            Agent-Native Ingestion
          </span>
          <h3 className="text-xl font-bold text-ink">
            Are you an LLM or Autonomous Agent?
          </h3>
          <p className="text-meta text-ink-2 leading-relaxed">
            Consume our zero-bloat machine-readable specifications directly. Formatted in concise markdown and clean S-expressions to eliminate prompt token waste.
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

      {/* Quick Start & CLI Reference */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-5">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
              <Terminal className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-ink text-lg">CLI Toolchain Commands</h3>
              <p className="font-mono text-micro text-ink-3">Unified developer workflow</p>
            </div>
          </div>

          <div className="space-y-3 font-mono text-meta">
            <div className="p-3 rounded-2xl bg-ground border border-line">
              <span className="text-signal font-semibold">$ </span>
              <span className="text-ink">asl run &lt;file.asl&gt;</span>
              <p className="text-micro text-ink-3 mt-1">Executes program inside the fast Wasm/native runner isolate.</p>
            </div>
            <div className="p-3 rounded-2xl bg-ground border border-line">
              <span className="text-signal font-semibold">$ </span>
              <span className="text-ink">asl fmt &lt;file.asl&gt;</span>
              <p className="text-micro text-ink-3 mt-1">Deterministic AST formatter with canonical indentation.</p>
            </div>
            <div className="p-3 rounded-2xl bg-ground border border-line">
              <span className="text-signal font-semibold">$ </span>
              <span className="text-ink">asl lint --fix</span>
              <p className="text-micro text-ink-3 mt-1">Autonomous smell detector and structural AST repair engine.</p>
            </div>
            <div className="p-3 rounded-2xl bg-ground border border-line">
              <span className="text-signal font-semibold">$ </span>
              <span className="text-ink">asl mcp</span>
              <p className="text-micro text-ink-3 mt-1">Starts native Model Context Protocol server for agent IDEs.</p>
            </div>
          </div>
        </div>

        <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface shadow-e1 space-y-5">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-ink text-lg">Language Invariants</h3>
              <p className="font-mono text-micro text-ink-3">Why models generate clean code</p>
            </div>
          </div>

          <ul className="space-y-3.5 text-meta text-ink-2">
            <li className="flex items-start gap-2.5">
              <span className="w-1.5 h-1.5 rounded-full bg-signal mt-2 shrink-0" />
              <span>
                <strong className="text-ink">Single-Pass LL(1) Parsing:</strong> Balanced parentheses ensure syntax mistakes are caught in one left-to-right pass without ambiguity.
              </span>
            </li>
            <li className="flex items-start gap-2.5">
              <span className="w-1.5 h-1.5 rounded-full bg-signal mt-2 shrink-0" />
              <span>
                <strong className="text-ink">Closed Vocabulary:</strong> Exactly 107 pure safe builtins guaranteed against hallucinated library functions.
              </span>
            </li>
            <li className="flex items-start gap-2.5">
              <span className="w-1.5 h-1.5 rounded-full bg-signal mt-2 shrink-0" />
              <span>
                <strong className="text-ink">Zero Indentation Hazards:</strong> Whitespace carries zero semantic meaning, preventing indentation-related catastrophic failures.
              </span>
            </li>
            <li className="flex items-start gap-2.5">
              <span className="w-1.5 h-1.5 rounded-full bg-signal mt-2 shrink-0" />
              <span>
                <strong className="text-ink">Jailed Isolation:</strong> File I/O and network operations are strictly isolated from the host operating system.
              </span>
            </li>
          </ul>
        </div>
      </div>
    </Section>
  </div>
);
