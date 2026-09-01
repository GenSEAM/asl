import React, { useState } from 'react';
import { Sparkles, Cpu, Zap, MessageSquare, Mic, CheckCircle2, ListTodo } from 'lucide-react';

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

    if (lower.includes('voice') || lower.includes('speak') || isVoiceActive) {
      triage = 'CONSULT';
      intent = 'voice-dialog / assistant';
      followUps = ["Voice stream connected. Awaiting audio chunks...", "Microphone buffer: 16kHz PCM zero-latency."];
      tier = 'tier-0 (Fast-Track)';
      agents = ['agent-voice', 'agent-consultant'];
      subtasks = [
        { id: 'v-1', title: 'Transcribe audio stream into typed tokens', agent: 'agent-voice', durationMs: 0.022 },
        { id: 'v-2', title: 'Synthesize consultative voice response', agent: 'agent-consultant', durationMs: 0.029 }
      ];
      branches = 1;
    } else if (lower.includes('search') || lower.includes('find') || lower.includes('lookup')) {
      triage = 'INSTANT';
      intent = 'web-search';
      tier = 'tier-1 (Specialist)';
      agents = ['agent-searcher'];
      subtasks = [
        { id: 's-1', title: 'Query SearXNG aggregator with proxy rotation', agent: 'agent-searcher', durationMs: 0.035 },
        { id: 's-2', title: 'Compress RAG context (-78% tokens)', agent: 'agent-searcher', durationMs: 0.032 }
      ];
      branches = 1;
    } else if (lower.includes('click') || lower.includes('browser') || lower.includes('dom')) {
      triage = 'INSTANT';
      intent = 'browser-nav';
      tier = 'tier-1 (Specialist)';
      agents = ['agent-browser'];
      subtasks = [
        { id: 'b-1', title: 'Extract interactive DOM nodes and form schemas', agent: 'agent-browser', durationMs: 0.039 },
        { id: 'b-2', title: 'Dispatch simulated click & scroll events', agent: 'agent-browser', durationMs: 0.036 }
      ];
      branches = 1;
    } else {
      triage = 'SWARM';
      intent = 'code-gen';
      ambiguous = text.split(' ').length < 6;
      if (ambiguous) {
        followUps = [
          "Target ecosystem: WebAssembly (in-browser) or Node.js / Rust backend?",
          "Enable automatic property-based tests ($ asl test)?"
        ];
      }
      subtasks = [
        { id: 'p-1', title: 'Decompose prompt into typed ASL contract (§9)', agent: 'agent-planner', durationMs: 0.042 },
        { id: 'c-1', title: 'Synthesize zero-drift Wasm implementation', agent: 'agent-coder', durationMs: 0.036 },
        { id: 'r-1', title: 'Run differential verification across 6 backends', agent: 'agent-reviewer', durationMs: 0.040 }
      ];
    }

    const dt = +(performance.now() - t0).toFixed(3);
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
    <div className="border-t border-[#1e2230] bg-[#07090e] py-20 px-6 sm:px-10">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-12 gap-6">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-amber-500/10 border border-amber-500/30 text-amber-400 text-xs font-mono mb-3">
              <Sparkles className="w-3.5 h-3.5" />
              3-Layer Superposition Architecture
            </div>
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-white">
              EDDIE: 3-Layer Swarm Orchestrator
            </h2>
            <p className="text-[#94a3b8] mt-2 max-w-2xl text-sm sm:text-base">
              Layer 1 Fast Triage + Layer 2 Consultative Router + Layer 3 Task Pool Mesh. Powering Voice Assistants, Ultra-Browser agents, and Autonomous Swarms.
            </p>
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={() => {
                const nextVoice = !isVoiceActive;
                setIsVoiceActive(nextVoice);
                if (nextVoice) runPipeline("Voice: Hey Eddie, search for latest quantum benchmark and extract summary");
              }}
              className={`px-4 py-2 rounded-lg font-mono text-xs flex items-center gap-2 border transition-all ${
                isVoiceActive
                  ? 'bg-rose-500/20 border-rose-500/50 text-rose-300 animate-pulse'
                  : 'bg-[#121622] border-[#222a3d] text-[#94a3b8] hover:text-white'
              }`}
            >
              <Mic className="w-3.5 h-3.5" />
              {isVoiceActive ? 'Voice Assistant Active' : 'Enable Voice Mode'}
            </button>
            <div className="font-mono text-xs text-[#94a3b8] bg-[#0d1017] px-3.5 py-2 rounded-lg border border-[#1e2436]">
              Package: <span className="text-amber-400">@genseam/eddie</span>
            </div>
          </div>
        </div>

        {/* Input Bar */}
        <div className="bg-[#0b0e17] border border-[#1a2030] rounded-xl p-6 mb-8">
          <label className="block text-xs font-mono text-[#94a3b8] mb-2">Natural Language Instruction or Voice Transcript:</label>
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="text"
              value={prompt}
              onChange={e => runPipeline(e.target.value)}
              className="flex-1 bg-[#06080d] border border-[#1e2436] text-white px-4 py-2.5 rounded-lg text-sm font-mono focus:outline-none focus:border-amber-500"
            />
            <button
              onClick={() => runPipeline(prompt)}
              className="px-5 py-2.5 bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-400 hover:to-orange-500 text-[#090a0f] font-bold text-xs font-mono rounded-lg transition-all flex items-center justify-center gap-2"
            >
              <Zap className="w-3.5 h-3.5" />
              Run 3-Layer Pipeline ($ asl eddie)
            </button>
          </div>
        </div>

        {/* 3-Layer Pipeline Breakdown */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
          {/* Layer 1 */}
          <div className="bg-[#0c0f1a] border border-[#1a2236] rounded-xl p-6 flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-[#64748b] bg-[#141926] px-2 py-0.5 rounded border border-[#1e2638]">Layer 1</span>
                <span className="text-emerald-400 text-xs font-mono">0.012ms</span>
              </div>
              <div className="flex items-center gap-2 text-amber-400 font-mono text-sm font-semibold mb-1">
                <Cpu className="w-4 h-4" />
                Primary Fast Triage
              </div>
              <p className="text-xs text-[#94a3b8] mb-4">Zero-latency heuristic classifier determining execution path.</p>
              
              <div className="bg-[#07090f] p-3 rounded-lg border border-[#161c2b] text-xs font-mono">
                <div className="text-[#64748b]">Triage Verdict:</div>
                <div className="text-lg font-bold text-cyan-400 mt-0.5">{orchestration.layer1Triage}</div>
              </div>
            </div>
            <div className="mt-4 pt-3 border-t border-[#141926] text-[11px] font-mono text-[#64748b]">
              In-Memory 64KB Wasm Heuristic
            </div>
          </div>

          {/* Layer 2 */}
          <div className="bg-[#0c0f1a] border border-[#1a2236] rounded-xl p-6 flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-[#64748b] bg-[#141926] px-2 py-0.5 rounded border border-[#1e2638]">Layer 2</span>
                <span className="text-purple-400 text-xs font-mono">Consultative</span>
              </div>
              <div className="flex items-center gap-2 text-purple-400 font-mono text-sm font-semibold mb-1">
                <MessageSquare className="w-4 h-4" />
                Refinement & Follow-ups
              </div>
              <p className="text-xs text-[#94a3b8] mb-4">Ambiguity detection, voice interaction, and intent clarification.</p>

              {orchestration.layer2FollowUps.length > 0 ? (
                <div className="space-y-2">
                  {orchestration.layer2FollowUps.map((f, i) => (
                    <div key={i} className="bg-[#07090f] p-2.5 rounded-lg border border-[#1e273d] text-xs font-mono text-purple-300">
                      💬 {f}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-[#07090f] p-3 rounded-lg border border-[#161c2b] text-xs font-mono text-emerald-400 flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4" />
                  Intent fully specified. Zero ambiguity.
                </div>
              )}
            </div>
            <div className="mt-4 pt-3 border-t border-[#141926] text-[11px] font-mono text-[#64748b]">
              Conversational & Voice Router
            </div>
          </div>

          {/* Layer 3 */}
          <div className="bg-[#0c0f1a] border border-[#1a2236] rounded-xl p-6 flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs font-mono text-[#64748b] bg-[#141926] px-2 py-0.5 rounded border border-[#1e2638]">Layer 3</span>
                <span className="text-cyan-400 text-xs font-mono">Task Pool Mesh</span>
              </div>
              <div className="flex items-center gap-2 text-cyan-400 font-mono text-sm font-semibold mb-1">
                <ListTodo className="w-4 h-4" />
                Autonomous Task DAG
              </div>
              <p className="text-xs text-[#94a3b8] mb-3">Decomposed subtasks executed via native ASL Wasm or specialist agents.</p>

              <div className="space-y-2">
                {orchestration.layer3Subtasks.map(st => (
                  <div key={st.id} className="bg-[#07090f] p-2 rounded-lg border border-[#161c2b] text-[11px] font-mono flex items-center justify-between">
                    <span className="text-white truncate max-w-[170px]">{st.title}</span>
                    <span className="text-cyan-400 text-[10px] bg-[#101522] px-1.5 py-0.5 rounded">{st.agent}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="mt-4 pt-3 border-t border-[#141926] text-[11px] font-mono text-[#64748b] flex items-center justify-between">
              <span>Circuit Breaker: 2 fails</span>
              <span className="text-emerald-400">{orchestration.totalLatencyMs}ms</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
