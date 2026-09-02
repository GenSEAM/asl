import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Globe, Cpu, Zap, Layers, CheckCircle2, Sparkles } from 'lucide-react';

export const InBrowserAgent: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'compressed' | 'raw'>('compressed');

  return (
    <Section id="browser-agent" variant="transparent" labelledBy="browser-agent-title" className="overflow-hidden">
      <SectionHeader
        id="browser-agent-title"
        index="03"
        eyebrow="Client-Side Agentics"
        title="An Autonomous Agent Inside the Browser. Not Just Automation — Real Ecosystem Interoperability."
        lead="Forget brittle browser scrapers and heavyweight remote DevTools. The AgentScript Browser Companion embeds a living, autonomous agent right inside the client tab — executing local 0.5B models via WebGPU or streaming semantic context to your IDE swarms with sub-millisecond latency."
        align="center"
      />

      {/* Status Clarity Badge */}
      <div className="flex justify-center -mt-6 mb-12">
        <span className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide">
          <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
          In-Browser Agent & Browser Extension: Alpha Preview (@genseam/asl-browser-plugin)
        </span>
      </div>

      {/* Interactive Browser Cockpit Visualizer */}
      <div className="max-w-5xl mx-auto rounded-3xl border border-line bg-surface/85 backdrop-blur-2xl shadow-e3 overflow-hidden">
        {/* Browser Top Navigation Chrome */}
        <div className="px-5 py-3.5 border-b border-line bg-inset/70 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-2.5">
            <span className="w-3 h-3 rounded-full bg-rose-500/70" />
            <span className="w-3 h-3 rounded-full bg-amber-500/70" />
            <span className="w-3 h-3 rounded-full bg-emerald-500/70" />
            <div className="ml-3 px-3 py-1 rounded-lg bg-ground border border-line text-micro font-mono text-ink-3 flex items-center gap-2">
              <Globe className="w-3.5 h-3.5 text-signal" />
              <span>https://app.dev/workspace/analytics</span>
            </div>
          </div>

          <div className="flex items-center gap-3 font-mono text-micro">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-signal/15 border border-signal/30 text-signal font-semibold">
              <Sparkles className="w-3 h-3" />
              0.5B In-Browser SLM (WebGPU)
            </span>
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-emerald-500/15 border border-emerald-500/30 text-emerald-400">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              Mesh Bus: Connected (0.04ms)
            </span>
          </div>
        </div>

        {/* Cockpit Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12">
          {/* Left Column: Semantic S-Expression Extraction */}
          <div className="lg:col-span-7 p-6 sm:p-8 border-b lg:border-b-0 lg:border-r border-line flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between pb-4 border-b border-line">
                <div>
                  <h3 className="font-mono text-xs font-bold uppercase tracking-wider text-ink">
                    Live Semantic DOM Stream
                  </h3>
                  <p className="text-micro text-ink-3 mt-0.5">
                    Real-time visual hierarchy compressed for autonomous agent consumption
                  </p>
                </div>
                <div className="flex rounded-lg bg-inset p-0.5 border border-line">
                  <button
                    onClick={() => setActiveTab('compressed')}
                    className={`px-2.5 py-1 rounded-md font-mono text-micro transition-all ${
                      activeTab === 'compressed'
                        ? 'bg-signal text-ground font-semibold shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    ASL S-Expr (-78%)
                  </button>
                  <button
                    onClick={() => setActiveTab('raw')}
                    className={`px-2.5 py-1 rounded-md font-mono text-micro transition-all ${
                      activeTab === 'raw'
                        ? 'bg-signal text-ground font-semibold shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    Raw DOM (Bloated)
                  </button>
                </div>
              </div>

              {/* Code Panel Display */}
              <div className="mt-5 p-4 rounded-2xl bg-ground border border-line font-mono text-xs leading-relaxed overflow-x-auto min-h-[220px]">
                {activeTab === 'compressed' ? (
                  <pre className="text-purple-300">
                    <span className="text-ink-3">;; Pure semantic context extracted by in-tab agent</span>{'\n'}
                    <span className="text-signal">(! dom/snapshot</span>{'\n'}
                    {'  '}:route <span className="text-emerald-400">"/workspace/analytics"</span>{'\n'}
                    {'  '}:vdom-state <span className="text-amber-300">:hydrated</span>{'\n'}
                    {'  '}:viewport-rect [1440 900]{'\n'}
                    {'  '}:active-components [<span className="text-blue-300">MetricsHeader</span> <span className="text-blue-300">CohortGrid</span> <span className="text-blue-300">TelemetryChart</span>]{'\n'}
                    {'  '}:performance-metrics {'{'}:fps 60 :dom-nodes 342 :heap-mb 14.8{'}'}{'\n'}
                    {'  '}:detected-anomalies [{'\n'}
                    {'    '}(<span className="text-rose-400">ui/excessive-rerender</span> :component <span className="text-blue-300">"CohortGrid"</span> :count 14){'\n'}
                    {'  '}])
                  </pre>
                ) : (
                  <pre className="text-ink-3 opacity-60">
                    {'<div id="root" class="min-h-screen bg-slate-950 text-slate-100 flex flex-col">\n'}
                    {'  <header class="h-16 border-b border-slate-800 px-6 flex items-center justify-between">\n'}
                    {'    <div class="flex items-center gap-3">...</div>\n'}
                    {'    <div class="relative"><button class="...">Profile</button></div>\n'}
                    {'  </header>\n'}
                    {'  <main class="flex-1 p-8 grid grid-cols-12 gap-6">\n'}
                    {'    <!-- 48,000 more characters of unparsed markup that burn your prompt budget -->\n'}
                    {'  </main>\n'}
                    {'</div>'}
                  </pre>
                )}
              </div>
            </div>

            <div className="mt-6 pt-4 border-t border-line flex items-center justify-between text-micro font-mono text-ink-3">
              <span className="flex items-center gap-1.5 text-emerald-400 font-semibold">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Prompt Reduction: 48.2 kB → 1.4 kB
              </span>
              <span>Latency: 0.18ms</span>
            </div>
          </div>

          {/* Right Column: Key Pillars */}
          <div className="lg:col-span-5 p-6 sm:p-8 bg-inset/30 flex flex-col justify-between space-y-6">
            <div>
              <span className="font-mono text-micro uppercase text-signal font-semibold tracking-wider">
                Full-Ecosystem Architecture
              </span>
              <h4 className="mt-2 text-h3 font-bold text-ink leading-snug">
                Not Just a Scraper. An Intelligent In-Tab Co-Pilot.
              </h4>
              <p className="mt-2.5 text-sm text-ink-2 leading-relaxed">
                The agent sits natively in the browser process, reading component states, detecting visual regressions, and feeding verified telemetry back to your orchestrator swarms.
              </p>
            </div>

            <div className="space-y-4">
              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Cpu className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">In-Browser SLM (0.5B Instruct)</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Runs privately inside the browser via WebGPU without leaking user data to external clouds.</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">Bi-Directional Mesh Sync</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Streams UI state and console anomalies to backend agents via Unix sockets, WebSockets, or SSE.</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Layers className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">Embed Everywhere (Web · Desktop · Mobile)</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Identical AgentScript WASI runtime runs in Service Workers, Tauri, React Native, or Node.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
