# TODOs

* [ ] use corsproxy.io (with API key) first, fallback to allorigins.win

* adjust story-ranking weights:
    * [ ] reduce recency bias to 0
    * [ ] review other weights

* add more sources (findings from 2026-10-02 research; "proxy" = no CORS headers, so it needs a CORS proxy)
    * [ ] Mother Jones: `https://www.motherjones.com/feed/`, 10 items/page; WordPress paging (`?paged=N`) reaches back ~1 year (paged=200 → Sept 2025); proxy
    * [ ] Vox: `https://www.vox.com/rss/index.xml`, 10 items (~2 days); no paging; proxy
    * [ ] The Nation: `https://www.thenation.com/feed/?post_type=article`, 50 items (~1 week) per page; `&paged=N` works (paged=10 → July 2026); proxy
    * [ ] [Common Dreams](https://www.commondreams.org/): `https://www.commondreams.org/feeds/feed.rss`, 30 items (~2.5 weeks); `?page=N` works; proxy
    * [ ] ~~Reuters~~: no public RSS any more (404); Google News search `site:reuters.com` was the usual workaround, but Google blocks proxies
    * [ ] ~~CNN~~: RSS abandoned (`rss.cnn.com` feeds last updated 2023/2024)
    * [ ] MS NOW: `https://www.ms.now/feed`, 10 items (same day only); paging params ignored; proxy
    * [ ] NYT RSS: `https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml`, 25 items (~1 day); **no proxy needed** (CORS `*`)
    * [ ] NYT APIs (free key; CORS `*`; 5 req/min, 500/day per key, shared by every visitor): Article Search can filter by date and by front page (`print_page`), a strong "importance" signal; Archive API returns a whole month (large)
    * [ ] Guardian Content API (free key; CORS `*`; reportedly 4000/day non-commercial): date-range search, but no importance ranking; the old public `test` key no longer works

* [ ] link to articles thru archive.is proxy

* [ ] debate publishing the RFC822-parsing file into a proper Elm package?

* duplicate stories
    * [ ] the same event can appear twice from different sources (e.g. a Wikipedia event summary and a BBC headline), with different URLs, so deduping by URL misses them
    * [ ] if Google News comes back as a source: its titles end in " - Outlet Name", which adds noise words to the title-similarity clustering; strip the suffix before comparing

* smaller trade-offs from the Elm port
    * [ ] Elm's HTTP requests can't set fetch's `cache: 'no-store'` like the old JS did; check whether browser/proxy caching ever serves stale feeds
    * [ ] feeds are fetched one after another; fetch them in parallel if loading feels slow
    * [ ] `Time.here` is a fixed UTC offset, so displayed times and the start-date cutoff can be an hour off around daylight-saving changes (fix: `justinmimbs/timezone-data`)
