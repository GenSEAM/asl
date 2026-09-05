import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';
import { aslPlugin } from './plugins/vite-plugin-asl';

export default defineConfig({
  plugins: [aslPlugin(), react()],
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
  },
});
