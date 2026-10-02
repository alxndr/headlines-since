import { Elm } from './Main.elm';

// All app logic lives in Elm. This file only starts the app and hands it the
// build-time CORS proxy key (Elm can't read Vite's import.meta.env itself).
Elm.Main.init({
  node: document.getElementById('app'),
  flags: {
    corsProxyKey: import.meta.env.VITE_CORSPROXY_API_KEY || '',
  },
});
