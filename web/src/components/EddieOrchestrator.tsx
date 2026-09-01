import React, { useState } from 'react';
import { Sparkles, Cpu, Zap, MessageSquare, Mic, Layers, Activity } from 'lucide-react';

interface Subtask {
  id: string;
  title: string;
  agent: string;
  durationMs: number;
}

interface OrchestrationState {
  layer1Triage: 'INSTANT' | 'CONSULT' | 'SWARM';
  layer2Intent: string;
  layer2Ambiguous: boolean;
  layer2FollowUps: string[];
  layer3Tier: string;
  layer3Subtasks: Subtask[];
  assignedAgents: string[];
  speculativeBranches: number;
  circuitBreakerLimit: number;
  totalLatencyMs: number;
}

export const EddieOrchestrator: React.FC = () => {
  const [prompt, setPrompt] = useState('Build a voice-controlled browser scraper with proxy pool');
  const [isVoiceActive, setIsVoiceActive] = useState(false);
  const [orchestration, setOrchestration] = useState<OrchestrationState>({
    layer1Triage: 'SWARM',
    layer2Intent: 'browser-nav / code-gen',
    layer2Ambiguous: true,
    layer2FollowUps: [
      "Which proxy protocol do you need (HTTP, SOCKS5, or SearXNG pool)?",
      "Should we enable automatic DOM element highlighting?"
    ],
    layer3Tier: 'tier-2 (Superposition)',
    layer3Subtasks: [
      { id: 'st-1', title: 'Synthesize browser navigation schema in ASL', agent: 'agent-planner', durationMs: 0.038 },
      { id: 'st-2', title: 'Compile in-memory WASI preview1 action dispatcher', agent: 'agent-coder', durationMs: 0.035 },
      { id: 'st-3', title: 'Verify 7 repository gates & differential checks', agent: 'agent-reviewer', durationMs: 0.041 }
    ],
    assignedAgents: ['agent-planner', 'agent-coder', 'agent-reviewer'],
    speculativeBranches: 2,
    circuitBreakerLimit: 2,
    totalLatencyMs: 0.038
  });

  const runPipeline = (text: string) => {
    setPrompt(text);
    const lower = text.toLowerCase();
    const t0 = performance.now();

    let triage: 'INSTANT' | 'CONSULT' | 'SWARM' = 'SWARM';
    let intent = 'code-gen';
    let ambiguous = false;
    let followUps: string[] = [];
    let tier = 'tier-2 (Superposition)';
    let subtasks: Subtask[] = [];
    let agents = ['agent-planner', 'agent-coder', 'agent-reviewer'];
    let branches = 2;

    if (lower.includes('calc') || lower.includes('fib') || lower.includes('2+2')) {
      triage = 'INSTANT';
      intent = 'deterministic-math';
      tier = 'tier-0 (Instant Wasm)';
      subtasks = [{ id: 'st-0', title: 'Execute pure in-memory Wasm binary', agent: 'wasm-executor', durationMs: 0.012 }];
      agents = ['wasm-executor'];
      branches = 0;
    } else if (lower.includes('deploy') || lower.includes('publish') || lower.includes('release')) {
      triage = 'CONSULT';
      intent = 'release-governance';
      ambiguous = true;
      followUps = ['Target environment confirmed as Cloudflare Pages production?', 'Run full monomorphism and differential gate suite?'];
      tier = 'tier-1 (Consultative Gate)';
      subtasks = [
        { id: 'st-1', title: 'Check Git working tree & tag consistency', agent: 'agent-auditor', durationMs: 0.025 },
        { id: 'st-2', title: 'Trigger differential gate runner across 6 targets', agent: 'agent-verifier', durationMs: 0.039 }
      ];
      agents = ['agent-auditor', 'agent-verifier'];
      branches = 1;
    } else {
      triage = 'SWARM';
      intent = 'multi-agent-synthesis';
      ambiguous = true;
      followUps = [
        "Which proxy protocol do you need (HTTP, SOCKS5, or SearXNG pool)?",
        "Should we enable automatic DOM element highlighting?"
      ];
      tier = 'tier-2 (Superposition Swarm)';
      subtasks = [
        { id: 'st-1', title: 'Synthesize browser navigation schema in ASL Nano', agent: 'agent-planner', durationMs: 0.038 },
        { id: 'st-2', title: 'Compile in-memory WASI preview1 action dispatcher', agent: 'agent-coder', durationMs: 0.035 },
        { id: 'st-3', title: 'Verify 7 repository gates & differential checks', agent: 'agent-reviewer', durationMs: 0.041 }
      ];
    }

    const dt = performance.now() - t0;
    setOrchestration({
      layer1Triage: triage,
      layer2Intent: intent,
      layer2Ambiguous: ambiguous,
      layer2FollowUps: followUps,
      layer3Tier: tier,
      layer3Subtasks: subtasks,
      assignedAgents: agents,
      speculativeBranches: branches,
      circuitBreakerLimit: 2,
      totalLatencyMs: dt || 0.038
    });
  };

  return (
    <section id="eddie" className="relative py-24 border-b border-craft-200 dark:border-craft-800/80 bg-craft-50/50 dark:bg-craft-950/70 transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Header Section with 3D Holographic Core */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center mb-12">
          <div className="lg:col-span-8 space-y-4 text-left">
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 dark:bg-purple-500/10 border border-purple-500/30 text-purple-600 dark:text-purple-400 text-xs font-mono">
              <Sparkles className="w-3.5 h-3.5" />
              <span>COMING SOON // AGENT HARNESS</span>
            </div>
            <h2 className="text-3xl sm:text-5xl font-extrabold tracking-tight text-craft-900 dark:text-craft-50 font-sans">
              Agent Harness: The Meta-Agent Engine
            </h2>
            <p className="text-craft-600 dark:text-craft-300 max-w-2xl text-sm sm:text-base leading-relaxed">
              The unified Agent Harness designed to orchestrate, supervise, and coordinate all autonomous agents. Layer 1 Fast Triage + Layer 2 Consultative Router + Layer 3 Task Pool Mesh.
            </p>

            <div className="flex flex-wrap items-center gap-3 pt-2">
              <button
                onClick={() => {
                  const nextVoice = !isVoiceActive;
                  setIsVoiceActive(nextVoice);
                  if (nextVoice) runPipeline("Voice: Hey Eddie, search for latest quantum benchmark and extract summary");
                }}
                className={`px-4 py-2 rounded-xl font-mono text-xs flex items-center gap-2 border transition-all ${
                  isVoiceActive
                    ? 'bg-rose-500/20 border-rose-500 text-rose-500 animate-pulse'
                    : 'bg-white dark:bg-craft-900 border-craft-300 dark:border-craft-700 text-craft-700 dark:text-craft-300 hover:border-craft-accent'
                }`}
              >
                <Mic className="w-3.5 h-3.5" />
                <span>{isVoiceActive ? 'Voice Stream Active' : 'Enable Voice Mode'}</span>
              </button>
              <div className="font-mono text-xs text-craft-600 dark:text-craft-400 bg-white dark:bg-craft-900 px-3.5 py-2 rounded-xl border border-craft-200 dark:border-craft-800">
                Package: <span className="text-amber-500 font-bold">@genseam/eddie</span>
              </div>
            </div>
          </div>

          {/* 3D Quantum Holographic Core Card */}
          <div className="lg:col-span-4 relative rounded-2xl overflow-hidden border border-craft-200 dark:border-craft-800 shadow-2xl group">
            <img
              src="/assets/images/eddie_core.jpg"
              alt="EDDIE Quantum Core"
              className="w-full h-56 object-cover group-hover:scale-105 transition-transform duration-700"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-craft-950 via-transparent to-transparent" />
            <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between text-[11px] font-mono text-white">
              <span className="flex items-center gap-1.5 text-craft-accent">
                <Activity className="w-3.5 h-3.5 animate-pulse" />
                QUANTUM MESH: READY
              </span>
              <span className="text-amber-400">LATENCY: 0.012ms</span>
            </div>
          </div>
        </div>

        {/* Interactive Simulator Bar */}
        <div className="bg-white dark:bg-craft-900/90 border border-craft-200 dark:border-craft-800 rounded-2xl p-6 mb-8 shadow-xl">
          <label className="block text-xs font-mono text-craft-600 dark:text-craft-400 mb-2 font-semibold text-left">
            Natural Language Instruction or Voice Stream:
          </label>
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="text"
              value={prompt}
              onChange={e => runPipeline(e.target.value)}
              className="flex-1 bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 text-craft-900 dark:text-white px-4 py-3 rounded-xl text-sm font-mono focus:outline-none focus:border-craft-accent transition-colors shadow-inner"
            />
            <button
              onClick={() => runPipeline(prompt)}
              className="px-6 py-3 bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-400 hover:to-orange-500 text-craft-950 font-bold text-xs font-mono rounded-xl transition-all shadow-md flex items-center justify-center gap-2"
            >
              <Zap className="w-3.5 h-3.5" />
              <span>Simulate Pipeline ($ asl eddie)</span>
            </button>
          </div>
        </div>

        {/* 3-Layer Visual Pipeline Columns */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Layer 1 */}
          <div className="bg-white dark:bg-craft-900/80 border border-craft-200 dark:border-craft-800/90 rounded-2xl p-6 flex flex-col justify-between shadow-lg text-left">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-craft-500 bg-craft-100 dark:bg-craft-800 px-2 py-0.5 rounded-md border border-craft-200 dark:border-craft-700">Layer 1</span>
                <span className="text-craft-emerald text-xs font-mono font-bold">0.012ms</span>
              </div>
              <div className="flex items-center gap-2 text-amber-500 font-mono text-sm font-semibold mb-1">
                <Cpu className="w-4 h-4" />
                <span>Primary Fast Triage</span>
              </div>
              <p className="text-xs text-craft-600 dark:text-craft-400 mb-4 leading-relaxed">
                Zero-latency heuristic classifier determining execution path.
              </p>
              
              <div className="bg-craft-50 dark:bg-craft-950 p-4 rounded-xl border border-craft-200 dark:border-craft-800 text-xs font-mono">
                <div className="text-craft-500">Triage Verdict:</div>
                <div className="text-xl font-bold text-craft-accent mt-0.5">{orchestration.layer1Triage}</div>
              </div>
            </div>
            <div className="mt-4 pt-3 border-t border-craft-200 dark:border-craft-800 text-[11px] font-mono text-craft-500">
              In-Memory 64KB Wasm Heuristic
            </div>
          </div>

          {/* Layer 2 */}
          <div className="bg-white dark:bg-craft-900/80 border border-craft-200 dark:border-craft-800/90 rounded-2xl p-6 flex flex-col justify-between shadow-lg text-left">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-craft-500 bg-craft-100 dark:bg-craft-800 px-2 py-0.5 rounded-md border border-craft-200 dark:border-craft-700">Layer 2</span>
                <span className="text-craft-purple text-xs font-mono font-bold">Consultative</span>
              </div>
              <div className="flex items-center gap-2 text-craft-purple font-mono text-sm font-semibold mb-1">
                <MessageSquare className="w-4 h-4" />
                <span>Refinement & Follow-ups</span>
              </div>
              <p className="text-xs text-craft-600 dark:text-craft-400 mb-4 leading-relaxed">
                Ambiguity detection, voice interaction, and intent clarification.
              </p>

              <div className="space-y-2">
                {orchestration.layer2FollowUps.map((fu, idx) => (
                  <div key={idx} className="p-2.5 rounded-xl bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 text-xs font-mono text-craft-700 dark:text-craft-300">
                    • {fu}
                  </div>
                ))}
              </div>
            </div>
            <div className="mt-4 pt-3 border-t border-craft-200 dark:border-craft-800 text-[11px] font-mono text-craft-500">
              Conversational & Voice Router
            </div>
          </div>

          {/* Layer 3 */}
          <div className="bg-white dark:bg-craft-900/80 border border-craft-200 dark:border-craft-800/90 rounded-2xl p-6 flex flex-col justify-between shadow-lg text-left">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-craft-500 bg-craft-100 dark:bg-craft-800 px-2 py-0.5 rounded-md border border-craft-200 dark:border-craft-700">Layer 3</span>
                <span className="text-craft-cyan text-xs font-mono font-bold">Task Pool Mesh</span>
              </div>
              <div className="flex items-center gap-2 text-craft-cyan font-mono text-sm font-semibold mb-1">
                <Layers className="w-4 h-4" />
                <span>Autonomous Task DAG</span>
              </div>
              <p className="text-xs text-craft-600 dark:text-craft-400 mb-4 leading-relaxed">
                Decomposed subtasks executed via native ASL Wasm or specialist agents.
              </p>

              <div className="space-y-2">
                {orchestration.layer3Subtasks.map((st) => (
                  <div key={st.id} className="p-2.5 rounded-xl bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 text-xs font-mono flex items-center justify-between">
                    <span className="truncate max-w-[180px] text-craft-800 dark:text-craft-200">{st.title}</span>
                    <span className="px-2 py-0.5 rounded-md bg-craft-100 dark:bg-craft-800 text-craft-accent text-[10px]">
                      {st.agent}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <div className="mt-4 pt-3 border-t border-craft-200 dark:border-craft-800 text-[11px] font-mono text-craft-500 flex items-center justify-between">
              <span>Circuit Breaker: 2 fails</span>
              <span className="text-craft-emerald">0.038ms</span>
            </div>
          </div>
        </div>

      </div>
    </section>
  );
};
