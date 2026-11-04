// Thin client for Wikipedia's public REST API (CORS-enabled, no key needed).
// Content is available under CC BY-SA; every card links back to its article.
const API = 'https://en.wikipedia.org/api/rest_v1';
const cache = new Map();

async function getJson(url) {
  const res = await fetch(url, { headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res.json();
}

// Events that happened on this calendar day in history.
// Returns [{year, text, thumb, page: {title, url}}]
export async function onThisDay(month, day) {
  const key = `otd-${month}-${day}`;
  if (cache.has(key)) return cache.get(key);
  const mm = String(month).padStart(2, '0'), dd = String(day).padStart(2, '0');
  const data = await getJson(`${API}/feed/onthisday/events/${mm}/${dd}`);
  const out = (data.events || []).map((e) => {
    const p = (e.pages || [])[0];
    return {
      year: e.year,
      text: e.text,
      thumb: p && p.thumbnail ? p.thumbnail.source : null,
      page: p ? { title: (p.titles && p.titles.normalized) || p.normalizedtitle || p.title.replace(/_/g, ' '), url: p.content_urls ? p.content_urls.desktop.page : `https://en.wikipedia.org/wiki/${encodeURIComponent(p.title)}` } : null,
    };
  });
  cache.set(key, out);
  return out;
}

// A random article summary, skipping stubs, lists and disambiguation pages.
// Returns {title, description, extract, thumb, url} or null.
export async function randomArticle(tries = 4) {
  for (let i = 0; i < tries; i++) {
    const a = await getJson(`${API}/page/random/summary`);
    if (a.type !== 'standard') continue;
    if (!a.extract || a.extract.length < 160) continue;
    if (/^List of|^Lists of/.test(a.title)) continue;
    return {
      title: (a.titles && a.titles.normalized) || a.title,
      description: a.description || '',
      extract: a.extract,
      thumb: a.thumbnail ? a.thumbnail.source : null,
      url: a.content_urls ? a.content_urls.desktop.page : `https://en.wikipedia.org/wiki/${encodeURIComponent(a.title)}`,
    };
  }
  return null;
}
