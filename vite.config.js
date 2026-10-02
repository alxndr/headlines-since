import { defineConfig } from 'vite';
import elmPlugin from 'vite-plugin-elm';

export default defineConfig(({ command, mode }) => ({
  plugins: [elmPlugin()],
  root: 'src',
  base: mode === 'production' || command === 'build' && process.env.GITHUB_ACTIONS ? '/headlines-since/' : '/',
  build: {
    outDir: '../build',
    sourcemap: false,
    emptyOutDir: true
  }
}));
