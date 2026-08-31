/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Monaco', 'Consolas', 'monospace'],
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      colors: {
        craft: {
          950: '#0a0a0c',
          900: '#111215',
          850: '#17191e',
          800: '#20232a',
          700: '#2f343f',
          600: '#464c5b',
          400: '#8a92a3',
          300: '#b8bfc9',
          100: '#eef1f6',
          50: '#fafbfd',
          accent: '#2dd4bf', // teal/cyan industrial accent
          amber: '#f59e0b',
          emerald: '#10b981',
          rose: '#f43f5e',
        }
      }
    },
  },
  plugins: [],
}
