import { fetchAllRSS } from './fetchers.js';
import { clusterStories } from './cluster.js';
import { rankStories } from './ranker.js';
import { daysAgo, formatDateISO } from './utils.js';

function $(sel) {
  return document.querySelector(sel);
}

function clear(el) {
  el.innerHTML = '';
}

function setStatus(el, msg) {
  el.textContent = msg;
}

function showError(el, msg) {
  clear(el);
  const div = document.createElement('div');
  div.className = 'error';
  div.textContent = msg;
  el.appendChild(div);
}

function showResults(el, stories) {
  clear(el);
  for (const s of stories) {
    const card = document.createElement('article');
    card.className = 'story';
    const h3 = document.createElement('h3');
    const a = document.createElement('a');
    a.href = s.url || '#';
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.textContent = s.title || '';
    h3.appendChild(a);
    card.appendChild(h3);
    const meta = document.createElement('div');
    meta.className = 'story-meta';
    const src = s.sourceName || '';
    const pub = s.publishedAt;
    const whenStr = pub ? pub.toLocaleString() : '';
    meta.textContent = src + (src && whenStr ? ' • ' : '') + whenStr;
    card.appendChild(meta);
    el.appendChild(card);
  }
}

async function main() {
  const form = $('#hs-form');
  const dateInput = $('#start-date');
  const countInput = $('#count');
  const status = $('#hs-status');
  const results = $('#hs-results');

  if (dateInput) {
    const d = daysAgo(14);
    dateInput.value = formatDateISO(d);
    const max = formatDateISO(daysAgo(365));
    dateInput.max = max;
  }

  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      clear(results);
      setStatus(status, 'Fetching headlines...');
      const startStr = dateInput ? dateInput.value : '';
      const count = countInput ? parseInt(countInput.value, 10) : 10;
      if (!startStr) {
        showError(results, 'Please pick a start date.');
        return;
      }
      try {
        const start = new Date(startStr);
        const all = await fetchAllRSS();
        const filtered = all.filter((s) => s.publishedAt && s.publishedAt >= start);
        const clusters = clusterStories(filtered);
        const top = rankStories(filtered, clusters, count);
        if (top.length === 0) {
          setStatus(status, 'No stories found for this range.');
        } else {
          setStatus(status, `Found ${top.length} biggest stories`);
          showResults(results, top);
        }
      } catch (err) {
        showError(results, `Error: ${err?.message || 'unknown'}`);
      }
    });
  }
}

main();