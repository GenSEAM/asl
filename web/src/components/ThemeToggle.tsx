import React from 'react';
import { Sun, Gem } from 'lucide-react';
import { useTheme } from '../lib/theme';

export const ThemeToggle: React.FC = () => {
  const { resolvedTheme, setTheme } = useTheme();

  const toggleTheme = () => {
    setTheme(resolvedTheme === 'dark' ? 'light' : 'dark');
  };

  const isDark = resolvedTheme === 'dark';

  return (
    <button
      onClick={toggleTheme}
      className={`relative w-8 h-8 rounded-full border transition-all duration-300 flex items-center justify-center overflow-hidden ${
        isDark
          ? 'border-white/[0.12] bg-white/[0.04] text-cyan-400 hover:border-cyan-400/50 hover:bg-cyan-500/10 shadow-sm'
          : 'border-amber-300 bg-amber-50 text-amber-600 hover:border-amber-400 hover:bg-amber-100 shadow-sm ring-1 ring-amber-400/30'
      }`}
      title={isDark ? 'Switch to Light Mode' : 'Switch to Obsidian Dark Mode'}
      aria-label="Toggle Theme"
    >
      {isDark ? (
        <Gem className="w-3.5 h-3.5 text-cyan-400 transition-transform duration-300 hover:rotate-12" />
      ) : (
        <Sun className="w-3.5 h-3.5 text-amber-500 animate-spin" style={{ animationDuration: '10s' }} />
      )}
    </button>
  );
};
