import React, { useState } from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Globe, Cpu, Zap, Eye, CheckCircle2, Sparkles } from 'lucide-react';

export const InBrowserAgent: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'context' | 'action' | 'raw'>('context');

  return (
    <Section id="browser-agent" variant="transparent" labelledBy="browser-agent-title" className="overflow-hidden">
      <SectionHeader
        id="browser-agent-title"
        index="05"
        eyebrow="In-Browser Autonomous Companion"
        title="An Agent Inside the Browser. Full Visual Context & Direct In-Tab Execution."
        lead="Stop fighting brittle remote DevTools and bloated HTML scraping. Connect your external agent (Antigravity, Cursor, Claude Code) directly to an in-browser companion agent. It checks render readiness, extracts visual layout state, executes actions locally, and coordinates with on-board WebGPU SLMs or cloud vision models."
        align="center"
      />

      {/* Prominent In-Development Status Badge */}
      <div className="flex justify-center -mt-6 mb-12">
        <span className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-amber-500/40 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wider shadow-sm">
          <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
          In Active Development // Research Preview (@genseam/asl-browser-plugin)
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
              <span>https://checkout.store.dev/cart</span>
            </div>
          </div>

          <div className="flex items-center gap-3 font-mono text-micro">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-signal/15 border border-signal/30 text-signal font-semibold">
              <Sparkles className="w-3 h-3" />
              On-Board SLM / Vision API
            </span>
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-emerald-500/15 border border-emerald-500/30 text-emerald-400">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              Agent Bus: Connected (0.04ms)
            </span>
          </div>
        </div>

        {/* Cockpit Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12">
          {/* Left Column: Semantic Context & Render Readiness */}
          <div className="lg:col-span-7 p-6 sm:p-8 border-b lg:border-b-0 lg:border-r border-line flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between pb-4 border-b border-line flex-wrap gap-2">
                <div>
                  <h3 className="font-mono text-xs font-bold uppercase tracking-wider text-ink">
                    In-Tab Agent Inspector
                  </h3>
                  <p className="text-micro text-ink-3 mt-0.5">
                    Live visual context, render readiness & instruction execution
                  </p>
                </div>
                <div className="flex rounded-lg bg-inset p-0.5 border border-line">
                  <button
                    onClick={() => setActiveTab('context')}
                    className={`px-2.5 py-1 rounded-md font-mono text-micro transition-all ${
                      activeTab === 'context'
                        ? 'bg-signal text-ground font-semibold shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    UI Context & Render
                  </button>
                  <button
                    onClick={() => setActiveTab('action')}
                    className={`px-2.5 py-1 rounded-md font-mono text-micro transition-all ${
                      activeTab === 'action'
                        ? 'bg-signal text-ground font-semibold shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    Action Execution
                  </button>
                  <button
                    onClick={() => setActiveTab('raw')}
                    className={`px-2.5 py-1 rounded-md font-mono text-micro transition-all ${
                      activeTab === 'raw'
                        ? 'bg-signal text-ground font-semibold shadow-sm'
                        : 'text-ink-3 hover:text-ink'
                    }`}
                  >
                    Raw HTML (Bloat)
                  </button>
                </div>
              </div>

              {/* Code Panel Display */}
              <div className="mt-5 p-4 rounded-2xl bg-ground border border-line font-mono text-xs leading-relaxed overflow-x-auto min-h-[230px]">
                {activeTab === 'context' && (
                  <pre className="text-purple-300">
                    <span className="text-ink-3">;; Render readiness & visual layout synthesized by browser agent</span>{'\n'}
                    <span className="text-signal">(! browser/context</span>{'\n'}
                    {'  '}:route <span className="text-emerald-400">"/cart"</span>{'\n'}
                    {'  '}:render-status <span className="text-emerald-400">:hydrated-ready</span>{'\n'}
                    {'  '}:layout-shifts <span className="text-blue-300">0.0</span>{'\n'}
                    {'  '}:visual-viewport [1440 900]{'\n'}
                    {'  '}:visible-actionables [{'\n'}
                    {'    '}(:target <span className="text-amber-300">"#coupon-code"</span> :role <span className="text-blue-300">:input</span> :val <span className="text-emerald-400">""</span>){'\n'}
                    {'    '}(:target <span className="text-amber-300">"#btn-apply"</span> :role <span className="text-blue-300">:button</span> :enabled <span className="text-emerald-400">true</span>){'\n'}
                    {'    '}(:target <span className="text-amber-300">"#btn-checkout"</span> :role <span className="text-blue-300">:button</span> :enabled <span className="text-emerald-400">true</span>){'\n'}
                    {'  '}]{'\n'}
                    {'  '}:vision-critique <span className="text-emerald-400">"Layout verified clean: zero overlapping elements"</span>)
                  </pre>
                )}

                {activeTab === 'action' && (
                  <pre className="text-emerald-300">
                    <span className="text-ink-3">;; External agent (Antigravity/Cursor) dispatches instruction</span>{'\n'}
                    <span className="text-signal">(? browser/exec</span>{'\n'}
                    {'  '}:action <span className="text-blue-300">:click</span>{'\n'}
                    {'  '}:target <span className="text-amber-300">"#btn-checkout"</span>{'\n'}
                    {'  '}:wait-for <span className="text-emerald-400">:navigation-complete</span>{'\n'}
                    {'  '}:verify-render <span className="text-blue-300">true</span>){'\n\n'}
                    <span className="text-ink-3">;; In-browser agent executes locally and returns confirmation</span>{'\n'}
                    <span className="text-signal">(! browser/ack</span>{'\n'}
                    {'  '}:status <span className="text-emerald-400">:completed</span>{'\n'}
                    {'  '}:new-route <span className="text-emerald-400">"/checkout/shipping"</span>{'\n'}
                    {'  '}:render-ready <span className="text-blue-300">true</span>{'\n'}
                    {'  '}:latency-ms <span className="text-amber-300">4.2</span>)
                  </pre>
                )}

                {activeTab === 'raw' && (
                  <pre className="text-ink-3 opacity-60">
                    {'<div id="root" class="min-h-screen bg-slate-950 flex flex-col">\n'}
                    {'  <header class="h-16 border-b border-slate-800 px-6 flex items-center justify-between">\n'}
                    {'    <div class="flex items-center gap-3">...</div>\n'}
                    {'    <div class="relative"><button class="...">Profile</button></div>\n'}
                    {'  </header>\n'}
                    {'  <main class="flex-1 p-8 grid grid-cols-12 gap-6">\n'}
                    {'    <!-- 52,000 more characters of unparsed markup & script tags that burn prompt tokens -->\n'}
                    {'  </main>\n'}
                    {'</div>'}
                  </pre>
                )}
              </div>
            </div>

            <div className="mt-6 pt-4 border-t border-line flex items-center justify-between text-micro font-mono text-ink-3">
              <span className="flex items-center gap-1.5 text-emerald-400 font-semibold">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Prompt Reduction: 52.4 kB → 1.2 kB (-97%)
              </span>
              <span>Zero Selenium / DevTools bloat</span>
            </div>
          </div>

          {/* Right Column: Key Modes of Operation */}
          <div className="lg:col-span-5 p-6 sm:p-8 bg-inset/30 flex flex-col justify-between space-y-6">
            <div>
              <span className="font-mono text-micro uppercase text-signal font-semibold tracking-wider">
                Flexible In-Browser Topology
              </span>
              <h4 className="mt-2 text-h3 font-bold text-ink leading-snug">
                One Extension. Three Execution Modes.
              </h4>
              <p className="mt-2.5 text-sm text-ink-2 leading-relaxed">
                External agents don't connect directly to clumsy browser windows. They talk to an intelligent in-tab agent that understands DOM, layout readiness, and visual state.
              </p>
            </div>

            <div className="space-y-3.5">
              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">1. Zero-LLM Deterministic Bus</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Operates purely as a high-speed tool execution bus. Handles events, layout reads, and page readiness without burning any LLM tokens.</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Cpu className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">2. Local On-Board SLM (WebGPU)</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Runs lightweight 0.5B-1.5B models directly in the tab via WebGPU for instant client-side autonomy without sending data to clouds.</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3.5 rounded-2xl bg-surface/80 border border-line">
                <div className="p-2 rounded-xl bg-ground border border-line text-signal shrink-0">
                  <Eye className="w-4 h-4" />
                </div>
                <div>
                  <h5 className="text-xs font-bold text-ink">3. Cloud Vision Bridge</h5>
                  <p className="text-micro text-ink-2 mt-0.5">Connects with Gemini Flash, Claude Sonnet, or GPT-4o Vision to evaluate UI rendering, detect visual bugs, and verify complete layout state.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
