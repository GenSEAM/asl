import React, { useState } from 'react';
import { Terminal, FolderPlus, Copy, Check, Sparkles, X, Code, ShieldCheck } from 'lucide-react';

interface ScaffoldModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const ScaffoldModal: React.FC<ScaffoldModalProps> = ({ isOpen, onClose }) => {
  const [projectName, setProjectName] = useState('my-agent-service');
  const [template, setTemplate] = useState<'cli' | 'wasm' | 'web' | 'lib'>('wasm');
  const [copied, setCopied] = useState(false);

  if (!isOpen) return null;

  const initCommand = `agentscript init ${projectName} --template ${template}`;

  const handleCopy = () => {
    navigator.clipboard.writeText(initCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-craft-950/80 backdrop-blur-md font-mono">
      <div className="relative w-full max-w-2xl rounded-xl border border-craft-700 bg-craft-900 shadow-2xl p-6">
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-craft-400 hover:text-craft-100 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent">
            <FolderPlus className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-lg font-bold text-craft-50">Scaffold New AgentScript Project</h3>
            <p className="text-xs text-craft-400 font-sans">
              Instant workspace with pre-configured <code className="text-craft-accent">AGENTS.md</code>, <code className="text-craft-accent">CLAUDE.md</code>, and verified skills.
            </p>
          </div>
        </div>

        {/* Project Options */}
        <div className="space-y-4 text-xs mb-6">
          <div>
            <label className="block text-craft-300 font-semibold mb-1">Project Name (kebab-case)</label>
            <input
              type="text"
              value={projectName}
              onChange={(e) => setProjectName(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ''))}
              className="w-full px-3 py-2 rounded bg-craft-950 border border-craft-700 text-craft-100 focus:outline-none focus:border-craft-accent"
              placeholder="my-agent-service"
            />
          </div>

          <div>
            <label className="block text-craft-300 font-semibold mb-1">Template Preset</label>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {[
                { id: 'wasm', label: 'Wasm Edge', desc: 'Browser & WASI' },
                { id: 'cli', label: 'CLI Tool', desc: 'Native executable' },
                { id: 'web', label: 'React Bridge', desc: 'TS frontend glue' },
                { id: 'lib', label: 'Multi-Target Lib', desc: 'Wasm/TS/Rust/Go' },
              ].map((t) => (
                <button
                  key={t.id}
                  onClick={() => setTemplate(t.id as any)}
                  className={`p-2.5 rounded border text-left transition-all ${
                    template === t.id
                      ? 'bg-craft-800 border-craft-accent text-craft-accent font-bold shadow-sm'
                      : 'bg-craft-950 border-craft-800 text-craft-400 hover:text-craft-200'
                  }`}
                >
                  <div className="font-bold">{t.label}</div>
                  <div className="text-[10px] text-craft-500 font-sans">{t.desc}</div>
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Generated Workspace Preview */}
        <div className="p-3.5 rounded-lg bg-craft-950 border border-craft-800 mb-6 text-xs">
          <div className="text-craft-400 font-semibold mb-2 flex items-center gap-1.5">
            <Code className="w-3.5 h-3.5 text-craft-accent" />
            <span>Generated File Tree:</span>
          </div>
          <ul className="text-craft-300 space-y-1 text-[11px]">
            <li className="flex items-center gap-2">
              <span className="text-craft-500">├──</span>
              <strong className="text-craft-accent">AGENTS.md</strong>
              <span className="text-craft-500 font-sans">— Agent protocol & gate commands</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="text-craft-500">├──</span>
              <strong className="text-craft-accent">CLAUDE.md</strong>
              <span className="text-craft-500 font-sans">— Claude Code skill instructions</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="text-craft-500">├──</span>
              <strong className="text-craft-accent">.skills/agentscript/SKILL.md</strong>
              <span className="text-craft-500 font-sans">— Embedded zero-shot cheat sheet</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="text-craft-500">├──</span>
              <span>asex.json</span>
              <span className="text-craft-500 font-sans">— Project manifest</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="text-craft-500">└──</span>
              <span>src/main.agentscript</span>
              <span className="text-craft-500 font-sans">— Starter S-expression module</span>
            </li>
          </ul>
        </div>

        {/* Command Box */}
        <div className="flex items-center justify-between gap-3 p-3 rounded-lg bg-craft-950 border border-craft-700 text-xs">
          <div className="flex items-center gap-2 text-craft-100 overflow-x-auto">
            <Terminal className="w-4 h-4 text-craft-accent shrink-0" />
            <code>$ {initCommand}</code>
          </div>

          <button
            onClick={handleCopy}
            className="px-3 py-1.5 rounded bg-craft-accent text-craft-950 font-bold text-xs hover:bg-craft-accent/90 transition-colors flex items-center gap-1.5 shrink-0"
          >
            {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
            <span>{copied ? 'Copied!' : 'Copy Command'}</span>
          </button>
        </div>

        <div className="mt-4 flex items-center justify-between text-[11px] text-craft-500">
          <span className="flex items-center gap-1">
            <ShieldCheck className="w-3.5 h-3.5 text-craft-emerald" />
            <span>Agent-Ready Out of the Box</span>
          </span>
          <span className="flex items-center gap-1">
            <Sparkles className="w-3.5 h-3.5 text-craft-accent" />
            <span>1-Pass Deterministic LLM Generation</span>
          </span>
        </div>
      </div>
    </div>
  );
};
