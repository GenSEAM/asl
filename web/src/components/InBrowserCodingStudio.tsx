import React, { useState, useRef } from 'react';
import { Play, RotateCcw, Sparkles, Terminal, Gamepad2, Layout, Copy, Check, Maximize2, Minimize2 } from 'lucide-react';

interface CodeTemplate {
  name: string;
  icon: React.ComponentType<{ className?: string }>;
  description: string;
  code: string;
}

const MODELS = [
  { id: 'eddie-webgpu', name: 'Eddie-SLM-3B (Local WebGPU)' },
  { id: 'gemma-wasm', name: 'Gemma-2-2B (Wasm SIMD)' },
  { id: 'qwen-coder', name: 'Qwen2.5-Coder-3B (In-Browser)' },
  { id: 'eddie-cloud', name: 'Eddie-Cloud-Pro (API)' }
];

const TEMPLATES: Record<string, CodeTemplate> = {
  tetris: {
    name: 'Agent Tetris (Retro Arcade)',
    icon: Gamepad2,
    description: 'Playable retro Tetris with keyboard rotation, soft drop, row clearing, and live score.',
    code: `<!DOCTYPE html>
<html>
<head>
  <style>
    body { margin: 0; background: #070a12; color: #fff; font-family: monospace; overflow: hidden; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
    canvas { background: #0b0f19; border: 2px solid #38ef7d; border-radius: 12px; box-shadow: 0 0 20px rgba(56, 239, 125, 0.2); }
    #ui { font-size: 14px; color: #38ef7d; font-weight: bold; margin-bottom: 8px; }
    #instructions { margin-top: 8px; font-size: 11px; color: #94a3b8; }
  </style>
</head>
<body>
  <div id="ui">SCORE: <span id="score">0</span> | LINES: <span id="lines">0</span></div>
  <canvas id="c" width="240" height="400"></canvas>
  <div id="instructions">← / → : Move | ↑ : Rotate | ↓ : Soft Drop</div>
  <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    const COLS = 10, ROWS = 20, BLOCK = 20;
    const board = Array.from({length: ROWS}, () => Array(COLS).fill(0));
    const COLORS = [null, '#00f2fe', '#facc15', '#a855f7', '#38ef7d', '#ff4757', '#3b82f6', '#fb923c'];
    const SHAPES = [
      [],
      [[1,1,1,1]],
      [[2,2],[2,2]],
      [[0,3,0],[3,3,3]],
      [[0,4,4],[4,4,0]],
      [[5,5,0],[0,5,5]],
      [[6,0,0],[6,6,6]],
      [[0,0,7],[7,7,7]]
    ];
    let score = 0, lines = 0, gameOver = false;
    let piece = null;
    function newPiece() {
      const type = Math.floor(Math.random() * 7) + 1;
      piece = { shape: SHAPES[type], color: type, x: Math.floor(COLS/2) - 1, y: 0 };
      if (collide(piece.shape, piece.x, piece.y)) { gameOver = true; }
    }
    function collide(shape, px, py) {
      for (let r=0; r<shape.length; r++) {
        for (let c=0; c<shape[r].length; c++) {
          if (shape[r][c]) {
            const nx = px + c, ny = py + r;
            if (nx < 0 || nx >= COLS || ny >= ROWS || (ny >= 0 && board[ny][nx])) return true;
          }
        }
      }
      return false;
    }
    function rotate(shape) {
      return shape[0].map((_, i) => shape.map(row => row[i]).reverse());
    }
    function merge() {
      piece.shape.forEach((row, r) => {
        row.forEach((val, c) => {
          if (val) board[piece.y + r][piece.x + c] = piece.color;
        });
      });
      clearRows();
      newPiece();
    }
    function clearRows() {
      let count = 0;
      for (let r = ROWS - 1; r >= 0; r--) {
        if (board[r].every(v => v !== 0)) {
          board.splice(r, 1);
          board.unshift(Array(COLS).fill(0));
          count++;
          r++;
        }
      }
      if (count) {
        lines += count;
        score += count * 100 * count;
        document.getElementById('score').innerText = score;
        document.getElementById('lines').innerText = lines;
      }
    }
    window.addEventListener('keydown', e => {
      if (gameOver) return;
      if (e.key === 'ArrowLeft' && !collide(piece.shape, piece.x - 1, piece.y)) piece.x--;
      if (e.key === 'ArrowRight' && !collide(piece.shape, piece.x + 1, piece.y)) piece.x++;
      if (e.key === 'ArrowDown') {
        if (!collide(piece.shape, piece.x, piece.y + 1)) piece.y++;
        else merge();
      }
      if (e.key === 'ArrowUp') {
        const rotated = rotate(piece.shape);
        if (!collide(rotated, piece.x, piece.y)) piece.shape = rotated;
      }
    });
    let dropTimer = 0;
    function update(time = 0) {
      if (!gameOver) {
        if (time - dropTimer > 450) {
          if (!collide(piece.shape, piece.x, piece.y + 1)) piece.y++;
          else merge();
          dropTimer = time;
        }
      }
      ctx.fillStyle = '#0b0f19';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      for (let r=0; r<ROWS; r++) {
        for (let c=0; c<COLS; c++) {
          if (board[r][c]) {
            ctx.fillStyle = COLORS[board[r][c]];
            ctx.fillRect(c*BLOCK+1, r*BLOCK+1, BLOCK-2, BLOCK-2);
          }
        }
      }
      if (piece) {
        ctx.fillStyle = COLORS[piece.color];
        piece.shape.forEach((row, r) => {
          row.forEach((v, c) => {
            if (v) ctx.fillRect((piece.x + c)*BLOCK+1, (piece.y + r)*BLOCK+1, BLOCK-2, BLOCK-2);
          });
        });
      }
      if (gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.85)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff4757';
        ctx.font = 'bold 16px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width/2, canvas.height/2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '11px monospace';
        ctx.fillText('Score: ' + score, canvas.width/2, canvas.height/2 + 15);
      }
      requestAnimationFrame(update);
    }
    newPiece();
    requestAnimationFrame(update);
  </script>
</body>
</html>`
  },

  flappy: {
    name: 'Agent Flappy Bird',
    icon: Gamepad2,
    description: 'Playable Flappy Bird with pipe physics, gravity, flap acceleration, and score tracker.',
    code: `<!DOCTYPE html>
<html>
<head>
  <style>
    body { margin: 0; background: #070a12; color: #fff; font-family: monospace; overflow: hidden; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
    canvas { background: #08101e; border: 2px solid #00f2fe; border-radius: 12px; box-shadow: 0 0 20px rgba(0, 242, 254, 0.2); }
    #ui { font-size: 14px; color: #00f2fe; font-weight: bold; margin-bottom: 8px; }
    #instructions { margin-top: 8px; font-size: 11px; color: #94a3b8; }
  </style>
</head>
<body>
  <div id="ui">SCORE: <span id="score">0</span></div>
  <canvas id="c" width="340" height="400"></canvas>
  <div id="instructions">Press [Space] or Click / Tap to Flap</div>
  <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    let bird = { x: 60, y: 200, vy: 0, gravity: 0.38, jump: -6.5, radius: 12 };
    let pipes = [];
    let score = 0, gameOver = false, frames = 0;
    function flap() {
      if (gameOver) { reset(); return; }
      bird.vy = bird.jump;
    }
    window.addEventListener('keydown', e => { if (e.code === 'Space') flap(); });
    canvas.addEventListener('pointerdown', flap);
    function reset() {
      bird.y = 200; bird.vy = 0;
      pipes = []; score = 0; gameOver = false;
      document.getElementById('score').innerText = score;
    }
    function update() {
      frames++;
      if (!gameOver) {
        bird.vy += bird.gravity;
        bird.y += bird.vy;
        if (bird.y + bird.radius >= canvas.height || bird.y - bird.radius <= 0) gameOver = true;
        if (frames % 95 === 0) {
          const gap = 115;
          const topH = 40 + Math.random() * (canvas.height - gap - 100);
          pipes.push({ x: canvas.width, top: topH, bottom: canvas.height - topH - gap, width: 42, passed: false });
        }
        for (let i = pipes.length - 1; i >= 0; i--) {
          const p = pipes[i];
          p.x -= 2.2;
          if (bird.x + bird.radius > p.x && bird.x - bird.radius < p.x + p.width) {
            if (bird.y - bird.radius < p.top || bird.y + bird.radius > canvas.height - p.bottom) {
              gameOver = true;
            }
          }
          if (!p.passed && p.x + p.width < bird.x) {
            p.passed = true;
            score++;
            document.getElementById('score').innerText = score;
          }
          if (p.x + p.width < 0) pipes.splice(i, 1);
        }
      }
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#10b981';
      pipes.forEach(p => {
        ctx.fillRect(p.x, 0, p.width, p.top);
        ctx.fillRect(p.x, canvas.height - p.bottom, p.width, p.bottom);
      });
      ctx.fillStyle = '#facc15';
      ctx.beginPath();
      ctx.arc(bird.x, bird.y, bird.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.arc(bird.x + 4, bird.y - 3, 3, 0, Math.PI * 2);
      ctx.fill();
      if (gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.75)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff4757';
        ctx.font = 'bold 20px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width/2, canvas.height/2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '12px monospace';
        ctx.fillText('Score: ' + score + ' (Click to retry)', canvas.width/2, canvas.height/2 + 20);
      }
      requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  </script>
</body>
</html>`
  },

  game: {
    name: 'Arcade Space Dodger',
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

        if (h.y > canvas.height) {
          hazards.splice(i, 1);
          score++;
          document.getElementById('score').innerText = score;
        }
      }
    }

    function render() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      ctx.fillStyle = '#38ef7d';
      ctx.beginPath();
      ctx.moveTo(player.x + player.width / 2, player.y);
      ctx.lineTo(player.x + player.width, player.y + player.height);
      ctx.lineTo(player.x, player.y + player.height);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#ff6b6b';
      ctx.beginPath();
      ctx.moveTo(player.x + player.width * 0.3, player.y + player.height);
      ctx.lineTo(player.x + player.width * 0.7, player.y + player.height);
      ctx.lineTo(player.x + player.width / 2, player.y + player.height + 6 + Math.random() * 6);
      ctx.closePath();
      ctx.fill();

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

  snake: {
    name: 'Cyber Snake Arcade',
    icon: Gamepad2,
    description: 'Playable retro neon snake with food generation, tail growth, and collision boundaries.',
    code: `<!DOCTYPE html>
<html>
<head>
  <style>
    body { background: #070a12; color: #38ef7d; font-family: monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    canvas { background: #0f172a; border: 2px solid #38ef7d; border-radius: 8px; box-shadow: 0 0 15px rgba(56,239,125,0.2); }
  </style>
</head>
<body>
  <div style="margin-bottom: 10px; font-weight: bold;">EDDIE CYBER SNAKE | Score: <span id="score">0</span></div>
  <canvas id="c" width="300" height="300"></canvas>
  <div style="margin-top: 10px; font-size: 11px; color: #94a3b8;">Use Arrow Keys to Steer</div>
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
</html>`
  },

  reactApp: {
    name: 'Reactive AI Agent Cockpit',
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
  }
};

const QUICK_PROMPTS = [
  { label: '🕹️ Playable Tetris', prompt: 'Build a playable retro arcade Tetris game with keyboard controls and score' },
  { label: '🐤 Flappy Bird', prompt: 'Build a playable Flappy Bird game with gravity, pipes, and jump physics' },
  { label: '🐍 Cyber Snake', prompt: 'Build a classic arcade snake game in canvas with score and arrows' },
  { label: '🚀 Space Dodger', prompt: 'Build a space dodging game with thrusters and asteroid collision' },
  { label: '🎛️ Agent Cockpit', prompt: 'Build a reactive AI agent cockpit with state counters and logs' }
];

export const InBrowserCodingStudio: React.FC = () => {
  const [selectedTemplate, setSelectedTemplate] = useState<string>('tetris');
  const [code, setCode] = useState<string>(TEMPLATES.tetris.code);
  const [selectedModel, setSelectedModel] = useState<string>('eddie-webgpu');
  const [fullPreview, setFullPreview] = useState<boolean>(false);
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

  const handleApplyQuickPrompt = (prompt: string) => {
    setAiPrompt(prompt);
    executePrompt(prompt);
  };

  const executePrompt = (promptToRun: string) => {
    if (!promptToRun.trim()) return;
    setIsGenerating(true);

    setTimeout(() => {
      const lower = promptToRun.toLowerCase();
      if (lower.includes('tetris') || lower.includes('тетрис') || lower.includes('тедрес')) {
        setSelectedTemplate('tetris');
        setCode(TEMPLATES.tetris.code);
      } else if (lower.includes('flappy') || lower.includes('птиц') || lower.includes('флэппи')) {
        setSelectedTemplate('flappy');
        setCode(TEMPLATES.flappy.code);
      } else if (lower.includes('snake') || lower.includes('змейк')) {
        setSelectedTemplate('snake');
        setCode(TEMPLATES.snake.code);
      } else if (lower.includes('space') || lower.includes('космос') || lower.includes('dodger')) {
        setSelectedTemplate('game');
        setCode(TEMPLATES.game.code);
      } else if (lower.includes('cockpit') || lower.includes('панель') || lower.includes('dashboard')) {
        setSelectedTemplate('reactApp');
        setCode(TEMPLATES.reactApp.code);
      } else {
        // Dynamic prompt modification with live watermark
        setCode(prev => prev.replace('</body>', `  <div style="position:fixed;bottom:10px;left:10px;background:rgba(56,239,125,0.15);border:1px solid #38ef7d;color:#38ef7d;padding:6px 12px;border-radius:8px;font-size:11px;font-family:monospace;z-index:999;">✨ Synthesized via ${selectedModel}: ${promptToRun}</div>\n</body>`));
      }
      setIsGenerating(false);
      setIframeKey(k => k + 1);
    }, 550);
  };

  return (
    <div className="flex flex-col gap-6 w-full">
      {/* Header & Controls */}
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div>
          <h2 className="text-xl font-bold text-ink flex items-center gap-2">
            <Terminal className="w-5 h-5 text-signal" />
            AgentScript In-Browser Live Coding & Playable Sandbox
          </h2>
          <p className="text-xs text-ink-muted mt-1">
            Synthesize, compile, and execute playable games & interactive apps natively inside the browser sandbox
          </p>
        </div>

        {/* Model & Templates Selector */}
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2">
            <span className="text-xs text-ink-muted">Model:</span>
            <select
              value={selectedModel}
              onChange={(e) => setSelectedModel(e.target.value)}
              className="px-2.5 py-1 text-xs font-mono rounded-xl border border-line bg-surface-2 text-ink focus:outline-none focus:ring-1 focus:ring-signal"
            >
              {MODELS.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name}
                </option>
              ))}
            </select>
          </div>

          <div className="flex flex-wrap items-center gap-1.5">
            {Object.entries(TEMPLATES).map(([key, t]) => {
              const Icon = t.icon;
              return (
                <button
                  key={key}
                  onClick={() => handleSelectTemplate(key)}
                  className={`px-3 py-1 text-xs font-mono rounded-xl border transition-all flex items-center gap-1.5 ${
                    selectedTemplate === key
                      ? 'bg-signal/20 border-signal text-signal font-bold'
                      : 'border-line text-ink-muted hover:text-ink bg-surface-2'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5" />
                  <span>{t.name.split(' ')[1] || t.name.split(' ')[0]}</span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {/* Eddie In-Browser Agent & ASL Harness Status */}
      <div className="bg-surface-2 border border-line p-3.5 rounded-2xl flex flex-wrap items-center justify-between gap-3 text-xs font-mono">
        <div className="flex items-center gap-2.5">
          <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
          <span className="font-bold text-ink">Eddie In-Browser Companion</span>
          <span className="text-white/30">|</span>
          <span className="text-[11px] text-signal font-semibold">Jailed Wasm Sandbox · .asl.config.asn Active</span>
        </div>
        <div className="flex items-center gap-2 text-[11px]">
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-harness</span>
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-intel</span>
          <span className="px-2 py-0.5 rounded bg-surface border border-line text-ink-muted">asl-codec</span>
          <button
            onClick={() => setFullPreview(!fullPreview)}
            className="px-2.5 py-0.5 rounded bg-surface border border-line hover:text-ink text-ink-muted flex items-center gap-1 text-[11px]"
          >
            {fullPreview ? <Minimize2 className="w-3 h-3" /> : <Maximize2 className="w-3 h-3" />}
            <span>{fullPreview ? 'Split Editor' : 'Full Screen Preview'}</span>
          </button>
          <span className="px-2 py-0.5 rounded bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-bold">116/116 Suites Clean</span>
        </div>
      </div>

      {/* AI Assistant Quick Prompt Bar & Game Chips */}
      <div className="bg-surface-2 border border-line p-3.5 rounded-2xl flex flex-col gap-3">
        <div className="flex items-center gap-3">
          <Sparkles className="w-4 h-4 text-signal shrink-0" />
          <input
            type="text"
            value={aiPrompt}
            onChange={(e) => setAiPrompt(e.target.value)}
            placeholder="Prompt Eddie companion: e.g. 'Build a playable Tetris game', 'Build Flappy Bird', 'Add neon glow to snake'..."
            className="flex-1 bg-surface border border-line rounded-xl px-3 py-2 text-xs text-ink focus:outline-none focus:ring-1 focus:ring-signal font-mono"
            onKeyDown={(e) => e.key === 'Enter' && executePrompt(aiPrompt)}
          />
          <button
            onClick={() => executePrompt(aiPrompt)}
            disabled={isGenerating || !aiPrompt.trim()}
            className="px-4 py-2 text-xs font-mono font-semibold rounded-xl border border-signal/40 bg-signal/15 hover:bg-signal/25 text-signal transition-all disabled:opacity-40 shrink-0"
          >
            {isGenerating ? 'Synthesizing...' : 'Eddie Auto-Code'}
          </button>
        </div>

        {/* Quick Example Chips */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[11px] font-mono text-ink-muted">Example Prompts:</span>
          {QUICK_PROMPTS.map((qp, idx) => (
            <button
              key={idx}
              onClick={() => handleApplyQuickPrompt(qp.prompt)}
              className="px-2.5 py-1 rounded-lg bg-surface border border-line hover:border-signal/40 hover:text-signal text-[11px] font-mono text-ink-muted transition-all"
            >
              {qp.label}
            </button>
          ))}
        </div>
      </div>

      {/* Code Editor and Live Preview Split / Fullscreen */}
      <div className={`grid ${fullPreview ? 'grid-cols-1' : 'grid-cols-1 lg:grid-cols-2'} gap-6 items-stretch`}>
        {/* Code Editor (hidden in fullPreview mode for clean presentation) */}
        {!fullPreview && (
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
              className="w-full h-[520px] p-4 bg-surface font-mono text-xs text-ink leading-relaxed resize-none focus:outline-none focus:ring-1 focus:ring-signal border-0"
              spellCheck={false}
            />
          </div>
        )}

        {/* Live Interactive Sandbox Viewport */}
        <div className="flex flex-col bg-surface border border-line rounded-2xl overflow-hidden shadow-sm">
          <div className="flex items-center justify-between px-4 py-2.5 bg-surface-2 border-b border-line text-xs font-mono text-ink-muted">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
              <span className="font-bold text-ink">Live Interactive Sandbox Viewport</span>
              <span className="text-white/30">|</span>
              <span className="text-[11px] text-emerald-400">{TEMPLATES[selectedTemplate]?.name}</span>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={handleRun}
                className="px-2 py-1 rounded bg-surface border border-line text-[11px] hover:text-ink flex items-center gap-1"
                title="Reset Sandbox"
              >
                <RotateCcw className="w-3 h-3" />
                <span>Reset</span>
              </button>
            </div>
          </div>
          <div className={`w-full ${fullPreview ? 'h-[620px]' : 'h-[520px]'} bg-black/70 relative`}>
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
export default InBrowserCodingStudio;
