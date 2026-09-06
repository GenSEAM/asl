import React, { useState } from 'react';
import { transpile } from '../utils/transpile';
import { Layers, Check, Copy } from 'lucide-react';

const DEFAULT_ASL_EXAMPLE = `(div (:class "p-6 rounded-2xl bg-surface border border-line shadow-lg")
  (div (:class "flex items-center gap-3 mb-4")
    (span (:class "w-3 h-3 rounded-full bg-signal") "")
    (h2 (:class "text-xl font-bold text-ink") "AgentScript Polyglot VNode"))
  (p (:class "text-sm text-ink-muted mb-6 leading-relaxed")
    "Single declarative AST compiled natively across modern web targets.")
  (button (:class "px-4 py-2 rounded-xl bg-signal text-ground font-semibold" :onclick "handleAction")
    "Execute Action"))`;

export const PolyglotStudio: React.FC = () => {
  const [aslCode, setAslCode] = useState<string>(DEFAULT_ASL_EXAMPLE);
  const [activeTab, setActiveTab] = useState<'react' | 'vue' | 'svelte' | 'html'>('react');
  const [copied, setCopied] = useState<boolean>(false);

  const getGeneratedCode = () => {
    try {
      return transpile(
        {
          name: 'PolyglotCard',
          propsType: 'PolyglotCardProps',
          props: [{ name: 'title', type: 'string' }],
          state: [{ name: 'isActive', type: 'boolean', initial: false }],
          handlers: {
            handleAction: 'setIsActive(!isActive);'
          },
          root: aslCode
        },
        activeTab
      );
    } catch (err: any) {
      return `// Compilation error: ${err.message}`;
    }
  };

  const outputCode = getGeneratedCode();

  const handleCopy = () => {
    navigator.clipboard.writeText(outputCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="w-full flex flex-col gap-6 bg-surface border border-line rounded-2xl p-6 shadow-xl">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div>
          <h3 className="text-lg font-bold text-ink flex items-center gap-2">
            <Layers className="w-5 h-5 text-signal" />
            Universal Polyglot UI Transpiler Studio
          </h3>
          <p className="text-xs text-ink-muted mt-1">
            Write declarative AgentScript once — compile directly to React 19, Vue 3, Svelte 5, or zero-overhead SSR HTML.
          </p>
        </div>

        {/* Framework Target Tabs */}
        <div className="flex items-center bg-surface-2 p-1 rounded-xl border border-line">
          {(['react', 'vue', 'svelte', 'html'] as const).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-all capitalize ${
                activeTab === tab
                  ? 'bg-signal text-ground font-bold shadow-sm'
                  : 'text-ink-muted hover:text-ink'
              }`}
            >
              {tab === 'react' ? 'React 19 (TSX)' : tab === 'vue' ? 'Vue 3 (SFC)' : tab === 'svelte' ? 'Svelte 5 (Runes)' : 'SSR HTML'}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Source Input */}
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between text-xs font-mono text-ink-muted px-1">
            <span>Declarative ASL Source</span>
            <span className="text-[10px] bg-signal/10 text-signal px-2 py-0.5 rounded border border-signal/20">AgentScript VNode</span>
          </div>
          <textarea
            value={aslCode}
            onChange={(e) => setAslCode(e.target.value)}
            className="w-full h-80 bg-black/80 border border-line/80 rounded-xl p-4 font-mono text-xs text-purple-200 leading-relaxed resize-none focus:outline-none focus:border-signal/70 focus:ring-1 focus:ring-signal/30 selection:bg-signal/40 shadow-inner"
            spellCheck={false}
          />
        </div>

        {/* Transpiled Output */}
        <div className="flex flex-col gap-2 relative">
          <div className="flex items-center justify-between text-xs font-mono text-ink-muted px-1">
            <span>Target Output: {activeTab.toUpperCase()}</span>
            <button
              onClick={handleCopy}
              className="flex items-center gap-1 text-[11px] text-ink hover:text-signal transition-colors bg-surface-2 px-2 py-0.5 rounded border border-line"
            >
              {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          <pre className="w-full h-80 bg-black/80 border border-line/80 rounded-xl p-4 font-mono text-xs text-emerald-400/95 leading-relaxed overflow-auto shadow-inner">
            <code>{outputCode}</code>
          </pre>
        </div>
      </div>
    </div>
  );
};

export default PolyglotStudio;
