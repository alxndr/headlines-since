import { fetchAllRSS } from './fetchers.js';
import { clusterStories } from './cluster.js';
import { rankStories } from './ranker.js';

function formatDateForDisplay(date) {
  return date.toLocaleString();
}

function transformStories(stories) {
  return stories.map(s => ({
    title: s.title || '',
    url: s.url || '#',
    sourceName: s.sourceName || '',
    publishedAt: s.publishedAt ? formatDateForDisplay(s.publishedAt) : ''
  }));
}

export function setupPorts(app) {
  if (app.ports && app.ports.fetchRequest) {
    app.ports.fetchRequest.subscribe(async (req) => {
      try {
        const startDate = req.startDate;
        const count = req.count || 10;
        const start = new Date(startDate);
        const all = await fetchAllRSS();
        const filtered = all.filter(s => s.publishedAt && s.publishedAt >= start);
        const clusters = clusterStories(filtered);
        const top = rankStories(filtered, clusters, count);
        if (app.ports.fetchResponse) {
          app.ports.fetchResponse.send({ type: 'success', stories: transformStories(top) });
        }
      } catch (err) {
        if (app.ports.fetchResponse) {
          app.ports.fetchResponse.send({ type: 'error', error: err?.message || 'unknown error' });
        }
      }
    });
  }
}
