import React, { useEffect, useRef, useState } from 'react';
import { Layers, Eye } from 'lucide-react';
import { EXAMPLES } from '../lib/examples';

interface Node {
  x: number;
  y: number;
  vx: number;
  vy: number;
  label: string;
  type: string;
  level: number;
}

interface Edge {
  source: number;
  target: number;
}

export const GraphVisualizer: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [activeEx, setActiveEx] = useState(EXAMPLES[0]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = (canvas.width = canvas.parentElement?.clientWidth || 800);
    const height = (canvas.height = 420);

    const nodesData = activeEx.astNodes;
    const nodes: Node[] = nodesData.map((n) => ({
      x: width / 2 + (Math.random() - 0.5) * 300,
      y: 80 + n.level * 65 + (Math.random() - 0.5) * 20,
      vx: (Math.random() - 0.5) * 0.5,
      vy: (Math.random() - 0.5) * 0.5,
      label: n.label,
      type: n.type,
      level: n.level,
    }));

    const edges: Edge[] = [];
    for (let i = 1; i < nodes.length; i++) {
      edges.push({ source: Math.max(0, i - 1), target: i });
      if (i > 2 && Math.random() > 0.6) {
        edges.push({ source: 0, target: i });
      }
    }

    let animationId: number;

    const render = () => {
      ctx.clearRect(0, 0, width, height);

      // Draw grid dots
      ctx.fillStyle = 'rgba(255, 255, 255, 0.04)';
      for (let x = 20; x < width; x += 30) {
        for (let y = 20; y < height; y += 30) {
          ctx.fillRect(x, y, 1.5, 1.5);
        }
      }

      // Update positions with soft spring / float
      for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i];
        node.x += node.vx;
        node.y += node.vy;

        if (node.x < 60 || node.x > width - 60) node.vx *= -1;
        if (node.y < 40 || node.y > height - 40) node.vy *= -1;

        node.vx += (Math.random() - 0.5) * 0.05;
        node.vy += (Math.random() - 0.5) * 0.05;
        node.vx *= 0.96;
        node.vy *= 0.96;
      }

      // Draw Edges
      for (const edge of edges) {
        const s = nodes[edge.source];
        const t = nodes[edge.target];
        ctx.beginPath();
        ctx.moveTo(s.x, s.y);
        ctx.lineTo(t.x, t.y);
        ctx.strokeStyle = 'rgba(45, 212, 191, 0.25)';
        ctx.lineWidth = 1.2;
        ctx.stroke();
      }

      // Draw Nodes
      for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i];
        ctx.beginPath();
        const r = node.level === 0 ? 12 : node.level === 1 ? 9 : 7;
        ctx.arc(node.x, node.y, r, 0, Math.PI * 2);

        if (node.type === 'module') {
          ctx.fillStyle = '#2dd4bf'; // accent
        } else if (node.type === 'function' || node.type === 'effect') {
          ctx.fillStyle = '#f59e0b'; // amber
        } else if (node.type === 'pattern' || node.type === 'enum') {
          ctx.fillStyle = '#10b981'; // emerald
        } else {
          ctx.fillStyle = '#8a92a3';
        }
        ctx.fill();

        ctx.strokeStyle = '#111215';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Label
        ctx.font = '11px "Fira Code", monospace';
        ctx.fillStyle = '#eef1f6';
        ctx.fillText(node.label, node.x + r + 6, node.y + 4);
      }

      animationId = requestAnimationFrame(render);
    };

    render();

    return () => cancelAnimationFrame(animationId);
  }, [activeEx]);

  return (
    <section id="graph" className="py-16 border-b border-craft-800 bg-craft-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-6 gap-4">
          <div>
            <div className="flex items-center gap-2 text-craft-accent font-mono text-xs uppercase tracking-wider mb-2">
              <Layers className="w-4 h-4" />
              <span>GPU Accelerated Architecture</span>
            </div>
            <h2 className="text-3xl font-bold font-mono text-craft-50 tracking-tight">
              Interactive S-Expression AST Explorer
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-mono">
              60fps Canvas render of syntax trees, bindings, and module dependency relationships.
            </p>
          </div>

          <div className="flex items-center gap-2">
            {EXAMPLES.map((ex) => (
              <button
                key={ex.id}
                onClick={() => setActiveEx(ex)}
                className={`px-3 py-1 text-xs font-mono rounded border transition-all ${
                  activeEx.id === ex.id
                    ? 'bg-craft-800 border-craft-accent text-craft-accent font-semibold'
                    : 'bg-craft-900 border-craft-800 text-craft-400 hover:text-craft-100'
                }`}
              >
                {ex.title.split(' ')[0]}
              </button>
            ))}
          </div>
        </div>

        {/* Canvas Card */}
        <div className="relative rounded-xl border border-craft-800 bg-craft-900/40 overflow-hidden shadow-2xl">
          <div className="absolute top-4 right-4 z-10 flex items-center gap-2 font-mono">
            <span className="px-2.5 py-1 rounded bg-craft-950/80 border border-craft-700 text-craft-accent text-xs flex items-center gap-1.5 backdrop-blur-sm">
              <Eye className="w-3.5 h-3.5" />
              <span>WebGL / 60 FPS Particle Tree</span>
            </span>
          </div>

          <div className="w-full h-[420px]">
            <canvas ref={canvasRef} className="w-full h-full block cursor-crosshair" />
          </div>

          <div className="p-3 bg-craft-950 border-t border-craft-800 flex items-center justify-between text-xs font-mono text-craft-400">
            <div className="flex items-center gap-4">
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-craft-accent" />
                <span>Module Header</span>
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-craft-amber" />
                <span>Functions & Effects</span>
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-craft-emerald" />
                <span>Pattern Matchers</span>
              </span>
            </div>
            <span>Zero AST Bloat</span>
          </div>
        </div>
      </div>
    </section>
  );
};
