import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';
import {
  Bot,
  CheckCircle2,
  AlertTriangle,
  Radio,
  Send,
  RefreshCw,
  Zap,
  Mail,
  ShieldAlert,
  Sliders,
  Code2
} from 'lucide-react';

interface AgentNode {
  id: string;
  name: string;
  role: string;
  dialect: 'asl/v1' | 'compact/v1' | 'polyglot/v1';
  isAslNative: boolean;
  status: 'active' | 'stalled' | 'lonely' | 'offline';
  mailboxCount: number;
}

const INITIAL_AGENTS: AgentNode[] = [
  {
    id: 'agent-orchestrator',
    name: 'Orchestrator Pro',
    role: 'Swarm Supervisor',
    dialect: 'asl/v1',
    isAslNative: true,
    status: 'active',
    mailboxCount: 0,
  },
  {
    id: 'agent-planner',
    name: 'Strategic Planner',
    role: 'DAG & Roadmap Architect',
    dialect: 'asl/v1',
    isAslNative: true,
    status: 'active',
    mailboxCount: 0,
  },
  {
    id: 'agent-coder-1',
    name: 'Fast Coder 1',
    role: 'Wasm Core Builder',
    dialect: 'compact/v1',
    isAslNative: false,
    status: 'active',
    mailboxCount: 0,
  },
  {
    id: 'agent-vanilla-llm',
    name: 'Vanilla Claude/GPT',
    role: 'Unprimed External Model',
    dialect: 'polyglot/v1',
    isAslNative: false,
    status: 'active',
    mailboxCount: 0,
  },
  {
    id: 'agent-lonely-sub',
    name: 'Late-Joining Specialist',
    role: 'Offline Worker',
    dialect: 'asl/v1',
    isAslNative: true,
    status: 'lonely',
    mailboxCount: 2,
  },
];

export const SkyLoomVisualizer: React.FC = () => {
  const [agents, setAgents] = useState<AgentNode[]>(INITIAL_AGENTS);
  const [selectedScenario, setSelectedScenario] = useState<'aware' | 'asymmetric' | 'lonely' | 'stalled' | 'dlq'>('aware');
  const [activeTab, setActiveTab] = useState<'asl' | 'polyglot' | 'compact'>('asl');
  const [isTransmitting, setIsTransmitting] = useState<boolean>(false);
  const [stats, setStats] = useState({
    framesRouted: 1428,
    tokenSavings: '68.4%',
    avgLatency: '0.038ms',
    mailboxQueued: 2,
    dlqErrors: 0,
  });

  const runScenario = (scenario: typeof selectedScenario) => {
    setSelectedScenario(scenario);
    setIsTransmitting(true);

    if (scenario === 'aware') {
      setActiveTab('asl');
      setStats(prev => ({
        ...prev,
        framesRouted: prev.framesRouted + 2,
        dlqErrors: 0,
      }));
    } else if (scenario === 'asymmetric') {
      setActiveTab('polyglot');
      setStats(prev => ({
        ...prev,
        framesRouted: prev.framesRouted + 1,
      }));
    } else if (scenario === 'lonely') {
      setActiveTab('asl');
      setAgents(prev =>
        prev.map(a =>
          a.id === 'agent-lonely-sub'
            ? { ...a, status: 'active', mailboxCount: 0 }
            : a
        )
      );
      setStats(prev => ({
        ...prev,
        mailboxQueued: 0,
        framesRouted: prev.framesRouted + 2,
      }));
    } else if (scenario === 'stalled') {
      setAgents(prev =>
        prev.map(a =>
          a.id === 'agent-coder-1'
            ? { ...a, status: 'stalled' }
            : a
        )
      );
    } else if (scenario === 'dlq') {
      setStats(prev => ({
        ...prev,
        dlqErrors: prev.dlqErrors + 1,
      }));
    }

    setTimeout(() => {
      setIsTransmitting(false);
    }, 1200);
  };

  const resetAll = () => {
    setAgents(INITIAL_AGENTS);
    setSelectedScenario('aware');
    setActiveTab('asl');
    setStats({
      framesRouted: 1428,
      tokenSavings: '68.4%',
      avgLatency: '0.038ms',
      mailboxQueued: 2,
      dlqErrors: 0,
    });
  };

  return (
    <Section id="skyloom-mesh" ground="sunken" labelledBy="skyloom-title" className="overflow-hidden border-t border-line py-16">
      <SectionHeader
        id="skyloom-title"
        index="03"
        eyebrow="SkyLoom Resilient Swarm Mesh"
        title="Zero-Drift Inter-Agent Protocol & Asymmetric Mesh"
        lead="A unified high-speed machine protocol connecting ASL-native aware agents, unprimed vanilla LLMs, and warm CLI subagents with self-healing mailbox queues, heartbeat watchdogs, and zero schema drift."
        align="center"
      />

      <div className="max-w-6xl mx-auto px-4 mt-8 space-y-8">
        {/* Telemetry Bar */}
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 p-4 rounded-xl border border-line bg-surface/80 backdrop-blur-md">
          <div className="flex flex-col">
            <span className="font-mono text-micro text-ink-3 uppercase">Total Frames</span>
            <span className="font-mono text-h4 font-bold text-ink flex items-center gap-1.5">
              <Zap className="w-4 h-4 text-accent" />
              {stats.framesRouted.toLocaleString()}
            </span>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-micro text-ink-3 uppercase">Token Compression</span>
            <span className="font-mono text-h4 font-bold text-ink-1">
              -{stats.tokenSavings}
            </span>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-micro text-ink-3 uppercase">P2P Latency</span>
            <span className="font-mono text-h4 font-bold text-ink-2">
              {stats.avgLatency}
            </span>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-micro text-ink-3 uppercase">Lonely Mailbox</span>
            <span className="font-mono text-h4 font-bold text-ink flex items-center gap-1.5">
              <Mail className="w-4 h-4 text-ink-2" />
              {stats.mailboxQueued} pending
            </span>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-micro text-ink-3 uppercase">DLQ Faults</span>
            <span className="font-mono text-h4 font-bold text-ink flex items-center gap-1.5">
              <ShieldAlert className="w-4 h-4 text-ink-3" />
              {stats.dlqErrors}
            </span>
          </div>
        </div>

        {/* Live Swarm Topology Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Agent Nodes Panel */}
          <div className="lg:col-span-1 p-6 rounded-2xl border border-line bg-surface flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between pb-4 border-b border-line mb-4">
                <span className="font-mono text-micro uppercase font-semibold text-ink">Connected Swarm Mesh</span>
                <span className="flex items-center gap-1.5 font-mono text-micro text-ink-2">
                  <Radio className="w-3.5 h-3.5 text-accent animate-pulse" />
                  Live Socket / MCP
                </span>
              </div>

              <div className="space-y-3">
                {agents.map((agent) => (
                  <div
                    key={agent.id}
                    className={`p-3 rounded-xl border transition-all ${
                      agent.status === 'stalled'
                        ? 'border-line bg-inset/40 opacity-60'
                        : agent.status === 'lonely'
                        ? 'border-line bg-surface shadow-sm'
                        : 'border-line bg-ground hover:border-line'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center">
                          <Bot className="w-4 h-4 text-ink-2" />
                        </div>
                        <div>
                          <p className="font-sans text-sm font-semibold text-ink leading-none">{agent.name}</p>
                          <p className="font-mono text-micro text-ink-3 mt-0.5">{agent.role}</p>
                        </div>
                      </div>

                      <div className="flex items-center gap-1.5">
                        {agent.isAslNative ? (
                          <span className="px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-ink text-ground">
                            ASL Aware
                          </span>
                        ) : (
                          <span className="px-1.5 py-0.5 rounded font-mono text-micro uppercase font-medium bg-inset border border-line text-ink-2">
                            Polyglot
                          </span>
                        )}

                        {agent.status === 'lonely' && (
                          <span className="px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-inset text-ink-3 border border-line flex items-center gap-1">
                            <Mail className="w-2.5 h-2.5" /> {agent.mailboxCount}
                          </span>
                        )}

                        {agent.status === 'stalled' && (
                          <span className="px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-inset text-ink-3 border border-line">
                            Stalled
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Scenario Trigger Buttons */}
            <div className="pt-6 border-t border-line mt-6">
              <p className="font-mono text-micro uppercase text-ink-3 mb-2 flex items-center gap-1.5">
                <Sliders className="w-3.5 h-3.5" /> Interactive Chaos & Simulation Suite:
              </p>
              <div className="grid grid-cols-2 gap-2">
                <button
                  onClick={() => runScenario('aware')}
                  className={`px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all ${
                    selectedScenario === 'aware'
                      ? 'border-ink bg-ink text-ground'
                      : 'border-line bg-surface hover:bg-inset text-ink-2'
                  }`}
                >
                  1. Aware ↔ Aware S-Expr
                </button>
                <button
                  onClick={() => runScenario('asymmetric')}
                  className={`px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all ${
                    selectedScenario === 'asymmetric'
                      ? 'border-ink bg-ink text-ground'
                      : 'border-line bg-surface hover:bg-inset text-ink-2'
                  }`}
                >
                  2. Aware ↔ Unaware LLM
                </button>
                <button
                  onClick={() => runScenario('lonely')}
                  className={`px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all ${
                    selectedScenario === 'lonely'
                      ? 'border-ink bg-ink text-ground'
                      : 'border-line bg-surface hover:bg-inset text-ink-2'
                  }`}
                >
                  3. Lonely Mailbox Drain
                </button>
                <button
                  onClick={() => runScenario('stalled')}
                  className={`px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all ${
                    selectedScenario === 'stalled'
                      ? 'border-ink bg-ink text-ground'
                      : 'border-line bg-surface hover:bg-inset text-ink-2'
                  }`}
                >
                  4. Stalled Peer Evict
                </button>
              </div>

              <div className="flex items-center justify-between mt-3 pt-3 border-t border-line">
                <button
                  onClick={() => runScenario('dlq')}
                  className="font-mono text-micro text-ink-3 hover:text-ink flex items-center gap-1"
                >
                  <AlertTriangle className="w-3 h-3 text-ink-3" /> Test DLQ Trigger
                </button>
                <button
                  onClick={resetAll}
                  className="font-mono text-micro text-ink-3 hover:text-ink flex items-center gap-1"
                >
                  <RefreshCw className="w-3 h-3" /> Reset Swarm
                </button>
              </div>
            </div>
          </div>

          {/* Wire Format & Live Packet Inspector */}
          <div className="lg:col-span-2 p-6 rounded-2xl border border-line bg-surface flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between pb-4 border-b border-line mb-4">
                <div className="flex items-center gap-2">
                  <Code2 className="w-4 h-4 text-ink-2" />
                  <span className="font-mono text-micro uppercase font-semibold text-ink">
                    SkyLoom Wire Frame Inspector
                  </span>
                  {isTransmitting && (
                    <span className="flex items-center gap-1 font-mono text-micro text-ink font-bold animate-pulse">
                      <Send className="w-3 h-3" /> Transmitting
                    </span>
                  )}
                </div>

                <div className="flex items-center gap-1 p-0.5 rounded-lg bg-inset border border-line">
                  <button
                    onClick={() => setActiveTab('asl')}
                    className={`px-2 py-1 rounded font-mono text-micro font-medium transition-all ${
                      activeTab === 'asl'
                        ? 'bg-surface text-ink shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    ASL Native (S-Expr)
                  </button>
                  <button
                    onClick={() => setActiveTab('polyglot')}
                    className={`px-2 py-1 rounded font-mono text-micro font-medium transition-all ${
                      activeTab === 'polyglot'
                        ? 'bg-surface text-ink shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    Polyglot Markdown
                  </button>
                  <button
                    onClick={() => setActiveTab('compact')}
                    className={`px-2 py-1 rounded font-mono text-micro font-medium transition-all ${
                      activeTab === 'compact'
                        ? 'bg-surface text-ink shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    Compact Token
                  </button>
                </div>
              </div>

              {/* Code Previews */}
              <div className="relative">
                {activeTab === 'asl' && (
                  <pre className="p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed">
{`(loom:frame
  :v 1
  :id "msg-9f201"
  :from "agent-orchestrator"
  :to "${selectedScenario === 'lonely' ? 'agent-lonely-sub' : 'agent-planner'}"
  :dialect "asl/v1"
  :ts ${Date.now()}
  :type "DATA"
  :channel "tasks/codegen"
  :body (loom:task
          :action "compile_wasm"
          :module "core/matrix"
          :optimization "O3"
          :verified-by-checker true))`}
                  </pre>
                )}

                {activeTab === 'polyglot' && (
                  <pre className="p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed">
{`<!-- SKYLOOM_HEADER: {"v":1,"id":"msg-9f201","from":"agent-orchestrator","to":"agent-vanilla-llm","dialect":"polyglot/v1","type":"DATA"} -->
[SkyLoom Autonomous Protocol Primer]
You are communicating with agent "agent-orchestrator" over SkyLoom.
Please execute the requested task and reply in a fenced JSON code block:

\`\`\`json
{
  "action": "audit_architecture",
  "target": "mesh_topology",
  "replyTo": "msg-9f201"
}
\`\`\`
<!-- SKYLOOM_FOOTER -->`}
                  </pre>
                )}

                {activeTab === 'compact' && (
                  <pre className="p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed">
{`SK1|1|msg-9f201|agent-orchestrator|agent-coder-1|DATA|tasks/codegen|${Date.now()}||{"action":"compile_wasm","module":"core/matrix","opt":"O3"}`}
                  </pre>
                )}
              </div>
            </div>

            {/* Protocol Explanation Footer */}
            <div className="mt-6 pt-4 border-t border-line flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-ink-2" />
                <span className="font-sans text-xs text-ink-2">
                  Nominal ASL AST types guarantee zero schema drift across all agent runtimes.
                </span>
              </div>

              <div className="flex items-center gap-2">
                <span className="font-mono text-micro text-ink-3 uppercase font-medium">Access Modes:</span>
                <span className="px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink">
                  CLI ($ asl loom)
                </span>
                <span className="px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink">
                  MCP Server
                </span>
                <span className="px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink">
                  Wasm SDK
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
