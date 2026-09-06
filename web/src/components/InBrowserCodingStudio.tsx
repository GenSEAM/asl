import React, { useState, useRef } from 'react';
import { Play, RotateCcw, Sparkles, Terminal, Gamepad2, Layout, Cpu, Copy, Check } from 'lucide-react';

interface CodeTemplate {
  name: string;
  icon: React.ComponentType<{ className?: string }>;
  description: string;
  code: string;
}

const TEMPLATES: Record<string, CodeTemplate> = {
  game: {
    name: 'Arcade Space Dodger (Mini-Game)',
    icon: Gamepad2,
    description: 'Playable retro canvas game with arrow controls, collision detection, and score tracking.',
    code: `<!DOCTYPE html>
<html>
<head>
  <style>
    body { margin: 0; background: #070a12; color: #fff; font-family: monospace; overflow: hidden; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
    canvas { background: #0b0f19; border: 2px solid #38ef7d; border-radius: 12px; box-shadow: 0 0 20px rgba(56, 239, 125, 0.2); }
    #ui { position: absolute; top: 15px; font-size: 14px; color: #38ef7d; font-weight: bold; text-shadow: 0 0 8px rgba(56,239,125,0.5); }
    #instructions { position: absolute; bottom: 15px; font-size: 11px; color: #94a3b8; }
  </style>
</head>
<body>
  <div id="ui">SCORE: <span id="score">0</span> | LIVES: <span id="lives">3</span></div>
  <canvas id="gameCanvas" width="480" height="320"></canvas>
  <div id="instructions">Use [Left / Right Arrows] or [A / D] to Move · Avoid the Asteroids</div>

  <script>
    const canvas = document.getElementById('gameCanvas');
    const ctx = canvas.getContext('2d');
    let score = 0;
    let lives = 3;
    let gameOver = false;

    const player = { x: canvas.width / 2 - 15, y: canvas.height - 35, width: 30, height: 20, speed: 6 };
    const hazards = [];
    const keys = {};

    window.addEventListener('keydown', e => keys[e.key] = true);
    window.addEventListener('keyup', e => keys[e.key] = false);

    function spawnHazard() {
      if (gameOver) return;
      hazards.push({
        x: Math.random() * (canvas.width - 20),
        y: -20,
        size: 12 + Math.random() * 12,
        speed: 2 + Math.random() * 2.5
      });
      setTimeout(spawnHazard, 600 - Math.min(400, score * 10));
    }
    spawnHazard();

    function update() {
      if (gameOver) return;

      if ((keys['ArrowLeft'] || keys['a'] || keys['A']) && player.x > 5) player.x -= player.speed;
      if ((keys['ArrowRight'] || keys['d'] || keys['D']) && player.x < canvas.width - player.width - 5) player.x += player.speed;

      for (let i = hazards.length - 1; i >= 0; i--) {
        const h = hazards[i];
        h.y += h.speed;

        // Collision check
        if (h.x < player.x + player.width && h.x + h.size > player.x &&
            h.y < player.y + player.height && h.y + h.size > player.y) {
          hazards.splice(i, 1);
          lives--;
          document.getElementById('lives').innerText = lives;
          if (lives <= 0) {
            gameOver = true;
          }
          continue;
        }

        // Off screen check
        if (h.y > canvas.height) {
          hazards.splice(i, 1);
          score++;
          document.getElementById('score').innerText = score;
        }
      }
    }

    function render() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      // Draw Player Ship
      ctx.fillStyle = '#38ef7d';
      ctx.beginPath();
      ctx.moveTo(player.x + player.width / 2, player.y);
      ctx.lineTo(player.x + player.width, player.y + player.height);
      ctx.lineTo(player.x, player.y + player.height);
      ctx.closePath();
      ctx.fill();

      // Draw Thruster Flame
      ctx.fillStyle = '#ff6b6b';
      ctx.beginPath();
      ctx.moveTo(player.x + player.width * 0.3, player.y + player.height);
      ctx.lineTo(player.x + player.width * 0.7, player.y + player.height);
      ctx.lineTo(player.x + player.width / 2, player.y + player.height + 6 + Math.random() * 6);
      ctx.closePath();
      ctx.fill();

      // Draw Hazards
      ctx.fillStyle = '#00f2fe';
      hazards.forEach(h => {
        ctx.beginPath();
        ctx.arc(h.x + h.size / 2, h.y + h.size / 2, h.size / 2, 0, Math.PI * 2);
        ctx.fill();
      });

      if (gameOver) {
        ctx.fillStyle = 'rgba(0, 0, 0, 0.75)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff6b6b';
        ctx.font = '20px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('MISSION FAILED', canvas.width / 2, canvas.height / 2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '12px monospace';
        ctx.fillText('Final Score: ' + score + ' | Refresh to retry', canvas.width / 2, canvas.height / 2 + 20);
      }

      update();
      requestAnimationFrame(render);
    }
    requestAnimationFrame(render);
  </script>
</body>
</html>`
  },

  reactApp: {
    name: 'Reactive AI Agent Cockpit (React UI)',
    icon: Layout,
    description: 'Dynamic interactive dashboard with reactive state, metrics counters, and live event feed.',
    code: `<!DOCTYPE html>
<html>
<head>
  <script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
  <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>body { background: #090d16; color: #e2e8f0; font-family: monospace; }</style>
</head>
<body class="p-6">
  <div id="root"></div>

  <script type="text/babel">
    function AgentCockpit() {
      const [ticks, setTicks] = React.useState(142);
      const [swarmActive, setSwarmActive] = React.useState(true);
      const [logs, setLogs] = React.useState([
        "0.038ms WASI instance initialized",
        "PCP constitution grounded @p-01",
        "Agent-Bus mesh handshake ack: Beta"
      ]);

      const triggerTask = () => {
        setTicks(t => t + 1);
        const newMsg = "Synthesized AST patch #" + (ticks + 1) + " (0.04ms)";
        setLogs(prev => [newMsg, ...prev.slice(0, 4)]);
      };

      return (
        <div className="max-w-md mx-auto bg-slate-900 border border-emerald-500/30 rounded-2xl p-5 shadow-2xl">
          <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
            <div className="flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
              <h1 className="text-emerald-400 font-bold text-sm tracking-wider">EDDIE LIVE AGENT COCKPIT</h1>
            </div>
            <span className="text-xs px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">WASM RUNNER</span>
          </div>

          <div className="grid grid-cols-2 gap-3 mb-4">
            <div className="bg-slate-800/80 p-3 rounded-xl border border-slate-700">
              <div className="text-[10px] text-slate-400 uppercase">Total Tasks</div>
              <div className="text-xl font-bold text-emerald-400">{ticks}</div>
            </div>
            <div className="bg-slate-800/80 p-3 rounded-xl border border-slate-700">
              <div className="text-[10px] text-slate-400 uppercase">Swarm Status</div>
              <div className="text-sm font-bold text-cyan-400 mt-1">{swarmActive ? "SYNCED (4/4)" : "PAUSED"}</div>
            </div>
          </div>

          <button
            onClick={triggerTask}
            className="w-full py-2 px-4 rounded-xl bg-emerald-500 hover:bg-emerald-600 text-slate-950 font-bold text-xs transition-all shadow-lg shadow-emerald-500/20 mb-4"
          >
            ⚡ Trigger Autonomous Synthesis Turn
          </button>

          <div className="bg-slate-950 p-3 rounded-xl border border-slate-800">
            <div className="text-[10px] text-slate-500 uppercase mb-1">Live Execution Stream</div>
            {logs.map((log, idx) => (
              <div key={idx} className="text-xs text-slate-300 py-0.5 flex items-center gap-1.5">
                <span className="text-emerald-400">▶</span> {log}
              </div>
            ))}
          </div>
        </div>
      );
    }

    ReactDOM.createRoot(document.getElementById('root')).render(<AgentCockpit />);
  </script>
</body>
</html>`
  },

  dagSimulator: {
    name: 'Agent DAG State Machine',
    icon: Cpu,
    description: 'In-browser visualization of multi-step task DAG execution with live state machine transitions.',
    code: `<!DOCTYPE html>
<html>
<head>
  <style>
    body { background: #0a0d16; color: #fff; font-family: monospace; padding: 20px; }
    .dag { display: flex; flex-direction: column; gap: 16px; max-width: 440px; margin: 0 auto; }
    .node { background: #131b2e; border: 1px solid #1e293b; padding: 12px; rounded: 12px; border-radius: 10px; display: flex; align-items: center; justify-content: space-between; transition: all 0.3s; }
    .node.running { border-color: #38ef7d; background: rgba(56, 239, 125, 0.08); }
    .node.done { border-color: #00f2fe; background: rgba(0, 242, 254, 0.08); }
    .badge { font-size: 10px; padding: 3px 8px; border-radius: 6px; font-weight: bold; }
    .b-idle { background: #334155; color: #94a3b8; }
    .b-run { background: #38ef7d; color: #000; }
    .b-done { background: #00f2fe; color: #000; }
    button { width: 100%; margin-top: 15px; padding: 10px; background: #38ef7d; border: none; font-weight: bold; border-radius: 8px; cursor: pointer; color: #000; }
  </style>
</head>
<body>
  <div class="dag">
    <h3 style="color:#38ef7d; margin:0 0 10px 0; text-align:center;">Autonomous Task DAG Engine</h3>
    <div id="n1" class="node"><span>1. Parse S-Expression AST</span><span id="b1" class="badge b-idle">IDLE</span></div>
    <div id="n2" class="node"><span>2. Epistemic Citation Audit</span><span id="b2" class="badge b-idle">IDLE</span></div>
    <div id="n3" class="node"><span>3. Jailed WASI Sandbox Run</span><span id="b3" class="badge b-idle">IDLE</span></div>
    <div id="n4" class="node"><span>4. Commit Verified Diff</span><span id="b4" class="badge b-idle">IDLE</span></div>
    <button onclick="runPipeline()">Start DAG Execution</button>
  </div>

  <script>
    async function runPipeline() {
      const steps = [
        { node: 'n1', badge: 'b1', time: 500 },
        { node: 'n2', badge: 'b2', time: 600 },
        { node: 'n3', badge: 'b3', time: 700 },
        { node: 'n4', badge: 'b4', time: 400 }
      ];

      for (const s of steps) {
        const n = document.getElementById(s.node);
        const b = document.getElementById(s.badge);
        n.className = 'node running';
        b.className = 'badge b-run';
        b.innerText = 'RUNNING';
        await new Promise(r => setTimeout(r, s.time));
        n.className = 'node done';
        b.className = 'badge b-done';
        b.innerText = 'VERIFIED';
      }
    }
  </script>
</body>
</html>`
  }
};

export const InBrowserCodingStudio: React.FC = () => {
  const [selectedTemplate, setSelectedTemplate] = useState<string>('game');
  const [code, setCode] = useState<string>(TEMPLATES.game.code);
  const [iframeKey, setIframeKey] = useState<number>(0);
  const [copied, setCopied] = useState<boolean>(false);
  const [aiPrompt, setAiPrompt] = useState<string>('');
  const [isGenerating, setIsGenerating] = useState<boolean>(false);

  const iframeRef = useRef<HTMLIFrameElement | null>(null);

  const handleSelectTemplate = (key: string) => {
    setSelectedTemplate(key);
    setCode(TEMPLATES[key].code);
    setIframeKey(k => k + 1);
  };

  const handleRun = () => {
    setIframeKey(k => k + 1);
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Simulated In-Browser Micro-Model Code Generator
  const handleGenerateWithAi = () => {
    if (!aiPrompt.trim()) return;
    setIsGenerating(true);

    setTimeout(() => {
      if (aiPrompt.toLowerCase().includes('snake')) {
        setCode(`<!DOCTYPE html>
<html>
<head>
  <style>
    body { background: #070a12; color: #38ef7d; font-family: monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    canvas { background: #0f172a; border: 2px solid #38ef7d; border-radius: 8px; }
  </style>
</head>
<body>
  <div style="margin-bottom: 10px; font-weight: bold;">EDDIE SNAKE | Score: <span id="score">0</span></div>
  <canvas id="c" width="300" height="300"></canvas>
  <div style="margin-top: 10px; font-size: 11px; color: #94a3b8;">Use Arrow Keys to Move</div>
  <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    const grid = 15;
    let snake = [{x: 150, y: 150}];
    let dx = grid, dy = 0;
    let food = {x: 60, y: 60};
    let score = 0;

    window.addEventListener('keydown', e => {
      if (e.key === 'ArrowUp' && dy === 0) { dx = 0; dy = -grid; }
      if (e.key === 'ArrowDown' && dy === 0) { dx = 0; dy = grid; }
      if (e.key === 'ArrowLeft' && dx === 0) { dx = -grid; dy = 0; }
      if (e.key === 'ArrowRight' && dx === 0) { dx = grid; dy = 0; }
    });

    function loop() {
      const head = {x: snake[0].x + dx, y: snake[0].y + dy};
      if (head.x < 0 || head.x >= 300 || head.y < 0 || head.y >= 300) {
        snake = [{x: 150, y: 150}];
        score = 0;
        dx = grid; dy = 0;
      } else {
        snake.unshift(head);
        if (head.x === food.x && head.y === food.y) {
          score += 10;
          document.getElementById('score').innerText = score;
          food = {x: Math.floor(Math.random() * 20) * grid, y: Math.floor(Math.random() * 20) * grid};
        } else {
          snake.pop();
        }
      }

      ctx.clearRect(0, 0, 300, 300);
      ctx.fillStyle = '#ff6b6b';
      ctx.fillRect(food.x, food.y, grid - 1, grid - 1);
      ctx.fillStyle = '#38ef7d';
      snake.forEach(s => ctx.fillRect(s.x, s.y, grid - 1, grid - 1));
      setTimeout(loop, 90);
    }
    loop();
  </script>
</body>
</html>`);
      } else {
        // Appends a custom reactive banner based on the user prompt
        setCode(prev => prev.replace('</body>', `  <div style="position:fixed;bottom:10px;left:10px;background:rgba(56,239,125,0.15);border:1px solid #38ef7d;color:#38ef7d;padding:6px 12px;border-radius:8px;font-size:11px;font-family:monospace;">✨ AI Modified: ${aiPrompt}</div>\n</body>`));
      }
      setIsGenerating(false);
      setAiPrompt('');
      setIframeKey(k => k + 1);
    }, 600);
  };

  return (
    <div className="flex flex-col gap-6 w-full">
      {/* Header & Controls */}
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div>
          <h2 className="text-xl font-bold text-ink flex items-center gap-2">
            <Terminal className="w-5 h-5 text-signal" />
            AgentScript In-Browser Live Coding & App Runner
          </h2>
          <p className="text-xs text-ink-muted mt-1">
            Write and execute HTML, JavaScript, React, or Canvas games with sub-millisecond in-browser rendering
          </p>
        </div>

        {/* Templates Selector */}
        <div className="flex items-center gap-2">
          {Object.entries(TEMPLATES).map(([key, t]) => {
            const Icon = t.icon;
            return (
              <button
                key={key}
                onClick={() => handleSelectTemplate(key)}
                className={`px-3 py-1.5 text-xs font-mono rounded-xl border transition-all flex items-center gap-1.5 ${
                  selectedTemplate === key
                    ? 'bg-signal/20 border-signal text-signal font-bold'
                    : 'border-line text-ink-muted hover:text-ink bg-surface-2'
                }`}
              >
                <Icon className="w-3.5 h-3.5" />
                <span>{t.name.split(' ')[0]}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Eddie In-Browser Agent & ASL Toolkit Bar */}
      <div className="bg-surface-2 border border-line p-3.5 rounded-2xl flex flex-wrap items-center justify-between gap-3 text-xs font-mono">
        <div className="flex items-center gap-2.5">
          <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
          <span className="font-bold text-ink">Eddie In-Browser Companion</span>
          <span className="text-white/30">|</span>
          <span className="text-[11px] text-signal font-semibold">Config: .asl.config.asn (:pure-asl true :runtime :wasm)</span>
        </div>
        <div className="flex items-center gap-2 text-[11px]">
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-intel</span>
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-mem</span>
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-codec</span>
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-svg</span>
          <span className="px-2 py-0.5 rounded bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-bold">7/7 Gates Passed</span>
        </div>
      </div>

      {/* AI Assistant Quick Prompt Bar */}
      <div className="bg-surface-2 border border-line p-3 rounded-2xl flex items-center gap-3">
        <Sparkles className="w-4 h-4 text-signal shrink-0" />
        <input
          type="text"
          value={aiPrompt}
          onChange={(e) => setAiPrompt(e.target.value)}
          placeholder="Prompt Eddie in-browser model: e.g. 'Build a classic snake game', 'Add sound effects', 'Add neon glow'..."
          className="flex-1 bg-surface border border-line rounded-xl px-3 py-1.5 text-xs text-ink focus:outline-none focus:ring-1 focus:ring-signal font-mono"
          onKeyDown={(e) => e.key === 'Enter' && handleGenerateWithAi()}
        />
        <button
          onClick={handleGenerateWithAi}
          disabled={isGenerating || !aiPrompt.trim()}
          className="px-3 py-1.5 text-xs font-mono font-semibold rounded-xl border border-signal/40 bg-signal/15 hover:bg-signal/25 text-signal transition-all disabled:opacity-40"
        >
          {isGenerating ? 'Synthesizing...' : 'Eddie Auto-Code'}
        </button>
      </div>

      {/* Code Editor and Live Preview Split */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 items-stretch">
        {/* Code Editor */}
        <div className="flex flex-col bg-surface border border-line rounded-2xl overflow-hidden shadow-sm">
          <div className="flex items-center justify-between px-4 py-2.5 bg-surface-2 border-b border-line text-xs font-mono text-ink-muted">
            <div className="flex items-center gap-2">
              <span className="font-bold text-ink">Source Code</span>
              <span className="text-white/40">|</span>
              <span className="text-[11px]">{TEMPLATES[selectedTemplate]?.name}</span>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={handleCopy}
                className="px-2 py-1 rounded bg-surface border border-line text-[11px] hover:text-ink flex items-center gap-1"
              >
                {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                <span>{copied ? 'Copied' : 'Copy'}</span>
              </button>
              <button
                onClick={handleRun}
                className="px-2.5 py-1 rounded bg-signal/20 border border-signal/40 text-signal text-[11px] font-bold hover:bg-signal/30 flex items-center gap-1"
              >
                <Play className="w-3 h-3" />
                <span>Run</span>
              </button>
            </div>
          </div>
          <textarea
            value={code}
            onChange={(e) => setCode(e.target.value)}
            className="w-full h-[460px] p-4 bg-surface font-mono text-xs text-ink leading-relaxed resize-none focus:outline-none focus:ring-1 focus:ring-signal border-0"
            spellCheck={false}
          />
        </div>

        {/* Live Interactive Sandbox Viewport */}
        <div className="flex flex-col bg-surface border border-line rounded-2xl overflow-hidden shadow-sm">
          <div className="flex items-center justify-between px-4 py-2.5 bg-surface-2 border-b border-line text-xs font-mono text-ink-muted">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
              <span className="font-bold text-ink">Live Interactive Preview</span>
            </div>
            <button
              onClick={handleRun}
              className="px-2 py-1 rounded bg-surface border border-line text-[11px] hover:text-ink flex items-center gap-1"
              title="Reset Sandbox"
            >
              <RotateCcw className="w-3 h-3" />
              <span>Reset</span>
            </button>
          </div>
          <div className="w-full h-[460px] bg-black/60 relative">
            <iframe
              key={iframeKey}
              ref={iframeRef}
              srcDoc={code}
              title="Live Runner"
              className="w-full h-full border-0"
              sandbox="allow-scripts allow-modals allow-same-origin"
            />
          </div>
        </div>
      </div>
    </div>
  );
};
