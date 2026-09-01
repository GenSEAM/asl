import React, { useState } from 'react';
import { Network, Radio, Send, ArrowRight, Cpu, Bot, ShieldCheck, Search, Flame } from 'lucide-react';

interface AgentNode {
  id: string;
  name: string;
  role: string;
  status: 'idle' | 'busy' | 'streaming';
  latencyMs: number;
  icon: React.ReactNode;
  lastMessage?: string;
}

interface MessagePacket {
  id: string;
  from: string;
  to: string;
  payload: string;
  latencyMs: number;
  time: string;
}

export const AgentSwarmVisualizer: React.FC = () => {
  const [agents, setAgents] = useState<AgentNode[]>([
    { id: 'agent-orchestrator', name: 'Orchestrator', role: 'Master Dispatcher', status: 'idle', latencyMs: 0.038, icon: <Bot className="w-5 h-5 text-craft-cyan" /> },
    { id: 'agent-planner', name: 'Strategic Planner', role: 'Decomposition & Specs', status: 'idle', latencyMs: 0.042, icon: <Cpu className="w-5 h-5 text-craft-purple" /> },
    { id: 'agent-coder', name: 'ASL Coder', role: 'In-Memory Wasm Synthesis', status: 'idle', latencyMs: 0.035, icon: <Flame className="w-5 h-5 text-amber-500" /> },
    { id: 'agent-reviewer', name: 'Gate Auditor', role: 'Zero-Drift Verifier', status: 'idle', latencyMs: 0.039, icon: <ShieldCheck className="w-5 h-5 text-craft-emerald" /> },
    { id: 'agent-searcher', name: 'SearXNG Scout', role: 'Proxy Pool Web RAG', status: 'idle', latencyMs: 0.045, icon: <Search className="w-5 h-5 text-blue-500" /> }
  ]);

  const [packets, setPackets] = useState<MessagePacket[]>([
    { id: 'pkt-1', from: 'agent-orchestrator', to: 'agent-coder', payload: '(module/build :target wasm)', latencyMs: 0.038, time: '10:18:22' },
    { id: 'pkt-2', from: 'agent-coder', to: 'agent-reviewer', payload: '(verify/gates :all-green)', latencyMs: 0.035, time: '10:18:23' }
  ]);

  const [inputMsg, setInputMsg] = useState('(agent/delegate :task "Generate typed FSM schema")');
  const [selectedAgent, setSelectedAgent] = useState('agent-coder');

  const dispatchTask = () => {
    if (!inputMsg.trim()) return;

    const newPkt: MessagePacket = {
      id: `pkt-${Date.now()}`,
      from: 'agent-orchestrator',
      to: selectedAgent,
      payload: inputMsg,
      latencyMs: +(0.035 + Math.random() * 0.015).toFixed(3),
      time: new Date().toLocaleTimeString()
    };

    setPackets(prev => [newPkt, ...prev.slice(0, 7)]);
    setAgents(prev => prev.map(a => a.id === selectedAgent ? { ...a, status: 'streaming', lastMessage: inputMsg } : a));

    setTimeout(() => {
      setAgents(prev => prev.map(a => a.id === selectedAgent ? { ...a, status: 'idle' } : a));
    }, 1200);
  };

  return (
    <section id="bus" className="relative py-24 border-b border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-950 transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-12 gap-6 text-left">
          <div>
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-500/30 text-purple-600 dark:text-purple-400 text-xs font-mono mb-3">
              <Network className="w-3.5 h-3.5" />
              <span>Inter-Agent Mesh & SSE Swarm Bus</span>
            </div>
            <h2 className="text-3xl sm:text-5xl font-extrabold tracking-tight text-craft-900 dark:text-craft-50 font-sans">
              Warm Subagents & In-Memory Socket Bus
            </h2>
            <p className="text-craft-600 dark:text-craft-300 mt-2 max-w-2xl text-sm sm:text-base leading-relaxed">
              Subagents stay hot in memory with zero container spin-up. Broadcast typed S-expression ASTs over local SSE & Unix domain sockets with <strong>&lt;0.04ms latency</strong>.
            </p>
          </div>

          <div className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-craft-100 dark:bg-craft-900 border border-craft-200 dark:border-craft-800 text-xs font-mono text-craft-600 dark:text-craft-400">
            <span className="w-2 h-2 rounded-full bg-craft-emerald animate-ping" />
            <span>Daemon Active: <strong>http://localhost:8765/events</strong></span>
          </div>
        </div>

        {/* Live Warm Subagent Nodes Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
          {agents.map((agent) => {
            const isStreaming = agent.status === 'streaming';
            return (
              <div
                key={agent.id}
                className={`p-5 rounded-2xl border transition-all text-left ${
                  isStreaming
                    ? 'border-craft-accent bg-craft-100 dark:bg-craft-900 shadow-glow-sm ring-1 ring-craft-accent/50 scale-[1.02]'
                    : 'border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-900/50 hover:border-craft-300 dark:hover:border-craft-700'
                }`}
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="p-2.5 rounded-xl bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800">
                    {agent.icon}
                  </div>
                  <span
                    className={`px-2 py-0.5 rounded-md text-[10px] font-mono font-semibold uppercase ${
                      isStreaming
                        ? 'bg-craft-accent text-craft-950 animate-pulse font-bold'
                        : 'bg-craft-100 dark:bg-craft-800 text-craft-emerald'
                    }`}
                  >
                    {agent.status}
                  </span>
                </div>

                <div className="font-mono font-bold text-sm text-craft-900 dark:text-craft-100">{agent.name}</div>
                <div className="text-[11px] text-craft-500 dark:text-craft-400 font-sans mt-0.5">{agent.role}</div>

                <div className="mt-4 pt-3 border-t border-craft-200 dark:border-craft-800/80 flex items-center justify-between text-[10px] font-mono text-craft-500">
                  <span>IPC Latency</span>
                  <span className="text-craft-accent font-bold">{agent.latencyMs}ms</span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Live SSE Event Stream & Interactive Task Dispatcher */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left: Dispatcher Console */}
          <div className="lg:col-span-5 bg-white dark:bg-craft-900/80 border border-craft-200 dark:border-craft-800 rounded-2xl p-6 shadow-xl text-left flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-2 text-craft-accent font-mono text-xs font-bold uppercase mb-4">
                <Radio className="w-4 h-4 text-craft-accent animate-pulse" />
                <span>SSE Mesh Task Dispatcher</span>
              </div>

              <div className="space-y-4 font-mono text-xs">
                <div>
                  <label className="block text-craft-500 mb-1 font-semibold">Target Warm Agent:</label>
                  <select
                    value={selectedAgent}
                    onChange={(e) => setSelectedAgent(e.target.value)}
                    className="w-full bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 rounded-xl px-3.5 py-2.5 text-craft-900 dark:text-craft-100 focus:outline-none focus:border-craft-accent"
                  >
                    {agents.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name} ({a.id})
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-craft-500 mb-1 font-semibold">Typed S-Expression Payload:</label>
                  <textarea
                    rows={3}
                    value={inputMsg}
                    onChange={(e) => setInputMsg(e.target.value)}
                    className="w-full bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 rounded-xl p-3 text-craft-900 dark:text-craft-100 font-mono text-xs focus:outline-none focus:border-craft-accent shadow-inner"
                  />
                </div>
              </div>
            </div>

            <button
              onClick={dispatchTask}
              className="mt-6 w-full py-3 rounded-xl bg-craft-accent hover:bg-craft-accent/90 text-craft-950 font-mono font-bold text-xs shadow-glow-sm hover:shadow-glow-md transition-all flex items-center justify-center gap-2"
            >
              <Send className="w-3.5 h-3.5" />
              <span>Dispatch Packet ($ asl bus send)</span>
            </button>
          </div>

          {/* Right: Real-time Event Stream Viewer */}
          <div className="lg:col-span-7 bg-craft-50 dark:bg-craft-950 border border-craft-200 dark:border-craft-800 rounded-2xl p-5 shadow-xl text-left font-mono flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-craft-800/80 pb-3 mb-4">
                <div className="flex items-center gap-2 text-xs font-bold text-craft-900 dark:text-craft-100">
                  <span className="w-2 h-2 rounded-full bg-craft-emerald animate-ping" />
                  <span>Live SSE Event Stream (/events)</span>
                </div>
                <span className="text-[10px] text-craft-500">Wire Protocol: ASL S-Expressions</span>
              </div>

              <div className="space-y-2.5 max-h-72 overflow-y-auto pr-1">
                {packets.map((pkt) => (
                  <div
                    key={pkt.id}
                    className="p-3 rounded-xl bg-white dark:bg-craft-900/90 border border-craft-200 dark:border-craft-800/80 text-xs flex items-center justify-between shadow-sm hover:border-craft-accent/50 transition-colors"
                  >
                    <div className="flex items-center gap-2 truncate">
                      <span className="text-craft-accent font-bold">{pkt.from}</span>
                      <ArrowRight className="w-3 h-3 text-craft-400 shrink-0" />
                      <span className="text-purple-600 dark:text-purple-400 font-bold">{pkt.to}</span>
                      <span className="text-craft-700 dark:text-craft-300 font-mono text-[11px] truncate ml-2">
                        {pkt.payload}
                      </span>
                    </div>
                    <div className="text-right text-[10px] text-craft-500 shrink-0 ml-3">
                      <span className="text-craft-emerald font-bold">{pkt.latencyMs}ms</span> • {pkt.time}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="mt-4 pt-3 border-t border-craft-200 dark:border-craft-800/80 flex items-center justify-between text-[11px] text-craft-500">
              <span>Unix Domain Sockets & Zero-Copy VFS</span>
              <span className="text-craft-cyan font-bold">100% Deterministic</span>
            </div>
          </div>
        </div>

      </div>
    </section>
  );
};
