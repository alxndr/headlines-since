const AUTHORITY = new Set([
  'apnews.com',
  'reuters.com',
  'bbc.co.uk',
  'bbc.com',
  'theguardian.com',
  'nytimes.com',
  'wsj.com',
  'washingtonpost.com',
  'npr.org',
  'ft.com',
  'aljazeera.com',
  'cnn.com',
]);

const IMPACT_TERMS = [
  'dead','killed','deaths','injured','attack','attacks','war','ceasefire','bomb','bombing','earthquake','hurricane','storm','flood','flooding','election','elections','vote','court','ruling','supreme court','law','bill','passed','sanction','sanctions','market','crash','recession','inflation','rate hike','strike','unrest','protest','protests','mass shooting','tornado','tsunami','outbreak','pandemic'
];

export function scoreStory(story, clusterSize = 1, now = new Date()) {
  let score = 0;
  const pub = story.publishedAt;
  if (pub) {
    const hours = Math.max(0, (now - pub) / (1000 * 60 * 60));
    const recency = Math.exp(-hours / (24 * 3)); // ~3 day half-ish decay
    score += recency * 0.3; // w_rec
  } else {
    score += 0.1 * 0.3;
  }
  const cov = Math.min(clusterSize / 10, 1);
  score += cov * 0.4; // w_cov
  const t = (story.title || '').toLowerCase();
  let imp = 0;
  for (const term of IMPACT_TERMS) {
    if (t.includes(term)) imp++;
  }
  score += Math.min(imp / 4, 1) * 0.2; // w_imp
  let auth = 0;
  try {
    const host = new URL(story.url).hostname.replace(/^www\./, '');
    if (AUTHORITY.has(host)) auth = 1;
  } catch {}
  score += auth * 0.1; // w_auth
  return score;
}

export function rankStories(stories, clusters, count) {
  const byIdx = new Map();
  clusters.forEach((c) => c.members.forEach((m) => byIdx.set(m.idx, c.size)));
  const scored = stories.map((s, i) => ({
    ...s,
    score: scoreStory(s, byIdx.get(i) || 1),
  }));
  scored.sort((a, b) => b.score - a.score);
  const seen = new Set();
  const out = [];
  for (const s of scored) {
    const key = s.url || s.rawTitleNorm;
    if (key && seen.has(key)) continue;
    if (key) seen.add(key);
    out.push(s);
    if (out.length >= count) break;
  }
  return out;
}