import React, { useState } from 'react';
import { Zap, TrendingDown, DollarSign, Cpu, CheckCircle } from 'lucide-react';
import { BENCHMARKS } from '../lib/examples';

export const TokenCalculator: React.FC = () => {
  const [numModules, setNumModules] = useState(25);
  const [callsPerDay, setCallsPerDay] = useState(500);

  // Math calculations
  const standardTokens = numModules * 650 * callsPerDay;
  const asexTokens = numModules * 142 * callsPerDay;
  const tokensSaved = standardTokens - asexTokens;
  const costPerMillion = 3.0; // Claude/GPT-4o typical blend
  const monthlyCostStandard = ((standardTokens * 30) / 1_000_000) * costPerMillion;
  const monthlyCostAsex = ((asexTokens * 30) / 1_000_000) * costPerMillion;
  const monthlySavings = monthlyCostStandard - monthlyCostAsex;

  return (
    <section id="benchmarks" className="py-16 border-b border-craft-800 bg-craft-900/30 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-8">
          <div className="flex items-center gap-2 text-craft-accent text-xs uppercase tracking-wider mb-2">
            <Zap className="w-4 h-4" />
            <span>Token Economics & Benchmarks</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            78% Prompt Token Reduction for AI Workflows
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Because AgentScript interface compression (`asex_compress_module`) strips internal function bodies into stubbed signatures while retaining full type safety, multi-agent LLM calls use a fraction of the context window.
          </p>
        </div>

        {/* Calculator Widget & Benchmark Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Interactive Calculator */}
          <div className="lg:col-span-6 rounded-xl border border-craft-800 bg-craft-950 p-6 shadow-2xl">
            <h3 className="text-base font-bold text-craft-100 mb-4 flex items-center gap-2">
              <TrendingDown className="w-4 h-4 text-craft-accent" />
              <span>Interactive ROI & Context Estimator</span>
            </h3>

            <div className="space-y-4 mb-6 text-xs text-craft-300">
              <div>
                <div className="flex justify-between mb-1.5">
                  <span>Project Size (Imported Modules):</span>
                  <span className="text-craft-accent font-bold">{numModules} modules</span>
                </div>
                <input
                  type="range"
                  min="5"
                  max="100"
                  value={numModules}
                  onChange={(e) => setNumModules(Number(e.target.value))}
                  className="w-full accent-craft-accent cursor-pointer"
                />
              </div>

              <div>
                <div className="flex justify-between mb-1.5">
                  <span>Agent Invocations per Day:</span>
                  <span className="text-craft-accent font-bold">{callsPerDay} calls/day</span>
                </div>
                <input
                  type="range"
                  min="50"
                  max="5000"
                  step="50"
                  value={callsPerDay}
                  onChange={(e) => setCallsPerDay(Number(e.target.value))}
                  className="w-full accent-craft-accent cursor-pointer"
                />
              </div>
            </div>

            {/* Savings Cards */}
            <div className="grid grid-cols-2 gap-3 p-4 rounded-lg bg-craft-900/60 border border-craft-800">
              <div>
                <div className="text-[11px] text-craft-400">Monthly Tokens Saved</div>
                <div className="text-xl font-bold text-craft-accent mt-0.5">
                  {(tokensSaved * 30 / 1_000_000).toFixed(1)}M
                </div>
                <div className="text-[10px] text-craft-500">-78.1% context load</div>
              </div>

              <div>
                <div className="flex items-center gap-1 text-[11px] text-craft-400">
                  <DollarSign className="w-3.5 h-3.5 text-craft-emerald" />
                  <span>Est. Monthly Savings</span>
                </div>
                <div className="text-xl font-bold text-craft-emerald mt-0.5">
                  ${monthlySavings.toFixed(0)}
                </div>
                <div className="text-[10px] text-craft-500">at $3.0/M token blend</div>
              </div>
            </div>
          </div>

          {/* Performance Execution Benchmark Table */}
          <div className="lg:col-span-6 rounded-xl border border-craft-800 bg-craft-950 p-6 shadow-2xl flex flex-col justify-between">
            <div>
              <h3 className="text-base font-bold text-craft-100 mb-4 flex items-center gap-2">
                <Cpu className="w-4 h-4 text-craft-accent" />
                <span>Execution Speed (Measured Medians)</span>
              </h3>

              <div className="border border-craft-800 rounded-lg overflow-hidden text-xs">
                <div className="grid grid-cols-12 px-3 py-2 bg-craft-900 border-b border-craft-800 font-semibold text-craft-400">
                  <div className="col-span-6">Benchmark Task</div>
                  <div className="col-span-3 text-right">AgentScript / Wasm</div>
                  <div className="col-span-3 text-right">Python 3.13</div>
                </div>

                <div className="divide-y divide-craft-800/80">
                  {BENCHMARKS.slice(0, 3).map((b, i) => (
                    <div key={i} className="grid grid-cols-12 px-3 py-2.5 items-center hover:bg-craft-900/30">
                      <div className="col-span-6 text-craft-100 font-sans">{b.name}</div>
                      <div className="col-span-3 text-right font-bold text-craft-accent">{b.wasm}</div>
                      <div className="col-span-3 text-right text-craft-rose">{b.python}</div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="mt-4 pt-3 border-t border-craft-800 flex items-center justify-between text-xs text-craft-400">
              <span className="flex items-center gap-1.5 text-craft-emerald">
                <CheckCircle className="w-3.5 h-3.5" />
                <span>Zero-overhead WASI bounds checking</span>
              </span>
              <span className="text-craft-300">~30x faster than Python</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
