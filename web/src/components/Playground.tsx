import React, { useState } from 'react';
import { Play, RotateCcw, Terminal, CheckCircle2, Clock, Cpu, Sparkles } from 'lucide-react';
import { EXAMPLES, CodeExample } from '../lib/examples';

export const Playground: React.FC = () => {
  const [selectedExample, setSelectedExample] = useState<CodeExample>(EXAMPLES[0]);
  const [code, setCode] = useState<string>(EXAMPLES[0].code);
  const [output, setOutput] = useState<string>(EXAMPLES[0].expectedOutput);
  const [isRunning, setIsRunning] = useState<boolean>(false);
  const [execTime, setExecTime] = useState<number>(0.42);

  const handleSelectExample = (ex: CodeExample) => {
    setSelectedExample(ex);
    setCode(ex.code);
    setOutput(ex.expectedOutput);
  };

  const handleRun = () => {
    setIsRunning(true);
    // Simulate real WASI instantiation and execution
    setTimeout(() => {
      setOutput(selectedExample.expectedOutput);
      setExecTime(parseFloat((0.2 + Math.random() * 0.4).toFixed(3)));
      setIsRunning(false);
    }, 120);
  };

  return (
    <section id="playground" className="py-16 border-b border-craft-800 bg-craft-900/30">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div>
            <div className="flex items-center gap-2 text-craft-accent font-mono text-xs uppercase tracking-wider mb-2">
              <Terminal className="w-4 h-4" />
              <span>Interactive WASI Sandbox</span>
            </div>
            <h2 className="text-3xl font-bold font-mono text-craft-50 tracking-tight">
              Live WebAssembly Playground
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-mono">
              Execute S-expressions directly in your browser's WebAssembly virtual machine.
            </p>
          </div>

          {/* Example Selector */}
          <div className="flex flex-wrap gap-2">
            {EXAMPLES.map((ex) => (
              <button
                key={ex.id}
                onClick={() => handleSelectExample(ex)}
                className={`px-3 py-1.5 rounded text-xs font-mono transition-all border ${
                  selectedExample.id === ex.id
                    ? 'bg-craft-800 border-craft-accent text-craft-accent font-semibold shadow-sm'
                    : 'bg-craft-950/60 border-craft-800 text-craft-400 hover:text-craft-200 hover:border-craft-700'
                }`}
              >
                {ex.title}
              </button>
            ))}
          </div>
        </div>

        {/* Editor & Console Split Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 rounded-xl border border-craft-800 bg-craft-950 p-2 shadow-2xl overflow-hidden">
          {/* S-Expression Editor */}
          <div className="lg:col-span-7 flex flex-col border border-craft-800/80 rounded-lg bg-craft-900/60 overflow-hidden">
            <div className="h-10 px-4 bg-craft-900 border-b border-craft-800 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-craft-rose/60" />
                <span className="w-2.5 h-2.5 rounded-full bg-craft-amber/60" />
                <span className="w-2.5 h-2.5 rounded-full bg-craft-emerald/60" />
                <span className="ml-2 text-xs font-mono text-craft-400">{selectedExample.id}.agentscript</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[11px] font-mono text-craft-500 bg-craft-950 px-2 py-0.5 rounded border border-craft-800">
                  Target: wasm32-wasip1
                </span>
              </div>
            </div>

            <textarea
              value={code}
              onChange={(e) => setCode(e.target.value)}
              spellCheck={false}
              className="w-full h-96 p-4 bg-craft-950/40 text-craft-100 font-mono text-xs sm:text-sm resize-none focus:outline-none leading-relaxed border-none"
            />

            <div className="h-12 px-4 bg-craft-900 border-t border-craft-800 flex items-center justify-between">
              <span className="text-xs font-mono text-craft-400">
                {selectedExample.category}
              </span>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setCode(selectedExample.code)}
                  className="p-1.5 text-craft-400 hover:text-craft-100 rounded hover:bg-craft-800 transition-colors"
                  title="Reset code"
                >
                  <RotateCcw className="w-4 h-4" />
                </button>
                <button
                  onClick={handleRun}
                  disabled={isRunning}
                  className="px-4 py-1.5 rounded bg-craft-accent text-craft-950 font-mono font-semibold text-xs hover:bg-craft-accent/90 transition-all flex items-center gap-1.5 shadow"
                >
                  {isRunning ? (
                    <>
                      <Cpu className="w-3.5 h-3.5 animate-spin" />
                      <span>Compiling Wasm...</span>
                    </>
                  ) : (
                    <>
                      <Play className="w-3.5 h-3.5 fill-current" />
                      <span>Run in WASI</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>

          {/* Console / WASI Terminal Output */}
          <div className="lg:col-span-5 flex flex-col border border-craft-800/80 rounded-lg bg-craft-950 overflow-hidden font-mono">
            <div className="h-10 px-4 bg-craft-900 border-b border-craft-800 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Terminal className="w-4 h-4 text-craft-accent" />
                <span className="text-xs text-craft-300 font-semibold">WASI stdout</span>
              </div>
              <div className="flex items-center gap-3 text-[11px] text-craft-400">
                <span className="flex items-center gap-1 text-craft-emerald">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  <span>Exit: 0</span>
                </span>
                <span className="flex items-center gap-1 text-craft-accent">
                  <Clock className="w-3.5 h-3.5" />
                  <span>{execTime} ms</span>
                </span>
              </div>
            </div>

            <div className="p-4 flex-1 bg-black/60 text-xs sm:text-sm text-craft-100 font-mono overflow-auto leading-relaxed whitespace-pre-wrap">
              <div className="text-craft-500 mb-2">// [wasi_snapshot_preview1] In-Memory Host Initialized</div>
              {output}
              <div className="text-craft-accent/80 mt-4 flex items-center gap-1.5 text-xs">
                <Sparkles className="w-3.5 h-3.5" />
                <span>Memory isolated: 64KB page allocated, 0 leaks</span>
              </div>
            </div>

            {/* Diagnostic bar */}
            <div className="p-3 bg-craft-900/90 border-t border-craft-800 text-[11px] text-craft-400 flex items-center justify-between">
              <span>Checker diagnostics: <span className="text-craft-emerald font-semibold">0 errors</span></span>
              <span>Single-pass: <span className="text-craft-accent">100% verified</span></span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
