# Headlines Since

Catch up on the biggest news stories that happened since a date you choose. After being away from the news (e.g. on vacation), get a small curated list of the most significant individual stories from your chosen start date to today.

The code in this project was bootstrapped by Cohere's [`north-mini-code-1.0`](https://cohere.com/blog/north-mini-code) with OpenCode and finished with Anthropic's Claude Code.

## Goals

- **Biggest individual stories**: Ranked by significance (public interest, number of sources, soft authority), not by how recent they are. No forced topic diversification.
- **Elm frontend**: Clean, simple UI and all app logic written in [Elm](https://elm-lang.org/). The only JavaScript is `src/index.js`, which starts the Elm app.
- **Client-side data**: Fetches news in the browser, from Wikipedia directly and from RSS feeds via CORS proxies.
- **Pure static**: Deployed as static HTML/CSS/JS to GitHub Pages (no backend).

## Data Sources

- **[Wikipedia's Current Events portal](https://en.wikipedia.org/wiki/Portal:Current_events)**: an editor-curated list of each day's notable events, with citations. One page per day, so it covers any start date. Fetched directly from the Wikipedia API (no proxy needed).
- **BBC News RSS**: fetched through CORS proxies ([corsproxy.io](https://corsproxy.io/) if an API key is configured, falling back to [allorigins.win](https://allorigins.win/)). The feed only contains roughly the last day or two of stories.

Google News RSS was removed as a source: Google answers requests from CORS proxies with a "Sorry..." block page (HTTP 503).

## Configuration

The corsproxy.io API key is read from the `VITE_CORSPROXY_API_KEY` environment variable at build time and passed into Elm as a flag. It is optional; without it, only allorigins.win is used.

For local development, copy the example file and fill in your key:
```bash
cp .env.example .env
```

For CI deployment, set the same name, `VITE_CORSPROXY_API_KEY`, as a GitHub repository secret; the deploy workflow passes it to the build as an environment variable. corsproxy.io also needs the deployed site's domain (`alxndr.github.io`) allowed in its dashboard.

The key ends up in the public JavaScript bundle, as any key used from the browser must; corsproxy.io's domain allowlist is what stops others from using it.

## Development

### Quick start with Vite

[Vite](https://vitejs.dev/) with [vite-plugin-elm](https://github.com/hmsk/vite-plugin-elm) provides hot module reloading for Elm.

```bash
# Install dependencies
npm install

# Optional: configure the corsproxy.io API key
cp .env.example .env

# Start dev server
npm run dev
```

Visit http://localhost:5173.

### Build for production

```bash
npm run build
```

The built site will be in the `build/` directory. Preview it locally with:

```bash
npm run preview
```

Production builds use the `/headlines-since/` base path (for GitHub Pages), so the preview is at http://localhost:4173/headlines-since/.

### Tests and formatting

```bash
npm test              # elm-test, in tests/
npm run format        # elm-format, rewrites files
npm run format:check  # elm-format, fails if anything needs formatting
```

The Tests workflow (`.github/workflows/test.yml`) runs the format check, tests, and a build on every push and pull request.

### Using mise for tool versions

With [mise](https://mise.jdx.dev/), the correct Elm version will be used automatically (pinned in `.tool-versions`).

```bash
mise install
mise exec -- npm run dev
```

## Deployment

GitHub Actions workflow (`.github/workflows/deploy.yml`) builds the app with Vite and deploys to GitHub Pages on push to `main`. The build step reads the corsproxy.io key from the `VITE_CORSPROXY_API_KEY` secret. Enable Pages in repo settings (source: GitHub Actions).

## Code layout

| Module | Purpose |
|---|---|
| `src/Main.elm` | UI: the form, request state, results |
| `src/Feeds.elm` | Fetches every source (RSS via the CORS proxies; Wikipedia directly) |
| `src/Rss.elm` | Parses RSS XML into stories |
| `src/WikipediaCurrentEvents.elm` | Parses Wikipedia Current Events day pages into stories |
| `src/Rfc822.elm` | Parses RSS `<pubDate>` dates |
| `src/PageViews.elm` | Fetches Wikipedia page views for story topics |
| `src/Rank.elm` | Scores and picks the top stories |
| `src/Story.elm` | The `Story` type |

## Algorithm

Stories are filtered to those published on or after the start date (in your time zone), then scored as a weighted sum of:

- **Public interest (0.5)**: average daily [Wikipedia page views](https://wikitech.wikimedia.org/wiki/Analytics/AQS/Pageviews) during the date range for the story's topic article (e.g. "2026 Iran war"), on a log scale. Only Wikipedia events have topics. For ranges older than 60 days, only the 50 most-cited topics are looked up, because each needs its own request.
- **Sources (0.15)**: how many news reports a Wikipedia event cites
- **Authority (0.1)**: whether the outlet (for Wikipedia events, the first cited outlet) is a major one

Sports and arts stories get half the score, because they draw far more page views than their significance warrants.

Two things are deliberately not factors:
- **Recency**: when catching up after time away, a big story from the first day matters as much as one from today.
- **Keyword lists** (e.g. "killed", "election"): page views measure significance more directly, and a hand-written list skews toward whatever kinds of news it happens to cover.

Top N individual stories are returned (deduped by URL).
