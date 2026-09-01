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
    { id: 'agent-orchestrator', name: 'Orchestrator', role: 'Master Dispatcher', status: 'idle', latencyMs: 0.038, icon: <Bot className="w-5 h-5 text-cyan-400" /> },
    { id: 'agent-planner', name: 'Strategic Planner', role: 'Decomposition & Specs', status: 'idle', latencyMs: 0.042, icon: <Cpu className="w-5 h-5 text-purple-400" /> },
    { id: 'agent-coder', name: 'ASL Coder', role: 'In-Memory Wasm Synthesis', status: 'idle', latencyMs: 0.035, icon: <Flame className="w-5 h-5 text-amber-400" /> },
    { id: 'agent-reviewer', name: 'Gate Auditor', role: 'Zero-Drift Verifier', status: 'idle', latencyMs: 0.039, icon: <ShieldCheck className="w-5 h-5 text-green-400" /> },
    { id: 'agent-searcher', name: 'SearXNG Scout', role: 'Proxy Pool Web RAG', status: 'idle', latencyMs: 0.045, icon: <Search className="w-5 h-5 text-blue-400" /> }
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
    <div className="border-t border-[#1e2230] bg-[#080a10] py-20 px-6 sm:px-10">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-12 gap-6">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/10 border border-purple-500/30 text-purple-400 text-xs font-mono mb-3">
              <Network className="w-3.5 h-3.5" />
              Inter-Agent Mesh & SSE Swarm Bus
            </div>
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-white">
              Warm Subagents & In-Memory Socket Bus
            </h2>
            <p className="text-[#94a3b8] mt-2 max-w-2xl text-sm sm:text-base">
              Subagents stay hot in memory with zero container spin-up. Broadcast typed S-expression ASTs over local SSE & Unix domain sockets with <strong>&lt;0.04ms latency</strong>.
            </p>
          </div>

          <div className="flex items-center gap-3 font-mono text-xs text-[#94a3b8] bg-[#0f131d] px-4 py-2 rounded-lg border border-[#1e2436]">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
            Daemon Active: <span className="text-white">http://localhost:8765/events</span>
          </div>
        </div>

        {/* Top Swarm Nodes Matrix */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
          {agents.map(agent => (
            <div
              key={agent.id}
              onClick={() => setSelectedAgent(agent.id)}
              className={`bg-[#0b0e17] border rounded-xl p-4 cursor-pointer transition-all ${
                selectedAgent === agent.id ? 'border-purple-500 shadow-lg shadow-purple-500/10 bg-[#121624]' : 'border-[#1a2030] hover:border-[#2a334d]'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <div className="w-8 h-8 rounded-lg bg-[#161c2b] flex items-center justify-center">
                  {agent.icon}
                </div>
                <span className={`text-[10px] font-mono px-2 py-0.5 rounded-full border ${
                  agent.status === 'streaming'
                    ? 'bg-amber-500/20 text-amber-300 border-amber-500/40 animate-pulse'
                    : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                }`}>
                  {agent.status}
                </span>
              </div>
              <h4 className="text-white font-semibold text-sm">{agent.name}</h4>
              <p className="text-[#64748b] text-xs mt-0.5">{agent.role}</p>
              <div className="mt-3 pt-3 border-t border-[#161c2b] flex items-center justify-between text-[11px] font-mono text-[#94a3b8]">
                <span>IPC Latency</span>
                <span className="text-purple-400">{agent.latencyMs}ms</span>
              </div>
            </div>
          ))}
        </div>

        {/* Live Dispatcher & Event Log */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Dispatcher Box */}
          <div className="bg-[#0b0e17] border border-[#1a2030] rounded-xl p-6 flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-2 mb-4">
                <Radio className="w-4 h-4 text-purple-400" />
                <h3 className="text-white font-semibold text-sm">SSE Mesh Task Dispatcher</h3>
              </div>

              <label className="block text-xs font-mono text-[#94a3b8] mb-1.5">Target Warm Agent:</label>
              <select
                value={selectedAgent}
                onChange={e => setSelectedAgent(e.target.value)}
                className="w-full bg-[#121624] border border-[#222a40] text-white rounded-lg px-3 py-2 text-xs font-mono mb-4 focus:outline-none focus:border-purple-500"
              >
                {agents.map(a => (
                  <option key={a.id} value={a.id}>{a.name} ({a.id})</option>
                ))}
              </select>

              <label className="block text-xs font-mono text-[#94a3b8] mb-1.5">Typed S-Expression Payload:</label>
              <textarea
                value={inputMsg}
                onChange={e => setInputMsg(e.target.value)}
                rows={4}
                className="w-full bg-[#07090f] border border-[#1a2030] text-[#a7f3d0] rounded-lg p-3 text-xs font-mono focus:outline-none focus:border-purple-500"
              />
            </div>

            <button
              onClick={dispatchTask}
              className="mt-4 w-full py-2.5 bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 text-white font-semibold rounded-lg text-xs font-mono flex items-center justify-center gap-2 shadow-lg shadow-purple-500/20 transition-all"
            >
              <Send className="w-3.5 h-3.5" />
              Dispatch Packet ($ asl bus send)
            </button>
          </div>

          {/* Real-Time Packet Stream */}
          <div className="lg:col-span-2 bg-[#07090f] border border-[#1a2030] rounded-xl p-6 flex flex-col">
            <div className="flex items-center justify-between mb-4 border-b border-[#141926] pb-3">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-purple-400 animate-ping" />
                <h3 className="text-white font-semibold text-sm font-mono">Live SSE Event Stream (/events)</h3>
              </div>
              <span className="text-xs font-mono text-[#64748b]">Wire Protocol: ASL S-Expressions</span>
            </div>

            <div className="space-y-2.5 flex-1 overflow-y-auto max-h-[220px]">
              {packets.map(pkt => (
                <div key={pkt.id} className="bg-[#0c0f18] border border-[#161c2b] rounded-lg p-3 font-mono text-xs flex items-center justify-between gap-4 hover:border-purple-500/30 transition-colors">
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-purple-400 font-semibold">{pkt.from}</span>
                    <ArrowRight className="w-3 h-3 text-[#64748b]" />
                    <span className="text-cyan-400 font-semibold">{pkt.to}</span>
                  </div>
                  <div className="text-[#a7f3d0] truncate flex-1 font-mono text-[11px] bg-[#07080d] px-2 py-1 rounded border border-[#161c28]">
                    {pkt.payload}
                  </div>
                  <div className="text-[10px] text-[#64748b] shrink-0">
                    {pkt.latencyMs}ms • {pkt.time}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
