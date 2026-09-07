import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';
import { aslPlugin } from './plugins/vite-plugin-asl';

export default defineConfig({
  plugins: [aslPlugin(), react({ include: /\.(asl|[tj]sx?)$/ })],
  css: {
    postcss: {
      plugins: [tailwindcss(), autoprefixer()],
    },
  },
  resolve: {
    alias: {
      '@backend': path.resolve(__dirname, '../backend'),
      '@': path.resolve(__dirname, './src'),
    },
    extensions: ['.mjs', '.js', '.mts', '.ts', '.jsx', '.tsx', '.json', '.asl'],
  },
  build: {
    rollupOptions: {
      external: ['@mlc-ai/web-llm'],
    },
  },
});
