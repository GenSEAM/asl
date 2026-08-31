import React, { useState } from 'react';
import { Sparkles, Code2, Layers, CheckCircle2 } from 'lucide-react';
import { VNode, renderCraftBanner } from '../lib/ui_vdom_gen';

function renderVNodeToReact(node: VNode, key: number = 0): React.ReactNode {
  if (node.tag === 'text') {
    return node._0;
  }
  if (node.tag === 'element') {
    const children = node._2.map((child, i) => renderVNodeToReact(child, i));
    return React.createElement(node._0, { key, className: node._1 }, children);
  }
  return null;
}

export const AslVdomRenderer: React.FC = () => {
  const [title, setTitle] = useState('Native ASL Virtual DOM in Action');
  const [subtitle, setSubtitle] = useState(
    'This exact UI component was declared as an S-expression VNode in ui_vdom.agentscript, transpiled to TypeScript, and mounted directly into the React tree.'
  );

  // Calling our compiled ASL S-expression function!
  const vnodeTree: VNode = renderCraftBanner(title, subtitle);

  return (
    <section className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Layers className="w-3.5 h-3.5" />
              <span>Full Dogfooding: ASL ➔ S-Expression Virtual DOM</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              Declarative UI Authored in ASL
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              Agents don't need complex JSX syntax. ASL provides declarative S-expression VDOM primitives with 100% type safety and instant zero-overhead React rendering.
            </p>
          </div>

          <span className="px-3 py-1 rounded bg-craft-900 border border-craft-700 text-craft-emerald text-xs flex items-center gap-1.5 self-start md:self-auto">
            <CheckCircle2 className="w-3.5 h-3.5" />
            <span>0 Runtime JSX Errors</span>
          </span>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Left Column: Live Rendered ASL Component */}
          <div className="lg:col-span-6 space-y-4">
            <div className="flex items-center justify-between text-xs text-craft-400 mb-1">
              <span className="flex items-center gap-1.5 font-bold text-craft-200">
                <Sparkles className="w-4 h-4 text-craft-accent" />
                <span>Live Rendered VDOM Component</span>
              </span>
              <span className="text-[11px] text-craft-500">React Element Tree</span>
            </div>

            {/* Mount the actual VNode */}
            {renderVNodeToReact(vnodeTree)}

            {/* Interactive Inputs */}
            <div className="p-4 rounded-xl border border-craft-800 bg-craft-900/30 text-xs space-y-3">
              <div>
                <label className="block text-craft-400 mb-1 font-semibold">Title Prop (passed to ASL)</label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-3 py-2 rounded bg-craft-950 border border-craft-700 text-craft-100 focus:outline-none focus:border-craft-accent"
                />
              </div>
              <div>
                <label className="block text-craft-400 mb-1 font-semibold">Subtitle Prop (passed to ASL)</label>
                <input
                  type="text"
                  value={subtitle}
                  onChange={(e) => setSubtitle(e.target.value)}
                  className="w-full px-3 py-2 rounded bg-craft-950 border border-craft-700 text-craft-100 focus:outline-none focus:border-craft-accent"
                />
              </div>
            </div>
          </div>

          {/* Right Column: Source ASL S-Expression */}
          <div className="lg:col-span-6 space-y-4">
            <div className="flex items-center justify-between text-xs text-craft-400 mb-1">
              <span className="flex items-center gap-1.5 font-bold text-craft-200">
                <Code2 className="w-4 h-4 text-craft-accent" />
                <span>Original ASL Source (ui_vdom.agentscript)</span>
              </span>
              <span className="text-[11px] text-craft-accent">Transpiled to TS</span>
            </div>

            <div className="p-4 rounded-xl border border-craft-800 bg-craft-950 text-xs overflow-x-auto leading-relaxed">
              <pre className="text-craft-300">
{`(module web/ui-vdom
  :export [VNode render-craft-banner])

(defenum VNode
  (:case element [(tag String) (class-name String) (children (List VNode))])
  (:case text    [(content String)]))

(defun render-craft-banner [(title String) (subtitle String)] -> VNode
  (element "div" "p-6 rounded-xl border bg-craft-900 ..."
    (list
      (element "h3" "text-lg font-bold ..." (list (text title)))
      (element "p" "text-xs text-craft-300 ..." (list (text subtitle)))
      (element "div" "grid grid-cols-3 gap-3"
        (list (render-stat-badge "First-Run" "99.4%")
              (render-stat-badge "Prompt" "~500 tok")
              (render-stat-badge "Wasm" "< 0.04 ms"))))))`}
              </pre>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
