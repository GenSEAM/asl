import { defineConfig } from 'vite';
import path from 'path';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';
import { aslPlugin } from './plugins/vitePluginAsl.js';

export default defineConfig({
  plugins: [aslPlugin()],
  server: {
    port: 4173,
    allowedHosts: true,
  },
  preview: {
    port: 4173,
    allowedHosts: true,
  },
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
