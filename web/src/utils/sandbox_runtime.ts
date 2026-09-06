/**
 * High-Aesthetic In-Browser Sandbox Runtime & Harness
 * Pre-injects modern CSS styling, Web Audio retro synthesizer,
 * high-DPI Retina canvas scaling, and focus management into the sandbox iframe.
 */

export function prepareSandboxDocument(rawHtml: string): string {
  const trimmed = rawHtml.trim();

  // If already a full HTML document, inject runtime hooks into <head> or <body>
  const runtimePreamble = `
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
<script src="https://cdn.tailwindcss.com"></script>
<style>
  :root {
    --bg: #090d16;
    --surface: #0f172a;
    --surface-card: rgba(30, 41, 59, 0.7);
    --border: rgba(148, 163, 184, 0.15);
    --signal: #38bdf8;
    --signal-glow: rgba(56, 189, 248, 0.35);
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: var(--bg);
    color: #f1f5f9;
    font-family: 'Inter', system-ui, -apple-system, sans-serif;
    overflow-x: hidden;
  }
  /* Modern Button Primitives */
  .btn-primary {
    background: linear-gradient(135deg, #0284c7, #38bdf8);
    color: #ffffff;
    font-weight: 600;
    padding: 0.5rem 1rem;
    border-radius: 0.75rem;
    border: none;
    cursor: pointer;
    box-shadow: 0 4px 14px var(--signal-glow);
    transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .btn-primary:hover {
    transform: translateY(-1px);
    box-shadow: 0 6px 20px var(--signal-glow);
  }
  /* Glass Card */
  .glass-card {
    background: var(--surface-card);
    backdrop-filter: blur(16px);
    border: 1px solid var(--border);
    border-radius: 1rem;
    padding: 1.25rem;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
  }
  /* Canvas Default Styling */
  canvas {
    display: block;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
    touch-action: none;
    outline: none;
  }
</style>
<script>
  // Web Audio API Retro Sound Effects Engine (Zero External Audio Assets)
  (function() {
    let ctx = null;
    function getAudio() {
      if (!ctx) {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (AudioContext) ctx = new AudioContext();
      }
      if (ctx && ctx.state === 'suspended') {
        ctx.resume();
      }
      return ctx;
    }

    function playTone(freqStart, freqEnd, duration, type = 'square', vol = 0.1) {
      const ac = getAudio();
      if (!ac) return;
      const osc = ac.createOscillator();
      const gain = ac.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freqStart, ac.currentTime);
      if (freqEnd && freqEnd !== freqStart) {
        osc.frequency.exponentialRampToValueAtTime(Math.max(10, freqEnd), ac.currentTime + duration);
      }
      gain.gain.setValueAtTime(vol, ac.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + duration);
      osc.connect(gain);
      gain.connect(ac.destination);
      osc.start();
      osc.stop(ac.currentTime + duration);
    }

    window.Sound = {
      coin: () => {
        playTone(987, 987, 0.08, 'sine', 0.15);
        setTimeout(() => playTone(1318, 1318, 0.2, 'sine', 0.15), 80);
      },
      jump: () => playTone(150, 600, 0.15, 'square', 0.1),
      laser: () => playTone(880, 110, 0.12, 'sawtooth', 0.12),
      hit: () => playTone(180, 50, 0.12, 'triangle', 0.2),
      boom: () => playTone(120, 30, 0.35, 'square', 0.25),
      powerup: () => {
        [440, 554, 659, 880].forEach((f, i) => {
          setTimeout(() => playTone(f, f, 0.1, 'sine', 0.12), i * 60);
        });
      },
      gameover: () => {
        [440, 415, 392, 349].forEach((f, i) => {
          setTimeout(() => playTone(f, f, 0.15, 'sawtooth', 0.15), i * 120);
        });
      }
    };

    // Auto-focus & prevent accidental page scrolling inside canvas games
    window.addEventListener('DOMContentLoaded', () => {
      window.focus();
      window.addEventListener('click', () => window.focus());
      window.addEventListener('keydown', (e) => {
        if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' '].includes(e.key)) {
          e.preventDefault();
        }
      });
    });
  })();
</script>
`;

  if (trimmed.includes('<html') || trimmed.includes('<!DOCTYPE')) {
    // Inject runtime into existing head
    if (trimmed.includes('<head>')) {
      return trimmed.replace('<head>', `<head>${runtimePreamble}`);
    } else {
      return trimmed.replace('<html>', `<html><head>${runtimePreamble}</head>`);
    }
  }

  // Wrap partial snippets in clean HTML5 container
  return `<!DOCTYPE html>
<html lang="en">
<head>
  ${runtimePreamble}
</head>
<body class="p-4 flex flex-col items-center justify-center min-h-screen">
  ${trimmed}
</body>
</html>`;
}
