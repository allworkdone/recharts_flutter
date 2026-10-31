import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
const root = path.resolve(import.meta.dirname);
export default defineConfig({
  root, plugins: [react()], base: './',
  publicDir: path.resolve(root, '../../../example/assets/fonts'),
  server: { fs: { strict: false } },
  build: { outDir: path.resolve(root, 'dist'), emptyOutDir: true },
});
