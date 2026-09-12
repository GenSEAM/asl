(module asl-web/skyloom-visualizer
  :d "SeamBus Resilient Swarm Mesh Visualizer in pure AgentScript."
  :x [skyloom-visualizer render-skyloom-visualizer]
  :i [])

(df render-skyloom-visualizer [] -> Str
  :d "Renders the interactive SeamBus inter-agent protocol and asymmetric mesh cockpit."
  "<section id=\"skyloom-mesh\" class=\"overflow-hidden border-t border-line py-16 bg-sunken/40\">
    
    <div class=\"text-center max-w-3xl mx-auto px-4 mb-6\">
      <span class=\"font-mono text-micro uppercase tracking-widest text-signal font-semibold mb-2 inline-block\">SeamBus Resilient Swarm Mesh</span>
      <h2 id=\"skyloom-title\" class=\"text-3xl sm:text-4xl font-bold text-ink tracking-tight\">Zero-Drift Inter-Agent Protocol &amp; Asymmetric Mesh</h2>
      <p class=\"mt-4 text-ink-2 text-base sm:text-lg leading-relaxed\">A unified high-speed machine protocol connecting ASL-native aware agents, unprimed vanilla LLMs, and warm CLI subagents with self-healing mailbox queues, heartbeat watchdogs, and zero schema drift.</p>
    </div>

    
    <div class=\"flex justify-center -mt-2 mb-8\">
      <span class=\"inline-flex items-center gap-2 px-3.5 py-1 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide\">
        <span class=\"w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse\"></span>
        Wire Protocol: Active · Mesh Engine: Under Development
      </span>
    </div>

    <div class=\"max-w-canvas mx-auto px-4 space-y-8\">
      
      <div class=\"grid grid-cols-2 sm:grid-cols-5 gap-3 p-4 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-e1\" id=\"skyloom-telemetry\">
        <div class=\"flex flex-col\">
          <span class=\"font-mono text-micro text-ink-3 uppercase\">Total Frames</span>
          <span class=\"font-mono text-h4 font-bold text-ink flex items-center gap-1.5 mt-1\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-signal\"><polygon points=\"13 2 3 14 12 14 11 22 21 10 12 10 13 2\"></polygon></svg>
            <span id=\"sl-frames-count\">1,428</span>
          </span>
        </div>
        <div class=\"flex flex-col\">
          <span class=\"font-mono text-micro text-ink-3 uppercase\">Token Compression</span>
          <span class=\"font-mono text-h4 font-bold text-ink-1 mt-1\" id=\"sl-compression-val\">
            -83.4%
          </span>
        </div>
        <div class=\"flex flex-col\">
          <span class=\"font-mono text-micro text-ink-3 uppercase\">P2P Latency</span>
          <span class=\"font-mono text-h4 font-bold text-ink-2 mt-1\">
            &lt;0.038ms
          </span>
        </div>
        <div class=\"flex flex-col\">
          <span class=\"font-mono text-micro text-ink-3 uppercase\">Lonely Mailbox</span>
          <span class=\"font-mono text-h4 font-bold text-ink flex items-center gap-1.5 mt-1\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-2\"><rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\"></rect><path d=\"m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7\"></path></svg>
            <span id=\"sl-mailbox-count\">2 pending</span>
          </span>
        </div>
        <div class=\"flex flex-col\">
          <span class=\"font-mono text-micro text-ink-3 uppercase\">DLQ Faults</span>
          <span class=\"font-mono text-h4 font-bold text-ink flex items-center gap-1.5 mt-1\">
            <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-3\"><path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10\"></path><path d=\"M12 8v4\"></path><path d=\"M12 16h.01\"></path></svg>
            <span id=\"sl-dlq-count\">0</span>
          </span>
        </div>
      </div>

      
      <div class=\"grid grid-cols-1 lg:grid-cols-3 gap-6\">
        
        <div class=\"lg:col-span-1 p-6 rounded-2xl border border-line bg-surface flex flex-col justify-between shadow-e2\">
          <div>
            <div class=\"flex items-center justify-between pb-4 border-b border-line mb-4\">
              <span class=\"font-mono text-micro uppercase font-semibold text-ink\">Connected Swarm Mesh</span>
              <span class=\"flex items-center gap-1.5 font-mono text-micro text-ink-2\">
                <span class=\"w-2 h-2 rounded-full bg-signal animate-pulse\"></span>
                Live Socket / MCP
              </span>
            </div>

            
            <div class=\"space-y-3\" id=\"sl-agent-list\">
              
              <div class=\"p-3 rounded-xl border border-line bg-ground hover:border-line transition-all sl-agent-node\" data-id=\"agent-orchestrator\">
                <div class=\"flex items-center justify-between\">
                  <div class=\"flex items-center gap-2.5\">
                    <div class=\"w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center text-ink-2\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8V4H8\"></path><rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect><path d=\"M2 14h2\"></path><path d=\"M20 14h2\"></path><path d=\"M15 13v2\"></path><path d=\"M9 13v2\"></path></svg>
                    </div>
                    <div>
                      <p class=\"font-sans text-sm font-semibold text-ink leading-none\">Orchestrator Pro</p>
                      <p class=\"font-mono text-micro text-ink-3 mt-0.5\">Swarm Supervisor</p>
                    </div>
                  </div>
                  <div class=\"flex items-center gap-1.5\">
                    <span class=\"px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-ink text-ground\">ASL Aware</span>
                  </div>
                </div>
              </div>

              
              <div class=\"p-3 rounded-xl border border-line bg-ground hover:border-line transition-all sl-agent-node\" data-id=\"agent-planner\">
                <div class=\"flex items-center justify-between\">
                  <div class=\"flex items-center gap-2.5\">
                    <div class=\"w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center text-ink-2\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8V4H8\"></path><rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect><path d=\"M2 14h2\"></path><path d=\"M20 14h2\"></path><path d=\"M15 13v2\"></path><path d=\"M9 13v2\"></path></svg>
                    </div>
                    <div>
                      <p class=\"font-sans text-sm font-semibold text-ink leading-none\">Strategic Planner</p>
                      <p class=\"font-mono text-micro text-ink-3 mt-0.5\">DAG &amp; Roadmap Architect</p>
                    </div>
                  </div>
                  <div class=\"flex items-center gap-1.5\">
                    <span class=\"px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-ink text-ground\">ASL Aware</span>
                  </div>
                </div>
              </div>

              
              <div class=\"p-3 rounded-xl border border-line bg-ground hover:border-line transition-all sl-agent-node\" data-id=\"agent-coder-1\">
                <div class=\"flex items-center justify-between\">
                  <div class=\"flex items-center gap-2.5\">
                    <div class=\"w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center text-ink-2\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8V4H8\"></path><rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect><path d=\"M2 14h2\"></path><path d=\"M20 14h2\"></path><path d=\"M15 13v2\"></path><path d=\"M9 13v2\"></path></svg>
                    </div>
                    <div>
                      <p class=\"font-sans text-sm font-semibold text-ink leading-none\">Fast Coder 1</p>
                      <p class=\"font-mono text-micro text-ink-3 mt-0.5\">Wasm Core Builder</p>
                    </div>
                  </div>
                  <div class=\"flex items-center gap-1.5 sl-status-wrap\">
                    <span class=\"px-1.5 py-0.5 rounded font-mono text-micro uppercase font-medium bg-inset border border-line text-ink-2\">Polyglot</span>
                  </div>
                </div>
              </div>

              
              <div class=\"p-3 rounded-xl border border-line bg-ground hover:border-line transition-all sl-agent-node\" data-id=\"agent-vanilla-llm\">
                <div class=\"flex items-center justify-between\">
                  <div class=\"flex items-center gap-2.5\">
                    <div class=\"w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center text-ink-2\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8V4H8\"></path><rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect><path d=\"M2 14h2\"></path><path d=\"M20 14h2\"></path><path d=\"M15 13v2\"></path><path d=\"M9 13v2\"></path></svg>
                    </div>
                    <div>
                      <p class=\"font-sans text-sm font-semibold text-ink leading-none\">Vanilla Claude/GPT</p>
                      <p class=\"font-mono text-micro text-ink-3 mt-0.5\">Unprimed External Model</p>
                    </div>
                  </div>
                  <div class=\"flex items-center gap-1.5\">
                    <span class=\"px-1.5 py-0.5 rounded font-mono text-micro uppercase font-medium bg-inset border border-line text-ink-2\">Polyglot</span>
                  </div>
                </div>
              </div>

              
              <div class=\"p-3 rounded-xl border border-line bg-surface shadow-sm transition-all sl-agent-node\" data-id=\"agent-lonely-sub\">
                <div class=\"flex items-center justify-between\">
                  <div class=\"flex items-center gap-2.5\">
                    <div class=\"w-8 h-8 rounded-lg bg-surface border border-line flex items-center justify-center text-ink-2\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8V4H8\"></path><rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\"></rect><path d=\"M2 14h2\"></path><path d=\"M20 14h2\"></path><path d=\"M15 13v2\"></path><path d=\"M9 13v2\"></path></svg>
                    </div>
                    <div>
                      <p class=\"font-sans text-sm font-semibold text-ink leading-none\">Late-Joining Specialist</p>
                      <p class=\"font-mono text-micro text-ink-3 mt-0.5\">Offline Worker</p>
                    </div>
                  </div>
                  <div class=\"flex items-center gap-1.5 sl-status-wrap\">
                    <span class=\"px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-ink text-ground\">ASL Aware</span>
                    <span class=\"sl-lonely-pill px-1.5 py-0.5 rounded font-mono text-micro uppercase font-bold bg-inset text-ink-3 border border-line flex items-center gap-1\">
                      <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-2.5 h-2.5\"><rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\"></rect><path d=\"m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7\"></path></svg>
                      <span class=\"sl-agent-mailbox\">2</span>
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          
          <div class=\"pt-6 border-t border-line mt-6\">
            <p class=\"font-mono text-micro uppercase text-ink-3 mb-2 flex items-center gap-1.5\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3.5 h-3.5\"><line x1=\"4\" x2=\"4\" y1=\"21\" y2=\"14\"></line><line x1=\"4\" x2=\"4\" y1=\"10\" y2=\"3\"></line><line x1=\"12\" x2=\"12\" y1=\"21\" y2=\"12\"></line><line x1=\"12\" x2=\"12\" y1=\"8\" y2=\"3\"></line><line x1=\"20\" x2=\"20\" y1=\"21\" y2=\"16\"></line><line x1=\"20\" x2=\"20\" y1=\"12\" y2=\"3\"></line><line x1=\"2\" x2=\"6\" y1=\"14\" y2=\"14\"></line><line x1=\"10\" x2=\"14\" y1=\"8\" y2=\"8\"></line><line x1=\"18\" x2=\"22\" y1=\"16\" y2=\"16\"></line></svg>
              Interactive Chaos &amp; Simulation Suite:
            </p>
            <div class=\"grid grid-cols-2 sm:grid-cols-3 gap-2\">
              <button type=\"button\" data-scenario=\"aware\" class=\"sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-ink bg-ink text-ground\">
                1. Aware &harr; Aware
              </button>
              <button type=\"button\" data-scenario=\"asymmetric\" class=\"sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2\">
                2. Aware &harr; Unaware
              </button>
              <button type=\"button\" data-scenario=\"handoff\" class=\"sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2\">
                3. Handoff &amp; Scoping
              </button>
              <button type=\"button\" data-scenario=\"lonely\" class=\"sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2\">
                4. Lonely Mailbox
              </button>
              <button type=\"button\" data-scenario=\"stalled\" class=\"sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2\">
                5. Stalled Watchdog
              </button>
            </div>

            <div class=\"flex items-center justify-between mt-3 pt-3 border-t border-line\">
              <button type=\"button\" id=\"sl-dlq-btn\" class=\"font-mono text-micro text-ink-3 hover:text-ink flex items-center gap-1 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3 text-ink-3\"><path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z\"></path><line x1=\"12\" y1=\"9\" x2=\"12\" y2=\"13\"></line><line x1=\"12\" y1=\"17\" x2=\"12.01\" y2=\"17\"></line></svg>
                Test DLQ Trigger
              </button>
              <button type=\"button\" id=\"sl-reset-btn\" class=\"font-mono text-micro text-ink-3 hover:text-ink flex items-center gap-1 transition-colors\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\"><path d=\"M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8\"></path><path d=\"M3 3v5h5\"></path><path d=\"M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16\"></path><path d=\"M16 21h5v-5\"></path></svg>
                Reset Swarm
              </button>
            </div>
          </div>
        </div>

        
        <div class=\"lg:col-span-2 p-6 rounded-2xl border border-line bg-surface flex flex-col justify-between shadow-e2\">
          <div>
            <div class=\"flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 pb-4 border-b border-line mb-4\">
              <div class=\"flex items-center gap-2\">
                <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-ink-2 shrink-0\"><polyline points=\"16 18 22 12 16 6\"></polyline><polyline points=\"8 6 2 12 8 18\"></polyline></svg>
                <span class=\"font-mono text-micro uppercase font-semibold text-ink\">
                  SeamBus Wire Frame Inspector
                </span>
                <span id=\"sl-transmitting-badge\" class=\"hidden items-center gap-1 font-mono text-micro text-signal font-bold animate-pulse\">
                  <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-3 h-3\"><line x1=\"22\" y1=\"2\" x2=\"11\" y2=\"13\"></line><polygon points=\"22 2 15 22 11 13 2 9 22 2\"></polygon></svg>
                  Transmitting
                </span>
              </div>

              
              <div class=\"flex flex-wrap items-center gap-1 p-0.5 rounded-lg bg-inset border border-line max-w-full\" id=\"sl-tabs-container\">
                <button type=\"button\" data-tab=\"asl\" class=\"sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all bg-surface text-ink shadow-sm\">
                  ASL Native
                </button>
                <button type=\"button\" data-tab=\"coord\" class=\"sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all text-ink-3 hover:text-ink\">
                  asl/coord (Handoff)
                </button>
                <button type=\"button\" data-tab=\"polyglot\" class=\"sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all text-ink-3 hover:text-ink\">
                  Polyglot
                </button>
                <button type=\"button\" data-tab=\"compact\" class=\"sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all text-ink-3 hover:text-ink\">
                  Compact
                </button>
              </div>
            </div>

            
            <div class=\"relative min-h-[220px]\">
              
              <div class=\"sl-code-pane block\" id=\"sl-pane-asl\">
                <pre class=\"p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed shadow-inner\" id=\"sl-asl-pre\">(sb
  :v 1
  :id \"msg-9f201\"
  :from \"agent-orchestrator\"
  :to \"agent-planner\"
  :dialect \"asl/v1\"
  :ts 1772879500000
  :type \"DATA\"
  :channel \"tasks/codegen\"
  :body {\"action\":\"compile_wasm\",\"module\":\"core/matrix\",\"opt\":\"O3\",\"timeout-ms\":5000})

(:d \"Pure S-expression envelope with typed coordination frame.\")</pre>
              </div>

              
              <div class=\"sl-code-pane hidden space-y-3\" id=\"sl-pane-coord\">
                <pre class=\"p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed shadow-inner\">(pass
  :v 1
  :id \"h-7721\"
  :from \"agent-orchestrator\"
  :to \"agent-coder-1\"
  :ts 1772879500000
  :task \"implement_rate_limiter\"
  :cwd \"packages/asl-rate\"
  :owns [\"src/limiter.asl\" \"tests/limiter_test.asl\"]
  :frozen [\"src/core.asl\"]
  :gate \"asl check src/limiter.asl &amp;&amp; asl test tests/\"
  :budget 4000)</pre>
                <div class=\"p-3 rounded-xl bg-inset border border-line flex flex-col sm:flex-row items-start sm:items-center justify-between gap-2 text-xs\">
                  <div>
                    <span class=\"font-mono font-bold text-ink\">Context Compression Benchmark:</span>
                    <span class=\"text-ink-2\">Raw Chat: 1,716 tokens &rarr; SeamBus AST: 285 tokens</span>
                  </div>
                  <div class=\"flex items-center gap-2\">
                    <span class=\"px-2 py-0.5 rounded bg-surface border border-line font-mono font-bold text-ink\">
                      -83.4% Tokens
                    </span>
                    <span class=\"px-2 py-0.5 rounded bg-surface border border-line font-mono font-bold text-ink\">
                      Zero-Leak Firewall
                    </span>
                  </div>
                </div>
              </div>

              
              <div class=\"sl-code-pane hidden\" id=\"sl-pane-polyglot\">
                <pre class=\"p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed shadow-inner\">&lt;!-- SEAMBUS_HEADER: {\"v\":1,\"id\":\"msg-9f201\",\"from\":\"agent-orchestrator\",\"to\":\"agent-vanilla-llm\",\"dialect\":\"polyglot/v1\",\"type\":\"DATA\"} --&gt;
[SeamBus Autonomous Protocol Primer]
You are communicating with agent \"agent-orchestrator\" over SeamBus.
Please execute the requested task and reply in a fenced JSON code block:

```json
{
  \"action\": \"audit_architecture\",
  \"target\": \"mesh_topology\",
  \"replyTo\": \"msg-9f201\"
}
```
&lt;!-- SEAMBUS_FOOTER --&gt;</pre>
              </div>

              
              <div class=\"sl-code-pane hidden\" id=\"sl-pane-compact\">
                <pre class=\"p-4 rounded-xl font-mono text-xs bg-ground text-ink border border-line overflow-x-auto leading-relaxed shadow-inner\">SB1|1|msg-9f201|agent-orchestrator|agent-coder-1|DATA|tasks/codegen|1772879500000||{\"action\":\"compile_wasm\",\"module\":\"core/matrix\",\"opt\":\"O3\"}</pre>
              </div>
            </div>
          </div>

          
          <div class=\"mt-6 pt-4 border-t border-line flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3\">
            <div class=\"flex items-center gap-2\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" class=\"w-4 h-4 text-emerald-400\"><circle cx=\"12\" cy=\"12\" r=\"10\"></circle><path d=\"m9 12 2 2 4-4\"></path></svg>
              <span class=\"font-sans text-xs text-ink-2\">
                Nominal ASL AST types guarantee zero schema drift across all agent runtimes.
              </span>
            </div>

            <div class=\"flex items-center gap-2\">
              <span class=\"font-mono text-micro text-ink-3 uppercase font-medium\">Access Modes:</span>
              <span class=\"px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink\">
                CLI ($ asl bus)
              </span>
              <span class=\"px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink\">
                MCP Server
              </span>
              <span class=\"px-2 py-0.5 rounded bg-inset border border-line font-mono text-micro font-semibold text-ink\">
                Wasm SDK
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <script>
    (function() {
      function init() {
        var framesCountEl = document.getElementById('sl-frames-count');
        var compressionEl = document.getElementById('sl-compression-val');
        var mailboxEl = document.getElementById('sl-mailbox-count');
        var dlqEl = document.getElementById('sl-dlq-count');
        var transmittingBadge = document.getElementById('sl-transmitting-badge');
        var scenarioBtns = document.querySelectorAll('.sl-scenario-btn');
        var tabBtns = document.querySelectorAll('.sl-tab-btn');
        var panes = {
          'asl': document.getElementById('sl-pane-asl'),
          'coord': document.getElementById('sl-pane-coord'),
          'polyglot': document.getElementById('sl-pane-polyglot'),
          'compact': document.getElementById('sl-pane-compact')
        };
        var agentNodes = document.querySelectorAll('.sl-agent-node');

        var frames = 1428;
        var dlqs = 0;

        function setTab(tab) {
          tabBtns.forEach(function(btn) {
            if (btn.getAttribute('data-tab') === tab) {
              btn.className = 'sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all bg-surface text-ink shadow-sm';
            } else {
              btn.className = 'sl-tab-btn px-2 py-1 rounded font-mono text-micro font-medium transition-all text-ink-3 hover:text-ink';
            }
          });
          for (var k in panes) {
            if (panes[k]) {
              if (k === tab) {
                panes[k].classList.remove('hidden');
                panes[k].classList.add('block');
              } else {
                panes[k].classList.remove('block');
                panes[k].classList.add('hidden');
              }
            }
          }
        }

        tabBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            setTab(btn.getAttribute('data-tab'));
          });
        });

        function triggerTransmission() {
          if (!transmittingBadge) return;
          transmittingBadge.classList.remove('hidden');
          transmittingBadge.classList.add('inline-flex');
          setTimeout(function() {
            transmittingBadge.classList.remove('inline-flex');
            transmittingBadge.classList.add('hidden');
          }, 1200);
        }

        scenarioBtns.forEach(function(btn) {
          btn.addEventListener('click', function() {
            var scenario = btn.getAttribute('data-scenario');
            scenarioBtns.forEach(function(b) {
              if (b === btn) {
                b.className = 'sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-ink bg-ink text-ground';
              } else {
                b.className = 'sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2';
              }
            });

            triggerTransmission();

            if (scenario === 'aware') {
              setTab('asl');
              frames += 2;
              framesCountEl.textContent = frames.toLocaleString();
            } else if (scenario === 'asymmetric') {
              setTab('polyglot');
              frames += 1;
              framesCountEl.textContent = frames.toLocaleString();
            } else if (scenario === 'handoff') {
              setTab('coord');
              frames += 3;
              framesCountEl.textContent = frames.toLocaleString();
              compressionEl.textContent = '-83.4%';
            } else if (scenario === 'lonely') {
              setTab('asl');
              frames += 2;
              framesCountEl.textContent = frames.toLocaleString();
              mailboxEl.textContent = '0 pending';
              var lonelyAgent = document.querySelector('[data-id=\"agent-lonely-sub\"]');
              if (lonelyAgent) {
                var pill = lonelyAgent.querySelector('.sl-lonely-pill');
                if (pill) pill.style.display = 'none';
              }
            } else if (scenario === 'stalled') {
              var coderAgent = document.querySelector('[data-id=\"agent-coder-1\"]');
              if (coderAgent) {
                coderAgent.classList.add('opacity-60');
              }
            }
          });
        });

        var dlqBtn = document.getElementById('sl-dlq-btn');
        if (dlqBtn) {
          dlqBtn.addEventListener('click', function() {
            dlqs++;
            dlqEl.textContent = dlqs;
            triggerTransmission();
          });
        }

        var resetBtn = document.getElementById('sl-reset-btn');
        if (resetBtn) {
          resetBtn.addEventListener('click', function() {
            frames = 1428;
            dlqs = 0;
            framesCountEl.textContent = '1,428';
            compressionEl.textContent = '-68.4%';
            mailboxEl.textContent = '2 pending';
            dlqEl.textContent = '0';
            setTab('asl');

            scenarioBtns.forEach(function(b, idx) {
              if (idx === 0) {
                b.className = 'sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-ink bg-ink text-ground';
              } else {
                b.className = 'sl-scenario-btn px-2.5 py-1.5 rounded-lg font-mono text-micro font-medium border text-left transition-all border-line bg-surface hover:bg-inset text-ink-2';
              }
            });

            var coderAgent = document.querySelector('[data-id=\"agent-coder-1\"]');
            if (coderAgent) coderAgent.classList.remove('opacity-60');

            var lonelyAgent = document.querySelector('[data-id=\"agent-lonely-sub\"]');
            if (lonelyAgent) {
              var pill = lonelyAgent.querySelector('.sl-lonely-pill');
              if (pill) pill.style.display = '';
            }
          });
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
      } else {
        init();
      }
    })();
  </script>")

(df skyloom-visualizer [] -> Str
  :d "Alias for render-skyloom-visualizer."
  (render-skyloom-visualizer))
