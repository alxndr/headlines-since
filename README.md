# Headlines Since

Catch up on the biggest news stories that happened since a date you choose. After being away from the news (e.g. on vacation), get a small curated list of the most significant individual stories from your chosen start date to today.

## Goals

- **Biggest individual stories**: Ranked by significance (recency, coverage/velocity, impact, soft authority). No forced topic diversification.
- **Elm frontend**: Clean, simple UI built with [Elm](https://elm-lang.org/) talking to JS via ports.
- **Client-side data**: Fetches headlines from RSS feeds in the browser via CORS proxies.
- **Pure static**: Deployed as static HTML/CSS/JS to GitHub Pages (no backend).

## Data Sources

- Google News RSS
- BBC News RSS

Fetched client-side through CORS proxies. The CORS proxy API key is injected at build time via a generated config file (`src/config.js`), not committed to the repo.

## Configuration

For local development, copy the example config:
```bash
cp src/config.example.js src/config.js
```

Edit `src/config.js` with your CORS proxy API key if needed. For CI deployment, set `CORS_PROXY_KEY` as a GitHub repository secret.

## Development

### Quick start with Vite

[Vite](https://vitejs.dev/) with [vite-plugin-elm](https://github.com/hmsk/vite-plugin-elm) provides hot module reloading for Elm.

```bash
# Install dependencies
npm install

# Copy config if needed
cp src/config.example.js src/config.js

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

### Using mise for tool versions

With [mise](https://mise.jdx.dev/), the correct Elm version will be used automatically (pinned in `.tool-versions`).

```bash
mise install
mise exec -- npm run dev
```

## Deployment

GitHub Actions workflow (`.github/workflows/deploy.yml`) builds the app with Vite and deploys to GitHub Pages on push to `main`. The build step generates `src/config.js` from the `CORS_PROXY_KEY` secret. Enable Pages in repo settings (source: GitHub Actions).

## Algorithm

Stories are filtered by date range, clustered by title similarity (Jaccard) to estimate coverage (how many outlets report the same event), then scored:
- Recency (exponential decay)
- Coverage boost (key for "biggest story")
- Impact keywords (deaths, war, elections, natural disasters, etc.)
- Soft authority boost for major outlets

Top N individual stories are returned (deduped by URL).
