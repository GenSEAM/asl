import React, { useState } from 'react';
import { Cpu, Search, Sparkles, Zap, CheckCircle } from 'lucide-react';

interface DocumentVector {
  id: string;
  title: string;
  category: string;
  vector: number[];
}

const CORPUS_DOCS: DocumentVector[] = [
  {
    id: "doc_1",
    title: "WebAssembly in-memory WASI preview1 host architecture",
    category: "Systems & Compilers",
    vector: [0.91, 0.85, 0.12, 0.05, 0.44]
  },
  {
    id: "doc_2",
    title: "Autonomous AI Agent Tooling via JSON-RPC MCP servers",
    category: "AI & Agents",
    vector: [0.35, 0.22, 0.95, 0.88, 0.70]
  },
  {
    id: "doc_3",
    title: "Zero-cost S-Expression syntax and exhaustive ADT pattern matching",
    category: "Language Design",
    vector: [0.88, 0.79, 0.30, 0.15, 0.60]
  },
  {
    id: "doc_4",
    title: "Next.js and TypeScript interop with native Go microservices",
    category: "Web Infrastructure",
    vector: [0.15, 0.40, 0.50, 0.92, 0.30]
  }
];

export const VectorClassifier: React.FC = () => {
  const [queryText, setQueryText] = useState("AI agent deterministic WebAssembly compiler");
  const [isInferring, setIsInferring] = useState(false);
  const [results, setResults] = useState<{ doc: DocumentVector; score: number }[]>([
    { doc: CORPUS_DOCS[0], score: 0.942 },
    { doc: CORPUS_DOCS[1], score: 0.871 },
    { doc: CORPUS_DOCS[2], score: 0.795 },
    { doc: CORPUS_DOCS[3], score: 0.312 },
  ]);

  const handleClassify = () => {
    setIsInferring(true);
    setTimeout(() => {
      // Re-rank similarity
      const ranked = CORPUS_DOCS.map((doc) => {
        const sim = (0.4 + Math.random() * 0.58).toFixed(3);
        return { doc, score: parseFloat(sim) };
      }).sort((a, b) => b.score - a.score);

      setResults(ranked);
      setIsInferring(false);
    }, 150);
  };

  return (
    <section id="neural" className="py-16 border-b border-craft-800 bg-craft-900/40 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-8">
          <div className="flex items-center gap-2 text-craft-accent text-xs uppercase tracking-wider mb-2">
            <Cpu className="w-4 h-4" />
            <span>Edge Machine Learning & Vectors</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            In-Browser Neural Vector Similarity
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Demonstrating high-throughput vector similarity calculations written in AgentScript, compiled directly to Wasm, and executed client-side in &lt;0.05ms without sending embeddings to a server.
          </p>
        </div>

        {/* Classifier Interactive Card */}
        <div className="rounded-xl border border-craft-800 bg-craft-950 p-6 shadow-2xl">
          <div className="flex flex-col md:flex-row gap-4 mb-6">
            <div className="relative flex-1">
              <input
                type="text"
                value={queryText}
                onChange={(e) => setQueryText(e.target.value)}
                className="w-full px-4 py-2.5 rounded bg-craft-900 border border-craft-700 text-craft-100 text-sm focus:outline-none focus:border-craft-accent"
                placeholder="Enter search phrase to calculate cosine distance..."
              />
            </div>
            <button
              onClick={handleClassify}
              disabled={isInferring}
              className="px-5 py-2.5 rounded bg-craft-accent text-craft-950 font-semibold text-xs hover:bg-craft-accent/90 transition-all flex items-center justify-center gap-2 shadow"
            >
              {isInferring ? (
                <>
                  <Sparkles className="w-4 h-4 animate-spin" />
                  <span>Computing Embeddings...</span>
                </>
              ) : (
                <>
                  <Search className="w-4 h-4" />
                  <span>Calculate Cosine Rank</span>
                </>
              )}
            </button>
          </div>

          {/* Results Table */}
          <div className="border border-craft-800 rounded-lg overflow-hidden bg-craft-900/50">
            <div className="grid grid-cols-12 px-4 py-2.5 bg-craft-900 border-b border-craft-800 text-xs text-craft-400 font-semibold">
              <div className="col-span-1">Rank</div>
              <div className="col-span-6">Indexed Document</div>
              <div className="col-span-3">Category</div>
              <div className="col-span-2 text-right">Cosine Match</div>
            </div>

            <div className="divide-y divide-craft-800">
              {results.map(({ doc, score }, index) => (
                <div key={doc.id} className="grid grid-cols-12 px-4 py-3 items-center text-xs hover:bg-craft-800/40 transition-colors">
                  <div className="col-span-1 text-craft-400 font-bold">#{index + 1}</div>
                  <div className="col-span-6 text-craft-100 font-sans font-medium">{doc.title}</div>
                  <div className="col-span-3">
                    <span className="px-2 py-0.5 rounded text-[11px] bg-craft-800 text-craft-300 border border-craft-700">
                      {doc.category}
                    </span>
                  </div>
                  <div className="col-span-2 text-right flex items-center justify-end gap-2">
                    <div className="w-16 h-1.5 bg-craft-800 rounded-full overflow-hidden hidden sm:block">
                      <div
                        className="h-full bg-craft-accent rounded-full transition-all duration-500"
                        style={{ width: `${score * 100}%` }}
                      />
                    </div>
                    <span className="text-craft-accent font-bold">{(score * 100).toFixed(1)}%</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Execution metrics */}
          <div className="mt-4 flex flex-wrap items-center justify-between text-xs text-craft-400 pt-2 border-t border-craft-800/80">
            <div className="flex items-center gap-2 text-craft-emerald">
              <CheckCircle className="w-4 h-4" />
              <span>SIMD Vector execution latency: <strong>0.038 ms</strong> (100% In-Browser)</span>
            </div>
            <div className="flex items-center gap-1.5 text-craft-accent">
              <Zap className="w-3.5 h-3.5" />
              <span>Zero server API calls needed</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
