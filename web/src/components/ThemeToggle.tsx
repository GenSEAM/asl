import React, { useState } from 'react';
import { Sun, Moon } from 'lucide-react';
import { useTheme } from '../lib/theme';

export const ThemeToggle: React.FC = () => {
  const { resolvedTheme, setTheme } = useTheme();
  const [isHovered, setIsHovered] = useState(false);

  const toggleTheme = () => {
    setTheme(resolvedTheme === 'dark' ? 'light' : 'dark');
  };

  const isDark = resolvedTheme === 'dark';

  return (
    <button
      onClick={toggleTheme}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      className={`relative group px-3.5 py-1.5 rounded-full border transition-all duration-300 flex items-center gap-2 overflow-hidden ${
        isDark
          ? 'border-cyan-500/40 bg-[#06080d] text-craft-200 hover:border-cyan-400 shadow-[0_0_12px_rgba(6,182,212,0.15)]'
          : 'border-amber-400 bg-white text-amber-950 hover:border-amber-500 shadow-[0_0_20px_rgba(245,158,11,0.4)] ring-2 ring-amber-400/30'
      }`}
      title={isDark ? 'Switch to Blinded by the Light Mode (10,000 Nits)' : 'Switch to Core Obsidian (Agent Native)'}
      aria-label="Toggle Core Theme"
    >
      {/* Reactor / Solar Core Orb */}
      <div className="relative flex items-center justify-center">
        <span
          className={`w-2.5 h-2.5 rounded-full transition-all duration-300 ${
            isDark
              ? 'bg-cyan-400 shadow-[0_0_8px_#06b6d4]'
              : 'bg-amber-500 shadow-[0_0_14px_#f59e0b] scale-110'
          } ${isHovered ? 'scale-125 animate-ping' : ''}`}
        />
        <span
          className={`absolute w-2.5 h-2.5 rounded-full ${
            isDark ? 'bg-cyan-400' : 'bg-amber-500'
          }`}
        />
      </div>

      {/* Mode Label */}
      <div className="flex items-center gap-1.5 font-mono text-[11px] font-extrabold tracking-tight">
        {isDark ? (
          <>
            <Moon className="w-3.5 h-3.5 text-cyan-400" />
            <span className="text-cyan-400 uppercase tracking-wider">CORE // OBSIDIAN</span>
          </>
        ) : (
          <>
            <Sun className="w-3.5 h-3.5 text-amber-500 animate-spin" style={{ animationDuration: '8s' }} />
            <span className="text-amber-700 dark:text-amber-500 uppercase tracking-wider">DAZZLE // 10,000 NITS</span>
          </>
        )}
      </div>

      {/* Solar Flare Sweep */}
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-700 pointer-events-none" />
    </button>
  );
};
