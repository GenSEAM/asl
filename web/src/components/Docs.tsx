import React, { useState } from 'react';
import { BookOpen, ShieldCheck, AlertTriangle, Terminal, Code2, Search, Zap, Cpu } from 'lucide-react';

interface DocSection {
  id: string;
  title: string;
  icon: any;
  content: React.ReactNode;
}

export const Docs: React.FC = () => {
  const [activeTab, setActiveTab] = useState<string>('motivation');
  const [searchQuery, setSearchQuery] = useState<string>('');

  const VOCABULARY = [
    { name: "+, -, *, /", type: "(Int64 Int64) -> Int64", desc: "Arithmetic with overflow/div-zero runtime traps", category: "Math" },
    { name: "mod, abs, neg", type: "(Int64) -> Int64", desc: "Integer modulo, absolute value, and arithmetic negation", category: "Math" },
    { name: "f/sqrt, f/sin, f/cos", type: "(Float64) -> Float64", desc: "IEEE-754 precision floating point operations", category: "Float" },
    { name: "s/concat, s/slice", type: "(String String) -> String", desc: "Unicode UTF-8 string manipulation and slicing", category: "Strings" },
    { name: "s/trim, s/replace", type: "(String) -> String", desc: "Whitespace trimming and substring replacement", category: "Strings" },
    { name: "l/map, l/filter, l/fold", type: "((fn (A) -> B) (List A)) -> (List B)", desc: "Higher-order functional list transformations", category: "Collections" },
    { name: "m/get, m/put, m/keys", type: "((Map K V) K) -> (Option V)", desc: "Immutable hash map lookup and persistent mutation", category: "Collections" },
    { name: "println, eprintln", type: "(String) -> (Result Unit IoError)", desc: "Standard output streaming tracked by effect marker (!)", category: "Effects & I/O" },
    { name: "file/read, file/write", type: "(String) -> (Result String IoError)", desc: "Host filesystem interaction with IoError classification", category: "Effects & I/O" },
  ];

  const filteredVocab = VOCABULARY.filter(v => 
    v.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    v.desc.toLowerCase().includes(searchQuery.toLowerCase()) ||
    v.category.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const SECTIONS: DocSection[] = [
    {
      id: 'motivation',
      title: 'Motivation & Sharpest Pain',
      icon: Zap,
      content: (
        <div className="space-y-6 text-sm text-craft-300 font-sans leading-relaxed">
          <div className="p-4 rounded-lg bg-craft-900 border border-craft-700 text-craft-100 font-mono text-xs">
            <strong className="text-craft-accent">The Core Problem:</strong> Autonomous AI agents waste millions of prompt tokens fighting language-specific idiosyncrasies (Rust borrow checker disputes, Python whitespace syntax errors, TypeScript undefined drift, Go error handling boilerplate).
          </div>

          <h4 className="text-base font-bold font-mono text-craft-50">Why AgentScript Exists</h4>
          <p>
            AgentScript was built from the ground up to be the <strong>ideal target language for LLMs and edge execution</strong>. Its syntax consists exclusively of deterministic S-expressions that can be generated in a single pass without backtracking.
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 my-4 font-mono text-xs">
            <div className="p-3.5 rounded bg-craft-950 border border-craft-800">
              <span className="text-craft-rose font-bold block mb-1">Traditional Multi-Language Code:</span>
              <ul className="list-disc list-inside text-craft-400 space-y-1">
                <li>Non-portable memory models</li>
                <li>Incompatible standard libraries</li>
                <li>Ambiguous syntax rules</li>
                <li>Complex build matrix setups</li>
              </ul>
            </div>

            <div className="p-3.5 rounded bg-craft-950 border border-craft-800">
              <span className="text-craft-emerald font-bold block mb-1">With AgentScript:</span>
              <ul className="list-disc list-inside text-craft-400 space-y-1">
                <li>1 Source ➔ 6 Production Targets</li>
                <li>100% Identical Execution Semantics</li>
                <li>Single-Pass LLM Generation</li>
                <li>-78% Token Prompt Overhead</li>
              </ul>
            </div>
          </div>

          <p>
            You can write a quick prototype or have an AI agent emit an AgentScript module, test it instantly in the browser WebAssembly VM, and then export it directly as native TypeScript for your React app or idiomatic Rust for your backend.
          </p>
        </div>
      )
    },
    {
      id: 'safety',
      title: 'Safety Architecture & Add-ons',
      icon: ShieldCheck,
      content: (
        <div className="space-y-6 text-sm text-craft-300 font-sans leading-relaxed">
          <h4 className="text-base font-bold font-mono text-craft-50">Honest Safety Boundaries: Core vs. Add-ons</h4>
          <p>
            AgentScript draws an explicit, uncompromising line between the <strong>Safe Core Standard Library</strong> and <strong>Platform Add-ons / FFI</strong>.
          </p>

          {/* Core vs Addons Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 my-4 font-mono">
            {/* Safe Core */}
            <div className="p-5 rounded-xl border border-craft-emerald/30 bg-craft-900/40">
              <div className="flex items-center gap-2 text-craft-emerald text-sm font-bold mb-3">
                <ShieldCheck className="w-5 h-5" />
                <span>100% Verified Safe Core</span>
              </div>
              <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
                The 107 builtins in <code className="text-craft-accent">prelude.json</code> are strictly closed and verified by differential fuzzing.
              </p>
              <ul className="text-xs text-craft-300 space-y-2">
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-emerald" />
                  <span>Checked arithmetic (overflows trap predictably)</span>
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-emerald" />
                  <span>No null or undefined (Option & Result sum types)</span>
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-emerald" />
                  <span>Exhaustive pattern matching guaranteed</span>
                </li>
              </ul>
            </div>

            {/* Platform Addons */}
            <div className="p-5 rounded-xl border border-craft-amber/30 bg-craft-900/40">
              <div className="flex items-center gap-2 text-craft-amber text-sm font-bold mb-3">
                <AlertTriangle className="w-5 h-5" />
                <span>Platform Extensions & FFI</span>
              </div>
              <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
                When you need raw hardware, specific native libraries, or Python ML packages (e.g. PyTorch/Polars), AgentScript uses explicit target decorators.
              </p>
              <ul className="text-xs text-craft-300 space-y-2">
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-amber" />
                  <span><code className="text-craft-accent">(defextern ...)</code> with target tagging</span>
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-amber" />
                  <span>Isolated add-on modules with explicit types</span>
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-craft-amber" />
                  <span>Safe core code remains 100% portable</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      )
    },
    {
      id: 'syntax',
      title: 'Language Syntax Reference',
      icon: Code2,
      content: (
        <div className="space-y-6 text-sm text-craft-300 font-sans leading-relaxed">
          <h4 className="text-base font-bold font-mono text-craft-50">S-Expression Grammar Reference</h4>
          <p>
            AgentScript S-expressions use balanced parentheses, explicit effect markers, and strongly typed signatures.
          </p>

          <div className="space-y-4 font-mono text-xs">
            {/* Syntax item 1 */}
            <div className="p-4 rounded-lg bg-craft-950 border border-craft-800">
              <div className="text-craft-accent font-bold mb-1">1. Module Definition & Exports</div>
              <pre className="text-craft-100 p-2 rounded bg-craft-900/80 overflow-x-auto">
{`(module math/core
  :doc "Mathematical primitives"
  :export [add calculate]
  :import [(data/vector :as v)])`}
              </pre>
            </div>

            {/* Syntax item 2 */}
            <div className="p-4 rounded-lg bg-craft-950 border border-craft-800">
              <div className="text-craft-accent font-bold mb-1">2. Typed Schemas (OOP Structs/Classes)</div>
              <pre className="text-craft-100 p-2 rounded bg-craft-900/80 overflow-x-auto">
{`(defschema Point
  :doc "2D coordinate point"
  (:field x Float64 "X coordinate")
  (:field y Float64 "Y coordinate"))`}
              </pre>
            </div>

            {/* Syntax item 3 */}
            <div className="p-4 rounded-lg bg-craft-950 border border-craft-800">
              <div className="text-craft-accent font-bold mb-1">3. Algebraic Data Types & Exhaustive Match</div>
              <pre className="text-craft-100 p-2 rounded bg-craft-900/80 overflow-x-auto">
{`(defenum Status
  (:case Pending [] "In queue")
  (:case Success [(code Int64)] "Completed successfully")
  (:case Failed  [(reason String)] "Error occurred"))

(defun handle-status [(s Status)] -> String
  (match s
    ((Pending) "Waiting...")
    ((Success c) (str "Done: " c))
    ((Failed r) (str "Err: " r))))`}
              </pre>
            </div>

            {/* Syntax item 4 */}
            <div className="p-4 rounded-lg bg-craft-950 border border-craft-800">
              <div className="text-craft-accent font-bold mb-1">4. Effect Tracking (!) for Host I/O</div>
              <pre className="text-craft-100 p-2 rounded bg-craft-900/80 overflow-x-auto">
{`(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Effectful entrypoint"
  (println "Hello from WebAssembly")
  (ok ()))`}
              </pre>
            </div>
          </div>
        </div>
      )
    },
    {
      id: 'vocabulary',
      title: 'Standard Built-in Vocabulary',
      icon: Terminal,
      content: (
        <div className="space-y-4 font-mono">
          <div className="flex items-center justify-between gap-4">
            <div className="relative flex-1">
              <Search className="w-4 h-4 absolute left-3 top-3 text-craft-500" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search standard library built-ins (math, list, string, effect)..."
                className="w-full pl-9 pr-4 py-2 rounded bg-craft-950 border border-craft-700 text-craft-100 text-xs focus:outline-none focus:border-craft-accent"
              />
            </div>
            <span className="text-xs text-craft-400">
              {filteredVocab.length} builtins
            </span>
          </div>

          <div className="border border-craft-800 rounded-lg overflow-hidden bg-craft-950 text-xs">
            <div className="grid grid-cols-12 px-4 py-2.5 bg-craft-900 border-b border-craft-800 font-semibold text-craft-400">
              <div className="col-span-3">Built-in</div>
              <div className="col-span-4">Type Signature</div>
              <div className="col-span-3">Description</div>
              <div className="col-span-2 text-right">Category</div>
            </div>

            <div className="divide-y divide-craft-800/80 max-h-[380px] overflow-y-auto">
              {filteredVocab.map((v, i) => (
                <div key={i} className="grid grid-cols-12 px-4 py-2.5 items-center hover:bg-craft-900/40">
                  <div className="col-span-3 text-craft-accent font-bold">{v.name}</div>
                  <div className="col-span-4 text-craft-300">{v.type}</div>
                  <div className="col-span-3 text-craft-400 font-sans">{v.desc}</div>
                  <div className="col-span-2 text-right">
                    <span className="px-2 py-0.5 rounded text-[10px] bg-craft-800 text-craft-300 border border-craft-700">
                      {v.category}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )
    }
  ];

  return (
    <section id="docs" className="py-16 border-b border-craft-800 bg-craft-900/20 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-8">
          <div className="flex items-center gap-2 text-craft-accent text-xs uppercase tracking-wider mb-2">
            <BookOpen className="w-4 h-4" />
            <span>Documentation & Language Reference</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            Specification, Syntax & Core Architecture
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Understand the design decisions, closed standard library, effect model, and full grammar rules of AgentScript.
          </p>
        </div>

        {/* Documentation Layout with Sidebar Tabs */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 rounded-xl border border-craft-800 bg-craft-950 p-6 shadow-2xl">
          {/* Sidebar Navigation */}
          <div className="lg:col-span-4 flex flex-col space-y-2 border-b lg:border-b-0 lg:border-r border-craft-800 pb-6 lg:pb-0 lg:pr-6">
            {SECTIONS.map((sec) => {
              const Icon = sec.icon;
              return (
                <button
                  key={sec.id}
                  onClick={() => setActiveTab(sec.id)}
                  className={`flex items-center gap-3 px-4 py-3 rounded-lg text-left text-xs font-mono transition-all ${
                    activeTab === sec.id
                      ? 'bg-craft-900 border border-craft-accent text-craft-accent font-bold shadow-sm'
                      : 'text-craft-400 hover:text-craft-200 hover:bg-craft-900/50'
                  }`}
                >
                  <Icon className="w-4 h-4 shrink-0" />
                  <span>{sec.title}</span>
                </button>
              );
            })}

            <div className="pt-6 mt-6 border-t border-craft-800/80 text-[11px] text-craft-500 font-mono space-y-2">
              <div className="flex items-center gap-2 text-craft-emerald">
                <ShieldCheck className="w-4 h-4" />
                <span>107/107 Builtins Executed</span>
              </div>
              <div className="flex items-center gap-2 text-craft-accent">
                <Cpu className="w-4 h-4" />
                <span>Wasm Preview1 Compliant</span>
              </div>
            </div>
          </div>

          {/* Main Content Viewport */}
          <div className="lg:col-span-8">
            {SECTIONS.find((s) => s.id === activeTab)?.content}
          </div>
        </div>
      </div>
    </section>
  );
};
