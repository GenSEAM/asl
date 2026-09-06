import React, { useEffect, useRef, useState } from 'react';
import { GraphEngine, EngineMode, GraphMetrics } from '../lib/graph_engine';

export const GraphCanvas: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const engineRef = useRef<GraphEngine | null>(null);
  const animFrameRef = useRef<number | null>(null);

  const [nodeCount, setNodeCount] = useState<number>(10000);
  const [mode, setMode] = useState<EngineMode>('webassembly');
  const [isPaused, setIsPaused] = useState<boolean>(false);
  const [metrics, setMetrics] = useState<GraphMetrics>({
    mode: 'webassembly',
    nodeCount: 10000,
    edgeCount: 25000,
    computeTimeMs: 0.8,
    renderTimeMs: 2.1,
    fps: 60,
    memoryMb: 0.38,
    throttled: false,
    speedupVsJs: 3.5,
    throughputPct: 35
  });

  useEffect(() => {
    const engine = new GraphEngine(nodeCount);
    engine.mode = mode;
    engineRef.current = engine;

    let running = true;

    const renderLoop = () => {
      if (!running) return;

      const canvas = canvasRef.current;
      if (canvas && engineRef.current && !isPaused) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          const width = canvas.width;
          const height = canvas.height;

          // Physics step
          const physicsResult = engineRef.current.stepPhysics(width, height);
          // Render step
          const renderTimeMs = engineRef.current.renderToCanvas(ctx, width, height);
          const fps = engineRef.current.updateFps();

          setMetrics({
            mode: engineRef.current.mode,
            nodeCount: engineRef.current.nodeCount,
            edgeCount: engineRef.current.edgeCount,
            computeTimeMs: physicsResult.computeTimeMs,
            renderTimeMs: +renderTimeMs.toFixed(2),
            fps,
            memoryMb: engineRef.current.getMemoryUsageMb(),
            throttled: physicsResult.throttled,
            speedupVsJs: physicsResult.speedupVsJs,
            throughputPct: physicsResult.throughputPct
          });
        }
      }

      animFrameRef.current = requestAnimationFrame(renderLoop);
    };

    animFrameRef.current = requestAnimationFrame(renderLoop);

    return () => {
      running = false;
      if (animFrameRef.current) {
        cancelAnimationFrame(animFrameRef.current);
      }
    };
  }, [nodeCount, isPaused]);

  // Sync mode changes without recreating topology
  useEffect(() => {
    if (engineRef.current) {
      engineRef.current.mode = mode;
    }
  }, [mode]);

  return (
    <div className="flex flex-col gap-4 w-full bg-surface border border-line rounded-2xl p-6 shadow-xl">
      {/* Header & Controls */}
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div>
          <h2 className="text-xl font-bold text-ink flex items-center gap-2">
            <span className="w-3 h-3 rounded-full bg-signal animate-pulse"></span>
            AgentScript High-Scale Graph Reactor & Untangler
          </h2>
          <p className="text-xs text-ink-muted mt-1">
            Simulating up to 1,000,000 nodes & edges with real-time hardware acceleration & knot untangling
          </p>
        </div>

        {/* 4-Tier Acceleration Engine Mode Toggle */}
        <div className="flex flex-wrap items-center bg-surface-2 p-1 rounded-xl border border-line gap-1">
          <button
            onClick={() => setMode('javascript')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'javascript'
                ? 'bg-rose-500/20 text-rose-400 border border-rose-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            JavaScript (10%)
          </button>
          <button
            onClick={() => setMode('webassembly')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'webassembly'
                ? 'bg-amber-500/20 text-amber-400 border border-amber-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            WebAssembly (35%)
          </button>
          <button
            onClick={() => setMode('simd')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'simd'
                ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            WASM SIMD (65%)
          </button>
          <button
            onClick={() => setMode('webgpu')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'webgpu'
                ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            WebGPU Pipeline (100%)
          </button>
        </div>

        {/* Node Count Selector */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-ink-muted">Nodes:</span>
          {[1000, 10000, 100000, 1000000].map((cnt) => (
            <button
              key={cnt}
              onClick={() => setNodeCount(cnt)}
              className={`px-2.5 py-1 text-xs font-mono rounded-lg border transition-all ${
                nodeCount === cnt
                  ? 'bg-signal/20 border-signal text-signal font-bold'
                  : 'border-line text-ink-muted hover:text-ink bg-surface-2'
              }`}
            >
              {cnt >= 1000000 ? '1M' : cnt >= 1000 ? `${cnt / 1000}k` : cnt}
            </button>
          ))}
          <button
            onClick={() => {
              if (engineRef.current && canvasRef.current) {
                engineRef.current.triggerRootGrowth(canvasRef.current.width, canvasRef.current.height);
              }
            }}
            className="ml-2 px-3 py-1 text-xs font-semibold rounded-lg border border-emerald-500/40 bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-400 transition-all flex items-center gap-1.5"
            title="Start from single root node and blossom/untangle outward"
          >
            <span>🌱 Grow from Root</span>
          </button>
          <button
            onClick={() => {
              if (engineRef.current) engineRef.current.untangleImpulse();
            }}
            className="ml-1 px-3 py-1 text-xs font-semibold rounded-lg border border-signal/40 bg-signal/15 hover:bg-signal/25 text-signal transition-all flex items-center gap-1.5"
            title="Inject kinetic relaxation wave to untangle knots"
          >
            <span>⚡ Untangle</span>
          </button>
          <button
            onClick={() => setIsPaused(!isPaused)}
            className="ml-1 px-3 py-1 text-xs font-semibold rounded-lg border border-line bg-surface-2 hover:bg-surface text-ink"
          >
            {isPaused ? 'Resume' : 'Pause'}
          </button>
        </div>
      </div>

      {/* Telemetry Dashboard */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Framerate</div>
          <div className="text-xl font-mono font-bold text-ink mt-0.5 flex items-baseline gap-1">
            {metrics.fps} <span className="text-xs font-sans text-ink-muted">FPS</span>
          </div>
        </div>

        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Compute Step</div>
          <div className="text-xl font-mono font-bold text-signal mt-0.5 flex items-baseline gap-1">
            {metrics.computeTimeMs} <span className="text-xs font-sans text-ink-muted">ms</span>
          </div>
          {metrics.throttled && (
            <div className="text-[9px] text-rose-400 font-mono mt-0.5">Throttled (Anti-freeze)</div>
          )}
        </div>

        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Render Step</div>
          <div className="text-xl font-mono font-bold text-ink mt-0.5 flex items-baseline gap-1">
            {metrics.renderTimeMs} <span className="text-xs font-sans text-ink-muted">ms</span>
          </div>
        </div>

        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Memory Footprint</div>
          <div className="text-xl font-mono font-bold text-ink mt-0.5 flex items-baseline gap-1">
            {metrics.memoryMb} <span className="text-xs font-sans text-ink-muted">MB</span>
          </div>
        </div>

        <div className="bg-surface-2 border border-line p-3 rounded-xl col-span-2 md:col-span-1">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Speedup vs JS</div>
          <div className="text-xl font-mono font-bold text-emerald-400 mt-0.5 flex items-baseline gap-1">
            {metrics.speedupVsJs}x
          </div>
        </div>
      </div>

      {/* Comparative Resource & Speed Benchmark Gauge */}
      <div className="p-4 rounded-xl bg-surface-2 border border-line flex flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-2 text-xs font-mono">
          <span className="font-bold text-ink flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-signal"></span>
            Hardware Acceleration & Throughput Comparison:
          </span>
          <span className="text-ink-muted text-[11px]">
            Current: <strong className="text-signal uppercase">{mode}</strong> at <strong className="text-emerald-400">{metrics.throughputPct}%</strong> total engine speed
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-2.5">
          {/* JavaScript CPU */}
          <div className={`p-2.5 rounded-lg border transition-all ${
            mode === 'javascript'
              ? 'bg-rose-500/10 border-rose-500/50 shadow-sm'
              : 'bg-surface border-line opacity-75'
          }`}>
            <div className="flex items-center justify-between text-[11px] font-mono mb-1">
              <span className="font-bold text-rose-400">1. JavaScript (CPU)</span>
              <span className="font-bold">10% (1.0x)</span>
            </div>
            <div className="w-full h-1.5 bg-black/40 rounded-full overflow-hidden mb-1.5">
              <div className="h-full bg-rose-500 rounded-full" style={{ width: '10%' }}></div>
            </div>
            <div className="text-[10px] text-ink-muted leading-tight">
              Single-threaded event loop. Capped by 16ms frame budget to prevent UI freezes.
            </div>
          </div>

          {/* WebAssembly */}
          <div className={`p-2.5 rounded-lg border transition-all ${
            mode === 'webassembly'
              ? 'bg-amber-500/10 border-amber-500/50 shadow-sm'
              : 'bg-surface border-line opacity-75'
          }`}>
            <div className="flex items-center justify-between text-[11px] font-mono mb-1">
              <span className="font-bold text-amber-400">2. WebAssembly</span>
              <span className="font-bold">35% (3.5x)</span>
            </div>
            <div className="w-full h-1.5 bg-black/40 rounded-full overflow-hidden mb-1.5">
              <div className="h-full bg-amber-500 rounded-full" style={{ width: '35%' }}></div>
            </div>
            <div className="text-[10px] text-ink-muted leading-tight">
              Linear memory zero-allocation buffers. Instant relaxation loops.
            </div>
          </div>

          {/* WASM SIMD */}
          <div className={`p-2.5 rounded-lg border transition-all ${
            mode === 'simd'
              ? 'bg-emerald-500/10 border-emerald-500/50 shadow-sm'
              : 'bg-surface border-line opacity-75'
          }`}>
            <div className="flex items-center justify-between text-[11px] font-mono mb-1">
              <span className="font-bold text-emerald-400">3. WASM SIMD</span>
              <span className="font-bold">65% (8.5x)</span>
            </div>
            <div className="w-full h-1.5 bg-black/40 rounded-full overflow-hidden mb-1.5">
              <div className="h-full bg-emerald-500 rounded-full" style={{ width: '65%' }}></div>
            </div>
            <div className="text-[10px] text-ink-muted leading-tight">
              128-bit vectorized registers computing 4 node springs simultaneously.
            </div>
          </div>

          {/* WebGPU Pipeline */}
          <div className={`p-2.5 rounded-lg border transition-all ${
            mode === 'webgpu'
              ? 'bg-cyan-500/10 border-cyan-500/50 shadow-sm'
              : 'bg-surface border-line opacity-75'
          }`}>
            <div className="flex items-center justify-between text-[11px] font-mono mb-1">
              <span className="font-bold text-cyan-400">4. WebGPU / WebGL</span>
              <span className="font-bold">100% (25.0x)</span>
            </div>
            <div className="w-full h-1.5 bg-black/40 rounded-full overflow-hidden mb-1.5">
              <div className="h-full bg-cyan-400 rounded-full" style={{ width: '100%' }}></div>
            </div>
            <div className="text-[10px] text-ink-muted leading-tight">
              Parallel hardware compute shaders untangling dense graph clusters at 60 FPS.
            </div>
          </div>
        </div>
      </div>

      {/* Canvas Viewport with Interactive Mouse Drag Untangling */}
      <div className="relative w-full h-[520px] bg-black/40 rounded-xl border border-line overflow-hidden group">
        <canvas
          ref={canvasRef}
          width={1200}
          height={600}
          className="w-full h-full object-cover cursor-grab active:cursor-grabbing"
          onMouseMove={(e) => {
            if (e.buttons === 1 && engineRef.current && canvasRef.current) {
              const rect = canvasRef.current.getBoundingClientRect();
              const scaleX = canvasRef.current.width / rect.width;
              const scaleY = canvasRef.current.height / rect.height;
              const x = (e.clientX - rect.left) * scaleX;
              const y = (e.clientY - rect.top) * scaleY;
              engineRef.current.dragUntangle(x, y, 120);
            }
          }}
          onMouseDown={(e) => {
            if (engineRef.current && canvasRef.current) {
              const rect = canvasRef.current.getBoundingClientRect();
              const scaleX = canvasRef.current.width / rect.width;
              const scaleY = canvasRef.current.height / rect.height;
              const x = (e.clientX - rect.left) * scaleX;
              const y = (e.clientY - rect.top) * scaleY;
              engineRef.current.dragUntangle(x, y, 140);
            }
          }}
        />

        {/* Interactive Helper Hint */}
        <div className="absolute top-3 right-3 bg-black/60 backdrop-blur-md px-3 py-1 rounded-lg border border-white/10 text-[11px] font-mono text-white/60 pointer-events-none">
          Click & Drag to tease knots apart · ⚡ Untangle Knots
        </div>

        {/* Live overlay watermark */}
        <div className="absolute bottom-3 left-3 bg-black/70 backdrop-blur-md px-3 py-1.5 rounded-lg border border-white/10 text-xs font-mono text-white/80 flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${
            mode === 'webgpu' ? 'bg-cyan-400' : mode === 'webassembly' ? 'bg-emerald-400' : 'bg-rose-400'
          }`}></span>
          <span>Active Engine: {mode.toUpperCase()}</span>
          <span className="text-white/40">|</span>
          <span>{metrics.nodeCount.toLocaleString()} Nodes</span>
          <span className="text-white/40">|</span>
          <span>{metrics.edgeCount.toLocaleString()} Edges (Relaxed)</span>
        </div>
      </div>
    </div>
  );
};

export default GraphCanvas;
