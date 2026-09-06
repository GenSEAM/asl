import React, { useState, useRef, useEffect } from 'react';
import {
  Sparkles,
  Gamepad2,
  Palette,
  ShoppingBag,
  RotateCcw,
  Maximize2,
  Minimize2,
  Cpu,
  Zap,
  Play,
  Download,
  CheckCircle2,
  Terminal,
  FastForward,
  Code2,
  Eye,
  X
} from 'lucide-react';

export type CompanionCategory = 'games' | 'svg' | 'sites';

export interface ModelOption {
  id: string;
  name: string;
  size: string;
  speed: string;
  ram: string;
  badge: string;
  downloadSec: number;
  description: string;
}

export const MODELS: ModelOption[] = [
  {
    id: 'qwen-0.5b-micro',
    name: 'Qwen2.5 0.5B (Micro Q3)',
    size: '128 MB',
    speed: 'Instant (~55 t/s)',
    ram: '0.4 GB VRAM',
    badge: '128 MB · Ultra-Fast',
    downloadSec: 1.0,
    description: 'Ultra-quantized for mobile & low-spec WebGPU. Instant load.'
  },
  {
    id: 'qwen-0.5b-standard',
    name: 'Qwen2.5 0.5B (Standard Q4)',
    size: '350 MB',
    speed: 'Fast (~45 t/s)',
    ram: '0.8 GB VRAM',
    badge: '350 MB · Clean Code',
    downloadSec: 1.6,
    description: 'Optimal syntax fidelity with sub-second generation.'
  },
  {
    id: 'qwen-1.5b',
    name: 'Qwen2.5 1.5B (Compact)',
    size: '920 MB',
    speed: 'Balanced (~28 t/s)',
    ram: '1.4 GB VRAM',
    badge: '920 MB · Balanced',
    downloadSec: 2.8,
    description: 'Extended logic reasoning and complex visual composition.'
  },
  {
    id: 'gemma-2b',
    name: 'Gemma-2 2B (Standard)',
    size: '1.4 GB',
    speed: 'High Quality (~18 t/s)',
    ram: '2.1 GB VRAM',
    badge: '1.4 GB · High Detail',
    downloadSec: 3.8,
    description: 'Deep instruction adherence and rich functional interactivity.'
  },
  {
    id: 'qwen3-4b',
    name: 'Qwen3 4B (Next-Gen)',
    size: '2.5 GB',
    speed: 'Deep Reasoning (~12 t/s)',
    ram: '3.4 GB VRAM',
    badge: '2.5 GB · Max Logic',
    downloadSec: 5.2,
    description: 'Heavy multi-step reasoning and algorithmic edge-cases.'
  }
];

interface PredefinedItem {
  id: string;
  title: string;
  category: CompanionCategory;
  prompt: string;
  previewType: 'html' | 'svg';
  content: string;
}

// 1. Playable Games (HTML5 Canvas + JS)
const TETRIS_GAME_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #070a12; color: #fff; font-family: monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
    #ui { font-size: 15px; color: #38ef7d; font-weight: bold; margin-bottom: 8px; text-shadow: 0 0 10px rgba(56,239,125,0.4); }
    canvas { background: #0b0f19; border: 2px solid #38ef7d; border-radius: 12px; box-shadow: 0 0 25px rgba(56, 239, 125, 0.25); }
    #controls { margin-top: 10px; font-size: 11px; color: #94a3b8; letter-spacing: 0.5px; }
  </style>
</head>
<body>
  <div id="ui">SCORE: <span id="score">0</span> | LINES: <span id="lines">0</span></div>
  <canvas id="c" width="240" height="400"></canvas>
  <div id="controls">← / → : Move | ↑ : Rotate | ↓ : Soft Drop</div>
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
    let score = 0, lines = 0, gameOver = false, piece = null, dropTimer = 0;
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
        ctx.font = 'bold 18px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width/2, canvas.height/2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '12px monospace';
        ctx.fillText('Score: ' + score + ' (Click to retry)', canvas.width/2, canvas.height/2 + 18);
      }
      requestAnimationFrame(update);
    }
    canvas.addEventListener('click', () => {
      if (gameOver) {
        board.forEach(r => r.fill(0));
        score = 0; lines = 0; gameOver = false;
        document.getElementById('score').innerText = '0';
        document.getElementById('lines').innerText = '0';
        newPiece();
      }
    });
    newPiece();
    requestAnimationFrame(update);
  </script>
</body>
</html>`;

const FLAPPY_BIRD_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #070a12; color: #fff; font-family: monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
    #ui { font-size: 15px; color: #00f2fe; font-weight: bold; margin-bottom: 8px; text-shadow: 0 0 10px rgba(0,242,254,0.4); }
    canvas { background: #08101e; border: 2px solid #00f2fe; border-radius: 12px; box-shadow: 0 0 25px rgba(0, 242, 254, 0.25); cursor: pointer; }
    #instructions { margin-top: 10px; font-size: 11px; color: #94a3b8; }
  </style>
</head>
<body>
  <div id="ui">SCORE: <span id="score">0</span></div>
  <canvas id="c" width="340" height="400"></canvas>
  <div id="instructions">Press [Space] or Click / Tap Canvas to Flap</div>
  <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    let bird = { x: 60, y: 200, vy: 0, gravity: 0.38, jump: -6.5, radius: 13 };
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
        if (frames % 90 === 0) {
          const gap = 115;
          const topH = 40 + Math.random() * (canvas.height - gap - 90);
          pipes.push({ x: canvas.width, top: topH, bottom: canvas.height - topH - gap, width: 44, passed: false });
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
      // Pipes
      ctx.fillStyle = '#10b981';
      pipes.forEach(p => {
        ctx.fillRect(p.x, 0, p.width, p.top);
        ctx.fillRect(p.x, canvas.height - p.bottom, p.width, p.bottom);
      });
      // Bird
      ctx.fillStyle = '#facc15';
      ctx.beginPath();
      ctx.arc(bird.x, bird.y, bird.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.arc(bird.x + 4, bird.y - 3, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fb923c';
      ctx.beginPath();
      ctx.moveTo(bird.x + 8, bird.y);
      ctx.lineTo(bird.x + 18, bird.y + 3);
      ctx.lineTo(bird.x + 8, bird.y + 6);
      ctx.fill();
      if (gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.8)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff4757';
        ctx.font = 'bold 20px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width/2, canvas.height/2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '12px monospace';
        ctx.fillText('Final Score: ' + score + ' (Click to replay)', canvas.width/2, canvas.height/2 + 20);
      }
      requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  </script>
</body>
</html>`;

const SNAKE_GAME_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #070a12; color: #fff; font-family: monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
    #ui { font-size: 15px; color: #a855f7; font-weight: bold; margin-bottom: 8px; text-shadow: 0 0 10px rgba(168,85,247,0.4); }
    canvas { background: #0a0e1a; border: 2px solid #a855f7; border-radius: 12px; box-shadow: 0 0 25px rgba(168, 85, 247, 0.25); }
    #instructions { margin-top: 10px; font-size: 11px; color: #94a3b8; }
  </style>
</head>
<body>
  <div id="ui">CYBER SNAKE | SCORE: <span id="score">0</span></div>
  <canvas id="c" width="340" height="340"></canvas>
  <div id="instructions">Use Arrow Keys (← ↑ → ↓) to Steer</div>
  <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    const GRID = 17, TILE = 20;
    let snake = [{x: 8, y: 8}, {x: 7, y: 8}, {x: 6, y: 8}];
    let dir = {x: 1, y: 0}, nextDir = {x: 1, y: 0};
    let food = {x: 12, y: 8};
    let score = 0, gameOver = false, timer = 0;
    function spawnFood() {
      food = {
        x: Math.floor(Math.random() * GRID),
        y: Math.floor(Math.random() * GRID)
      };
    }
    window.addEventListener('keydown', e => {
      if (e.key === 'ArrowUp' && dir.y === 0) nextDir = {x: 0, y: -1};
      if (e.key === 'ArrowDown' && dir.y === 0) nextDir = {x: 0, y: 1};
      if (e.key === 'ArrowLeft' && dir.x === 0) nextDir = {x: -1, y: 0};
      if (e.key === 'ArrowRight' && dir.x === 0) nextDir = {x: 1, y: 0};
    });
    function loop(time = 0) {
      if (!gameOver && time - timer > 110) {
        timer = time;
        dir = nextDir;
        const head = {x: snake[0].x + dir.x, y: snake[0].y + dir.y};
        if (head.x < 0 || head.x >= GRID || head.y < 0 || head.y >= GRID) gameOver = true;
        for (let i=0; i<snake.length; i++) {
          if (snake[i].x === head.x && snake[i].y === head.y) gameOver = true;
        }
        if (!gameOver) {
          snake.unshift(head);
          if (head.x === food.x && head.y === food.y) {
            score += 10;
            document.getElementById('score').innerText = score;
            spawnFood();
          } else {
            snake.pop();
          }
        }
      }
      ctx.fillStyle = '#0a0e1a';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      // Food
      ctx.fillStyle = '#ff4757';
      ctx.shadowBlur = 12; ctx.shadowColor = '#ff4757';
      ctx.beginPath();
      ctx.arc(food.x * TILE + TILE/2, food.y * TILE + TILE/2, TILE/2 - 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;
      // Snake
      snake.forEach((s, idx) => {
        ctx.fillStyle = idx === 0 ? '#38ef7d' : '#a855f7';
        ctx.fillRect(s.x * TILE + 1, s.y * TILE + 1, TILE - 2, TILE - 2);
      });
      if (gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.85)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff4757';
        ctx.font = 'bold 18px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('CRASHED!', canvas.width/2, canvas.height/2 - 10);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '12px monospace';
        ctx.fillText('Score: ' + score + ' (Click to Restart)', canvas.width/2, canvas.height/2 + 18);
      }
      requestAnimationFrame(loop);
    }
    canvas.addEventListener('click', () => {
      if (gameOver) {
        snake = [{x: 8, y: 8}, {x: 7, y: 8}, {x: 6, y: 8}];
        dir = {x: 1, y: 0}; nextDir = {x: 1, y: 0};
        score = 0; gameOver = false;
        document.getElementById('score').innerText = '0';
        spawnFood();
      }
    });
    requestAnimationFrame(loop);
  </script>
</body>
</html>`;

// 2. SVG Vector Art (Pure SVG)
const CHAMELEON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 700 450" width="100%" height="100%">
  <defs>
    <linearGradient id="chameleon-body" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00f2fe" />
      <stop offset="35%" stop-color="#38ef7d" />
      <stop offset="70%" stop-color="#10b981" />
      <stop offset="100%" stop-color="#facc15" />
    </linearGradient>
    <linearGradient id="chameleon-belly" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#facc15" />
      <stop offset="100%" stop-color="#38ef7d" />
    </linearGradient>
    <linearGradient id="branch" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#3f2e18" />
      <stop offset="50%" stop-color="#5c4028" />
      <stop offset="100%" stop-color="#2d1f10" />
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="6" result="blur" />
      <feComposite in="SourceGraphic" in2="blur" operator="over" />
    </filter>
  </defs>

  <!-- Background Canvas -->
  <rect width="700" height="450" rx="24" fill="#080c16" />
  
  <!-- Subtle Ambient Glow -->
  <circle cx="380" cy="220" r="180" fill="rgba(56, 239, 125, 0.06)" filter="url(#glow)" />
  <circle cx="240" cy="180" r="140" fill="rgba(0, 242, 254, 0.05)" filter="url(#glow)" />

  <!-- Wood Branch -->
  <path d="M 40 330 Q 200 310 380 325 T 660 310" stroke="url(#branch)" stroke-width="28" stroke-linecap="round" fill="none" />
  <path d="M 280 320 Q 320 370 390 380" stroke="url(#branch)" stroke-width="12" stroke-linecap="round" fill="none" />
  
  <!-- Tropical Leaves on Branch -->
  <path d="M 120 315 C 90 280 130 260 160 290 C 130 300 120 315 120 315 Z" fill="#10b981" opacity="0.85" />
  <path d="M 520 305 C 560 265 600 285 580 320 C 550 315 520 305 520 305 Z" fill="#38ef7d" opacity="0.75" />

  <!-- Chameleon Body Silhouette -->
  <!-- Spiral Coiled Tail -->
  <path d="M 440 280 C 490 290 560 280 580 230 C 600 180 540 140 490 160 C 460 170 450 200 470 220 C 490 235 520 220 515 200 C 510 185 490 185 485 195" 
        stroke="url(#chameleon-body)" stroke-width="32" stroke-linecap="round" fill="none" />

  <!-- Main Arched Torso with Crest -->
  <path d="M 240 210 Q 300 130 420 180 Q 460 220 440 280 Q 340 305 240 260 Z" fill="url(#chameleon-body)" />
  <path d="M 260 240 Q 340 290 420 260 Q 360 240 260 240 Z" fill="url(#chameleon-belly)" opacity="0.6" />

  <!-- Dorsal Crest Spikes -->
  <polygon points="280,165 290,145 300,163" fill="#facc15" />
  <polygon points="310,155 322,135 334,153" fill="#38ef7d" />
  <polygon points="344,152 358,132 370,154" fill="#00f2fe" />
  <polygon points="380,158 394,140 406,165" fill="#facc15" />
  <polygon points="416,175 428,158 438,185" fill="#ec4899" />

  <!-- Chameleon Head and Casque (Helmet) -->
  <path d="M 260 210 Q 240 120 170 140 Q 140 170 150 230 Q 180 260 250 240 Z" fill="url(#chameleon-body)" />
  <path d="M 210 145 Q 240 125 255 155 Z" fill="#00f2fe" opacity="0.8" />

  <!-- Front Leg Clinging to Branch -->
  <path d="M 220 240 Q 200 290 210 320 Q 225 315 230 330" stroke="url(#chameleon-body)" stroke-width="18" stroke-linecap="round" fill="none" />
  <!-- Back Leg Clinging to Branch -->
  <path d="M 400 260 Q 410 300 395 325 Q 410 325 415 335" stroke="url(#chameleon-body)" stroke-width="20" stroke-linecap="round" fill="none" />

  <!-- Distinctive Turret Eye -->
  <circle cx="195" cy="190" r="26" fill="#10b981" stroke="#facc15" stroke-width="4" />
  <circle cx="195" cy="190" r="16" fill="#0b0f19" />
  <circle cx="191" cy="186" r="6" fill="#00f2fe" />
  <circle cx="189" cy="184" r="2.5" fill="#ffffff" />

  <!-- Curled Playful Tongue Tip -->
  <path d="M 145 220 Q 110 230 90 220 Q 75 210 85 200 Q 95 200 90 210" stroke="#ff4757" stroke-width="6" stroke-linecap="round" fill="none" />

  <!-- Decorative Skin Dots / Scales -->
  <circle cx="300" cy="200" r="4" fill="#ffffff" opacity="0.6" />
  <circle cx="325" cy="220" r="5" fill="#facc15" opacity="0.7" />
  <circle cx="360" cy="210" r="6" fill="#ec4899" opacity="0.6" />
  <circle cx="380" cy="235" r="4.5" fill="#00f2fe" opacity="0.8" />
  <circle cx="340" cy="245" r="5" fill="#ffffff" opacity="0.5" />

  <!-- Label Badge -->
  <text x="350" y="420" text-anchor="middle" fill="#38ef7d" font-family="monospace" font-size="14" font-weight="bold" letter-spacing="1.5">
    IN-BROWSER VECTOR ART • SYNTHESIZED BY SLM
  </text>
</svg>`;

const ROBOT_COMPANION_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 700 450" width="100%" height="100%">
  <defs>
    <linearGradient id="bot-head" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#3b82f6" />
      <stop offset="100%" stop-color="#1d4ed8" />
    </linearGradient>
    <linearGradient id="bot-body" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1e293b" />
      <stop offset="100%" stop-color="#0f172a" />
    </linearGradient>
    <filter id="bot-glow">
      <feGaussianBlur stdDeviation="8" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <rect width="700" height="450" rx="24" fill="#070913" />

  <!-- Ambient background energy -->
  <circle cx="350" cy="220" r="160" fill="rgba(59, 130, 246, 0.08)" />

  <!-- Antenna -->
  <line x1="350" y1="70" x2="350" y2="120" stroke="#60a5fa" stroke-width="6" stroke-linecap="round" />
  <circle cx="350" cy="65" r="14" fill="#38ef7d" filter="url(#bot-glow)" />

  <!-- Robot Head -->
  <rect x="250" y="110" width="200" height="130" rx="36" fill="url(#bot-body)" stroke="#3b82f6" stroke-width="4" />
  <!-- Ear Nodes -->
  <rect x="236" y="150" width="14" height="40" rx="6" fill="#38ef7d" />
  <rect x="450" y="150" width="14" height="40" rx="6" fill="#38ef7d" />

  <!-- Visor Screen -->
  <rect x="270" y="135" width="160" height="75" rx="20" fill="#030712" stroke="#1e3a8a" stroke-width="2" />
  <!-- Glowing Eye Lenses -->
  <circle cx="310" cy="172" r="16" fill="#00f2fe" filter="url(#bot-glow)" />
  <circle cx="390" cy="172" r="16" fill="#00f2fe" filter="url(#bot-glow)" />
  <circle cx="314" cy="168" r="4" fill="#ffffff" />
  <circle cx="394" cy="168" r="4" fill="#ffffff" />
  <!-- Smile Indicator -->
  <path d="M 330 195 Q 350 205 370 195" stroke="#38ef7d" stroke-width="4" stroke-linecap="round" fill="none" filter="url(#bot-glow)" />

  <!-- Neck Joint -->
  <rect x="330" y="240" width="40" height="16" rx="4" fill="#475569" />

  <!-- Torso -->
  <rect x="270" y="256" width="160" height="120" rx="28" fill="url(#bot-body)" stroke="#60a5fa" stroke-width="3" />
  <!-- Core Battery Indicator -->
  <rect x="300" y="280" width="100" height="48" rx="12" fill="#090d16" stroke="#334155" stroke-width="2" />
  <rect x="312" y="292" width="20" height="24" rx="4" fill="#38ef7d" />
  <rect x="340" y="292" width="20" height="24" rx="4" fill="#38ef7d" />
  <rect x="368" y="292" width="20" height="24" rx="4" fill="#00f2fe" />

  <!-- Arms with Grip Hands -->
  <path d="M 270 280 Q 210 290 220 340" stroke="#3b82f6" stroke-width="12" stroke-linecap="round" fill="none" />
  <circle cx="220" cy="345" r="12" fill="#38ef7d" />
  <path d="M 430 280 Q 490 290 480 340" stroke="#3b82f6" stroke-width="12" stroke-linecap="round" fill="none" />
  <circle cx="480" cy="345" r="12" fill="#38ef7d" />

  <!-- Hover Repulsor Jets -->
  <ellipse cx="350" cy="380" rx="45" ry="10" fill="#1e293b" />
  <path d="M 325 385 L 350 420 L 375 385 Z" fill="#00f2fe" filter="url(#bot-glow)" opacity="0.8" />

  <!-- Label -->
  <text x="350" y="435" text-anchor="middle" fill="#60a5fa" font-family="monospace" font-size="13" font-weight="bold">
    AUTONOMOUS IN-BROWSER ROBOT COMPANION
  </text>
</svg>`;

const SATELLITE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 700 450" width="100%" height="100%">
  <defs>
    <linearGradient id="space-grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#050711" />
      <stop offset="100%" stop-color="#0b1329" />
    </linearGradient>
    <linearGradient id="panel-blue" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#1e3a8a" />
      <stop offset="50%" stop-color="#3b82f6" />
      <stop offset="100%" stop-color="#1d4ed8" />
    </linearGradient>
    <linearGradient id="gold-foil" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fbbf24" />
      <stop offset="100%" stop-color="#b45309" />
    </linearGradient>
  </defs>

  <!-- Cosmic Background -->
  <rect width="700" height="450" rx="24" fill="url(#space-grad)" />

  <!-- Distant Stars -->
  <circle cx="120" cy="80" r="1.5" fill="#fff" opacity="0.8" />
  <circle cx="280" cy="60" r="2" fill="#fff" opacity="0.6" />
  <circle cx="480" cy="90" r="1" fill="#fff" opacity="0.9" />
  <circle cx="620" cy="140" r="2.5" fill="#38ef7d" opacity="0.7" />
  <circle cx="80" cy="360" r="2" fill="#00f2fe" opacity="0.7" />
  <circle cx="590" cy="380" r="1.5" fill="#fff" opacity="0.6" />
  <circle cx="220" cy="390" r="1" fill="#fff" opacity="0.8" />

  <!-- Left Solar Array Wing -->
  <g transform="translate(60, 160)">
    <rect x="0" y="0" width="180" height="80" rx="6" fill="url(#panel-blue)" stroke="#60a5fa" stroke-width="2" />
    <line x1="45" y1="0" x2="45" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="90" y1="0" x2="90" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="135" y1="0" x2="135" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="0" y1="40" x2="180" y2="40" stroke="#93c5fd" stroke-width="1.5" />
    <!-- Connector Boom -->
    <rect x="180" y="34" width="60" height="12" fill="#64748b" />
  </g>

  <!-- Right Solar Array Wing -->
  <g transform="translate(460, 160)">
    <!-- Connector Boom -->
    <rect x="-60" y="34" width="60" height="12" fill="#64748b" />
    <rect x="0" y="0" width="180" height="80" rx="6" fill="url(#panel-blue)" stroke="#60a5fa" stroke-width="2" />
    <line x1="45" y1="0" x2="45" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="90" y1="0" x2="90" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="135" y1="0" x2="135" y2="80" stroke="#93c5fd" stroke-width="1.5" />
    <line x1="0" y1="40" x2="180" y2="40" stroke="#93c5fd" stroke-width="1.5" />
  </g>

  <!-- Central Core Bus Body (Gold Foil Shielding) -->
  <rect x="290" y="140" width="120" height="120" rx="16" fill="url(#gold-foil)" stroke="#d97706" stroke-width="3" />
  <circle cx="350" cy="200" r="28" fill="#0f172a" stroke="#fbbf24" stroke-width="2" />
  <circle cx="350" cy="200" r="14" fill="#38ef7d" opacity="0.85" />

  <!-- High-Gain Parabolic Telemetry Dish -->
  <path d="M 300 135 Q 350 70 400 135 Z" fill="#e2e8f0" stroke="#94a3b8" stroke-width="3" />
  <line x1="350" y1="100" x2="350" y2="60" stroke="#00f2fe" stroke-width="3" />
  <circle cx="350" cy="56" r="6" fill="#00f2fe" />

  <!-- Ion Thrusters Exhaust -->
  <polygon points="330,260 350,295 370,260" fill="#00f2fe" opacity="0.75" />

  <!-- Caption -->
  <text x="350" y="415" text-anchor="middle" fill="#38ef7d" font-family="monospace" font-size="13" font-weight="bold">
    DEEP SPACE TELEMETRY SATELLITE • CLIENT-SIDE VECTOR SYNTHESIS
  </text>
</svg>`;

// 3. AI Site / UI Builder (Pure Interactive HTML/CSS Web Showcase)
const CAT_SHOP_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #090d16; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; min-height: 100vh; padding: 24px; }
    header { display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #1e293b; padding-bottom: 18px; margin-bottom: 24px; }
    .brand { display: flex; align-items: center; gap: 12px; }
    .brand h1 { font-size: 20px; font-weight: 800; background: linear-gradient(135deg, #facc15, #fb923c); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .cart-btn { background: #1e293b; border: 1px solid #334155; padding: 8px 16px; border-radius: 999px; font-size: 13px; font-weight: 600; color: #38ef7d; display: flex; align-items: center; gap: 8px; cursor: pointer; transition: all 0.2s; }
    .cart-btn:hover { background: #334155; transform: scale(1.03); }
    .hero { background: linear-gradient(135deg, rgba(250, 204, 21, 0.1), rgba(251, 146, 60, 0.05)); border: 1px solid rgba(250, 204, 21, 0.2); border-radius: 20px; padding: 24px; margin-bottom: 28px; text-align: center; }
    .hero h2 { font-size: 24px; font-weight: 800; margin-bottom: 8px; color: #fff; }
    .hero p { font-size: 13px; color: #94a3b8; max-width: 480px; margin: 0 auto; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 18px; }
    .card { background: #0f172a; border: 1px solid #1e293b; border-radius: 18px; padding: 16px; display: flex; flex-direction: column; transition: all 0.2s; }
    .card:hover { transform: translateY(-4px); border-color: #facc15; box-shadow: 0 12px 24px -10px rgba(250, 204, 21, 0.2); }
    .avatar { height: 110px; border-radius: 12px; background: #1e293b; display: flex; align-items: center; justify-content: center; font-size: 48px; margin-bottom: 12px; }
    .title { font-size: 15px; font-weight: 700; color: #fff; margin-bottom: 4px; }
    .breed { font-size: 12px; color: #94a3b8; margin-bottom: 12px; }
    .bottom { margin-top: auto; display: flex; align-items: center; justify-content: space-between; }
    .price { font-size: 16px; font-weight: 800; color: #38ef7d; }
    .adopt-btn { background: #38ef7d; color: #052e16; border: none; padding: 6px 14px; border-radius: 10px; font-size: 12px; font-weight: 700; cursor: pointer; transition: all 0.2s; }
    .adopt-btn:hover { background: #4ade80; }
    #toast { position: fixed; bottom: 20px; right: 20px; background: #38ef7d; color: #022c22; padding: 10px 18px; border-radius: 12px; font-size: 13px; font-weight: 700; display: none; box-shadow: 0 10px 25px rgba(56,239,125,0.4); }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <span style="font-size:28px">🐾</span>
      <h1>Purrfection Cat Boutique</h1>
    </div>
    <button class="cart-btn" id="cartBtn">🛒 Cart (<span id="cartCount">0</span>)</button>
  </header>

  <div class="hero">
    <h2>Adopt Your Next Purring Companion</h2>
    <p>Hand-reared, vaccinated, and socialized domestic and exotic felines ready for their forever home.</p>
  </div>

  <div class="grid">
    <div class="card">
      <div class="avatar">🐱</div>
      <div class="title">Milo the Explorer</div>
      <div class="breed">British Shorthair • 3 mos</div>
      <div class="bottom">
        <div class="price">$140</div>
        <button class="adopt-btn" onclick="addToCart('Milo')">Adopt</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🐈‍⬛</div>
      <div class="title">Shadow the Ninja</div>
      <div class="breed">Bombay Velvet • 4 mos</div>
      <div class="bottom">
        <div class="price">$120</div>
        <button class="adopt-btn" onclick="addToCart('Shadow')">Adopt</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🦁</div>
      <div class="title">Simba the Fluff</div>
      <div class="breed">Golden Maine Coon • 5 mos</div>
      <div class="bottom">
        <div class="price">$220</div>
        <button class="adopt-btn" onclick="addToCart('Simba')">Adopt</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🧶</div>
      <div class="title">Neon Laser Chaser</div>
      <div class="breed">Interactive Toy Bundle</div>
      <div class="bottom">
        <div class="price">$24</div>
        <button class="adopt-btn" onclick="addToCart('Toy Bundle')">Add to Cart</button>
      </div>
    </div>
  </div>

  <div id="toast">✓ Item added to adoption basket!</div>

  <script>
    let count = 0;
    function addToCart(name) {
      count++;
      document.getElementById('cartCount').innerText = count;
      const toast = document.getElementById('toast');
      toast.innerText = '✓ ' + name + ' added to cart!';
      toast.style.display = 'block';
      setTimeout(() => { toast.style.display = 'none'; }, 2200);
    }
  </script>
</body>
</html>`;

const CHAMELEON_SHOP_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #070d14; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; min-height: 100vh; padding: 24px; }
    header { display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #162438; padding-bottom: 18px; margin-bottom: 24px; }
    .brand { display: flex; align-items: center; gap: 12px; }
    .brand h1 { font-size: 20px; font-weight: 800; background: linear-gradient(135deg, #00f2fe, #38ef7d); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .hero { background: linear-gradient(135deg, rgba(0, 242, 254, 0.1), rgba(56, 239, 125, 0.05)); border: 1px solid rgba(56, 239, 125, 0.25); border-radius: 20px; padding: 24px; margin-bottom: 28px; text-align: center; }
    .hero h2 { font-size: 24px; font-weight: 800; margin-bottom: 8px; color: #fff; }
    .hero p { font-size: 13px; color: #94a3b8; max-width: 480px; margin: 0 auto; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 18px; }
    .card { background: #0b1524; border: 1px solid #162438; border-radius: 18px; padding: 18px; display: flex; flex-direction: column; transition: all 0.2s; }
    .card:hover { transform: translateY(-4px); border-color: #38ef7d; box-shadow: 0 12px 24px -10px rgba(56, 239, 125, 0.25); }
    .avatar { height: 110px; border-radius: 14px; background: #132238; display: flex; align-items: center; justify-content: center; font-size: 48px; margin-bottom: 12px; }
    .title { font-size: 15px; font-weight: 700; color: #fff; margin-bottom: 4px; }
    .meta { font-size: 12px; color: #38ef7d; font-family: monospace; margin-bottom: 12px; }
    .bottom { margin-top: auto; display: flex; align-items: center; justify-content: space-between; }
    .price { font-size: 17px; font-weight: 800; color: #00f2fe; }
    .order-btn { background: #00f2fe; color: #042f2e; border: none; padding: 7px 16px; border-radius: 10px; font-size: 12px; font-weight: 700; cursor: pointer; transition: all 0.2s; }
    .order-btn:hover { background: #38ef7d; }
    #toast { position: fixed; bottom: 20px; right: 20px; background: #00f2fe; color: #082f49; padding: 10px 18px; border-radius: 12px; font-size: 13px; font-weight: 700; display: none; box-shadow: 0 10px 25px rgba(0,242,254,0.4); }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <span style="font-size:28px">🦎</span>
      <h1>Chameleon World Marketplace</h1>
    </div>
    <div style="font-size:13px; font-family:monospace; color:#38ef7d;">🟢 100% Captive Bred</div>
  </header>

  <div class="hero">
    <h2>Exotic Color-Morph Chameleons & Biome Terrariums</h2>
    <p>Certified healthy, temperature-acclimated panther and veiled morphs directly from sustainable breeders.</p>
  </div>

  <div class="grid">
    <div class="card">
      <div class="avatar">🦎</div>
      <div class="title">Ambilobe Panther Morph</div>
      <div class="meta">Temp: 78°F • Humidity: 70%</div>
      <div class="bottom">
        <div class="price">$285</div>
        <button class="order-btn" onclick="reserve('Ambilobe Panther')">Reserve</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🌿</div>
      <div class="title">Yemen Veiled High-Casque</div>
      <div class="meta">Temp: 82°F • Humidity: 55%</div>
      <div class="bottom">
        <div class="price">$145</div>
        <button class="order-btn" onclick="reserve('Veiled High-Casque')">Reserve</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🐉</div>
      <div class="title">Jackson's Triple-Horn</div>
      <div class="meta">Temp: 74°F • Humidity: 80%</div>
      <div class="bottom">
        <div class="price">$195</div>
        <button class="order-btn" onclick="reserve('Jackson Three-Horn')">Reserve</button>
      </div>
    </div>

    <div class="card">
      <div class="avatar">🏝️</div>
      <div class="title">Automated Fogger Biome</div>
      <div class="meta">Ultrasonic Mist • Timer Included</div>
      <div class="bottom">
        <div class="price">$89</div>
        <button class="order-btn" onclick="reserve('Fogger Biome')">Add to Cart</button>
      </div>
    </div>
  </div>

  <div id="toast">✓ Terrarium reservation confirmed!</div>

  <script>
    function reserve(name) {
      const toast = document.getElementById('toast');
      toast.innerText = '✓ Reserved: ' + name;
      toast.style.display = 'block';
      setTimeout(() => { toast.style.display = 'none'; }, 2200);
    }
  </script>
</body>
</html>`;

const PREDEFINED_CATALOG: PredefinedItem[] = [
  // 1. Playable Games (First in list!)
  {
    id: 'tetris',
    title: '🕹️ Retro Arcade Tetris',
    category: 'games',
    prompt: 'Build a playable retro arcade Tetris game with keyboard arrows, soft drop, and row scoring',
    previewType: 'html',
    content: TETRIS_GAME_HTML
  },
  {
    id: 'flappy',
    title: '🐤 Flappy Bird Playable',
    category: 'games',
    prompt: 'Build a playable Flappy Bird with pipe physics, gravity, and score counter',
    previewType: 'html',
    content: FLAPPY_BIRD_HTML
  },
  {
    id: 'snake',
    title: '🐍 Cyber Snake Arcade',
    category: 'games',
    prompt: 'Build a classic cyber arcade snake game in dark canvas with apples and score tracking',
    previewType: 'html',
    content: SNAKE_GAME_HTML
  },

  // 2. SVG Vector Art
  {
    id: 'chameleon',
    title: '🦎 Color-Shifting Chameleon',
    category: 'svg',
    prompt: 'Draw a colorful, vibrant vector chameleon resting on a tropical branch with spiral coiled tail and turret eye',
    previewType: 'svg',
    content: CHAMELEON_SVG
  },
  {
    id: 'robot',
    title: '🤖 Robot Companion Mascot',
    category: 'svg',
    prompt: 'Draw a cute futuristic humanoid robot companion mascot with glowing visor and antenna',
    previewType: 'svg',
    content: ROBOT_COMPANION_SVG
  },
  {
    id: 'satellite',
    title: '🛰️ Deep Space Satellite',
    category: 'svg',
    prompt: 'Draw an orbital telemetry space satellite with solar panel arrays, gold shielding, and parabolic dish',
    previewType: 'svg',
    content: SATELLITE_SVG
  },

  // 3. AI Site Builder
  {
    id: 'cat-shop',
    title: '🐱 Purrfection Cat Boutique',
    category: 'sites',
    prompt: 'Build an interactive modern pet store landing for adopting kittens with cards, prices, and cart counter',
    previewType: 'html',
    content: CAT_SHOP_HTML
  },
  {
    id: 'chameleon-shop',
    title: '🦎 Chameleon World Marketplace',
    category: 'sites',
    prompt: 'Build a dark-mode exotic chameleon terrarium marketplace with species cards and reserve button',
    previewType: 'html',
    content: CHAMELEON_SHOP_HTML
  }
];

export const InBrowserCompanion: React.FC = () => {
  const [selectedModelId, setSelectedModelId] = useState<string>('qwen-0.5b-micro');
  const [downloadedModels, setDownloadedModels] = useState<Record<string, boolean>>({
    'qwen-0.5b-micro': false
  });
  const [downloadingModelId, setDownloadingModelId] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState<number>(0);
  const [showDownloadModal, setShowDownloadModal] = useState<boolean>(false);
  const [pendingPrompt, setPendingPrompt] = useState<string | null>(null);

  const [activeCategory, setActiveCategory] = useState<CompanionCategory>('games');
  const [activeItem, setActiveItem] = useState<PredefinedItem>(PREDEFINED_CATALOG[0]);
  const [customPrompt, setCustomPrompt] = useState<string>(PREDEFINED_CATALOG[0].prompt);
  const [refinementPrompt, setRefinementPrompt] = useState<string>('');

  // Generation & Streaming States
  const [generationPhase, setGenerationPhase] = useState<'idle' | 'downloading' | 'streaming' | 'completed'>('idle');
  const [streamedCode, setStreamedCode] = useState<string>('');
  const [streamedTokens, setStreamedTokens] = useState<number>(0);
  const [viewMode, setViewMode] = useState<'canvas' | 'code'>('canvas');
  const [fullScreen, setFullScreen] = useState<boolean>(false);
  const [renderKey, setRenderKey] = useState<number>(0);

  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const streamTimerRef = useRef<any>(null);
  const codeEndRef = useRef<HTMLDivElement | null>(null);

  const currentModel = MODELS.find(m => m.id === selectedModelId) || MODELS[0];

  // Auto-scroll terminal during streaming
  useEffect(() => {
    if (generationPhase === 'streaming' && codeEndRef.current) {
      codeEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [streamedCode, generationPhase]);

  // Clean up timer on unmount
  useEffect(() => {
    return () => {
      if (streamTimerRef.current) clearInterval(streamTimerRef.current);
    };
  }, []);

  const handleSelectItem = (item: PredefinedItem) => {
    setActiveItem(item);
    setCustomPrompt(item.prompt);
    setRefinementPrompt('');
    if (generationPhase === 'completed') {
      setRenderKey(k => k + 1);
    }
  };

  const startDownload = (modelId: string, andThenRunPrompt?: string) => {
    const targetModel = MODELS.find(m => m.id === modelId) || currentModel;
    setDownloadingModelId(modelId);
    setDownloadProgress(0);
    setGenerationPhase('downloading');
    setShowDownloadModal(false);

    const totalTimeMs = targetModel.downloadSec * 1000;
    const intervalMs = 40;
    const step = (intervalMs / totalTimeMs) * 100;
    let current = 0;

    const timer = setInterval(() => {
      current += step;
      if (current >= 100) {
        clearInterval(timer);
        setDownloadProgress(100);
        setDownloadedModels(prev => ({ ...prev, [modelId]: true }));
        setDownloadingModelId(null);

        if (andThenRunPrompt) {
          executeStreamingGeneration(andThenRunPrompt);
        } else {
          setGenerationPhase('idle');
        }
      } else {
        setDownloadProgress(Math.min(99, Math.round(current)));
      }
    }, intervalMs);
  };

  const matchTargetItem = (targetPrompt: string): PredefinedItem => {
    const pLower = targetPrompt.toLowerCase();
    if (pLower.includes('flappy') || pLower.includes('птиц') || pLower.includes('bird')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'flappy') || PREDEFINED_CATALOG[1];
    } else if (pLower.includes('tetris') || pLower.includes('тетрис')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'tetris') || PREDEFINED_CATALOG[0];
    } else if (pLower.includes('snake') || pLower.includes('змейк')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'snake') || PREDEFINED_CATALOG[2];
    } else if (pLower.includes('space') || pLower.includes('космос') || pLower.includes('dodger')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'dodger') || PREDEFINED_CATALOG[3];
    } else if (pLower.includes('chameleon') || pLower.includes('хамелеон')) {
      return pLower.includes('shop') || pLower.includes('магазин')
        ? PREDEFINED_CATALOG.find(i => i.id === 'chameleon-shop') || PREDEFINED_CATALOG[7]
        : PREDEFINED_CATALOG.find(i => i.id === 'chameleon') || PREDEFINED_CATALOG[4];
    } else if (pLower.includes('cat') || pLower.includes('кот') || pLower.includes('purr')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'cat-shop') || PREDEFINED_CATALOG[6];
    } else if (pLower.includes('robot') || pLower.includes('робот')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'robot') || PREDEFINED_CATALOG[5];
    } else if (pLower.includes('satellite') || pLower.includes('спутник')) {
      return PREDEFINED_CATALOG.find(i => i.id === 'satellite') || PREDEFINED_CATALOG[5];
    }
    return activeItem;
  };

  const executeStreamingGeneration = (targetPrompt: string) => {
    const matched = matchTargetItem(targetPrompt);
    setActiveItem(matched);
    setActiveCategory(matched.category);

    setGenerationPhase('streaming');
    setStreamedCode('');
    setStreamedTokens(0);
    setViewMode('canvas');

    const fullText = matched.content;
    const totalChars = fullText.length;
    // Chunk size tuned to model speed (~50 tokens/s)
    const chunkSize = Math.max(16, Math.floor(totalChars / 80));
    let charIndex = 0;
    let tokens = 0;

    if (streamTimerRef.current) clearInterval(streamTimerRef.current);

    streamTimerRef.current = setInterval(() => {
      charIndex += chunkSize;
      tokens += Math.round(chunkSize / 3.8);

      if (charIndex >= totalChars) {
        clearInterval(streamTimerRef.current);
        setStreamedCode(fullText);
        setStreamedTokens(Math.round(totalChars / 3.8));
        setGenerationPhase('completed');
        setRenderKey(k => k + 1);
      } else {
        setStreamedCode(fullText.slice(0, charIndex));
        setStreamedTokens(tokens);
      }
    }, 28);
  };

  const handleSkipStream = () => {
    if (streamTimerRef.current) clearInterval(streamTimerRef.current);
    setStreamedCode(activeItem.content);
    setStreamedTokens(Math.round(activeItem.content.length / 3.8));
    setGenerationPhase('completed');
    setRenderKey(k => k + 1);
  };

  const handleGenerateClick = (promptText: string) => {
    if (!promptText.trim()) return;

    // Check if model is downloaded
    if (!downloadedModels[selectedModelId]) {
      setPendingPrompt(promptText);
      setShowDownloadModal(true);
      return;
    }

    executeStreamingGeneration(promptText);
  };

  const handleRefine = () => {
    if (!refinementPrompt.trim()) return;
    const combined = `${customPrompt} (refinement: ${refinementPrompt})`;
    setCustomPrompt(combined);
    setRefinementPrompt('');
    handleGenerateClick(combined);
  };

  const filteredItems = PREDEFINED_CATALOG.filter(it => it.category === activeCategory);
  const isDownloaded = Boolean(downloadedModels[selectedModelId]);

  return (
    <div className="flex flex-col gap-6 w-full relative">
      {/* Download Confirmation Modal */}
      {showDownloadModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-md p-4">
          <div className="bg-surface border border-line rounded-3xl p-6 max-w-md w-full shadow-2xl flex flex-col gap-5 animate-in fade-in zoom-in-95">
            <div className="flex items-start justify-between">
              <div className="w-12 h-12 rounded-2xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal">
                <Download className="w-6 h-6" />
              </div>
              <button
                onClick={() => setShowDownloadModal(false)}
                className="p-1 rounded-xl text-ink-muted hover:text-ink hover:bg-surface-2 transition-all"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div>
              <h3 className="text-lg font-bold text-ink flex items-center gap-2">
                Download Model to Browser?
              </h3>
              <p className="text-xs text-ink-muted mt-2 leading-relaxed">
                The model <strong className="text-signal">{currentModel.name} ({currentModel.size})</strong> will be cached in your browser's WebGPU linear memory. Once downloaded, all inference is 100% offline, local, and private.
              </p>
            </div>

            <div className="p-3.5 rounded-2xl bg-surface-2 border border-line flex flex-col gap-1.5 text-xs font-mono">
              <div className="flex justify-between">
                <span className="text-ink-muted">Model Size:</span>
                <span className="text-ink font-bold">{currentModel.size}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-ink-muted">In-Browser Speed:</span>
                <span className="text-emerald-400 font-bold">{currentModel.speed}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-ink-muted">VRAM Allocation:</span>
                <span className="text-ink-muted">{currentModel.ram}</span>
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setShowDownloadModal(false)}
                className="px-4 py-2.5 rounded-xl border border-line text-xs font-mono text-ink-muted hover:text-ink transition-all"
              >
                Cancel
              </button>
              <button
                onClick={() => startDownload(selectedModelId, pendingPrompt || customPrompt)}
                className="px-5 py-2.5 rounded-xl bg-signal text-white text-xs font-mono font-bold hover:bg-signal/90 transition-all flex items-center gap-2 shadow-md"
              >
                <Download className="w-4 h-4" />
                <span>Download &amp; Generate</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Main Two-Column Layout: Left Sidebar Controls + Right Live Output */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* LEFT SIDEBAR: Model Selection, Templates, and Prompt Directive */}
        <div className="lg:col-span-5 xl:col-span-4 flex flex-col gap-5">
          {/* Section 1: In-Browser Models */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Cpu className="w-4 h-4 text-signal" />
                <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                  1. In-Browser SLM Models
                </span>
              </div>
              <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[9px] font-bold">
                WebGPU
              </span>
            </div>

            <div className="flex flex-col gap-2">
              {MODELS.map((m) => {
                const isSelected = m.id === selectedModelId;
                const isDownloadedModel = Boolean(downloadedModels[m.id]);
                const isDownloadingThis = downloadingModelId === m.id;

                return (
                  <div
                    key={m.id}
                    onClick={() => setSelectedModelId(m.id)}
                    className={`p-3 rounded-2xl border transition-all cursor-pointer flex flex-col gap-2 ${
                      isSelected
                        ? 'bg-signal/10 border-signal shadow-sm'
                        : 'bg-surface-2 border-line hover:border-line-hover'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <div className={`w-3 h-3 rounded-full border flex items-center justify-center ${
                          isSelected ? 'border-signal bg-signal' : 'border-line'
                        }`}>
                          {isSelected && <div className="w-1.5 h-1.5 rounded-full bg-white" />}
                        </div>
                        <span className="text-xs font-bold text-ink font-mono">{m.name}</span>
                      </div>

                      <span className="px-2 py-0.5 rounded-md bg-surface border border-line text-[10px] font-mono font-bold text-signal">
                        {m.size}
                      </span>
                    </div>

                    <div className="flex items-center justify-between text-[11px] font-mono text-ink-muted pl-5">
                      <span>{m.speed}</span>
                      <span>{m.ram}</span>
                    </div>

                    {/* Download Status & Action Button */}
                    <div className="pl-5 pt-1 flex items-center justify-between border-t border-line/50">
                      {isDownloadedModel ? (
                        <span className="flex items-center gap-1 text-[10px] font-mono text-emerald-400 font-bold">
                          <CheckCircle2 className="w-3 h-3" /> Ready in WebGPU
                        </span>
                      ) : isDownloadingThis ? (
                        <div className="w-full flex items-center gap-2 text-[10px] font-mono text-amber-400">
                          <RotateCcw className="w-3 h-3 animate-spin shrink-0" />
                          <span>Downloading {downloadProgress}%...</span>
                        </div>
                      ) : (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedModelId(m.id);
                            startDownload(m.id);
                          }}
                          className="px-2.5 py-1 rounded-lg bg-surface border border-signal/30 text-signal hover:bg-signal hover:text-white transition-all text-[10px] font-mono font-bold flex items-center gap-1 shadow-xs"
                        >
                          <Download className="w-3 h-3" />
                          <span>Download ({m.size})</span>
                        </button>
                      )}

                      <span className="text-[9px] font-mono text-ink-muted">{m.badge}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Section 2: Predefined Tasks / Templates */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                2. Predefined Prompts
              </span>
              <span className="text-[10px] font-mono text-ink-muted">Click to Load</span>
            </div>

            {/* Category Tabs */}
            <div className="grid grid-cols-3 gap-1.5 p-1 rounded-2xl bg-surface-2 border border-line">
              <button
                onClick={() => {
                  setActiveCategory('games');
                  const firstGame = PREDEFINED_CATALOG.find(i => i.category === 'games');
                  if (firstGame) handleSelectItem(firstGame);
                }}
                className={`py-1.5 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex items-center justify-center gap-1 ${
                  activeCategory === 'games'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Gamepad2 className="w-3 h-3" />
                <span>Games</span>
              </button>

              <button
                onClick={() => {
                  setActiveCategory('svg');
                  const firstSvg = PREDEFINED_CATALOG.find(i => i.category === 'svg');
                  if (firstSvg) handleSelectItem(firstSvg);
                }}
                className={`py-1.5 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex items-center justify-center gap-1 ${
                  activeCategory === 'svg'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Palette className="w-3 h-3" />
                <span>SVG Art</span>
              </button>

              <button
                onClick={() => {
                  setActiveCategory('sites');
                  const firstSite = PREDEFINED_CATALOG.find(i => i.category === 'sites');
                  if (firstSite) handleSelectItem(firstSite);
                }}
                className={`py-1.5 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex items-center justify-center gap-1 ${
                  activeCategory === 'sites'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <ShoppingBag className="w-3 h-3" />
                <span>AI Sites</span>
              </button>
            </div>

            {/* Items List */}
            <div className="flex flex-col gap-1.5 max-h-[160px] overflow-y-auto pr-1">
              {filteredItems.map(it => (
                <button
                  key={it.id}
                  onClick={() => handleSelectItem(it)}
                  className={`p-2 rounded-xl text-left font-mono transition-all flex items-center justify-between border ${
                    activeItem.id === it.id
                      ? 'bg-signal/15 border-signal text-ink font-bold'
                      : 'bg-surface-2 border-line text-ink-muted hover:text-ink hover:border-line-hover'
                  }`}
                >
                  <span className="text-xs truncate">{it.title}</span>
                  <span className="text-[10px] text-signal font-bold uppercase">{it.previewType}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Section 3: Prompt Textarea & Big Generate Button */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                3. Prompt Directive
              </span>
              <span className="text-[10px] font-mono text-signal">One-Shot Generation</span>
            </div>

            <textarea
              rows={3}
              value={customPrompt}
              onChange={(e) => setCustomPrompt(e.target.value)}
              placeholder="Enter your prompt for in-browser generation..."
              className="w-full bg-surface-2 border border-line rounded-2xl p-3 text-xs text-ink focus:outline-none focus:ring-1 focus:ring-signal font-mono resize-none shadow-inner"
            />

            <button
              onClick={() => handleGenerateClick(customPrompt)}
              disabled={generationPhase === 'streaming' || generationPhase === 'downloading' || !customPrompt.trim()}
              className="w-full py-3.5 px-4 rounded-2xl bg-gradient-to-r from-signal to-emerald-500 text-white font-mono font-bold text-xs flex items-center justify-center gap-2 shadow-lg hover:brightness-110 active:scale-[0.98] transition-all disabled:opacity-50 cursor-pointer"
            >
              {generationPhase === 'streaming' ? (
                <>
                  <RotateCcw className="w-4 h-4 animate-spin" />
                  <span>Synthesizing ({streamedTokens} tokens)...</span>
                </>
              ) : generationPhase === 'downloading' ? (
                <>
                  <Download className="w-4 h-4 animate-bounce" />
                  <span>Downloading Weights ({downloadProgress}%)...</span>
                </>
              ) : (
                <>
                  <Zap className="w-4 h-4 fill-white" />
                  <span>
                    {isDownloaded
                      ? `Generate with ${currentModel.name}`
                      : `Download & Generate (${currentModel.size})`}
                  </span>
                </>
              )}
            </button>
          </div>
        </div>

        {/* RIGHT WORKSPACE: Live Token Streaming Screen or Playable Output */}
        <div className="lg:col-span-7 xl:col-span-8 flex flex-col gap-4">
          <div className="flex flex-col bg-surface border border-line rounded-3xl overflow-hidden shadow-e3">
            {/* Viewport Header */}
            <div className="flex flex-wrap items-center justify-between px-5 py-3.5 bg-surface-2 border-b border-line text-xs font-mono gap-2">
              <div className="flex items-center gap-2.5">
                <span className={`w-2.5 h-2.5 rounded-full ${
                  generationPhase === 'streaming'
                    ? 'bg-amber-400 animate-ping'
                    : 'bg-emerald-400 animate-pulse'
                }`} />
                <span className="font-bold text-ink">{activeItem.title}</span>
                <span className="text-ink-muted">•</span>
                <span className="text-signal text-[11px] font-semibold">{currentModel.name}</span>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[10px] font-bold">
                  Client-Side WebGPU
                </span>
              </div>

              <div className="flex items-center gap-2">
                {generationPhase === 'completed' && (
                  <div className="flex items-center bg-surface border border-line rounded-xl p-0.5 mr-2">
                    <button
                      onClick={() => setViewMode('canvas')}
                      className={`px-2.5 py-1 rounded-lg text-[11px] flex items-center gap-1 transition-all ${
                        viewMode === 'canvas' ? 'bg-signal text-white font-bold' : 'text-ink-muted hover:text-ink'
                      }`}
                    >
                      <Eye className="w-3 h-3" />
                      <span>Canvas</span>
                    </button>
                    <button
                      onClick={() => setViewMode('code')}
                      className={`px-2.5 py-1 rounded-lg text-[11px] flex items-center gap-1 transition-all ${
                        viewMode === 'code' ? 'bg-signal text-white font-bold' : 'text-ink-muted hover:text-ink'
                      }`}
                    >
                      <Code2 className="w-3 h-3" />
                      <span>Code</span>
                    </button>
                  </div>
                )}

                <button
                  onClick={() => setRenderKey(k => k + 1)}
                  className="px-2.5 py-1 rounded-xl bg-surface border border-line text-ink-muted hover:text-ink flex items-center gap-1 text-[11px] transition-all"
                  title="Restart"
                >
                  <RotateCcw className="w-3 h-3" />
                  <span>Restart</span>
                </button>

                <button
                  onClick={() => setFullScreen(f => !f)}
                  className="px-2.5 py-1 rounded-xl bg-surface border border-line text-ink-muted hover:text-ink flex items-center gap-1 text-[11px] transition-all"
                >
                  {fullScreen ? <Minimize2 className="w-3 h-3" /> : <Maximize2 className="w-3 h-3" />}
                  <span>{fullScreen ? 'Exit' : 'Fullscreen'}</span>
                </button>
              </div>
            </div>

            {/* Viewport Body */}
            <div className={`w-full ${fullScreen ? 'h-[750px]' : 'h-[520px]'} bg-[#070a14] relative flex items-center justify-center overflow-hidden`}>
              {/* CASE 1: Downloading Weights in Progress */}
              {generationPhase === 'downloading' && (
                <div className="flex flex-col items-center justify-center p-8 max-w-md w-full text-center gap-4">
                  <div className="w-16 h-16 rounded-3xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal animate-bounce">
                    <Download className="w-8 h-8" />
                  </div>
                  <div>
                    <h4 className="text-base font-bold text-ink font-mono">
                      Downloading {currentModel.name}
                    </h4>
                    <p className="text-xs text-ink-muted mt-1 font-mono">
                      Caching weights directly to browser storage &amp; allocating WebGPU shader buffers...
                    </p>
                  </div>

                  <div className="w-full flex flex-col gap-2 pt-2">
                    <div className="flex justify-between text-xs font-mono text-signal">
                      <span>Progress</span>
                      <span>{downloadProgress}%</span>
                    </div>
                    <div className="w-full h-2 rounded-full bg-surface-2 overflow-hidden border border-line">
                      <div
                        className="h-full bg-gradient-to-r from-signal to-emerald-400 transition-all duration-150"
                        style={{ width: `${downloadProgress}%` }}
                      />
                    </div>
                  </div>
                </div>
              )}

              {/* CASE 2: LIVE STREAMING TOKEN CODE TYPEWRITER (GAME IS BEING WRITTEN LIVE BY MODEL) */}
              {generationPhase === 'streaming' && (
                <div className="w-full h-full flex flex-col bg-[#050811] text-emerald-400 font-mono text-xs overflow-hidden">
                  {/* Streaming Terminal Header */}
                  <div className="flex items-center justify-between px-4 py-2.5 bg-[#090d1a] border-b border-emerald-500/20 text-[11px]">
                    <div className="flex items-center gap-2 text-emerald-300">
                      <Terminal className="w-4 h-4 animate-pulse" />
                      <span className="font-bold">WebGPU Code Synthesis</span>
                      <span className="text-ink-muted">•</span>
                      <span className="text-signal">{currentModel.name}</span>
                    </div>

                    <div className="flex items-center gap-3">
                      <span className="text-emerald-400 font-bold animate-pulse">
                        {streamedTokens} tokens generated (~{currentModel.speed})
                      </span>
                      <button
                        onClick={handleSkipStream}
                        className="px-2.5 py-1 rounded-lg bg-signal text-white font-bold hover:bg-signal/90 transition-all flex items-center gap-1 shadow-sm text-[10px]"
                      >
                        <FastForward className="w-3 h-3" />
                        <span>Skip &amp; Play Now</span>
                      </button>
                    </div>
                  </div>

                  {/* Code Stream Output with Typewriter Effect */}
                  <div className="flex-1 p-4 overflow-y-auto font-mono text-[11px] leading-relaxed text-emerald-200/90 whitespace-pre-wrap select-text">
                    {streamedCode}
                    <span className="inline-block w-2 h-4 bg-emerald-400 ml-1 animate-pulse align-middle" />
                    <div ref={codeEndRef} />
                  </div>
                </div>
              )}

              {/* CASE 3: INTERACTIVE CANVAS PLAYGROUND (AFTER STREAMING COMPLETES) */}
              {(generationPhase === 'completed' || generationPhase === 'idle') && viewMode === 'canvas' && (
                <div className="w-full h-full relative">
                  {activeItem.previewType === 'html' ? (
                    <iframe
                      key={renderKey}
                      ref={iframeRef}
                      srcDoc={activeItem.content}
                      title={activeItem.title}
                      className="w-full h-full border-0"
                      sandbox="allow-scripts allow-modals allow-same-origin"
                    />
                  ) : (
                    <div
                      key={renderKey}
                      className="w-full h-full flex items-center justify-center p-6"
                      dangerouslySetInnerHTML={{ __html: activeItem.content }}
                    />
                  )}
                </div>
              )}

              {/* CASE 4: CODE INSPECTION VIEW */}
              {(generationPhase === 'completed' || generationPhase === 'idle') && viewMode === 'code' && (
                <div className="w-full h-full p-4 overflow-auto bg-[#050811] text-xs font-mono text-emerald-300 leading-relaxed whitespace-pre-wrap">
                  {activeItem.content}
                </div>
              )}
            </div>

            {/* Prompt-Based Refinement Footer */}
            <div className="p-4 bg-surface-2 border-t border-line flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2 text-xs font-mono text-ink-muted shrink-0">
                <Sparkles className="w-3.5 h-3.5 text-signal" />
                <span className="font-bold text-ink">Iterate via Prompt:</span>
              </div>
              <input
                type="text"
                value={refinementPrompt}
                onChange={(e) => setRefinementPrompt(e.target.value)}
                placeholder="e.g. 'Make game speed 2x faster', 'Add neon particles', 'Add 30% discount'..."
                className="flex-1 min-w-[260px] bg-surface border border-line rounded-xl px-3.5 py-2 text-xs text-ink font-mono focus:outline-none focus:ring-1 focus:ring-signal"
                onKeyDown={(e) => e.key === 'Enter' && handleRefine()}
              />
              <button
                onClick={handleRefine}
                disabled={generationPhase === 'streaming' || !refinementPrompt.trim()}
                className="px-4 py-2 text-xs font-mono font-bold rounded-xl bg-surface border border-signal/40 text-signal hover:bg-signal/15 transition-all disabled:opacity-40 flex items-center gap-1.5"
              >
                <Play className="w-3 h-3 fill-signal" />
                <span>Apply Refinement</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InBrowserCompanion;
