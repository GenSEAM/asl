import React, { useState, useRef, useEffect } from 'react';
import {
  Sparkles,
  Gamepad2,
  Palette,
  RotateCcw,
  Maximize2,
  Minimize2,
  Cpu,
  Zap,
  Play,
  Square,
  AlertTriangle,
  Layers,
  ArrowRight,
  HardDrive,
  Download,
  WifiOff
} from 'lucide-react';
import { webLlmRunner, IN_BROWSER_MODELS, InBrowserModelSpec, WebLlmProgress } from '../utils/webllm_runner';

export interface PromptTemplate {
  id: string;
  title: string;
  category: 'games' | 'svg' | 'apps';
  prompt: string;
}

export const PROMPT_TEMPLATES: PromptTemplate[] = [
  {
    id: 'tetris',
    title: '🕹️ Retro Arcade Tetris',
    category: 'games',
    prompt: 'Write a retro arcade Tetris game in index.html with falling tetrominoes, canvas rendering, arrow controls, score counter, and game over state.'
  },
  {
    id: 'flappy',
    title: '🐤 Flappy Bird Playable',
    category: 'games',
    prompt: 'Write a playable Flappy Bird game in index.html with canvas physics, spacebar flap, pipe obstacles, and live score.'
  },
  {
    id: 'snake',
    title: '🐍 Cyber Snake Arcade',
    category: 'games',
    prompt: 'Write a playable cyberpunk Snake game in index.html with canvas rendering, arrow movement, neon food, and score.'
  },
  {
    id: 'pong',
    title: '🏓 Neon Arcade Pong',
    category: 'games',
    prompt: 'Write a playable neon arcade Pong game in index.html with AI paddle, player paddle, ball deflection physics, and score.'
  },
  {
    id: 'chameleon',
    title: '🦎 Color-Shifting Chameleon',
    category: 'svg',
    prompt: 'Draw a colorful stylized chameleon perched on a curved branch with coiled tail, big eyes, and jungle leaves.'
  },
  {
    id: 'robot',
    title: '🤖 Robot Mascot',
    category: 'svg',
    prompt: 'Draw a futuristic cute robot companion mascot with glowing antenna, expressive screen eyes, and metallic chassis.'
  },
  {
    id: 'calc',
    title: '🧮 Dark Calculator',
    category: 'apps',
    prompt: 'Write a sleek dark-mode scientific calculator in index.html with digital display, buttons, and clear arithmetic operations.'
  },
  {
    id: 'cat-boutique',
    title: '🐱 Kitten Boutique',
    category: 'apps',
    prompt: 'Write an interactive kitten adoption boutique in index.html with kitten cards, adoption counter, and playful filters.'
  }
];

export interface ModelOption {
  id: string;
  name: string;
  badge: string;
  speed: string;
  desc: string;
  inBrowserSpec: InBrowserModelSpec;
}

export const MODELS: ModelOption[] = [
  {
    id: 'qwen-coder-0.5b-q4',
    name: 'Qwen 2.5 Coder 0.5B',
    badge: 'q4f16_1 · 240MB',
    speed: '~55 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 945MB. Fast download (~240MB). Instant client-side streaming.',
    inBrowserSpec: IN_BROWSER_MODELS[0]
  },
  {
    id: 'qwen-coder-0.5b-fp16',
    name: 'Qwen 2.5 Coder 0.5B (Unquantized)',
    badge: 'q0f16 (FP16) · 980MB',
    speed: '~45 t/s',
    desc: 'Quantization: q0f16 (Unquantized FP16). VRAM: 1.6GB. 100% raw mathematical weights without quantization error.',
    inBrowserSpec: IN_BROWSER_MODELS[1]
  },
  {
    id: 'qwen-coder-1.5b-q4',
    name: 'Qwen 2.5 Coder 1.5B',
    badge: 'q4f16_1 · 850MB',
    speed: '~38 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 1.6GB. Strong multi-step reasoning for structured UI and game loops.',
    inBrowserSpec: IN_BROWSER_MODELS[2]
  },
  {
    id: 'qwen-coder-3b-q4',
    name: 'Qwen 2.5 Coder 3B',
    badge: 'q4f16_1 · 1.7GB',
    speed: '~25 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 2.5GB (~2GB memory footprint). Top-tier coding engine for complex state machines.',
    inBrowserSpec: IN_BROWSER_MODELS[3]
  }
];

export const InBrowserCompanion: React.FC = () => {
  const [selectedModelId, setSelectedModelId] = useState<string>('qwen-coder-0.5b-q4');
  const [activeCategory, setActiveCategory] = useState<'games' | 'svg' | 'apps'>('games');
  const [customPrompt, setCustomPrompt] = useState<string>(PROMPT_TEMPLATES[0].prompt);
  const [refinementPrompt, setRefinementPrompt] = useState<string>('');

  // WebGPU Hardware Support State
  const [hasWebGpu, setHasWebGpu] = useState<boolean | null>(null);

  // Generation & Engine States
  const [generationPhase, setGenerationPhase] = useState<'idle' | 'downloading' | 'generating' | 'completed' | 'error'>('idle');
  const [downloadProgress, setDownloadProgress] = useState<WebLlmProgress | null>(null);
  const [renderedCode, setRenderedCode] = useState<string>(''); // Pure transpiled output for sandbox (no raw ASL/ASN)
  const [streamedTokens, setStreamedTokens] = useState<number>(0);
  const [generationError, setGenerationError] = useState<string | null>(null);
  const [generationLatencyMs, setGenerationLatencyMs] = useState<number>(0);
  const [tokPerSec, setTokPerSec] = useState<number>(0);

  const [fullScreen, setFullScreen] = useState<boolean>(false);
  const [renderKey, setRenderKey] = useState<number>(0);

  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);

  const currentModel = MODELS.find(m => m.id === selectedModelId) || MODELS[0];

  // Detect WebGPU on mount
  useEffect(() => {
    webLlmRunner.isWebGpuAvailable().then(avail => {
      setHasWebGpu(avail);
    });
  }, []);

  // Clean up on unmount
  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);

  const handleSelectTemplate = (tpl: PromptTemplate) => {
    setCustomPrompt(tpl.prompt);
    setRefinementPrompt('');
  };

  const handleStopGeneration = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setGenerationPhase(renderedCode.trim() ? 'completed' : 'idle');
    setRenderKey(k => k + 1);
  };

  const executeGeneration = async (targetPrompt: string) => {
    if (!targetPrompt.trim()) return;

    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    const abortController = new AbortController();
    abortControllerRef.current = abortController;

    setRenderedCode('');
    setStreamedTokens(0);
    setGenerationError(null);

    try {
      const isGpuReady = await webLlmRunner.isWebGpuAvailable();
      if (!isGpuReady) {
        throw new Error('WebGPU hardware acceleration is not supported or disabled in this browser. Please open in Chrome 113+, Edge 113+, or Arc with hardware acceleration enabled.');
      }

      setGenerationPhase('downloading');
      setDownloadProgress({ progress: 0.05, text: 'Connecting to browser WebGPU device...', isDownloading: true });

      await webLlmRunner.loadModel(currentModel.inBrowserSpec, (prog) => {
        setDownloadProgress(prog);
      });

      setGenerationPhase('generating');
      const isSvgTask = activeCategory === 'svg' || targetPrompt.toLowerCase().includes('svg') || targetPrompt.toLowerCase().includes('draw') || targetPrompt.toLowerCase().includes('vector');
      const systemPrompt = isSvgTask
        ? `(:skill :name "asl-svg"
  :desc "Autonomous Vector Graphics Drawing and ASN <-> SVG Transpilation skill for AI agents. Uses standard native ASN vector representation (:rc, :circ, :p, :g, :ln, :txt, :def, :grad, :f, :s, :sw, :sz, :v) delivering 50% token compaction over verbose XML, guaranteed balanced delimiters, zero unclosed tags, and instant transpilation to valid SVG."
  :rules [
    (:rule :type "mandatory" :text "MANDATORY: Write vector graphics directly in standard ASN S-expression syntax (:svg ... (:rc ...) (:circ ...) (:p ...)).")
    (:rule :type "mandatory" :text "MANDATORY: Always specify viewBox (:v) or width and height (:w, :h) on root :svg element.")
    (:rule :type "style" :text "Use standard ASN vector primitives (:rc, :circ, :p, :ln, :txt, :g, :f, :s, :sw, :sz, :v) for clean, high-density generation.")
  ]
  :example
  (:svg :w 800 :h 500
    (:rc :x 0 :y 0 :w 800 :h 500 :f "#0f172a")
    (:circ :cx 400 :cy 250 :r 90 :f "#38bdf8" :s "#0284c7" :sw 3)
    (:p :d "M 200 300 L 400 150 L 600 300 Z" :f "#10b981")
    (:txt :x 260 :y 320 :text "ASL VECTOR" :f "#ffffff" :sz 16 :weight "bold")))`
        : `(:skill :name "asl-toolbelt"
  :desc "Autonomous AgentScript tool execution runtime."
  :rules [
    (:rule :type "mandatory" :text "MANDATORY: Execute file writes via ASL toolcall: (:call :tool \"write\" :path \"index.html\" :content \"...\")")
  ]
  :example
  (:call :tool "write" :path "index.html" :content "<!DOCTYPE html><html><head><style>body{margin:0;background:#000;color:#fff;font-family:monospace;}</style></head><body><canvas id='c'></canvas><script>/* logic */</script></body></html>"))`;

      await webLlmRunner.generateStreaming(
        targetPrompt,
        systemPrompt,
        (_delta, _accumulated, telemetry) => {
          setStreamedTokens(telemetry.tokensGenerated);
          setTokPerSec(telemetry.tokensPerSec);
        },
        (finalCode, telemetry) => {
          setRenderedCode(finalCode);
          setGenerationLatencyMs(Math.round(telemetry.elapsedMs));
          setGenerationPhase('completed');
          setRenderKey(k => k + 1);
        },
        (err) => {
          console.error('In-browser model error:', err);
          setGenerationError(err?.message || 'Error during in-browser inference');
          setGenerationPhase('error');
        }
      );

    } catch (err: any) {
      console.error('In-browser execution failed:', err);
      setGenerationError(err?.message || 'Failed to execute in-browser model');
      setGenerationPhase('error');
    } finally {
      abortControllerRef.current = null;
    }
  };

  const handleRefine = () => {
    if (!refinementPrompt.trim()) return;
    const combined = `${customPrompt}\n\n[USER REFINEMENT]: ${refinementPrompt}`;
    setCustomPrompt(combined);
    setRefinementPrompt('');
    executeGeneration(combined);
  };

  const filteredTemplates = PROMPT_TEMPLATES.filter(it => it.category === activeCategory);
  const isSvg = renderedCode.trim().startsWith('<svg') || customPrompt.toLowerCase().includes('svg') || activeCategory === 'svg';

  return (
    <div className="flex flex-col gap-6 w-full relative">
      {/* WebGPU Absence Warning Banner */}
      {hasWebGpu === false && (
        <div className="p-4 rounded-3xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3.5 text-amber-200 font-mono text-xs">
          <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
          <div className="flex flex-col gap-1">
            <span className="font-bold uppercase tracking-wider text-amber-300">
              WebGPU Hardware Acceleration Required
            </span>
            <p className="text-[11px] leading-relaxed text-amber-200/80">
              The in-browser agent executes 100% locally inside your browser tab using WebGPU compute shaders with <b>zero cloud servers</b>.
              To run in-browser models, please open this page in <b>Google Chrome 113+</b>, <b>Microsoft Edge 113+</b>, or <b>Arc</b> with hardware acceleration enabled.
            </p>
          </div>
        </div>
      )}

      {/* Top Simple Subtitle Banner */}
      <div className="flex flex-wrap items-center justify-between gap-3 text-xs font-mono text-ink-muted px-1">
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-surface border border-line text-ink font-medium">
            <WifiOff className="w-3.5 h-3.5 text-signal" />
            <span>100% On-Device WebGPU Agent</span>
          </span>
          <span className="text-[11px] text-ink-muted hidden sm:inline">
            Zero cloud servers · Isolated sandbox
          </span>
        </div>

        <span className="px-2.5 py-1 rounded-lg bg-surface border border-line text-[11px] text-signal font-bold">
          Active: {currentModel.name}
        </span>
      </div>

      {/* Main Two-Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* LEFT SIDEBAR: Compact Model Select & Expanded Directive Prompt */}
        <div className="lg:col-span-5 xl:col-span-4 flex flex-col gap-4">
          {/* Section 1: In-Browser Model Select Dropdown */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-2.5">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Cpu className="w-4 h-4 text-signal" />
                <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                  In-Browser Model
                </span>
              </div>
              <span className="px-2 py-0.5 rounded-full bg-signal/15 border border-signal/30 text-signal font-mono text-[10px] font-bold">
                WebGPU
              </span>
            </div>

            <select
              value={selectedModelId}
              onChange={(e) => setSelectedModelId(e.target.value)}
              disabled={generationPhase === 'generating' || generationPhase === 'downloading'}
              className="w-full p-2.5 rounded-xl bg-surface-2 border border-line text-xs font-mono text-ink focus:outline-none focus:border-signal cursor-pointer"
            >
              {MODELS.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name} ({m.badge})
                </option>
              ))}
            </select>

            <div className="flex items-center justify-between text-[11px] font-mono text-ink-muted px-1">
              <span>Speed: <b className="text-signal">{currentModel.speed}</b></span>
              <span>VRAM: <b className="text-ink">{currentModel.inBrowserSpec.vramMb}MB</b></span>
              <span>DL: <b className="text-ink">{currentModel.inBrowserSpec.approxSizeMb}MB</b></span>
            </div>
          </div>

          {/* Section 2: Templates & Category */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Layers className="w-4 h-4 text-signal" />
                <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                  Templates
                </span>
              </div>
              <span className="px-2 py-0.5 rounded-md bg-signal/10 border border-signal/30 text-[10px] font-mono font-bold text-signal">
                Skill: {activeCategory === 'svg' ? 'asl-svg' : 'asl-toolbelt'}
              </span>
            </div>

            {/* Category Tabs */}
            <div className="grid grid-cols-3 gap-1.5 p-1 rounded-2xl bg-surface-2 border border-line">
              <button
                onClick={() => {
                  setActiveCategory('games');
                  const first = PROMPT_TEMPLATES.find(i => i.category === 'games');
                  if (first) handleSelectTemplate(first);
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
                  const first = PROMPT_TEMPLATES.find(i => i.category === 'svg');
                  if (first) handleSelectTemplate(first);
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
                  setActiveCategory('apps');
                  const first = PROMPT_TEMPLATES.find(i => i.category === 'apps');
                  if (first) handleSelectTemplate(first);
                }}
                className={`py-1.5 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex items-center justify-center gap-1 ${
                  activeCategory === 'apps'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Sparkles className="w-3 h-3" />
                <span>Apps</span>
              </button>
            </div>

            {/* Template Buttons List */}
            <div className="grid grid-cols-2 gap-2">
              {filteredTemplates.map((tpl) => (
                <button
                  key={tpl.id}
                  onClick={() => handleSelectTemplate(tpl)}
                  className={`p-2.5 rounded-xl border text-left text-xs font-mono transition-all flex items-center justify-between ${
                    customPrompt === tpl.prompt
                      ? 'bg-signal/15 border-signal text-ink font-bold shadow-sm'
                      : 'bg-surface-2 border-line hover:border-line-hover text-ink-muted hover:text-ink'
                  }`}
                >
                  <span className="truncate">{tpl.title}</span>
                  <ArrowRight className="w-3 h-3 opacity-50 flex-shrink-0" />
                </button>
              ))}
            </div>
          </div>

          {/* Section 3: Expanded Directive Prompt Input */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                Directive Prompt
              </span>
              <span className="text-[10px] font-mono text-ink-muted">Free-form instruction</span>
            </div>

            <textarea
              value={customPrompt}
              onChange={(e) => setCustomPrompt(e.target.value)}
              rows={5}
              placeholder="Describe the application, game, or SVG you want the model to synthesize..."
              className="w-full p-3.5 rounded-2xl bg-surface-2 border border-line text-xs font-mono text-ink placeholder:text-ink-muted focus:outline-none focus:border-signal resize-none leading-relaxed min-h-[130px]"
            />

            <div className="flex items-center gap-2">
              {generationPhase === 'generating' || generationPhase === 'downloading' ? (
                <button
                  onClick={handleStopGeneration}
                  className="w-full py-3 rounded-2xl bg-rose-500 hover:bg-rose-600 text-white font-mono font-bold text-xs flex items-center justify-center gap-2 shadow-sm transition-all"
                >
                  <Square className="w-4 h-4 fill-white" />
                  <span>Interrupt Generation</span>
                </button>
              ) : (
                <button
                  onClick={() => executeGeneration(customPrompt)}
                  disabled={hasWebGpu === false}
                  className="w-full py-3 rounded-2xl bg-signal hover:bg-signal-hover disabled:opacity-50 text-white font-mono font-bold text-xs flex items-center justify-center gap-2 shadow-sm transition-all hover:scale-[1.01]"
                >
                  <Play className="w-4 h-4 fill-white" />
                  <span>Launch In-Browser Agent</span>
                </button>
              )}
            </div>
          </div>
        </div>

        {/* RIGHT MAIN AREA: Clean Live Sandbox Viewport */}
        <div className="lg:col-span-7 xl:col-span-8 flex flex-col gap-3">
          {/* Sandbox Top Bar */}
          <div className="p-3.5 rounded-2xl bg-surface border border-line flex items-center justify-between gap-3 font-mono text-xs">
            <div className="flex items-center gap-2.5">
              <div className={`w-2.5 h-2.5 rounded-full ${
                generationPhase === 'generating'
                  ? 'bg-amber-400 animate-ping'
                  : generationPhase === 'downloading'
                  ? 'bg-cyan-400 animate-pulse'
                  : generationPhase === 'completed'
                  ? 'bg-emerald-400'
                  : generationPhase === 'error'
                  ? 'bg-rose-500'
                  : 'bg-ink-muted'
              }`} />
              <span className="font-bold text-ink">
                {generationPhase === 'generating' && 'Synthesizing in Sandbox...'}
                {generationPhase === 'downloading' && 'Loading Model Weights...'}
                {generationPhase === 'completed' && (isSvg ? 'Vector Graphics Sandbox' : 'Interactive Application Sandbox')}
                {generationPhase === 'error' && 'Execution Error'}
                {generationPhase === 'idle' && 'Sandbox Application'}
              </span>
            </div>

            <div className="flex items-center gap-2">
              {generationPhase === 'completed' && (
                <div className="hidden sm:flex items-center gap-2 text-[11px] text-ink-muted mr-2">
                  <span className="text-emerald-400 font-bold">{streamedTokens} tokens</span>
                  <span>•</span>
                  <span>{tokPerSec} t/s</span>
                  <span>•</span>
                  <span>{generationLatencyMs} ms</span>
                </div>
              )}
              <button
                onClick={() => setRenderKey(k => k + 1)}
                title="Reload Sandbox"
                disabled={!renderedCode.trim()}
                className="p-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover disabled:opacity-30 text-ink-muted hover:text-ink transition-all"
              >
                <RotateCcw className="w-4 h-4" />
              </button>
              <button
                onClick={() => setFullScreen(!fullScreen)}
                title={fullScreen ? "Exit Fullscreen" : "Fullscreen Sandbox"}
                className="p-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover text-ink-muted hover:text-ink transition-all"
              >
                {fullScreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
              </button>
            </div>
          </div>

          {/* Model Weights Download Progress Card */}
          {generationPhase === 'downloading' && downloadProgress && (
            <div className="p-4 rounded-3xl bg-cyan-950/30 border border-cyan-500/40 flex flex-col gap-3 font-mono">
              <div className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-2 text-cyan-300 font-bold">
                  <Download className="w-4 h-4 animate-bounce text-cyan-400" />
                  <span>Loading Model into Browser VRAM (IndexedDB Cache)</span>
                </div>
                <span className="text-cyan-400 font-bold">
                  {Math.round((downloadProgress.progress || 0) * 100)}%
                </span>
              </div>

              <div className="w-full h-2 rounded-full bg-cyan-950/60 border border-cyan-800/40 overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-cyan-500 to-emerald-400 transition-all duration-200"
                  style={{ width: `${Math.min(100, Math.max(5, Math.round((downloadProgress.progress || 0) * 100)))}%` }}
                />
              </div>

              <div className="flex items-center justify-between text-[11px] text-cyan-300/70">
                <span>{downloadProgress.text || 'Fetching weights...'}</span>
                <span className="flex items-center gap-1">
                  <HardDrive className="w-3 h-3" />
                  Cached in browser
                </span>
              </div>
            </div>
          )}

          {/* Sandbox Canvas Viewport */}
          <div className={`w-full rounded-3xl border border-line bg-neutral-950 overflow-hidden relative shadow-md transition-all ${
            fullScreen ? 'fixed inset-4 z-50 h-[calc(100vh-2rem)]' : 'h-[560px]'
          }`}>
            {generationPhase === 'generating' ? (
              // STREAMING SYNTHESIS SPINNER & TOKEN COUNTER OVERLAY
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center gap-4 bg-neutral-950/95 font-mono">
                <div className="relative flex items-center justify-center">
                  <div className="w-16 h-16 rounded-full border-4 border-signal/20 border-t-signal animate-spin" />
                  <Sparkles className="w-6 h-6 text-signal absolute animate-pulse" />
                </div>

                <div className="flex flex-col gap-1">
                  <h4 className="text-sm font-bold text-ink tracking-wide">
                    Synthesizing in Browser Sandbox
                  </h4>
                  <p className="text-xs text-ink-muted">
                    Executing on-device WebGPU compute shaders with {currentModel.name}
                  </p>
                </div>

                {/* Token Counter and Speed Telemetry */}
                <div className="flex items-center gap-4 p-2.5 px-4 rounded-2xl bg-surface border border-line text-xs">
                  <div className="flex items-center gap-1.5 text-signal font-bold">
                    <Zap className="w-3.5 h-3.5" />
                    <span>{streamedTokens} tokens</span>
                  </div>
                  <span className="text-line">•</span>
                  <div className="text-ink font-semibold">
                    {tokPerSec > 0 ? `${tokPerSec} tok/s` : 'streaming...'}
                  </div>
                </div>

                <button
                  onClick={handleStopGeneration}
                  className="mt-2 px-4 py-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover text-ink-muted hover:text-ink text-xs font-bold transition-all flex items-center gap-1.5"
                >
                  <Square className="w-3.5 h-3.5 fill-current" />
                  <span>Interrupt</span>
                </button>
              </div>
            ) : generationPhase === 'error' ? (
              // ERROR STATE
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center max-w-md mx-auto gap-4 font-mono">
                <div className="w-12 h-12 rounded-2xl bg-rose-500/10 border border-rose-500/30 flex items-center justify-center text-rose-400">
                  <AlertTriangle className="w-6 h-6" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-rose-400">Synthesis Error</h4>
                  <p className="text-xs text-ink-muted mt-1 break-words">
                    {generationError || 'Failed to synthesize or run the requested prompt.'}
                  </p>
                </div>
                <button
                  onClick={() => executeGeneration(customPrompt)}
                  className="px-4 py-2 rounded-xl bg-signal text-white text-xs font-bold hover:bg-signal-hover transition-all"
                >
                  Retry Generation
                </button>
              </div>
            ) : renderedCode.trim() ? (
              // COMPLETED: RENDERED SANDBOX
              isSvg ? (
                <div
                  key={renderKey}
                  className="w-full h-full flex items-center justify-center p-6 bg-gradient-to-br from-neutral-950 to-neutral-900 overflow-auto"
                  dangerouslySetInnerHTML={{ __html: renderedCode.trim() }}
                />
              ) : (
                <iframe
                  key={renderKey}
                  ref={iframeRef}
                  srcDoc={renderedCode.trim()}
                  title="In-Browser WebGPU App Sandbox"
                  sandbox="allow-scripts allow-modals"
                  className="w-full h-full border-0 bg-neutral-950"
                />
              )
            ) : (
              // IDLE STATE
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center max-w-sm mx-auto gap-3 font-mono">
                <div className="w-12 h-12 rounded-2xl bg-surface border border-line flex items-center justify-center text-ink-muted">
                  <Sparkles className="w-6 h-6 text-signal" />
                </div>
                <span className="text-xs font-bold uppercase tracking-wider text-ink">
                  Sandbox Idle
                </span>
                <p className="text-[11px] text-ink-muted leading-relaxed">
                  Select a template or type a directive on the left, then click <b>Launch In-Browser Agent</b> to run 100% locally in your browser.
                </p>
              </div>
            )}
          </div>

          {/* Refinement Prompt Bar */}
          {renderedCode.trim() && generationPhase === 'completed' && (
            <div className="p-3 rounded-2xl bg-surface border border-line flex items-center gap-3">
              <Zap className="w-4 h-4 text-signal flex-shrink-0" />
              <input
                type="text"
                value={refinementPrompt}
                onChange={(e) => setRefinementPrompt(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleRefine()}
                placeholder="Iterate or refine app (e.g., 'Add a speed boost', 'Change theme to dark neon')..."
                className="flex-1 bg-transparent text-xs font-mono text-ink placeholder:text-ink-muted focus:outline-none"
              />
              <button
                onClick={handleRefine}
                disabled={!refinementPrompt.trim()}
                className="px-3 py-1.5 rounded-xl bg-signal text-white font-mono text-xs font-bold disabled:opacity-40 hover:bg-signal-hover transition-all"
              >
                Refine
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
