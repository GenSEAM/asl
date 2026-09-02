import React, { useState, useMemo } from 'react';
import { Search, X, ArrowRight, Code2, BookOpen, Terminal, Sparkles, Shield, Cpu } from 'lucide-react';

interface SearchResult {
  id: string;
  category: 'docs' | 'toolchain' | 'grammar' | 'protocol';
  title: string;
  desc: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
}

const ITEMS: SearchResult[] = [
  {
    id: '1',
    category: 'docs',
    title: 'The Agent Way',
    desc: 'Why languages designed for typing hands fail autonomous agents.',
    href: '#agent-way',
    icon: BookOpen,
  },
  {
    id: '2',
    category: 'toolchain',
    title: 'CLI Installation & Flow',
    desc: 'curl -fsSL https://aslang.dev/install.sh | bash',
    href: '#install',
    icon: Terminal,
  },
  {
    id: '3',
    category: 'protocol',
    title: 'A2A Wire Protocol',
    desc: 'Low-latency agent-to-agent S-expression frame serialization.',
    href: '#a2a-protocol',
    icon: Code2,
  },
  {
    id: '4',
    category: 'grammar',
    title: 'SkyLoom Mesh',
    desc: 'Zero-copy distributed consensus and inter-agent memory mesh.',
    href: '#skyloom-mesh',
    icon: Sparkles,
  },
  {
    id: '5',
    category: 'toolchain',
    title: 'ASL Quality Doctor',
    desc: 'Automatic linter, AST repair, and formal invariant validator.',
    href: '#quality-doctor',
    icon: Shield,
  },
  {
    id: '6',
    category: 'protocol',
    title: 'SQL Studio & Relational Engine',
    desc: 'Cross-dialect queries, schema migrations and query execution.',
    href: '#sql-studio',
    icon: Cpu,
  },
];

export const SearchModal: React.FC<{ isOpen: boolean; onClose: () => void }> = ({
  isOpen,
  onClose,
}) => {
  const [query, setQuery] = useState('');

  const filtered = useMemo(() => {
    if (!query.trim()) return ITEMS;
    const q = query.toLowerCase();
    return ITEMS.filter(
      (item) =>
        item.title.toLowerCase().includes(q) ||
        item.desc.toLowerCase().includes(q) ||
        item.category.toLowerCase().includes(q)
    );
  }, [query]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-20 sm:pt-28 px-4 bg-black/60 backdrop-blur-md animate-fade-in"
      onClick={onClose}
    >
      <div
        className="relative w-full max-w-xl rounded-2xl border border-line bg-surface/95 backdrop-blur-2xl shadow-e4 overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-3 px-4 py-3.5 border-b border-line">
          <Search className="w-5 h-5 text-signal" />
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search documentation, CLI tools, protocol..."
            className="flex-1 bg-transparent border-none outline-none font-mono text-body text-ink placeholder:text-ink-3"
            autoFocus
          />
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-lg text-ink-3 hover:text-ink hover:bg-inset transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="max-h-80 overflow-y-auto p-2 divide-y divide-line/40">
          {filtered.length === 0 ? (
            <div className="py-8 text-center text-ink-3 font-mono text-meta">
              No results found for "{query}"
            </div>
          ) : (
            filtered.map((item) => (
              <a
                key={item.id}
                href={item.href}
                onClick={onClose}
                className="group flex items-center justify-between p-3 rounded-xl hover:bg-inset transition-all"
              >
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-lg bg-surface border border-line group-hover:border-signal/40 transition-colors">
                    <item.icon className="w-4 h-4 text-signal" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-ink text-body group-hover:text-signal transition-colors">
                        {item.title}
                      </span>
                      <span className="font-mono text-[10px] uppercase px-1.5 py-0.5 rounded bg-surface border border-line text-ink-3">
                        {item.category}
                      </span>
                    </div>
                    <p className="text-meta text-ink-3 mt-0.5 line-clamp-1">{item.desc}</p>
                  </div>
                </div>
                <ArrowRight className="w-4 h-4 text-ink-3 group-hover:text-signal opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0" />
              </a>
            ))
          )}
        </div>

        <div className="px-4 py-2.5 bg-sunken/60 border-t border-line flex items-center justify-between font-mono text-[11px] text-ink-3">
          <span>Navigate with mouse or keyboard</span>
          <span>ESC to close</span>
        </div>
      </div>
    </div>
  );
};
