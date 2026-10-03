# Headlines Since

Catch up on the biggest news stories that happened since a date you choose. After being away from the news (e.g. on vacation), get a small curated list of the most significant individual stories from your chosen start date to today.

The code in this project was bootstrapped by Cohere's [`north-mini-code-1.0`](https://cohere.com/blog/north-mini-code) with OpenCode and finished with Anthropic's Claude Code.

## Goals

- **Biggest individual stories**: Ranked by significance (public interest, number of sources, soft authority), not by how recent they are. Reports of the same event are merged, and a gentle penalty on repeated topics keeps one big ongoing story (e.g. a war) from filling the whole list, without hiding its distinct developments.
- **Elm frontend**: Clean, simple UI and all app logic written in [Elm](https://elm-lang.org/). The only JavaScript is `src/index.js`, which starts the Elm app.
- **Client-side data**: Fetches news in the browser, from Wikipedia directly and from RSS feeds via CORS proxies.
- **Pure static**: Deployed as static HTML/CSS/JS to GitHub Pages (no backend).

## Data Sources

- **[Wikipedia's Current Events portal](https://en.wikipedia.org/wiki/Portal:Current_events)**: an editor-curated list of each day's notable events, with citations. One page per day, so it covers any start date. Fetched directly from the Wikipedia API (no proxy needed).

- **Outlets' RSS feeds**: [Mother Jones](https://www.motherjones.com/), [The Nation](https://www.thenation.com/) and [Common Dreams](https://www.commondreams.org/), fetched through CORS proxies ([corsproxy.io](https://corsproxy.io/) if an API key is configured, falling back to [allorigins.win](https://allorigins.win/)). The app pages back through each feed to the start date, up to 10 pages per outlet.

Outlets' articles can't be ranked against Wikipedia events (they have no Wikipedia topic, so no page views). An article is attached to a ranked story as a related report when it clearly reports the same event; the rest are listed per outlet below the ranked stories, newest first. See [Matching outlets' articles](#matching-outlets-articles).

The ranked stories appear as soon as Wikipedia has loaded; each outlet's section fills in when that outlet's feed has loaded.

Removed sources:
- **Google News RSS**: Google answers requests from CORS proxies with a "Sorry..." block page (HTTP 503).
- **BBC News RSS**: its headlines link to no Wikipedia article, so they can't be given a public-interest score or reliably matched to Wikipedia events about the same story (tested: exact citation URLs matched 0 of 33 headlines; title word overlap and Wikipedia search were both wrong too often). Its significant stories were already covered by Wikipedia.

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

The Tests workflow (`.github/workflows/test.yml`) runs the format check, tests, and a build. It runs on pull requests, and on pushes to `main` as the first step of the deploy workflow, which doesn't deploy unless it passes.

### Using mise for tool versions

With [mise](https://mise.jdx.dev/), the correct Elm version will be used automatically (pinned in `.tool-versions`).

```bash
mise install
mise exec -- npm run dev
```

## Deployment

GitHub Actions workflow (`.github/workflows/deploy.yml`) runs the Tests workflow, then builds the app with Vite and deploys to GitHub Pages, on push to `main`. If the format check, tests or build fail, nothing is deployed. The build step reads the corsproxy.io key from the `VITE_CORSPROXY_API_KEY` secret. Enable Pages in repo settings (source: GitHub Actions).

## Code layout

| Module | Purpose |
|---|---|
| `src/Main.elm` | The form and results; starts the Wikipedia ranking and each outlet's feed loading in parallel, and attaches outlets' articles to ranked stories |
| `src/Feeds.elm` | Fetches Wikipedia's Current Events, and pages through outlets' RSS feeds via the CORS proxies |
| `src/Rss.elm` | Parses RSS XML into stories |
| `src/WikipediaCurrentEvents.elm` | Parses Wikipedia Current Events day pages into stories |
| `src/Rfc822.elm` | Parses RSS `<pubDate>` dates |
| `src/PageViews.elm` | Fetches Wikipedia page views for story topics |
| `src/SameEvent.elm` | Recognises different reports of the same event |
| `src/OutletMatch.elm` | Matches outlets' articles to Wikipedia events |
| `src/Rank.elm` | Scores and picks the top stories |
| `src/Story.elm` | The `Story` type |

## Algorithm

Only Wikipedia events are ranked. They're filtered to those published from the start date through today (in your time zone), then scored as a weighted sum of:

- **Public interest (0.5)**: average daily [Wikipedia page views](https://wikitech.wikimedia.org/wiki/Analytics/AQS/Pageviews) during the date range for the event's most specific topic (e.g. for an event filed under "2026 Iran war › 2026 Iran war fuel crisis", the fuel crisis article), on a log scale. Events without a topic heading (about a fifth of them) get no public-interest score. For date ranges starting more than 60 days ago, only the 50 most-cited topics are looked up, because each needs its own request.
- **Sources (0.15)**: how many news reports the event cites
- **Authority (0.1)**: whether the first outlet the event cites is a major one

Sports and arts stories get half the score, because they draw far more page views than their significance warrants.

Two things are deliberately not factors:
- **Recency**: when catching up after time away, a big story from the first day matters as much as one from today.
- **Keyword lists** (e.g. "killed", "election"): page views measure significance more directly, and a hand-written list skews toward whatever kinds of news it happens to cover.

Stories are then picked one at a time, highest score first:

- **Same event, merged**: a report of an event that's already been picked (e.g. a disaster's death toll updated on later days) is listed under that story as a related report, rather than taking up a slot. Two Wikipedia events count as the same event if they're at most 3 days apart and link to largely the same Wikipedia articles (weighted Jaccard similarity of 0.55 or more, where articles linked from many events, like "United States", count for little).
- **Repeated topics, penalised**: each further story from a topic that's already been picked (e.g. a third story filed under "2026 Iran war") scores 15% less than the one before, so other news can compete.

Duplicate URLs are only considered once.

## Limitations

- **The most recent day is thin.** Wikipedia's page for a day fills in as the day goes on (e.g. at 01:39 UTC on 3 October 2026, that day's page had no events yet, 2 October had 14 and 1 October had 22), so the ranked list has little from today. Outlets' articles from today still appear in their sections, unranked.
- **Long date ranges are partly covered.** Outlets' feeds are paged back at most 10 pages each (about 2 weeks for Mother Jones, 3 months for The Nation, 6 months for Common Dreams), and for ranges starting more than 60 days ago, page views are looked up for only the 50 most-cited topics.
- **Proxy quota.** corsproxy.io's free plan allows 10,000 requests a month, and each outlet feed page is one request (a long date range can use about 30 per search).
- **Outlets' articles rarely match.** See below.

## Matching outlets' articles

An outlet's article (title plus its RSS summary) is compared with each Wikipedia event published within 3 days of it, as sets of words weighted by how rare each word is among the events (cosine similarity of TF-IDF-style weights). It's attached to the event if the similarity is at least 0.25.

This is deliberately strict. Tested on 142 real headlines from the BBC, The Nation, Common Dreams and Mother Jones, hand-checked against the Wikipedia events: only 12 had a matching event at all (these outlets mostly publish opinion and investigations, which Wikipedia doesn't list as events). At 0.25 the matcher found 2 of the 12 and made no wrong matches; looser settings found more but quickly made wrong ones, such as matching "Revolution or No Revolution" to an unrelated arrest in Myanmar.
