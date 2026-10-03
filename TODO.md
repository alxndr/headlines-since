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
    * [x] DW (RSS 1.0, no proxy), The Marshall Project, Popular Information, The New Yorker (no proxy), and the paged The 19th, Prism, Capital B and Truthdig: added 2026-10-03
    * [-] ~~LA Times~~ (won't do): refuses requests from corsproxy.io (HTTP 403), and allorigins.win hangs
    * more candidates from the 2026-10-03 research (all have summaries and need the proxy unless noted):
        * [ ] straight news: Semafor (~250 items, ~10 days), NBC News, CBS News, Washington Post (1-3 days each); Euronews, France 24, Sky News, CS Monitor (~1 day)
        * [ ] progressive/independent: The Lever, Drop Site News, Zeteo (~1 week each)
        * [ ] climate: Grist, Inside Climate News (both page with `?paged=N`)
        * [ ] politics: TPM, Reason (both page), The Bulwark, Time, Salon
        * [ ] tech: The Verge (Atom), 404 Media, Ars Technica
        * no summaries, so they'd rarely match: ABC News (no proxy), CNBC (Atom, no proxy), PBS NewsHour, The Economist, The Hill, Slate, Newsweek, The Dispatch, Rest of World (no proxy)
        * didn't work: AP and The Independent (403), USA Today (402), Kyiv Independent (`/rss/` is 404; find the right URL), HuffPost (0 items), WSJ world (not updated since January 2025)
    * [ ] American Prospect: `https://prospect.org/api/rss/all.rss` answered 429 (Too Many Requests) when probed twice; untested
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
    * [ ] on corsproxy.io's free plan (10,000 requests a month), a search uses ~25 requests for a week-long range, ~47 for a month, and at most 92 (one per outlet feed page)
    * [ ] a paged outlet's pages load one after another, so a month-long range takes ~26s for every outlet to load; pages could be requested several at a time
    * [ ] with 23 outlets, the "More from other outlets" list is long; consider grouping (e.g. news, progressive, magazines)

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
