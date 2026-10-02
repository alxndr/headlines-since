import { defineConfig } from 'vite';
import elmPlugin from 'vite-plugin-elm';

export default defineConfig({
  plugins: [elmPlugin()],
  root: 'src',
  base: '/headlines-since/',
  build: {
    outDir: '../build',
    sourcemap: false,
    emptyOutDir: true
  }
});
