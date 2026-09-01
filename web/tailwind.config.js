import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const channel = (name) => `rgb(var(--${name}) / <alpha-value>)`;

/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    path.join(__dirname, 'index.html'),
    path.join(__dirname, 'src/**/*.{js,ts,jsx,tsx}'),
  ],
  theme: {
    extend: {
      fontFamily: {
        mono: ['Fira Code', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      colors: {
        ground: channel('ground'),
        sunken: channel('sunken'),
        surface: channel('surface'),
        inset: channel('inset'),
        line: channel('line'),
        'line-strong': channel('line-strong'),
        ink: channel('ink'),
        'ink-2': channel('ink-2'),
        'ink-3': channel('ink-3'),
        signal: channel('signal'),
        'signal-soft': channel('signal-soft'),
      },
      fontSize: {
        micro: ['0.6875rem', { lineHeight: '1.4', letterSpacing: '0.08em' }],
        meta: ['0.75rem', { lineHeight: '1.45', letterSpacing: '0.02em' }],
        code: ['0.8125rem', { lineHeight: '1.85', letterSpacing: '0' }],
        body: ['0.9375rem', { lineHeight: '1.65', letterSpacing: '0' }],
        brand: ['1.0625rem', { lineHeight: '1.2', letterSpacing: '-0.03em' }],
        lead: ['1.125rem', { lineHeight: '1.6', letterSpacing: '-0.01em' }],
        h3: ['1.375rem', { lineHeight: '1.25', letterSpacing: '-0.02em' }],
        h2: ['clamp(2rem, 3.6vw, 2.5rem)', { lineHeight: '1.06', letterSpacing: '-0.035em' }],
        display: ['clamp(3rem, 6.2vw, 5rem)', { lineHeight: '0.94', letterSpacing: '-0.05em' }],
      },
      borderRadius: { '2xl': '1rem', '3xl': '1.5rem' },
      boxShadow: {
        e1: '0 2px 4px hsl(var(--shadow-hue) / var(--shadow-strength))',
        e2: '0 6px 12px hsl(var(--shadow-hue) / var(--shadow-strength))',
        e3: '0 12px 24px hsl(var(--shadow-hue) / var(--shadow-strength))',
        e4: '0 20px 40px hsl(var(--shadow-hue) / var(--shadow-strength))',
      },
      maxWidth: { prose: '68ch' },
    },
  },
  plugins: [],
};
