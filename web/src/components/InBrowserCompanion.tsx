import React, { useState, useRef, useEffect } from 'react';
import {
  Sparkles,
  Gamepad2,
  Palette,
  Globe,
  RotateCcw,
  Maximize2,
  Minimize2,
  Cpu,
  Zap,
  Play,
  Square,
  AlertTriangle,
  Layers,
  Code2,
  HardDrive,
  Download,
  CheckCircle2,
  XCircle,
  Copy,
  Check,
  Smartphone,
  Tablet,
  Monitor
} from 'lucide-react';
import { webLlmRunner, IN_BROWSER_MODELS, InBrowserModelSpec, WebLlmProgress } from '../utils/webllm_runner';
import { prepareSandboxDocument } from '../utils/sandbox_runtime';
import { runInBrowserGates, VerificationResult } from '../generated/browser_gate';

export interface PromptTemplate {
  id: string;
  title: string;
  shortTitle: string;
  icon: string;
  studio: 'svg' | 'games' | 'website';
  prompt: string;
}

export const PROMPT_TEMPLATES: PromptTemplate[] = [
  // 1. SVG STUDIO (Vector Badges, Icons, Emblems)
  {
    id: 'gem',
    title: '💎 Neon Crystal Gem',
    shortTitle: 'Gem',
    icon: '💎',
    studio: 'svg',
    prompt: 'Draw a glowing neon crystal gemstone badge in ASN notation centered on 320x320 canvas. Compose faceted diamond geometry with colored polygons (:poly) and sharp highlight edges in cyan (#38bdf8) and violet (#a855f7).'
  },
  {
    id: 'rocket',
    title: '🚀 Space Rocket Icon',
    shortTitle: 'Rocket',
    icon: '🚀',
    studio: 'svg',
    prompt: 'Draw a stylized space rocket icon in ASN notation on a 320x320 canvas. Compose a sleek fuselage with cockpit window (:circ), delta wings (:poly), and fiery orange exhaust booster flames (:poly).'
  },
  {
    id: 'lightning',
    title: '⚡ Lightning Shield',
    shortTitle: 'Shield',
    icon: '⚡',
    studio: 'svg',
    prompt: 'Draw an energetic golden lightning bolt emblem in ASN notation on a 320x320 badge. Compose a sharp zig-zag lightning polygon (:poly) with glowing gold (#fbbf24) and cyan (#38bdf8) accents.'
  },
  {
    id: 'chameleon',
    title: '🦎 Stylized Chameleon',
    shortTitle: 'Chameleon',
    icon: '🦎',
    studio: 'svg',
    prompt: 'Draw a stylized neon chameleon badge in ASN notation on a 320x320 canvas. Compose its coiled spiral tail, arched back, large circular eye (:circ), and branch with vivid emerald (#34d399) contours.'
  },
  {
    id: 'hex-portal',
    title: '🔮 Cyberpunk Hex Portal',
    shortTitle: 'Portal',
    icon: '🔮',
    studio: 'svg',
    prompt: 'Draw a futuristic cyberpunk portal emblem in ASN notation on a 320x320 canvas. Compose concentric hex rings (:poly), glowing energy vortex lines (:ln), and violet (#a855f7) and cyan (#38bdf8) nodes.'
  },

  // 2. TOYS & GAMES STUDIO (Playable Canvas Games & Physics)
  {
    id: 'tetris',
    title: '🕹️ Retro Arcade Tetris',
    shortTitle: 'Tetris',
    icon: '🕹️',
    studio: 'games',
    prompt: 'Write a retro arcade Tetris game in index.html with falling tetrominoes, canvas rendering, arrow controls, score counter, and game over state.'
  },
  {
    id: 'flappy',
    title: '🐤 Flappy Bird Playable',
    shortTitle: 'Flappy',
    icon: '🐤',
    studio: 'games',
    prompt: 'Write a playable Flappy Bird game in index.html with canvas physics, spacebar flap, pipe obstacles, and live score.'
  },
  {
    id: 'snake',
    title: '🐍 Cyber Snake Arcade',
    shortTitle: 'Snake',
    icon: '🐍',
    studio: 'games',
    prompt: 'Write a playable cyberpunk Snake game in index.html with canvas rendering, arrow movement, neon food, and score.'
  },
  {
    id: 'pong',
    title: '🏓 Neon Arcade Pong',
    shortTitle: 'Pong',
    icon: '🏓',
    studio: 'games',
    prompt: 'Write a playable neon arcade Pong game in index.html with AI paddle, player paddle, ball deflection physics, and score.'
  },
  {
    id: 'particles',
    title: '🌌 Gravity Particle Sandbox',
    shortTitle: 'Physics',
    icon: '🌌',
    studio: 'games',
    prompt: 'Write an interactive particle physics sandbox in index.html with 200 colorful gravity particles following mouse cursor and bouncing off screen borders.'
  },

  // 3. WEBSITES & UI STUDIO (Responsive Site Sections & Components)
  {
    id: 'hero-saas',
    title: '🌐 Modern SaaS Hero Section',
    shortTitle: 'Hero',
    icon: '🌐',
    studio: 'website',
    prompt: 'Write a responsive dark-mode SaaS landing hero section with glowing gradient headline, subtitle, primary/secondary CTA buttons, and interactive feature badges.'
  },
  {
    id: 'metric-card',
    title: '📊 Live Metric Dashboard Card',
    shortTitle: 'Metrics',
    icon: '📊',
    studio: 'website',
    prompt: 'Write a sleek dark telemetry card with live ticking request counter, latency gauge, uptime badge, and interactive refresh button.'
  },
  {
    id: 'pricing-grid',
    title: '💳 Interactive Pricing Grid',
    shortTitle: 'Pricing',
    icon: '💳',
    studio: 'website',
    prompt: 'Write an interactive 3-tier pricing table (Starter, Pro, Enterprise) with monthly/annual billing toggle and highlight on the recommended tier.'
  },
  {
    id: 'portfolio',
    title: '💼 Dark Developer Portfolio',
    shortTitle: 'Portfolio',
    icon: '💼',
    studio: 'website',
    prompt: 'Write a personal developer portfolio section with avatar, skills tags (ASL, TypeScript, WebGPU), interactive project cards, and contact button.'
  },
  {
    id: 'calc',
    title: '🧮 Dark Scientific Calculator',
    shortTitle: 'Calc',
    icon: '🧮',
    studio: 'website',
    prompt: 'Write a sleek dark-mode scientific calculator in index.html with digital display, buttons, and clear arithmetic operations.'
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
    speed: '~28 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 945MB. Fast download (~240MB). Instant client-side streaming.',
    inBrowserSpec: IN_BROWSER_MODELS[0]
  },
  {
    id: 'qwen-coder-1.5b-q4',
    name: 'Qwen 2.5 Coder 1.5B (Recommended)',
    badge: 'q4f16_1 · 850MB',
    speed: '~18 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 1.6GB. Strong multi-step reasoning for structured UI and game loops.',
    inBrowserSpec: IN_BROWSER_MODELS[1]
  },
  {
    id: 'qwen-coder-3b-q4',
    name: 'Qwen 2.5 Coder 3B (Pro)',
    badge: 'q4f16_1 · 1.7GB',
    speed: '~12 t/s',
    desc: 'Quantization: q4f16_1 (4-bit). VRAM: 2.5GB (~2GB memory footprint). Top-tier coding engine for complex state machines.',
    inBrowserSpec: IN_BROWSER_MODELS[2]
  }
];

export const InBrowserCompanion: React.FC = () => {
  const [selectedModelId, setSelectedModelId] = useState<string>('qwen-coder-0.5b-q4');
  const [activeStudio, setActiveStudio] = useState<'svg' | 'games' | 'website'>('svg');
  const [customPrompt, setCustomPrompt] = useState<string>(PROMPT_TEMPLATES[0].prompt);
  const [refinementPrompt, setRefinementPrompt] = useState<string>('');
  const [reasoningEnabled, setReasoningEnabled] = useState<boolean>(false);
  const [liveReasoning, setLiveReasoning] = useState<string>('');
  const [isThinkingOpen, setIsThinkingOpen] = useState<boolean>(false);

  // Viewport Switcher for Website Studio
  const [viewportWidth, setViewportWidth] = useState<'100%' | '768px' | '375px'>('100%');

  // Copy state
  const [isCopied, setIsCopied] = useState<boolean>(false);

  // WebGPU Hardware Support State
  const [hasWebGpu, setHasWebGpu] = useState<boolean | null>(null);

  // Model Cache & Download States
  const [cachedModels, setCachedModels] = useState<Record<string, boolean>>({});
  const [isCheckingCache, setIsCheckingCache] = useState<boolean>(false);
  const [isManualDownloading, setIsManualDownloading] = useState<boolean>(false);

  // Generation & Engine States
  const [generationPhase, setGenerationPhase] = useState<'idle' | 'downloading' | 'generating' | 'completed' | 'error'>('idle');
  const [downloadProgress, setDownloadProgress] = useState<WebLlmProgress | null>(null);
  const [renderedCode, setRenderedCode] = useState<string>('');
  const [streamedTokens, setStreamedTokens] = useState<number>(0);
  const [generationError, setGenerationError] = useState<string | null>(null);
  const [generationLatencyMs, setGenerationLatencyMs] = useState<number>(0);
  const [tokPerSec, setTokPerSec] = useState<number>(0);

  // Live Verification Gate Result
  const [gateResult, setGateResult] = useState<VerificationResult | null>(null);

  const [fullScreen, setFullScreen] = useState<boolean>(false);
  const [renderKey, setRenderKey] = useState<number>(0);

  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);

  const currentModel = MODELS.find(m => m.id === selectedModelId) || MODELS[0];
  const isCurrentModelCached = !!cachedModels[currentModel.id];
  const isReasoningSupported = !!currentModel.inBrowserSpec.supportsThinking;

  // Detect WebGPU on mount
  useEffect(() => {
    webLlmRunner.isWebGpuAvailable().then(avail => {
      setHasWebGpu(avail);
    });
  }, []);

  // Check cache status for currently selected model
  const checkModelCache = async (spec: InBrowserModelSpec) => {
    setIsCheckingCache(true);
    try {
      const inCache = await webLlmRunner.hasModelInCache(spec);
      setCachedModels(prev => ({ ...prev, [spec.id]: inCache }));
    } catch {
      // ignore
    } finally {
      setIsCheckingCache(false);
    }
  };

  useEffect(() => {
    checkModelCache(currentModel.inBrowserSpec);
  }, [selectedModelId]);

  // Clean up on unmount
  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);

  // Run gate verification whenever renderedCode or activeStudio changes
  useEffect(() => {
    if (renderedCode.trim() && generationPhase === 'completed') {
      const res = runInBrowserGates(renderedCode, activeStudio);
      setGateResult(res);
    } else {
      setGateResult(null);
    }
  }, [renderedCode, activeStudio, generationPhase]);

  const handleSelectTemplate = (tpl: PromptTemplate) => {
    setCustomPrompt(tpl.prompt);
    setRefinementPrompt('');
  };

  const handleStopGeneration = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsManualDownloading(false);
    setGenerationPhase(renderedCode.trim() ? 'completed' : 'idle');
    setRenderKey(k => k + 1);
  };

  // Dedicated manual download handler
  const handleDownloadModel = async () => {
    if (isManualDownloading || generationPhase === 'generating') return;
    setIsManualDownloading(true);
    setGenerationPhase('downloading');
    setGenerationError(null);
    setDownloadProgress({ progress: 0.05, text: `Connecting WebGPU cache for ${currentModel.name}...`, isDownloading: true });

    try {
      await webLlmRunner.downloadModelOnly(currentModel.inBrowserSpec, (prog) => {
        setDownloadProgress(prog);
      });
      setCachedModels(prev => ({ ...prev, [currentModel.id]: true }));
      setGenerationPhase(renderedCode.trim() ? 'completed' : 'idle');
    } catch (err: any) {
      console.error('Model download failed:', err);
      setGenerationError(err?.message || 'Failed to download model weights.');
      setGenerationPhase('error');
    } finally {
      setIsManualDownloading(false);
    }
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
    setGateResult(null);

    try {
      const isGpuReady = await webLlmRunner.isWebGpuAvailable();
      if (!isGpuReady) {
        throw new Error('WebGPU hardware acceleration is not supported or disabled in this browser. Please open in Google Chrome 113+, Edge 113+, or Arc with hardware acceleration enabled.');
      }

      setGenerationPhase('downloading');
      setDownloadProgress({ progress: 0.05, text: 'Verifying WebGPU cache...', isDownloading: true });

      await webLlmRunner.loadModel(currentModel.inBrowserSpec, (prog) => {
        setDownloadProgress(prog);
      });
      setCachedModels(prev => ({ ...prev, [currentModel.id]: true }));

      setGenerationPhase('generating');

      // Tailored affirmative skill prompts per studio
      let systemPrompt = '';
      if (activeStudio === 'svg') {
        systemPrompt = `(:skill :name "asl-svg"
  :desc "Autonomous Vector Graphics Drawing in AgentScript ASN notation. Transpiles to crisp W3C SVG."
  :rules [
    (:rule :type "mandatory" :text "Output ONLY a single valid ASN vector expression: (:svg :w 320 :h 320 :v \\\"0 0 320 320\\\" ...)")
    (:rule :type "canvas" :text "Always format on 320x320 canvas: :w 320 :h 320 :v \\\"0 0 320 320\\\" starting with dark badge background: (:rc :x 0 :y 0 :w 320 :h 320 :rx 24 :f \\\"#090d16\\\").")
    (:rule :type "colors" :text "Every element MUST have explicit visible color: specify fill :f (e.g. '#38bdf8', '#a855f7', '#34d399', '#fbbf24') or stroke :s (e.g. '#38bdf8'). Never leave elements without fill or stroke.")
    (:rule :type "geometry" :text "Compose the requested subject centered around (160, 160) using: polygons (:poly :points \\\"x1,y1 x2,y2 x3,y3 ...\\\" :f \\\"...\\\" :s \\\"...\\\") for geometric facets and crystals; circles (:circ :cx ... :cy ... :r ... :f ... :s ...) for rings/cores; paths (:p :d \\\"M x1 y1 L x2 y2 ... Z\\\" :f ... :s ...) for contours; lines (:ln :x1 ... :y1 ... :x2 ... :y2 ... :s ... :sw ...) for accents.")
    (:rule :type "layers" :text "Layer cleanly: 1. Base card (:rc), 2. Outer decorative aura/ring (:circ or :poly), 3. Central subject geometry with distinct colored facets.")
  ]
  :syntax
  (:svg :w 320 :h 320 :v "0 0 320 320"
    (:rc :x 0 :y 0 :w 320 :h 320 :rx 24 :f "#090d16")
    (:circ :cx 160 :cy 160 :r 120 :f "rgba(15, 23, 42, 0.6)" :s "rgba(56, 189, 248, 0.3)" :sw 2)
    (:poly :points "160,70 230,125 200,215 120,215 90,125" :f "#1e293b" :s "#38bdf8" :sw 2)
    (:circ :cx 160 :cy 155 :r 25 :f "#38bdf8" :s "#ffffff" :sw 2)))`;
      } else if (activeStudio === 'games') {
        systemPrompt = `(:skill :name "asl-arcade-game"
  :desc "Autonomous Playable Canvas 2D Game in a self-contained HTML document."
  :rules [
    (:rule :type "mandatory" :text "Output ONLY a single ASL write toolcall: (:call :tool \\\"write\\\" :path \\\"index.html\\\" :content \\\"<!DOCTYPE html>...\\\")")
    (:rule :type "mandatory" :text "Single self-contained file with HTML, inline CSS, and complete interactive JS game loop.")
    (:rule :type "canvas" :text "Use <canvas id='game' width='600' height='400'></canvas> with requestAnimationFrame(loop).")
    (:rule :type "controls" :text "Support Arrow keys / WASD / Spacebar controls with clean event listeners.")
    (:rule :type "features" :text "Include live score counter, collision detection, game over restart state, and window.Sound effects.")
  ]
  :example
  (:call :tool "write" :path "index.html" :content "<div class='flex flex-col items-center gap-3'><div class='flex justify-between w-[600px] px-4 py-2 rounded-xl bg-slate-900/80 border border-slate-700/50'><span class='font-mono font-bold text-sky-400'>ARCADE</span><span id='score' class='font-mono font-bold text-white'>SCORE: 0</span></div><canvas id='game' width='600' height='400' class='rounded-xl border border-sky-500/30 bg-slate-950 shadow-2xl'></canvas><div class='text-xs font-mono text-slate-400'>[← →] Move · [Space] Action</div></div><script>const c=document.getElementById('game'),ctx=c.getContext('2d'),sc=document.getElementById('score');let p={x:280,y:340,w:40,h:20,vx:0},score=0,over=false;window.addEventListener('keydown',e=>{if(e.code==='ArrowLeft')p.vx=-5;if(e.code==='ArrowRight')p.vx=5;if(e.code==='Space'&&over){score=0;over=false;Sound.powerup();}});window.addEventListener('keyup',e=>{if(e.code==='ArrowLeft'||e.code==='ArrowRight')p.vx=0;});function loop(){p.x=Math.max(0,Math.min(560,p.x+p.vx));ctx.fillStyle='#090d16';ctx.fillRect(0,0,600,400);ctx.fillStyle='#38bdf8';ctx.fillRect(p.x,p.y,p.w,p.h);if(!over){score++;sc.innerText='SCORE: '+score;}requestAnimationFrame(loop);}loop();</script>"))`;
      } else {
        // Websites & UI Studio
        systemPrompt = `(:skill :name "asl-website-ui"
  :desc "Autonomous Modern Responsive Website Section & Web UI Component."
  :rules [
    (:rule :type "mandatory" :text "Output ONLY a single ASL write toolcall: (:call :tool \\\"write\\\" :path \\\"index.html\\\" :content \\\"<!DOCTYPE html>...\\\")")
    (:rule :type "mandatory" :text "Single self-contained file with HTML, Tailwind CSS classes, and interactive JS.")
    (:rule :type "styling" :text "Tailwind CSS is pre-loaded. Use modern dark aesthetic: bg-slate-950, text-white, border border-slate-800, text-sky-400 accents, smooth hover states.")
    (:rule :type "interactivity" :text "Include working interactive elements (toggles, filters, tabs, counters, copy buttons) with clean Vanilla JS.")
    (:rule :type "responsive" :text "Ensure fluid layout that adapts seamlessly from mobile (375px) to desktop (1200px).")
  ]
  :example
  (:call :tool "write" :path "index.html" :content "<div class='w-full max-w-4xl mx-auto p-6 flex flex-col gap-6 font-sans text-slate-100'><div class='flex items-center justify-between border-b border-slate-800 pb-4'><div class='flex items-center gap-3'><div class='w-8 h-8 rounded-lg bg-sky-500/20 border border-sky-500/40 flex items-center justify-center text-sky-400 font-mono font-bold'>⚡</div><div><h2 class='text-base font-bold'>Cloud Analytics</h2><p class='text-xs text-slate-400'>Real-time edge telemetry</p></div></div><span class='px-2.5 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs font-mono font-bold flex items-center gap-1.5'><span class='w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse'></span>ONLINE</span></div><div class='grid grid-cols-1 md:grid-cols-3 gap-4'><div class='p-4 rounded-2xl bg-slate-900/60 border border-slate-800 flex flex-col gap-1'><span class='text-xs text-slate-400 font-mono'>REQUESTS</span><span class='text-2xl font-bold font-mono text-sky-400' id='req'>14,820</span><span class='text-[10px] text-emerald-400 font-mono'>+18.4% this hour</span></div><div class='p-4 rounded-2xl bg-slate-900/60 border border-slate-800 flex flex-col gap-1'><span class='text-xs text-slate-400 font-mono'>P99 LATENCY</span><span class='text-2xl font-bold font-mono text-white'>4.2ms</span><span class='text-[10px] text-slate-400 font-mono'>Client-side WebGPU</span></div><div class='p-4 rounded-2xl bg-slate-900/60 border border-slate-800 flex flex-col gap-1'><span class='text-xs text-slate-400 font-mono'>TOKEN SAVINGS</span><span class='text-2xl font-bold font-mono text-emerald-400'>83.8%</span><span class='text-[10px] text-slate-400 font-mono'>Dense ASN protocol</span></div></div></div><script>let count=14820;setInterval(()=>{count+=Math.floor(Math.random()*15);document.getElementById('req').innerText=count.toLocaleString();},2000);</script>"))`;
      }

      // Reasoning guidance injection (only when supported by model and toggled on)
      if (reasoningEnabled && isReasoningSupported) {
        systemPrompt = "First, perform an in-depth step-by-step reasoning analysis inside <think>...</think> covering layout, coordinate bounds, state management, and edge cases. Then output the pure code/ASN.\n\n" + systemPrompt;
      }

      const temperature = activeStudio === 'svg' ? 0.65 : 0.45;

      await webLlmRunner.generateStreaming(
        targetPrompt,
        systemPrompt,
        (_delta, _accumulated, telemetry) => {
          setStreamedTokens(telemetry.tokensGenerated);
          setTokPerSec(telemetry.tokensPerSec);
          if (telemetry.reasoningText) {
            setLiveReasoning(telemetry.reasoningText);
          }
        },
        (finalCode, telemetry) => {
          setRenderedCode(finalCode);
          if (telemetry.reasoningText) {
            setLiveReasoning(telemetry.reasoningText);
          }
          setGenerationLatencyMs(Math.round(telemetry.elapsedMs));
          setGenerationPhase('completed');
          setRenderKey(k => k + 1);
        },
        (err) => {
          console.error('In-browser model error:', err);
          setGenerationError(err?.message || 'Error during in-browser inference');
          setGenerationPhase('error');
        },
        { enableThinking: reasoningEnabled && isReasoningSupported, temperature }
      );

    } catch (err: any) {
      console.error('In-browser execution failed:', err);
      setGenerationError(err?.message || 'Failed to execute in-browser model');
      setGenerationPhase('error');
    } finally {
      abortControllerRef.current = null;
    }
  };

  const handleRefine = (explicitOverride?: string) => {
    const req = (explicitOverride || refinementPrompt).trim();
    if (!req) return;
    const prevCode = renderedCode.trim();
    let iteratePrompt = '';
    if (prevCode) {
      iteratePrompt = `${customPrompt}\n\n[CURRENT CODE]:\n${prevCode}\n\n[USER REFINEMENT]:\n${req}\n\nApply the requested refinement to the code above while preserving all existing functionality. Output the updated complete code.`;
    } else {
      iteratePrompt = `${customPrompt}\n\n[USER REFINEMENT]:\n${req}`;
    }
    setCustomPrompt(prev => `${prev}\n\n[REFINEMENT]: ${req}`);
    if (!explicitOverride) {
      setRefinementPrompt('');
    }
    executeGeneration(iteratePrompt);
  };

  const handleCopyCode = () => {
    if (!renderedCode.trim()) return;
    navigator.clipboard.writeText(renderedCode.trim());
    setIsCopied(true);
    setTimeout(() => setIsCopied(false), 2000);
  };

  const filteredTemplates = PROMPT_TEMPLATES.filter(it => it.studio === activeStudio);
  const isSvg = activeStudio === 'svg' || renderedCode.trim().startsWith('<svg') || customPrompt.toLowerCase().includes('svg');

  return (
    <div className="flex flex-col gap-6 w-full relative">
      {/* WebGPU Absence Warning */}
      {hasWebGpu === false && (
        <div className="p-4 rounded-3xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3.5 text-amber-200 font-mono text-xs">
          <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
          <div className="flex flex-col gap-1">
            <span className="font-bold uppercase tracking-wider text-amber-300">
              WebGPU Hardware Acceleration Required
            </span>
            <p className="text-[11px] leading-relaxed text-amber-200/80">
              The in-browser agent executes 100% locally inside your browser tab using WebGPU with <b>zero cloud servers</b>.
              Please open this page in <b>Google Chrome 113+</b>, <b>Microsoft Edge 113+</b>, or <b>Arc</b> with hardware acceleration enabled.
            </p>
          </div>
        </div>
      )}

      {/* Main Two-Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* LEFT SIDEBAR: Studio Modes, Model Select & Directive Prompt */}
        <div className="lg:col-span-5 xl:col-span-4 flex flex-col gap-4">
          {/* Studio Selector: 3 Environments */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase flex items-center gap-1.5">
                <Layers className="w-4 h-4 text-signal" />
                <span>Creative Studio</span>
              </span>
              <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-signal/15 text-signal font-bold">
                Tri-Studio
              </span>
            </div>

            {/* 3 Environment Tabs */}
            <div className="grid grid-cols-3 gap-1.5 p-1 rounded-2xl bg-surface-2 border border-line">
              <button
                type="button"
                onClick={() => {
                  setActiveStudio('svg');
                  const first = PROMPT_TEMPLATES.find(i => i.studio === 'svg');
                  if (first) handleSelectTemplate(first);
                }}
                className={`py-2 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex flex-col items-center justify-center gap-1 cursor-pointer ${
                  activeStudio === 'svg'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Palette className="w-4 h-4" />
                <span>SVG Art</span>
              </button>

              <button
                type="button"
                onClick={() => {
                  setActiveStudio('games');
                  const first = PROMPT_TEMPLATES.find(i => i.studio === 'games');
                  if (first) handleSelectTemplate(first);
                }}
                className={`py-2 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex flex-col items-center justify-center gap-1 cursor-pointer ${
                  activeStudio === 'games'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Gamepad2 className="w-4 h-4" />
                <span>Games</span>
              </button>

              <button
                type="button"
                onClick={() => {
                  setActiveStudio('website');
                  const first = PROMPT_TEMPLATES.find(i => i.studio === 'website');
                  if (first) handleSelectTemplate(first);
                }}
                className={`py-2 px-2 rounded-xl text-[11px] font-bold font-mono transition-all flex flex-col items-center justify-center gap-1 cursor-pointer ${
                  activeStudio === 'website'
                    ? 'bg-signal text-white shadow-sm'
                    : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Globe className="w-4 h-4" />
                <span>Websites</span>
              </button>
            </div>
          </div>

          {/* Model Selection Card */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Cpu className="w-4 h-4 text-signal" />
                <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase">
                  Model Engine
                </span>
              </div>

              {/* Cache status pill & Download action */}
              <div className="flex items-center gap-2">
                {isCheckingCache ? (
                  <span className="text-[10px] font-mono text-ink-muted animate-pulse">Checking cache...</span>
                ) : isCurrentModelCached ? (
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-semibold flex items-center gap-1">
                    <CheckCircle2 className="w-3 h-3" />
                    <span>In Cache</span>
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={handleDownloadModel}
                    disabled={isManualDownloading || generationPhase === 'generating'}
                    title="Pre-download model weights to IndexedDB cache"
                    className="px-2.5 py-1 rounded-xl bg-signal/15 hover:bg-signal/25 border border-signal/30 text-signal font-mono text-[11px] font-bold flex items-center gap-1.5 transition-all cursor-pointer"
                  >
                    <Download className="w-3.5 h-3.5" />
                    <span>Download ({currentModel.inBrowserSpec.approxSizeMb}MB)</span>
                  </button>
                )}
              </div>
            </div>

            {/* Compact Select Dropdown */}
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

            {/* Reasoning Toggle (Да / Нет) - Rendered only for models that support reasoning */}
            {isReasoningSupported && (
              <div className="flex items-center justify-between p-2 rounded-xl bg-surface-2 border border-line text-xs font-mono">
                <span className="text-ink-muted text-[11px] flex items-center gap-1.5 font-bold">
                  <Sparkles className="w-3.5 h-3.5 text-signal" />
                  <span>Reasoning (CoT):</span>
                </span>
                <div className="flex items-center gap-1 bg-surface p-0.5 rounded-lg border border-line">
                  <button
                    type="button"
                    onClick={() => setReasoningEnabled(false)}
                    disabled={generationPhase === 'generating' || generationPhase === 'downloading'}
                    className={`px-3 py-1 rounded-md text-[11px] font-bold transition-all ${
                      !reasoningEnabled
                        ? 'bg-inset text-ink border border-line/60 shadow-sm'
                        : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    Нет
                  </button>
                  <button
                    type="button"
                    onClick={() => setReasoningEnabled(true)}
                    disabled={generationPhase === 'generating' || generationPhase === 'downloading'}
                    className={`px-3 py-1 rounded-md text-[11px] font-bold transition-all ${
                      reasoningEnabled
                        ? 'bg-signal text-white shadow-sm'
                        : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    Да
                  </button>
                </div>
              </div>
            )}

            <div className="flex items-center justify-between text-[11px] font-mono text-ink-muted px-1">
              <span>Speed: <b className="text-signal">{currentModel.speed}</b></span>
              <span>VRAM: <b className="text-ink">{currentModel.inBrowserSpec.vramMb}MB</b></span>
              <span>Download: <b className="text-ink">{currentModel.inBrowserSpec.approxSizeMb}MB</b></span>
            </div>
          </div>

          {/* Section 2: Unified Directive Prompt & Inline Presets */}
          <div className="p-4 rounded-3xl bg-surface border border-line shadow-sm flex flex-col gap-3">
            {/* Title */}
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold font-mono tracking-wide text-ink uppercase flex items-center gap-1.5 shrink-0">
                <Code2 className="w-3.5 h-3.5 text-signal" />
                <span>Directive Prompt</span>
              </span>
            </div>

            {/* Presets in One Line Under Title (Icon Only) */}
            <div className="flex items-center gap-1.5">
              <span className="text-[10px] font-mono text-ink-muted uppercase shrink-0 mr-1">Presets:</span>
              <div className="flex items-center gap-1.5">
                {filteredTemplates.map((tpl) => (
                  <button
                    key={tpl.id}
                    type="button"
                    onClick={() => handleSelectTemplate(tpl)}
                    title={tpl.title}
                    aria-label={tpl.title}
                    className={`w-8 h-8 rounded-xl border flex items-center justify-center text-sm transition-all shrink-0 cursor-pointer ${
                      customPrompt === tpl.prompt
                        ? 'bg-signal/20 text-signal border-signal shadow-sm scale-105'
                        : 'bg-surface-2 border-line hover:border-line-hover text-ink-muted hover:text-ink hover:scale-105'
                    }`}
                  >
                    <span>{tpl.icon}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* Prompt Textarea: 1.5x larger, 8-10 lines tall (~200px) */}
            <textarea
              value={customPrompt}
              onChange={(e) => setCustomPrompt(e.target.value)}
              rows={9}
              placeholder={
                activeStudio === 'svg'
                  ? 'Describe the SVG emblem or icon to draw in 320x320 canvas...'
                  : activeStudio === 'games'
                  ? 'Describe the 2D arcade canvas game or interactive physics toy...'
                  : 'Describe the responsive website section or modern UI component...'
              }
              className="w-full p-3.5 rounded-2xl bg-surface-2 border border-line text-xs font-mono text-ink placeholder:text-ink-muted focus:outline-none focus:border-signal resize-y leading-relaxed min-h-[190px]"
            />

            <div className="flex items-center gap-2">
              {generationPhase === 'generating' || generationPhase === 'downloading' ? (
                <button
                  type="button"
                  onClick={handleStopGeneration}
                  className="w-full py-3 rounded-2xl bg-rose-500 hover:bg-rose-600 text-white font-mono font-bold text-xs flex items-center justify-center gap-2 shadow-sm transition-all cursor-pointer"
                >
                  <Square className="w-4 h-4 fill-white" />
                  <span>Interrupt Generation</span>
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => executeGeneration(customPrompt)}
                  disabled={hasWebGpu === false}
                  className="w-full py-3 rounded-2xl bg-signal hover:bg-signal-hover disabled:opacity-50 text-white font-mono font-bold text-xs flex items-center justify-center gap-2 shadow-sm transition-all hover:scale-[1.01] cursor-pointer"
                >
                  <Play className="w-4 h-4 fill-white" />
                  <span>
                    {activeStudio === 'svg' && 'Synthesize SVG Asset'}
                    {activeStudio === 'games' && 'Launch Playable Game'}
                    {activeStudio === 'website' && 'Build Website Component'}
                  </span>
                </button>
              )}
            </div>
          </div>
        </div>

        {/* RIGHT MAIN AREA: Sandbox Viewport with Gate Telemetry & Viewport Switcher */}
        <div className="lg:col-span-7 xl:col-span-8 flex flex-col gap-3">
          {/* Sandbox Top Bar */}
          <div className="p-3.5 rounded-2xl bg-surface border border-line flex flex-wrap items-center justify-between gap-3 font-mono text-xs">
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
                {generationPhase === 'generating' && 'Synthesizing in WebGPU...'}
                {generationPhase === 'downloading' && 'Loading Model Weights into Cache...'}
                {generationPhase === 'completed' && (
                  activeStudio === 'svg'
                    ? 'SVG Studio Viewport (320x320)'
                    : activeStudio === 'games'
                    ? 'Toys & Games Interactive Sandbox'
                    : 'Websites & UI Responsive Frame'
                )}
                {generationPhase === 'error' && 'Sandbox Error'}
                {generationPhase === 'idle' && (
                  activeStudio === 'svg' ? 'SVG Studio Viewport' : activeStudio === 'games' ? 'Games Sandbox' : 'Website Frame'
                )}
              </span>
            </div>

            <div className="flex items-center gap-2 flex-wrap">
              {/* Responsive Viewport Switcher for Website Studio */}
              {activeStudio === 'website' && (
                <div className="flex rounded-xl bg-surface-2 p-0.5 border border-line mr-2">
                  <button
                    type="button"
                    onClick={() => setViewportWidth('375px')}
                    title="Mobile 375px"
                    className={`p-1.5 rounded-lg transition-all cursor-pointer ${
                      viewportWidth === '375px' ? 'bg-signal text-white' : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    <Smartphone className="w-3.5 h-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => setViewportWidth('768px')}
                    title="Tablet 768px"
                    className={`p-1.5 rounded-lg transition-all cursor-pointer ${
                      viewportWidth === '768px' ? 'bg-signal text-white' : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    <Tablet className="w-3.5 h-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => setViewportWidth('100%')}
                    title="Desktop 100%"
                    className={`p-1.5 rounded-lg transition-all cursor-pointer ${
                      viewportWidth === '100%' ? 'bg-signal text-white' : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    <Monitor className="w-3.5 h-3.5" />
                  </button>
                </div>
              )}

              {/* Telemetry info */}
              {generationPhase === 'completed' && (
                <div className="hidden sm:flex items-center gap-2 text-[11px] text-ink-muted mr-1">
                  <span className="text-emerald-400 font-bold">{streamedTokens} tok</span>
                  <span>•</span>
                  <span>{tokPerSec} t/s</span>
                  <span>•</span>
                  <span>{generationLatencyMs}ms</span>
                </div>
              )}

              {/* Copy Code / Export Action */}
              <button
                type="button"
                onClick={handleCopyCode}
                title="Copy Source Code to Clipboard"
                disabled={!renderedCode.trim()}
                className="px-2.5 py-1.5 rounded-xl bg-surface-2 border border-line hover:border-line-hover disabled:opacity-30 text-ink-muted hover:text-ink transition-all flex items-center gap-1.5 cursor-pointer text-xs"
              >
                {isCopied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
                <span className="hidden xs:inline">{isCopied ? 'Copied' : 'Export'}</span>
              </button>

              <button
                type="button"
                onClick={() => setRenderKey(k => k + 1)}
                title="Reload Sandbox"
                disabled={!renderedCode.trim()}
                className="p-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover disabled:opacity-30 text-ink-muted hover:text-ink transition-all cursor-pointer"
              >
                <RotateCcw className="w-4 h-4" />
              </button>

              <button
                type="button"
                onClick={() => setFullScreen(!fullScreen)}
                title={fullScreen ? "Exit Fullscreen" : "Fullscreen Sandbox"}
                className="p-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover text-ink-muted hover:text-ink transition-all cursor-pointer"
              >
                {fullScreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
              </button>
            </div>
          </div>

          {/* Adaptive In-Browser Verification Gate Bar */}
          {gateResult && (
            <div className={`p-3 rounded-2xl border flex flex-wrap items-center justify-between gap-3 font-mono text-xs transition-all ${
              gateResult.allPassed
                ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-300'
                : 'bg-amber-500/10 border-amber-500/30 text-amber-300'
            }`}>
              <div className="flex items-center gap-3 flex-wrap">
                <span className="font-bold flex items-center gap-1">
                  {gateResult.allPassed ? (
                    <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                  ) : (
                    <XCircle className="w-4 h-4 text-amber-400" />
                  )}
                  <span>In-Browser Gate Suite ({gateResult.durationMs}ms):</span>
                </span>

                <div className="flex items-center gap-2 flex-wrap text-[11px]">
                  {gateResult.verdicts.map((v) => (
                    <span
                      key={v.gateNum}
                      className={`px-2 py-0.5 rounded-lg border font-semibold flex items-center gap-1 ${
                        v.passed
                          ? 'bg-emerald-500/15 border-emerald-500/30 text-emerald-300'
                          : 'bg-amber-500/20 border-amber-500/40 text-amber-300'
                      }`}
                      title={v.summary}
                    >
                      <span>G{v.gateNum}: {v.name}</span>
                      <span>{v.passed ? '✓' : '✗'}</span>
                    </span>
                  ))}
                </div>
              </div>

              {/* Self-Healing Trigger */}
              {gateResult.healingDirective && (
                <button
                  type="button"
                  onClick={() => handleRefine(gateResult.healingDirective)}
                  className="px-2.5 py-1 rounded-xl bg-amber-500 hover:bg-amber-600 text-neutral-950 font-bold text-xs flex items-center gap-1 cursor-pointer transition-all shadow-sm"
                >
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>Adaptive Self-Healing</span>
                </button>
              )}
            </div>
          )}

          {/* Download Progress Card */}
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
                  IndexedDB Cached
                </span>
              </div>
            </div>
          )}

          {/* Collapsible Reasoning Process Accordion */}
          {liveReasoning.trim() && (
            <div className="rounded-2xl bg-surface border border-line p-3 text-xs font-mono shadow-sm">
              <button
                type="button"
                onClick={() => setIsThinkingOpen(prev => !prev)}
                className="flex items-center justify-between w-full text-signal font-bold cursor-pointer"
              >
                <span className="flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>🧠 Reasoning Chain ({liveReasoning.length} chars)</span>
                </span>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-surface-2 text-ink-muted">
                  {isThinkingOpen ? '▲ Collapse' : '▼ Expand'}
                </span>
              </button>
              {isThinkingOpen && (
                <div className="mt-2.5 p-3 rounded-xl bg-surface-2 text-ink-muted text-[11px] whitespace-pre-wrap max-h-48 overflow-y-auto leading-relaxed border border-line">
                  {liveReasoning}
                </div>
              )}
            </div>
          )}

          {/* Sandbox Canvas Viewport */}
          <div className={`w-full rounded-3xl border border-line bg-neutral-950 overflow-hidden relative shadow-md transition-all flex items-center justify-center ${
            fullScreen ? 'fixed inset-4 z-50 h-[calc(100vh-2rem)]' : 'h-[580px]'
          }`}>
            {generationPhase === 'generating' ? (
              // 100% STEALTH SYNTHESIS SPINNER & TOKEN COUNTER (ZERO CODE DISPLAY)
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center gap-4 bg-neutral-950/95 font-mono">
                <div className="relative flex items-center justify-center">
                  <div className="w-16 h-16 rounded-full border-4 border-signal/20 border-t-signal animate-spin" />
                  <Sparkles className="w-6 h-6 text-signal absolute animate-pulse" />
                </div>

                <div className="flex flex-col gap-1">
                  <h4 className="text-sm font-bold text-ink tracking-wide">
                    Synthesizing in {activeStudio === 'svg' ? 'SVG Studio' : activeStudio === 'games' ? 'Games Studio' : 'Website Studio'}
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
                  type="button"
                  onClick={handleStopGeneration}
                  className="mt-2 px-4 py-2 rounded-xl bg-surface-2 border border-line hover:border-line-hover text-ink-muted hover:text-ink text-xs font-bold transition-all flex items-center gap-1.5 cursor-pointer"
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
                  <h4 className="text-sm font-bold text-rose-400">Sandbox Error</h4>
                  <p className="text-xs text-ink-muted mt-1 break-words">
                    {generationError || 'Failed to synthesize or run the requested prompt.'}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => executeGeneration(customPrompt)}
                  className="px-4 py-2 rounded-xl bg-signal text-white text-xs font-bold hover:bg-signal-hover transition-all cursor-pointer"
                >
                  Retry Generation
                </button>
              </div>
            ) : renderedCode.trim() ? (
              // COMPLETED: RENDERED SANDBOX
              isSvg ? (
                <div
                  key={renderKey}
                  className="w-full h-full flex flex-col items-center justify-center p-6 bg-gradient-to-br from-neutral-950 via-slate-950 to-neutral-900 overflow-hidden"
                >
                  <div
                    className="max-w-[340px] max-h-[340px] w-full aspect-square flex items-center justify-center drop-shadow-2xl [&>svg]:w-full [&>svg]:h-full [&>svg]:max-w-full [&>svg]:max-h-full transition-all"
                    dangerouslySetInnerHTML={{ __html: renderedCode.trim() }}
                  />
                </div>
              ) : (
                <div
                  className="h-full flex items-center justify-center transition-all duration-300"
                  style={{ width: activeStudio === 'website' ? viewportWidth : '100%' }}
                >
                  <iframe
                    key={renderKey}
                    ref={iframeRef}
                    srcDoc={prepareSandboxDocument(renderedCode)}
                    title="In-Browser WebGPU Sandbox Application"
                    sandbox="allow-scripts allow-modals"
                    className="w-full h-full border-0 bg-neutral-950 transition-all"
                  />
                </div>
              )
            ) : (
              // IDLE STATE
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center max-w-sm mx-auto gap-3 font-mono">
                <div className="w-12 h-12 rounded-2xl bg-surface border border-line flex items-center justify-center text-ink-muted">
                  <Sparkles className="w-6 h-6 text-signal" />
                </div>
                <span className="text-xs font-bold uppercase tracking-wider text-ink">
                  {activeStudio === 'svg' && 'SVG Studio Viewport'}
                  {activeStudio === 'games' && 'Games & Toys Sandbox'}
                  {activeStudio === 'website' && 'Websites & UI Frame'}
                </span>
                <p className="text-[11px] text-ink-muted leading-relaxed">
                  Select a template on the left or write a prompt, then click <b>Launch</b> to synthesize live with WebGPU on-device.
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
                placeholder={
                  activeStudio === 'svg'
                    ? "Refine vector asset (e.g., 'Make it more circular with gold border')..."
                    : activeStudio === 'games'
                    ? "Refine game (e.g., 'Add high score counter and faster movement')..."
                    : "Refine UI (e.g., 'Add quarterly billing switch and testimonials')..."
                }
                className="flex-1 bg-transparent text-xs font-mono text-ink placeholder:text-ink-muted focus:outline-none"
              />
              <button
                type="button"
                onClick={() => handleRefine()}
                disabled={!refinementPrompt.trim()}
                className="px-3 py-1.5 rounded-xl bg-signal text-white font-mono text-xs font-bold disabled:opacity-40 hover:bg-signal-hover transition-all cursor-pointer"
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
