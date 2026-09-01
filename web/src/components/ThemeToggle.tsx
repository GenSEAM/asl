import React, { useState } from 'react';
import { Cpu, Zap } from 'lucide-react';
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
      className={`relative group px-3 py-1.5 rounded-xl border transition-all duration-300 flex items-center gap-2.5 overflow-hidden ${
        isDark
          ? 'border-craft-accent/40 bg-craft-900/90 text-craft-200 hover:border-craft-accent shadow-glow-sm'
          : 'border-craft-300 bg-white/95 text-craft-800 hover:border-craft-accent shadow-sm'
      }`}
      title={isDark ? 'Switch to Lab Precision Light Mode' : 'Switch to Cyber Stealth Dark Mode'}
      aria-label="Toggle Droid System State"
    >
      {/* Reactor Core Pulsing Orb */}
      <div className="relative flex items-center justify-center">
        <span
          className={`w-2.5 h-2.5 rounded-full transition-all duration-300 ${
            isDark ? 'bg-craft-accent shadow-[0_0_8px_#06b6d4]' : 'bg-amber-500 shadow-[0_0_8px_#f59e0b]'
          } ${isHovered ? 'scale-125 animate-ping' : 'animate-pulse'}`}
        />
        <span
          className={`absolute w-2.5 h-2.5 rounded-full ${
            isDark ? 'bg-craft-accent' : 'bg-amber-500'
          }`}
        />
      </div>

      {/* Droid Mode Label */}
      <div className="flex flex-col text-left font-mono">
        <div className="flex items-center gap-1 text-[10px] font-bold tracking-wider uppercase">
          {isDark ? (
            <>
              <Cpu className="w-3 h-3 text-craft-accent" />
              <span className="text-craft-accent">CORE // STEALTH</span>
            </>
          ) : (
            <>
              <Zap className="w-3 h-3 text-amber-500" />
              <span className="text-amber-600">CORE // LAB LIGHT</span>
            </>
          )}
        </div>
      </div>

      {/* Subtle Scanline Overlay */}
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/5 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-700 pointer-events-none" />
    </button>
  );
};
