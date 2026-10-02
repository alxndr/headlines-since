import { defineConfig } from 'vite';
import elmPlugin from 'vite-plugin-elm';

export default defineConfig(({ mode }) => ({
  plugins: [elmPlugin()],
  root: 'src',
  // GitHub Pages serves the site from /headlines-since/. Both `vite build`
  // and `vite preview` run in production mode, so they agree on that base;
  // the dev server (development mode) uses /.
  base: mode === 'production' ? '/headlines-since/' : '/',
  build: {
    outDir: '../build',
    sourcemap: false,
    emptyOutDir: true
  }
}));
