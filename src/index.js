import { Elm } from './Main.elm';
import { setupPorts } from './ports.js';

const app = Elm.Main.init({
  node: document.getElementById('app')
});

setupPorts(app);
