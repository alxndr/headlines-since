import { parseRSSDate, normalizeTitle } from './utils.js';

const CORS_PROXY_KEY = import.meta.env.VITE_CORSPROXY_API_KEY || '';

const PROXIES = [
  (u) => `https://api.allorigins.win/raw?url=${encodeURIComponent(u)}`,
  (u) => CORS_PROXY_KEY ? `https://corsproxy.io/?url=${encodeURIComponent(u)}&api-key=${CORS_PROXY_KEY}` : null,
].filter(Boolean);

const RSS_SOURCES = [
  'https://news.google.com/rss',
  'https://feeds.bbci.co.uk/news/rss.xml',
];

export async function fetchWithProxy(url) {
  let lastErr;
  for (const mk of PROXIES) {
    try {
      const res = await fetch(mk(url), { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      if (!text || text.trim().length === 0) throw new Error('Empty response');
      if (text.trim().startsWith('<!DOCTYPE') || text.trim().startsWith('<html')) {
        throw new Error('Got HTML instead of XML');
      }
      return text;
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error('All proxies failed');
}

export async function fetchAllRSS() {
  const results = [];
  for (const url of RSS_SOURCES) {
    try {
      const xml = await fetchWithProxy(url);
      results.push(...parseRSS(xml));
    } catch (e) {
      // ignore individual source failures
    }
  }
  return results;
}
