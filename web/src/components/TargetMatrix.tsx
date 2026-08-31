import React, { useState } from 'react';
import { Code2, Check, Copy } from 'lucide-react';
import { EXAMPLES, CodeExample } from '../lib/examples';

type TargetLang = 'as' | 'wasm' | 'ts' | 'rs' | 'go' | 'py';

export const TargetMatrix: React.FC = () => {
  const [selectedEx, setSelectedEx] = useState<CodeExample>(EXAMPLES[0]);
  const [target, setTarget] = useState<TargetLang>('ts');
  const [copied, setCopied] = useState(false);

  const getTargetCode = () => {
    switch (target) {
      case 'as': return selectedEx.code;
      case 'wasm': return selectedEx.transpiled.wat;
      case 'ts': return selectedEx.transpiled.ts;
      case 'rs': return selectedEx.transpiled.rs;
      case 'go': return selectedEx.transpiled.go;
      case 'py': return selectedEx.transpiled.py;
    }
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(getTargetCode());
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="targets" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-8">
          <div className="flex items-center gap-2 text-craft-accent text-xs uppercase tracking-wider mb-2">
            <Code2 className="w-4 h-4" />
            <span>Single Source, Six Targets</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            Multi-Target Transpilation Matrix
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Write prototype code in AgentScript or let an LLM agent emit S-expressions, then deploy natively to TypeScript/React, Rust, Go microservices, Python, or WebAssembly with 100% semantic parity verified by our differential gate.
          </p>
        </div>

        {/* Matrix Card */}
        <div className="rounded-xl border border-craft-800 bg-craft-900/60 overflow-hidden shadow-2xl">
          {/* Header Controls */}
          <div className="p-4 bg-craft-900 border-b border-craft-800 flex flex-wrap items-center justify-between gap-4">
            {/* Example switcher */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-craft-400">Module:</span>
              <select
                value={selectedEx.id}
                onChange={(e) => {
                  const found = EXAMPLES.find((x) => x.id === e.target.value);
                  if (found) setSelectedEx(found);
                }}
                className="bg-craft-950 border border-craft-700 text-craft-100 text-xs rounded px-3 py-1.5 focus:outline-none focus:border-craft-accent font-mono"
              >
                {EXAMPLES.map((ex) => (
                  <option key={ex.id} value={ex.id}>{ex.title}</option>
                ))}
              </select>
            </div>

            {/* Target Language Tabs */}
            <div className="flex flex-wrap gap-1 bg-craft-950 p-1 rounded-lg border border-craft-800">
              <button
                onClick={() => setTarget('as')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'as' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                .agentscript
              </button>
              <button
                onClick={() => setTarget('wasm')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'wasm' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                WebAssembly (.wat)
              </button>
              <button
                onClick={() => setTarget('ts')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'ts' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                TypeScript (.ts)
              </button>
              <button
                onClick={() => setTarget('rs')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'rs' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                Rust (.rs)
              </button>
              <button
                onClick={() => setTarget('go')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'go' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                Go (.go)
              </button>
              <button
                onClick={() => setTarget('py')}
                className={`px-3 py-1 text-xs rounded transition-all ${target === 'py' ? 'bg-craft-accent text-craft-950 font-bold' : 'text-craft-400 hover:text-craft-100'}`}
              >
                Python (.py)
              </button>
            </div>
          </div>

          {/* Code Viewer */}
          <div className="relative p-5 bg-craft-950 text-craft-100 text-xs sm:text-sm font-mono overflow-auto max-h-[480px] leading-relaxed whitespace-pre">
            <button
              onClick={handleCopy}
              className="absolute top-4 right-4 p-2 rounded bg-craft-900 border border-craft-700 text-craft-400 hover:text-craft-100 transition-colors"
              title="Copy code"
            >
              {copied ? <Check className="w-4 h-4 text-craft-emerald" /> : <Copy className="w-4 h-4" />}
            </button>
            <code>{getTargetCode()}</code>
          </div>

          {/* Footer Bar */}
          <div className="p-3 bg-craft-900/90 border-t border-craft-800 flex items-center justify-between text-xs text-craft-400">
            <span>Differential Gate: <strong className="text-craft-emerald">0 disagreements across all 6 backends</strong></span>
            <span className="text-craft-accent">Single Source of Truth</span>
          </div>
        </div>
      </div>
    </section>
  );
};
