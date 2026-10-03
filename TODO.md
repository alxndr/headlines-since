# TODOs

* [x] use corsproxy.io (with API key) first, fallback to allorigins.win

* adjust story-ranking weights:
    * [x] reduce recency bias to 0 (removed entirely)
    * [x] review other weights (now: Wikipedia page views 0.5, cited sources 0.15, major outlet 0.1)
    * [x] can we remove the hardcoded list of "impact terms" and rely on other signals to determine what stories are important?

* add more sources (findings from 2026-10-02 research; "proxy" = no CORS headers, so it needs a CORS proxy)
    * [x] Mother Jones: `https://www.motherjones.com/feed/`, 10 items/page; WordPress paging (`?paged=N`) reaches back ~1 year (paged=200 → Sept 2025); proxy
    * [x] Vox: `https://www.vox.com/rss/index.xml`, 10 items (~2 days); no paging; proxy; Atom
    * [x] The Nation: `https://www.thenation.com/feed/?post_type=article`, 50 items (~1 week) per page; `&paged=N` works (paged=10 → July 2026); proxy
    * [x] [Common Dreams](https://www.commondreams.org/): `https://www.commondreams.org/feeds/feed.rss`, 30 items (~2.5 weeks); `?page=N` works; proxy
    * [x] NYT RSS: `https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml`, 25 items (~1 day); **no proxy needed** (CORS `*`)
    * [ ] NYT APIs (free key; CORS `*`; 5 req/min, 500/day per key, shared by every visitor): Article Search can filter by date and by front page (`print_page`), a strong "importance" signal; Archive API returns a whole month (large)
    * [x] The Intercept (paged), ProPublica, Democracy Now!, Truthout, Guardian US RSS, NPR, Axios, Politico, Jacobin (Atom), The Atlantic (Atom): added 2026-10-02
    * [ ] American Prospect: `https://prospect.org/api/rss/all.rss` answered 429 (Too Many Requests) when probed; untested
    * [ ] In These Times: `https://inthesetimes.com/rss`, 20 items (~3.5 weeks); no summaries; paging ignored; proxy
    * [ ] Guardian Content API (free key; CORS `*`; reportedly 4000/day non-commercial): date-range search, but no importance ranking; the old public `test` key no longer works
    * [-] ~~Reuters~~ (won't do): no public RSS any more (404); Google News search `site:reuters.com` was the usual workaround, but Google blocks proxies
    * [-] ~~CNN~~ (won't do): RSS abandoned (`rss.cnn.com` feeds last updated 2023/2024)

* [ ] link to articles thru archive.is proxy

* [ ] debate publishing the RFC822-parsing file into a proper Elm package?

* duplicate stories
    * [ ] an outlet's article about a ranked event usually still appears in that outlet's unranked section, because the strict matcher rarely recognises the match (see below)
    * [x] reports of the same event on different days (e.g. death toll updates) are merged, for Wikipedia events
    * [ ] the first report of an event and later updates aren't always merged when they share a specific topic but few other links (e.g. "A doublet earthquake strikes Yaracuy" and "The confirmed toll of the earthquakes in Venezuela rises", both under "2026 Venezuela earthquakes"); idea: treat a topic with only a few events in the range as a single event
    * [ ] if Google News comes back as a source: its titles end in " - Outlet Name"; strip the suffix (the outlet is already shown separately)

* outlets
    * [ ] outlets' articles rarely match a Wikipedia event (the strict matcher found 2 of 12 true matches in testing); a better matcher (e.g. a language model) would need a backend to hold an API key
    * [ ] on corsproxy.io's free plan (10,000 requests a month), a search uses ~16-20 requests for a week-long range and up to ~50 for long ranges (one per outlet feed page)

* coverage
    * [ ] the most recent day is thin in the ranked list, because Wikipedia's page for a day fills in as the day goes on (outlets' articles from today do appear, unranked); a source of ranked same-day news would help

* smaller trade-offs from the Elm port
    * [ ] Elm's HTTP requests can't set fetch's `cache: 'no-store'` like the old JS did; check whether browser/proxy caching ever serves stale feeds
    * [x] feeds are fetched one after another; fetch them in parallel if loading feels slow (outlets now load in parallel with each other and with Wikipedia; each outlet's pages still load one after another)
    * [ ] `Time.here` is a fixed UTC offset, so displayed times and the start-date cutoff can be an hour off around daylight-saving changes (fix: `justinmimbs/timezone-data`)

* ops
    * warnings on CI
        * [x] (switched to `ubuntu-26.04` explicitly, ahead of the migration) `"The ubuntu-latest label will migrate to Ubuntu 26 beginning October 19, 2026. For more information, see https://github.com/actions/runner-images/issues/14748"`
        * [x] (upgraded to checkout@v7, setup-node@v7, upload-pages-artifact@v5 and deploy-pages@v5, which run on Node 24; the CI build itself also moved from Node 20, end-of-life since April 2026, to Node 24) `Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/checkout@v4, actions/setup-node@v4. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/`
