import React, { useState } from 'react';
import { BookMarked, Copy, Check, Terminal, Cpu, Bot, GitBranch, Layers, ShieldCheck } from 'lucide-react';

interface Recipe {
  id: string;
  title: string;
  category: string;
  icon: any;
  summary: string;
  codeSnippet: string;
  language: string;
  benefits: string[];
}

export const BestPractices: React.FC = () => {
  const [activeRecipeId, setActiveRecipeId] = useState('wasm-sandbox');
  const [copied, setCopied] = useState(false);

  const RECIPES: Recipe[] = [
    {
      id: 'wasm-sandbox',
      title: 'In-Browser WebAssembly Sandbox',
      category: 'Frontend & Edge',
      icon: Cpu,
      summary: 'Execute agent-generated ASL Wasm binaries in React/Next.js with memory isolation and <1ms execution latency.',
      language: 'typescript',
      codeSnippet: `import { runWasmInBrowser } from './wasm_runner';

// Execute in-memory WebAssembly preview1 sandbox
async function executeAgentCode(wasmBytes: Uint8Array) {
  const result = await runWasmInBrowser(wasmBytes, ["app"], "input data");
  console.log("Stdout:", result.stdout);
  console.log("Exit Code:", result.exitCode);
  console.log("Duration:", result.durationMs, "ms");
}`,
      benefits: ['Zero-cost isolation', '<1ms execution', 'No backend container needed']
    },
    {
      id: 'agent-mcp',
      title: 'Multi-Agent MCP Tooling Loop',
      category: 'Agent Workflows',
      icon: Bot,
      summary: 'Wire the ASL MCP server to Claude Desktop or Cursor for 0-drift type checking and -78% prompt compression.',
      language: 'json',
      codeSnippet: `// Claude Desktop / Cursor MCP Configuration
{
  "mcpServers": {
    "asl": {
      "command": "asl",
      "args": ["mcp"]
    }
  }
}

// Workflow: asex_check -> asex_eval -> asex_compress_module`,
      benefits: ['-78% token context load', 'Zero syntax repair loops', 'Instant in-memory validation']
    },
    {
      id: 'cross-compilation',
      title: 'Cross-Compilation CI/CD Pipeline',
      category: 'Production DevOps',
      icon: GitBranch,
      summary: 'Transpile a single ASL business logic module into React/TypeScript, native Rust, and cloud Go microservices.',
      language: 'bash',
      codeSnippet: `# 1. Semantic verification
asl check src/main.agentscript

# 2. Build WebAssembly binary
asl build src/main.agentscript --target wasm -o dist/main.wasm

# 3. Transpile to React/TypeScript & Rust & Go
asl build src/main.agentscript --target ts -o src/generated/main.ts
asl build src/main.agentscript --target rs -o crates/core/src/main.rs
asl build src/main.agentscript --target go -o cmd/server/main.go`,
      benefits: ['1 Source of Truth', '0 semantic drift', 'Native speed everywhere']
    },
    {
      id: 'vfs-scratchpad',
      title: 'Agent VFS Scratchpad & AST Refactoring',
      category: 'AI Architecture',
      icon: Layers,
      summary: 'Let AI agents test algorithmic hypotheses and batch AST transformations in virtual memory before touching disk.',
      language: 'lisp',
      codeSnippet: `(module agent/scratchpad
  :doc "In-memory AST search & optimization"
  :export [optimize-tree Node]
  :import [(core/math :as m)])

(defschema Node
  (:field id Int64 "AST node id")
  (:field cost Float64 "Evaluation weight"))

(defun optimize-tree [(nodes (List Node))] -> (List Node)
  (match nodes
    ((list) (list))
    ((cons h t) (cons h (optimize-tree t)))))`,
      benefits: ['Safe exploratory execution', 'Zero host risk', 'Deterministic output']
    }
  ];

  const activeRecipe = RECIPES.find((r) => r.id === activeRecipeId) || RECIPES[0];

  const handleCopy = () => {
    navigator.clipboard.writeText(activeRecipe.codeSnippet);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="recipes" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-10">
          <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
            <BookMarked className="w-3.5 h-3.5" />
            <span>Patterns, Recipes & Anti-Patterns</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            Best Practices & Integration Recipes
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Tested integration patterns for embedding ASL into browser apps, multi-agent MCP loops, and cross-platform production pipelines.
          </p>
        </div>

        {/* Recipe Grid Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Recipe List Switcher */}
          <div className="lg:col-span-4 space-y-2">
            {RECIPES.map((r) => {
              const Icon = r.icon;
              return (
                <button
                  key={r.id}
                  onClick={() => setActiveRecipeId(r.id)}
                  className={`w-full p-4 rounded-xl border text-left transition-all ${
                    activeRecipeId === r.id
                      ? 'bg-craft-900 border-craft-accent shadow-lg shadow-craft-accent/5'
                      : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
                  }`}
                >
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-[10px] text-craft-500 uppercase tracking-wider">{r.category}</span>
                    <Icon className={`w-4 h-4 ${activeRecipeId === r.id ? 'text-craft-accent' : 'text-craft-400'}`} />
                  </div>
                  <h4 className={`text-sm font-bold ${activeRecipeId === r.id ? 'text-craft-50' : 'text-craft-200'}`}>
                    {r.title}
                  </h4>
                </button>
              );
            })}

            <div className="p-4 rounded-xl border border-craft-800 bg-craft-900/20 text-xs space-y-2 text-craft-400 font-sans mt-4">
              <div className="text-craft-200 font-mono font-bold text-[11px] uppercase tracking-wider">
                Key Anti-Patterns to Avoid:
              </div>
              <ul className="list-disc list-inside space-y-1 text-[11px] text-craft-400">
                <li>Never use silent null returns (use Option)</li>
                <li>Never use catch-all wildcards in match</li>
                <li>Never ignore ! effect markers on I/O functions</li>
              </ul>
            </div>
          </div>

          {/* Active Recipe Code & Details */}
          <div className="lg:col-span-8 space-y-4">
            <div className="p-6 rounded-xl border border-craft-800 bg-craft-900/50 shadow-2xl">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <span className="text-xs text-craft-accent font-semibold">{activeRecipe.category}</span>
                  <h3 className="text-xl font-bold text-craft-50 mt-0.5">{activeRecipe.title}</h3>
                </div>
                <button
                  onClick={handleCopy}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded bg-craft-800 border border-craft-700 text-craft-200 hover:text-craft-50 hover:border-craft-600 text-xs transition-colors"
                >
                  {copied ? <Check className="w-3.5 h-3.5 text-craft-emerald" /> : <Copy className="w-3.5 h-3.5" />}
                  <span>{copied ? 'Copied' : 'Copy Snippet'}</span>
                </button>
              </div>

              <p className="text-xs text-craft-300 font-sans leading-relaxed mb-4">
                {activeRecipe.summary}
              </p>

              {/* Code Snippet Box */}
              <div className="rounded-lg border border-craft-800 bg-craft-950 p-4 text-xs overflow-x-auto mb-4">
                <div className="flex items-center justify-between text-[11px] text-craft-500 mb-2 border-b border-craft-800/80 pb-1.5">
                  <span className="flex items-center gap-1.5 text-craft-400">
                    <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                    <span>Integration Blueprint</span>
                  </span>
                  <span>{activeRecipe.language.toUpperCase()}</span>
                </div>
                <pre className="text-craft-200 leading-relaxed font-mono">
                  {activeRecipe.codeSnippet}
                </pre>
              </div>

              {/* Benefits Checklist */}
              <div className="flex flex-wrap gap-3 text-xs pt-2 border-t border-craft-800/80">
                {activeRecipe.benefits.map((b, i) => (
                  <span key={i} className="flex items-center gap-1.5 text-craft-400">
                    <ShieldCheck className="w-3.5 h-3.5 text-craft-emerald" />
                    <span>{b}</span>
                  </span>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
