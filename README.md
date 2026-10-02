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

Fetched client-side through CORS proxies. The CORS proxy API key is injected at build time via a generated config file (`src/JS/config.js`), not committed to the repo.

## Configuration

For local development, copy the example config:
```bash
cp src/JS/config.example.js src/JS/config.js
```

Edit `src/JS/config.js` with your CORS proxy API key if needed. For CI deployment, set `CORS_PROXY_KEY` as a GitHub repository secret.

## Development

Prerequisites: [Elm](https://elm-lang.org/) 0.19.1.

Build the Elm app:
```bash
elm make src/Main.elm --output build/js/elm.js
```

Copy static assets:
```bash
mkdir -p build/js
cp src/index.html build/index.html
cp src/styles.css build/styles.css
cp -r src/JS/* build/js/
```

Then serve `build/` locally:
```bash
python3 -m http.server 8000 --directory build
```

Visit http://localhost:8000.

## Deployment

GitHub Actions workflow (`.github/workflows/deploy.yml`) builds the Elm app and deploys to GitHub Pages on push to `main`. The build step generates `src/JS/config.js` from the `CORS_PROXY_KEY` secret. Enable Pages in repo settings (source: GitHub Actions).

## Algorithm

Stories are filtered by date range, clustered by title similarity (Jaccard) to estimate coverage (how many outlets report the same event), then scored:
- Recency (exponential decay)
- Coverage boost (key for "biggest story")
- Impact keywords (deaths, war, elections, natural disasters, etc.)
- Soft authority boost for major outlets

Top N individual stories are returned (deduped by URL).
