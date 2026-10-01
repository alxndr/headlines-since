# PLAN.md: Headlines Since

## 1. Project Intent & Goals

**Name:** Headlines Since  
**Purpose:** After being away from the news for a week or two, help users quickly catch up by showing only the biggest/most important stories that happened since a given date (up to ~1 year ago), without drowning in noise or stories that are no longer significant.

**Key Requirements:**
- SSR site (static pre-rendered) so it can be hosted for free on GitHub Pages (no backend required).
- Bulk of code in Racket/Scheme; shipped output is HTML/CSS/JS.
- Simple form: (1) past date (max ~1 year ago), (2) number of stories to return.
- **Primary goal (per user):** surface the **biggest individual stories**, not artificially diversify topics. If top stories are all from the same topic (e.g. politics), that's fine.
- Minimal UI (dark mode not a priority at this time).
- No preference for specific outlets; significance/blast-radius is what matters most.

---

## 2. Architecture (SSR on GitHub Pages)

Since GitHub Pages only serves static files, we will use **static site generation (SSG/SSR-at-build)** with Racket, then publish the generated `build/` directory.

| Option | Pros | Cons | Decision |
|---|---|---|---|
| [Pollen](https://docs.racket-lang.org/pollen/) | Racket-native, clean templating (HTML x-exprs), easy to build static site | New to Pollen for some contributors | **Recommended**: keeps templates, structure, and much of the "bulk" in Racket. |
| Custom Racket build script (`build.rkt`) | Max flexibility, minimal dependencies | More plumbing to write/maintain | Viable alternative if Pollen feels heavy. |
| [RacketScript](https://racketscript.github.io/) | Can compile Racket to JS and run logic in browser | Interop complexity, harder to keep pure-SSR templates clean | Useful for porting ranking logic to browser, but not the main SSG driver. |
| [Scribble](https://docs.racket-lang.org/scribble/) | Great for docs, Racket-first | Document-oriented, less natural for app forms/results UI | Not ideal. |

**Chosen approach:** Start with **Pollen** (or fallback to custom Racket build). 
- **Build-time (Racket):** Generate static HTML shell, form, minimal styles, and project structure.
- **Runtime (Browser JS):** Handle form submission, fetch news data from client (no backend), run ranking/selection, render results. This keeps the shipped site static while allowing us to fetch live-ish headlines from public sources.

We can also implement the ranking heuristics in Racket (for clarity/testing) and mirror/port to JS for runtime execution.

---

## 3. Data Sources & Strategy

We need headlines from [user-date, today]. Without a backend, all fetching must happen client-side (CORS-aware).

### Comparison

| Source | Free Tier | Date Range | Auth/Key | CORS from Browser | Notes |
|---|---|---|---|---|---|
| [Google News RSS](https://news.google.com/rss) | Free, no key | Heuristic by `<pubDate>`/RSS; easy to filter client-side | None | Blocked directly; needs CORS proxy | **Strong candidate to start.** No key exposed, simple, broad coverage. |
| [GNews](https://gnews.io/) | 100 req/day, 10k/month | Good date range support (search from/to) | API key required | Works client-side but **key is exposed** in JS | Clean JSON, easy filtering. Acceptable for personal use, but we should document tradeoff. |
| [NewsAPI.org](https://newsapi.org/) | Developer 100 req/day | `from`/`to` supported | API key | **CORS-blocked** from browser (designed for server use) | Cleaner data but requires proxy if used client-side. |
| [MediaStack](https://mediastack.com/) | 500 req/month free | Historical search available | API key | Often needs proxy or server | Decent, but quota tight for frequent testing. |
| [Bing News Search](https://www.microsoft.com/bing/apis/bing-news-search-api) | Free quota via Azure | Flexible date ranges | Azure key | Requires setup; may need proxy | Solid, but more setup friction. |
| [AP RSS](https://apnews.com/rss), [Reuters RSS](https://www.reuters.com/rss), [BBC RSS](https://feeds.bbci.co.uk/news/rss.xml), [Guardian RSS](https://www.theguardian.com/rss) | Free | Varies (often recent-heavy) | None | Same CORS issue | Good to supplement Google News for coverage diversity/authority. Can query multiple RSS feeds in parallel. |

### Proxy Strategy (for RSS & CORS-blocked APIs)

Since many RSS feeds and some APIs block direct browser fetches, we'll use a lightweight CORS proxy for client-side calls:
- **Primary:** `https://api.allorigins.win/raw?url=...` (simple, widely used)
- **Fallbacks:** `https://corsproxy.io/?`, `https://r.jina.ai/` style? Or `https://api.allorigins.win/get?` (if we need JSON wrapper) — prefer raw for RSS XML.
- **Consideration:** Proxy reliability/rate limits. For personal use this is acceptable. Can add fallback in JS if first proxy fails.

**Decision:** **Start with Google News RSS + CORS proxy** (no API key, easiest path). Also design the fetch layer to be pluggable so we can add other RSS sources (AP/Reuters/BBC/Guardian) or swap to GNews if we later accept key exposure or add a tiny proxy.

---

## 4. Ranking: Biggest Individual Stories (Primary)

**User priority:** Return the **biggest individual stories** (top N by significance). Do **not** force topic balancing. Clustering is optional as a helper, but final output is a list of individual stories ranked by importance.

### Signals to Consider

| Signal | Weight Intent | Rationale |
|---|---|---|
| **Recency** | Moderate–high | Stories closer to today often feel more pressing after being away. Still want significant older stories in range if truly big. |
| **Coverage/Velocity** | High | How many distinct outlets report the same event? Strong indicator of blast-radius/significance. |
| **Source authority/quality** | Medium | Weight reputable outlets slightly (AP, Reuters, BBC, NYT, WSJ, etc.) without hard-filtering others. No strict whitelist required. |
| **Impact keywords/heuristics** | Medium | Mentions of: deaths/casualties, war/conflict, elections, policy/law, markets/economy, natural disasters, major court rulings, etc. Simple, explainable. |
| **Magnitude/scale** | Medium | Numbers, regions affected, global reach. |
| **Title prominence/length** | Low | Minor tie-breaker only. |

### Algorithm Sketch

1. **Fetch** all candidate items in [user-date, today] from selected sources (deduplicate by URL or near-duplicate titles).
2. **Normalize**: `title`, `url`, `sourceName`, `publishedAt` (parse to UTC), `description/summary`.
3. **Group/cluster (optional helper)**: find near-duplicates/events by token similarity (Jaccard on title words, strip stopwords) or simple entity overlap. Purpose: compute **coverage count** (how many outlets cover same event) to boost significance. Clusters are not surfaced as topics—just used to inform per-story scoring or to pick the canonical representative.
4. **Score individual stories**:
   - `recencyScore` = exponential/linear decay from today back to `publishedAt` (tune so recent big stories compete fairly with major stories from earlier in range).
   - `coverageBoost` = based on size of the cluster this story belongs to (number of distinct sources covering event). This is key for "biggest story".
   - `authorityBoost` = small bump for known major outlets (soft, non-exclusive).
   - `impactScore` = keyword-based heuristic (presence of impact terms, scale cues).
   - `score = w_rec * recencyScore + w_cov * coverageBoost + w_auth * authorityBoost + w_imp * impactScore`
5. **Rank & select top N**: Sort all individual stories by score desc, return top N. If duplicates remain (same event represented many times), prefer **canonical** story (e.g. from top source in cluster, or best URL/title) and avoid listing near-identical stories back-to-back unless truly different events. But user wants **individual stories** as the key feature—so we may show one strong representative per major event or just let the top N be the highest-scoring individual links (could include different angles). The key constraint: **no forced topic diversification**.
6. **Render**: List with title, source, relative/absolute date, and link to original.

### Implementation Notes
- Prototype algorithm in **Racket** first (data structures, scoring, tests with sample data) for clarity, then port to **JS** for browser runtime (or compile via RacketScript if feasible). 
- Use lightweight entity/token similarity (no heavy ML required initially). Can iterate later.
- Keep heuristics simple and explainable in UI (optional short "how we ranked" note if desired, but minimal UI).

---

## 5. Project Structure

```
headlines-since/
├── .github/workflows/deploy.yml   # Build + deploy to GitHub Pages
├── README.md
├── PLAN.md                        # This file
├── pollen.rkt                     # Pollen config (if using Pollen)
├── info.rkt                       # Racket package info (optional)
├── src/
│   ├── index.html.pm              # Main page template (Pollen/Racket)
│   ├── template.html.pm           # Base template (Pollen)
│   ├── styles.css.pp              # Styles (minimal)
│   ├── ranker.rkt                 # Ranking logic (Racket) — reference/tests
│   └── js/
│       ├── app.js                 # Form, fetch, ranking, render (client)
│       ├── fetchers.js            # RSS/API fetch + proxy handling
│       ├── cluster.js             # Clustering/similarity helpers
│       ├── ranker.js              # Scoring logic (mirrors Racket)
│       └── utils.js               # Date parsing, dedup, etc.
├── build/                         # Generated static output (gitignored in src, deployed)
└── test/                          # (optional) rackunit tests for ranker.rkt
```

If using custom Racket build instead of Pollen, `.pm/.pp` are replaced by Racket scripts that emit files to `build/`.

---

## 6. TODOs & Phased Plan

### Phase 1: Setup & Scaffolding
- [ ] Create GitHub repo `headlines-since` (if not exists)
- [ ] Decide build system: Pollen vs custom Racket build. Document choice in README if needed.
- [ ] Set up basic Racket project structure (`info.rkt` optional)
- [ ] Create `PLAN.md` (this file) — track progress here
- [ ] Scaffold minimal form UI (date input, max = today-365 days; number input, sensible range e.g. 5–20)
- [ ] Set up static build output to `build/`

### Phase 2: Data Fetching (Client-Side)
- [ ] Implement RSS fetcher with CORS proxy (Google News RSS first)
- [ ] Add pluggable fetch layer (support multiple RSS feeds)
- [ ] Parse RSS (DOMParser) and normalize fields
- [ ] Filter by `publishedAt >= userDate`
- [ ] Deduplicate by URL and near-duplicate titles
- [ ] Add fallback proxy(s) and basic error handling
- [ ] Explore adding other sources: AP, Reuters, BBC, Guardian (optional but useful)
- [ ] Evaluate GNews API path (document key-exposure tradeoff) — defer unless RSS coverage insufficient

### Phase 3: Ranking & Selection (Individual Stories First)
- [ ] Write core scoring in JS (`ranker.js`) per algorithm above
- [ ] Implement coverage/cluster detection (token similarity) to power `coverageBoost`
- [ ] Implement recency decay, impact keyword scoring, soft authority boost
- [ ] Select top N individual stories (no forced topic diversity)
- [ ] Prefer canonical representative per event to reduce duplicates
- [ ] Write reference implementation in Racket (`ranker.rkt`) with sample cases (optional but keeps bulk in Racket)
- [ ] Add lightweight tests (Racket `rackunit`) for scoring logic

### Phase 4: UI/UX (Minimal)
- [ ] Minimal, clean styling (`styles.css.pp` or plain CSS)
- [ ] Form + results layout, mobile-friendly
- [ ] Loading, empty state ("No stories found for this range"), error states
- [ ] Show per-story: title, source, date (relative or readable), external link
- [ ] Keep UI minimal as requested

### Phase 5: Build, Deploy & Polish
- [ ] GitHub Actions: build with Racket (Pollen/render) and deploy `build/` to `gh-pages`
- [ ] Enable GitHub Pages from `gh-pages` branch
- [ ] Test across desktop/mobile
- [ ] Update README with purpose, usage, build instructions
- [ ] Verify SSR/static output is correct
- [ ] Manual QA with sample date ranges (recent, 1 week ago, 2 weeks ago, older)

### Phase 6: Future Enhancements (Optional)
- [ ] Add more RSS sources and merge results
- [ ] Tweak weights based on real-world testing
- [ ] Cache results in `localStorage` for identical queries
- [ ] Add "how we ranked" explainer (minimal text)

---

## 7. Open Questions & Decisions Log

| Question | Decision | Date/Notes |
|---|---|---|
| RSS vs API to start? | **Google News RSS + proxy** (no key). Keep fetcher pluggable. | Current |
| Individual stories vs topic clusters? | **Individual stories primary.** No forced diversification. Clusters only to compute coverage. | Per user request |
| Minimal vs dark mode? | **Minimal UI.** Dark mode not important now. | Per user request |
| Outlet preferences? | **None.** Significance/blast-radius only. | Per user request |
| Build system? | **Pollen preferred.** Re-evaluate if friction arises. | Tentative |

---

## 8. Progress Tracking

- [x] PLAN.md created with intent, decisions, TODOs
- [ ] Phase 1 complete
- [ ] Phase 2 complete
- [ ] Phase 3 complete
- [ ] Phase 4 complete
- [ ] Phase 5 complete