# Headlines Since

Catch up on the biggest news stories that happened since a date you choose. After being away from the news (e.g. on vacation), get a small curated list of the most significant individual stories from your chosen start date to today.

## Goals

- **Biggest individual stories**: Ranked by significance (recency, coverage/velocity, impact, soft authority). No forced topic diversification.
- **Static SSR/SSG**: Built with Racket/Pollen, deployed as static HTML/CSS/JS to GitHub Pages (no backend).
- **Client-side data**: Fetches headlines from RSS feeds in the browser via CORS proxies.
- **Bulk in Racket**: Templates and build in Racket (Pollen). Client logic is written in vanilla JS (with RacketScript source also provided under `src/client/`).

## Data Sources

- Google News RSS
- AP RSS
- Reuters RSS
- BBC RSS
- Guardian RSS

Fetched client-side through CORS proxies (`allorigins.win` primary, `corsproxy.io` fallback).

## Development

Prerequisites: [Racket](https://racket-lang.org/) 8.18+, [Pollen](https://docs.racket-lang.org/pollen/).

With [mise](https://mise.jdx.dev/):

```bash
mise install
mise exec -- raco pollen render src
```

Then serve `build/` locally:
```bash
python3 -m http.server 8000 --directory build
```

Visit http://localhost:8000.

## Deployment

GitHub Actions workflow (`.github/workflows/deploy.yml`) builds and deploys to GitHub Pages on push to `main`. Enable Pages in repo settings (source: GitHub Actions).

## Algorithm

Stories are filtered by date range, clustered by title similarity (Jaccard) to estimate coverage (how many outlets report the same event), then scored:
- Recency (exponential decay)
- Coverage boost (key for "biggest story")
- Impact keywords (deaths, war, elections, natural disasters, etc.)
- Soft authority boost for major outlets

Top N individual stories are returned (deduped by URL).