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
    speedupVsJs: 18.2
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
            speedupVsJs: physicsResult.speedupVsJs
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
            AgentScript High-Scale Graph Reactor
          </h2>
          <p className="text-xs text-ink-muted mt-1">
            Simulating up to 1,000,000 nodes & edges via WebAssembly Linear Memory & WebGPU Compute Pipeline
          </p>
        </div>

        {/* Engine Mode Toggle */}
        <div className="flex items-center bg-surface-2 p-1 rounded-xl border border-line">
          <button
            onClick={() => setMode('javascript')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'javascript'
                ? 'bg-rose-500/20 text-rose-400 border border-rose-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            JavaScript (CPU)
          </button>
          <button
            onClick={() => setMode('webassembly')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'webassembly'
                ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            WebAssembly SIMD
          </button>
          <button
            onClick={() => setMode('webgpu')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              mode === 'webgpu'
                ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/40'
                : 'text-ink-muted hover:text-ink'
            }`}
          >
            WebGPU Pipeline
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
            onClick={() => setIsPaused(!isPaused)}
            className="ml-2 px-3 py-1 text-xs font-semibold rounded-lg border border-line bg-surface-2 hover:bg-surface text-ink"
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

      {/* Canvas Viewport */}
      <div className="relative w-full h-[520px] bg-black/40 rounded-xl border border-line overflow-hidden">
        <canvas
          ref={canvasRef}
          width={1200}
          height={600}
          className="w-full h-full object-cover"
        />

        {/* Live overlay watermark */}
        <div className="absolute bottom-3 left-3 bg-black/70 backdrop-blur-md px-3 py-1.5 rounded-lg border border-white/10 text-xs font-mono text-white/80 flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${
            mode === 'webgpu' ? 'bg-cyan-400' : mode === 'webassembly' ? 'bg-emerald-400' : 'bg-rose-400'
          }`}></span>
          <span>Active Engine: {mode.toUpperCase()}</span>
          <span className="text-white/40">|</span>
          <span>{metrics.nodeCount.toLocaleString()} Nodes</span>
          <span className="text-white/40">|</span>
          <span>{metrics.edgeCount.toLocaleString()} Edges</span>
        </div>
      </div>
    </div>
  );
};

export default GraphCanvas;
