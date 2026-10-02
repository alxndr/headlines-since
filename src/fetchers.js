import { parseRSSDate, normalizeTitle } from './utils.js';

const CORS_PROXY_KEY = import.meta.env.VITE_CORS_PROXY_KEY || '';

const PROXIES = [
  (u) => `https://api.allorigins.win/raw?url=${encodeURIComponent(u)}`,
  (u) => `https://corsproxy.io/?url=${encodeURIComponent(u)}&api-key=${CORS_PROXY_KEY}`,
];

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

export function parseRSS(xml) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xml, 'application/xml');
  const parseError = doc.querySelector('parsererror');
  if (parseError) return [];
  const items = Array.from(doc.querySelectorAll('item'));
  return items.map((it) => {
    const title = it.querySelector('title')?.textContent || '';
    const link = it.querySelector('link')?.textContent || '';
    const pub = it.querySelector('pubDate')?.textContent || it.querySelector('pubdate')?.textContent || '';
    const src = it.querySelector('source')?.textContent || it.getAttribute('source') || '';
    const desc = it.querySelector('description')?.textContent || '';
    const pubDate = parseRSSDate(pub);
    return {
      title: title.replace(/<[^>]+>/g, '').trim(),
      url: link.trim(),
      sourceName: src.trim() || guessSourceFromURL(link),
      publishedAt: pubDate,
      description: desc.replace(/<[^>]+>/g, '').trim(),
      rawTitleNorm: normalizeTitle(title),
    };
  });
}

function guessSourceFromURL(u) {
  try {
    const host = new URL(u).hostname;
    return host.replace(/^www\./, '');
  } catch {
    return '';
  }
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
