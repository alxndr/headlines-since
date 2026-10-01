export function formatDateISO(d) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function daysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d;
}

export function parseRSSDate(s) {
  if (!s) return null;
  const d = new Date(s);
  return isNaN(d) ? null : d;
}

export function normalizeTitle(t) {
  if (!t) return '';
  return t
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

export function jaccardTokens(a, b) {
  const A = new Set(a.split(/\W+/).filter(x => x && x.length > 2));
  const B = new Set(b.split(/\W+/).filter(x => x && x.length > 2));
  if (A.size === 0 && B.size === 0) return 0;
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  const union = A.size + B.size - inter;
  return union === 0 ? 0 : inter / union;
}

export const STOPWORDS = new Set([
  'the','a','an','and','or','but','of','to','in','on','for','with','at','by','from','as','is','are','was','were','be','been','has','have','had','not','this','that','these','those','it','its','their','about','after','before','into','over','up','down','out','off','new','news'
]);