# Headlines Since

Catch up on the biggest news stories that happened since a date you choose. After being away from the news (e.g. on vacation), get a small curated list of the most significant individual stories from your chosen start date to today.

The code in this project was bootstrapped by Cohere's [`north-mini-code-1.0`](https://cohere.com/blog/north-mini-code) with OpenCode and finished with Anthropic's Claude Code.

## Goals

- **Biggest individual stories**: Ranked by significance (recency, coverage/velocity, impact, soft authority). No forced topic diversification.
- **Elm frontend**: Clean, simple UI and all app logic written in [Elm](https://elm-lang.org/). The only JavaScript is `src/index.js`, which starts the Elm app.
- **Client-side data**: Fetches headlines from RSS feeds in the browser via CORS proxies.
- **Pure static**: Deployed as static HTML/CSS/JS to GitHub Pages (no backend).

## Data Sources

- Google News RSS
- BBC News RSS

Fetched client-side through CORS proxies ([allorigins.win](https://allorigins.win/), then [corsproxy.io](https://corsproxy.io/) if an API key is configured). Each feed only contains the most recent stories (roughly the last day or two), so older start dates don't surface older stories.

## Configuration

The corsproxy.io API key is read from the `VITE_CORSPROXY_API_KEY` environment variable at build time and passed into Elm as a flag. It is optional; without it, only allorigins.win is used.

For local development, copy the example file and fill in your key:
```bash
cp .env.example .env
```

For CI deployment, set `CORS_PROXY_KEY` as a GitHub repository secret; the deploy workflow writes it into `.env` before building.

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

GitHub Actions workflow (`.github/workflows/deploy.yml`) builds the app with Vite and deploys to GitHub Pages on push to `main`. The build step generates `src/config.js` from the `CORS_PROXY_KEY` secret. Enable Pages in repo settings (source: GitHub Actions).

## Code layout

| Module | Purpose |
|---|---|
| `src/Main.elm` | UI: the form, request state, results |
| `src/Feeds.elm` | Fetches each feed via the CORS proxies |
| `src/Rss.elm` | Parses RSS XML into stories |
| `src/Rfc822.elm` | Parses RSS `<pubDate>` dates |
| `src/Cluster.elm` | Groups similar headlines |
| `src/Rank.elm` | Scores and picks the top stories |
| `src/Story.elm` | The `Story` type |

## Algorithm

Stories are filtered to those published on or after the start date (in your time zone), clustered by title similarity (Jaccard) to estimate coverage (how many outlets report the same event), then scored:
- Recency (exponential decay)
- Coverage boost (key for "biggest story")
- Impact keywords (deaths, war, elections, natural disasters, etc.)
- Soft authority boost for major outlets (for Google News items, based on the original outlet rather than the news.google.com link)

Top N individual stories are returned (deduped by URL).
