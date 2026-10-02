import { jaccardTokens, normalizeTitle } from './utils.js';

export function clusterStories(stories, threshold = 0.4) {
  const items = stories.map((s, i) => ({ ...s, idx: i }));
  const clusters = [];
  const used = new Set();
  for (let i = 0; i < items.length; i++) {
    if (used.has(i)) continue;
    const seed = items[i];
    const members = [seed];
    used.add(i);
    for (let j = i + 1; j < items.length; j++) {
      if (used.has(j)) continue;
      const cand = items[j];
      const sim = jaccardTokens(seed.rawTitleNorm || seed.title.toLowerCase(), cand.rawTitleNorm || cand.title.toLowerCase());
      if (sim >= threshold) {
        members.push(cand);
        used.add(j);
      }
    }
    clusters.push(members);
  }
  return clusters.map((m) => ({ members: m, size: m.length }));
}