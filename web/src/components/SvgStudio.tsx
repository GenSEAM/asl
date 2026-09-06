import React, { useState, useMemo } from 'react';
import { asnToSvg } from '../utils/asn_svg';
import { Download, Copy, Check, Sparkles, Code2, Eye } from 'lucide-react';

const PRESETS: Record<string, { label: string; asn: string }> = {
  logo: {
    label: 'Eddie Agentic Logo',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#090d16" :r 24)
  (:circ :cx 300 :cy 180 :r 110 :f "none" :s "rgba(56, 239, 125, 0.2)" :sw 2)
  (:circ :cx 300 :cy 180 :r 85 :f "rgba(16, 185, 129, 0.08)" :s "#10b981" :sw 3)
  (:p :d "M 250 150 L 300 210 L 350 150 Z" :f "none" :s "#38ef7d" :sw 4)
  (:circ :cx 300 :cy 150 :r 14 :f "#00f2fe" :s "#ffffff" :sw 2)
  (:ln :x1 180 :y1 180 :x2 240 :y2 180 :s "#38ef7d" :sw 2)
  (:ln :x1 360 :y1 180 :x2 420 :y2 180 :s "#38ef7d" :sw 2)
  (:txt :x 215 :y 290 :text "EDDIE AUTONOMOUS AGENT" :f "#38ef7d" :sz 13 :weight "bold")
  (:txt :x 250 :y 315 :text "AgentScript Vector Engine" :f "rgba(255,255,255,0.4)" :sz 10)
)`
  },
  topology: {
    label: 'Swarm Mesh Topology',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#070a12" :r 20)
  (:ln :x1 140 :y1 180 :x2 300 :y2 100 :s "rgba(0, 242, 254, 0.4)" :sw 2)
  (:ln :x1 140 :y1 180 :x2 300 :y2 260 :s "rgba(0, 242, 254, 0.4)" :sw 2)
  (:ln :x1 300 :y1 100 :x2 460 :y2 180 :s "rgba(56, 239, 125, 0.4)" :sw 2)
  (:ln :x1 300 :y1 260 :x2 460 :y2 180 :s "rgba(56, 239, 125, 0.4)" :sw 2)
  (:ln :x1 300 :y1 100 :x2 300 :y2 260 :s "rgba(255, 107, 107, 0.3)" :sw 1.5)
  (:rc :x 90 :y 150 :w 100 :h 60 :f "#0f172a" :r 12 :s "#00f2fe" :sw 2)
  (:txt :x 105 :y 185 :text "Coordinator" :f "#00f2fe" :sz 12 :weight "bold")
  (:rc :x 250 :y 70 :w 100 :h 60 :f "#0f172a" :r 12 :s "#38ef7d" :sw 2)
  (:txt :x 270 :y 105 :text "Worker A" :f "#38ef7d" :sz 12 :weight "bold")
  (:rc :x 250 :y 230 :w 100 :h 60 :f "#0f172a" :r 12 :s "#38ef7d" :sw 2)
  (:txt :x 270 :y 265 :text "Worker B" :f "#38ef7d" :sz 12 :weight "bold")
  (:rc :x 410 :y 150 :w 100 :h 60 :f "#0f172a" :r 12 :s "#a855f7" :sw 2)
  (:txt :x 430 :y 185 :text "Evaluator" :f "#a855f7" :sz 12 :weight "bold")
)`
  },
  arcade: {
    label: 'Retro Game Vector Sprite',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#0d0914" :r 20)
  (:g :transform "translate(150, 60)"
    (:rc :x 60 :y 40 :w 180 :h 140 :f "#4f46e5" :r 16 :s "#818cf8" :sw 3)
    (:circ :cx 110 :cy 100 :r 22 :f "#f43f5e" :s "#ffffff" :sw 2)
    (:circ :cx 190 :cy 100 :r 22 :f "#10b981" :s "#ffffff" :sw 2)
    (:rc :x 130 :y 135 :w 40 :h 20 :f "#fbbf24" :r 6)
    (:p :d "M 150 10 L 150 40" :s "#818cf8" :sw 6)
    (:circ :cx 150 :cy 8 :r 10 :f "#ef4444")
    (:txt :x 75 :y 215 :text "AGENT BOT SPRITE" :f "#818cf8" :sz 14 :weight "bold")
  )
)`
  }
};

const MODELS = [
  { id: 'eddie-webgpu', name: 'Eddie-SLM-3B (Local WebGPU)' },
  { id: 'gemma-wasm', name: 'Gemma-2-2B (Wasm SIMD)' },
  { id: 'qwen-coder', name: 'Qwen2.5-Coder-3B (In-Browser)' },
  { id: 'eddie-cloud', name: 'Eddie-Cloud-Pro (API)' }
];

const PROMPT_SUGGESTIONS = [
  {
    label: '🛡️ Security Shield',
    prompt: 'Draw a glowing agentic cyber security shield with lock core',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#070b14" :r 20)
  (:p :d "M 300 80 L 400 120 L 390 230 Q 300 290 300 290 Q 210 230 200 120 Z" :f "rgba(16, 185, 129, 0.15)" :s "#10b981" :sw 4)
  (:p :d "M 300 110 L 370 140 L 360 215 Q 300 260 300 260 Q 240 215 230 140 Z" :f "rgba(6, 182, 212, 0.12)" :s "#06b6d4" :sw 2)
  (:circ :cx 300 :cy 185 :r 22 :f "#0f172a" :s "#38ef7d" :sw 3)
  (:rc :x 293 :y 180 :w 14 :h 18 :f "#38ef7d" :r 3)
  (:txt :x 220 :y 325 :text "VERIFIED HARNESS SHIELD" :f "#10b981" :sz 13 :weight "bold")
)`
  },
  {
    label: '🚀 Space Rocket',
    prompt: 'Draw a sleek vector space shuttle rocket launching with flames',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#080914" :r 20)
  (:p :d "M 300 60 Q 340 120 340 220 L 260 220 Q 260 120 300 60 Z" :f "#1e293b" :s "#38ef7d" :sw 3)
  (:p :d "M 260 170 L 220 220 L 260 220 Z" :f "#0f172a" :s "#00f2fe" :sw 2)
  (:p :d "M 340 170 L 380 220 L 340 220 Z" :f "#0f172a" :s "#00f2fe" :sw 2)
  (:circ :cx 300 :cy 130 :r 16 :f "#00f2fe" :s "#ffffff" :sw 2)
  (:p :d "M 280 220 L 300 270 L 320 220 Z" :f "#ff4757" :s "#ffa502" :sw 3)
  (:txt :x 230 :y 315 :text "ASL WASM VECTOR ENGINE" :f "#38ef7d" :sz 12 :weight "bold")
)`
  },
  {
    label: '💀 Cyber Skull',
    prompt: 'Draw a neon cybernetic robot skull with glowing visor optics',
    asn: `(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#090614" :r 20)
  (:p :d "M 230 110 Q 300 70 370 110 Q 390 190 350 230 L 350 260 L 250 260 L 250 230 Q 210 190 230 110 Z" :f "#17102b" :s "#a855f7" :sw 4)
  (:circ :cx 270 :cy 160 :r 18 :f "#00f2fe" :s "#ffffff" :sw 2)
  (:circ :cx 330 :cy 160 :r 18 :f "#00f2fe" :s "#ffffff" :sw 2)
  (:ln :x1 270 :y1 240 :x2 270 :y2 260 :s "#ec4899" :sw 2)
  (:ln :x1 300 :y1 240 :x2 300 :y2 260 :s "#ec4899" :sw 2)
  (:ln :x1 330 :y1 240 :x2 330 :y2 260 :s "#ec4899" :sw 2)
  (:txt :x 235 :y 310 :text "CYBERNETIC HARNESS AST" :f "#a855f7" :sz 12 :weight "bold")
)`
  }
];

export const SvgStudio: React.FC = () => {
  const [activePreset, setActivePreset] = useState<string>('logo');
  const [asnCode, setAsnCode] = useState<string>(PRESETS.logo.asn);
  const [selectedModel, setSelectedModel] = useState<string>('eddie-webgpu');
  const [promptText, setPromptText] = useState<string>('');
  const [isGenerating, setIsGenerating] = useState<boolean>(false);
  const [copiedXml, setCopiedXml] = useState(false);
  const [copiedAsn, setCopiedAsn] = useState(false);

  const { svg: svgXml, error } = useMemo(() => asnToSvg(asnCode), [asnCode]);

  const asnTokensCount = Math.round(asnCode.length / 4);
  const xmlTokensCount = Math.round((svgXml || '').length / 4);
  const tokensSaved = Math.max(0, xmlTokensCount - asnTokensCount);
  const pctSaved = xmlTokensCount > 0 ? Math.round((tokensSaved / xmlTokensCount) * 100) : 0;

  const handleSelectPreset = (key: string) => {
    setActivePreset(key);
    setAsnCode(PRESETS[key].asn);
  };

  const handleApplySuggestion = (sug: typeof PROMPT_SUGGESTIONS[0]) => {
    setPromptText(sug.prompt);
    setAsnCode(sug.asn);
  };

  const handleGenerateVector = () => {
    if (!promptText.trim()) return;
    setIsGenerating(true);
    setTimeout(() => {
      const lower = promptText.toLowerCase();
      const match = PROMPT_SUGGESTIONS.find(s => lower.includes(s.label.slice(2).trim().toLowerCase()));
      if (match) {
        setAsnCode(match.asn);
      } else {
        // Synthesize dynamic ASN vector based on prompt
        const title = promptText.slice(0, 24).toUpperCase();
        setAsnCode(`(:svg :w 600 :h 360 :v "0 0 600 360"
  (:rc :x 0 :y 0 :w 600 :h 360 :f "#0a0f1d" :r 20)
  (:circ :cx 300 :cy 160 :r 90 :f "none" :s "#38ef7d" :sw 3)
  (:p :d "M 240 140 L 300 200 L 360 140 Z" :f "rgba(56, 239, 125, 0.15)" :s "#00f2fe" :sw 3)
  (:circ :cx 300 :cy 140 :r 14 :f "#38ef7d")
  (:txt :x 230 :y 290 :text "${title}" :f "#38ef7d" :sz 13 :weight "bold")
  (:txt :x 235 :y 315 :text "Synthesized via ${selectedModel}" :f "rgba(255,255,255,0.4)" :sz 10)
)`);
      }
      setIsGenerating(false);
    }, 450);
  };

  const handleDownloadSvg = () => {
    if (!svgXml) return;
    const blob = new Blob([svgXml], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `agentscript-drawing-${Date.now()}.svg`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleCopyXml = () => {
    if (!svgXml) return;
    navigator.clipboard.writeText(svgXml);
    setCopiedXml(true);
    setTimeout(() => setCopiedXml(false), 2000);
  };

  const handleCopyAsn = () => {
    navigator.clipboard.writeText(asnCode);
    setCopiedAsn(true);
    setTimeout(() => setCopiedAsn(false), 2000);
  };

  return (
    <div className="flex flex-col gap-6 w-full">
      {/* Header & Controls */}
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line pb-4">
        <div>
          <h2 className="text-xl font-bold text-ink flex items-center gap-2">
            <Sparkles className="w-5 h-5 text-signal" />
            AgentScript In-Browser SVG Vector Studio
          </h2>
          <p className="text-xs text-ink-muted mt-1">
            Author and transpile compact ASN S-expressions (<code className="text-signal">:rc</code>, <code className="text-signal">:circ</code>, <code className="text-signal">:p</code>, <code className="text-signal">:ln</code>, <code className="text-signal">:txt</code>) directly into hardware-accelerated SVG
          </p>
        </div>

        {/* Model & Preset Selector Row */}
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

          <div className="flex items-center gap-1.5">
            <span className="text-xs text-ink-muted">Presets:</span>
            {Object.entries(PRESETS).map(([key, item]) => (
              <button
                key={key}
                onClick={() => handleSelectPreset(key)}
                className={`px-3 py-1 text-xs font-mono rounded-xl border transition-all ${
                  activePreset === key
                    ? 'bg-signal/20 border-signal text-signal font-bold'
                    : 'border-line text-ink-muted hover:text-ink bg-surface-2'
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* AI Vector Prompt Bar & Quick Suggestion Chips */}
      <div className="p-4 rounded-2xl bg-surface-2 border border-line flex flex-col gap-3">
        <div className="flex items-center gap-3">
          <Sparkles className="w-4 h-4 text-signal shrink-0" />
          <input
            type="text"
            value={promptText}
            onChange={(e) => setPromptText(e.target.value)}
            placeholder="Prompt vector engine: e.g. 'Draw a cyber security shield', 'Draw a space rocket', 'Draw a neon skull'..."
            className="flex-1 bg-surface border border-line rounded-xl px-3 py-2 text-xs text-ink focus:outline-none focus:ring-1 focus:ring-signal font-mono"
            onKeyDown={(e) => e.key === 'Enter' && handleGenerateVector()}
          />
          <button
            onClick={handleGenerateVector}
            disabled={isGenerating || !promptText.trim()}
            className="px-4 py-2 text-xs font-mono font-semibold rounded-xl border border-signal/40 bg-signal/15 hover:bg-signal/25 text-signal transition-all disabled:opacity-40 shrink-0"
          >
            {isGenerating ? 'Drawing ASN...' : 'Draw Vector'}
          </button>
        </div>

        {/* Quick Example Prompt Chips */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[11px] font-mono text-ink-muted">Example Prompts:</span>
          {PROMPT_SUGGESTIONS.map((sug, idx) => (
            <button
              key={idx}
              onClick={() => handleApplySuggestion(sug)}
              className="px-2.5 py-1 rounded-lg bg-surface border border-line hover:border-signal/40 hover:text-signal text-[11px] font-mono text-ink-muted transition-all"
            >
              {sug.label}
            </button>
          ))}
        </div>
      </div>

      {/* Token Compaction Telemetry Bar */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">ASN Representation</div>
          <div className="text-lg font-mono font-bold text-signal mt-0.5">{asnTokensCount} tokens</div>
        </div>
        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Standard SVG XML</div>
          <div className="text-lg font-mono font-bold text-ink mt-0.5">{xmlTokensCount} tokens</div>
        </div>
        <div className="bg-surface-2 border border-line p-3 rounded-xl">
          <div className="text-[10px] text-ink-muted uppercase font-mono">Agent Bandwidth Saved</div>
          <div className="text-lg font-mono font-bold text-emerald-400 mt-0.5">-{pctSaved}%</div>
        </div>
        <div className="bg-surface-2 border border-line p-3 rounded-xl flex items-center justify-end gap-2">
          <button
            onClick={handleCopyAsn}
            className="px-2.5 py-1.5 text-xs font-mono rounded-lg border border-line bg-surface hover:bg-inset text-ink flex items-center gap-1.5"
            title="Copy ASN S-Expression"
          >
            {copiedAsn ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Code2 className="w-3.5 h-3.5 text-signal" />}
            <span>{copiedAsn ? 'Copied' : 'Copy ASN'}</span>
          </button>
          <button
            onClick={handleCopyXml}
            className="px-2.5 py-1.5 text-xs font-mono rounded-lg border border-line bg-surface hover:bg-inset text-ink flex items-center gap-1.5"
            title="Copy SVG XML"
          >
            {copiedXml ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5 text-ink-muted" />}
            <span>{copiedXml ? 'Copied' : 'Copy SVG'}</span>
          </button>
          <button
            onClick={handleDownloadSvg}
            className="px-2.5 py-1.5 text-xs font-mono rounded-lg border border-signal/40 bg-signal/15 hover:bg-signal/25 text-signal flex items-center gap-1.5"
            title="Download SVG file"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Save .svg</span>
          </button>
        </div>
      </div>

      {/* Editor & Live Render Split View */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 items-stretch">
        {/* ASN Editor Pane */}
        <div className="flex flex-col bg-surface border border-line rounded-2xl overflow-hidden shadow-sm">
          <div className="flex items-center justify-between px-4 py-2.5 bg-surface-2 border-b border-line text-xs font-mono text-ink-muted">
            <div className="flex items-center gap-2">
              <Code2 className="w-4 h-4 text-signal" />
              <span>ASN Vector Source (Editable)</span>
            </div>
            <span className="text-[10px] text-signal font-bold uppercase">Live Compiling</span>
          </div>
          <textarea
            value={asnCode}
            onChange={(e) => setAsnCode(e.target.value)}
            className="w-full h-[380px] p-4 bg-surface font-mono text-xs text-ink leading-relaxed resize-none focus:outline-none focus:ring-1 focus:ring-signal border-0"
            spellCheck={false}
          />
          {error && (
            <div className="p-3 bg-rose-500/10 border-t border-rose-500/30 text-rose-400 font-mono text-xs">
              ✗ {error}
            </div>
          )}
        </div>

        {/* Live SVG Viewport */}
        <div className="flex flex-col bg-surface border border-line rounded-2xl overflow-hidden shadow-sm">
          <div className="flex items-center justify-between px-4 py-2.5 bg-surface-2 border-b border-line text-xs font-mono text-ink-muted">
            <div className="flex items-center gap-2">
              <Eye className="w-4 h-4 text-signal" />
              <span>Live Render Canvas</span>
            </div>
            <span className="text-[10px] text-emerald-400 font-bold uppercase">Vector Preview</span>
          </div>
          <div className="w-full h-[380px] flex items-center justify-center p-4 bg-black/40 relative overflow-hidden">
            {svgXml ? (
              <div
                className="w-full h-full flex items-center justify-center"
                dangerouslySetInnerHTML={{ __html: svgXml }}
              />
            ) : (
              <div className="text-ink-muted text-xs font-mono">No valid SVG output</div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
