import React from 'react';
import { Sun, Moon } from 'lucide-react';
import { useTheme } from '../lib/theme';

export const ThemeToggle: React.FC = () => {
  const { resolvedTheme, setTheme } = useTheme();

  return (
    <div className="flex items-center p-0.5 rounded-lg border border-craft-700/60 dark:border-craft-800 bg-craft-200/40 dark:bg-craft-900/80 backdrop-blur-md">
      <button
        onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
        className="p-1.5 rounded-md text-craft-600 dark:text-craft-400 hover:text-craft-950 dark:hover:text-craft-100 hover:bg-white/80 dark:hover:bg-craft-800 transition-all"
        title={`Switch to ${resolvedTheme === 'dark' ? 'light' : 'dark'} mode`}
        aria-label="Toggle theme"
      >
        {resolvedTheme === 'dark' ? (
          <Sun className="w-3.5 h-3.5 text-craft-amber" />
        ) : (
          <Moon className="w-3.5 h-3.5 text-craft-accent" />
        )}
      </button>
    </div>
  );
};
