module Feeds exposing (FeedResult, Outlet, OutletResult, fetchOutlet, fetchWikipedia, outlets)

{-| Download and parse every news source:

  - Wikipedia's Current Events portal, which the browser can fetch directly,
    and which covers any date range. Its events are what gets ranked.
  - News outlets' RSS feeds, via CORS proxies (the feeds don't allow direct
    cross-origin requests from a browser). Their articles can't be ranked
    against Wikipedia events, so they're shown separately, or attached to
    the Wikipedia event they report when that can be told reliably.

-}

import Date exposing (Date)
import Http
import Json.Decode as Decode
import List.Extra
import Rss
import Story exposing (Story)
import Task exposing (Task)
import Time
import Url
import Url.Builder
import WikipediaCurrentEvents


{-| Each source succeeds or fails on its own, so one broken source doesn't
hide the stories from the others.
-}
type alias FeedResult =
    { feedName : String
    , stories : Result String (List Story)
    }


{-| `complete` is False when paging stopped before reaching the start date
(the page limit was hit, or a later page failed to load), so older articles
are missing.
-}
type alias OutletResult =
    { outletName : String
    , stories : Result String (List Story)
    , complete : Bool
    }


{-| An outlet's RSS or Atom feed.

Removed sources:

  - Google News (<https://news.google.com/rss>): Google answers requests from
    CORS proxies with a "Sorry..." block page (HTTP 503).
  - BBC News (<https://feeds.bbci.co.uk/news/rss.xml>): no paging (only the
    last day or two), and its significant stories were already on Wikipedia.

-}
type alias Outlet =
    { name : String
    , pages : FeedPages
    , access : Access
    }


{-| Some feeds can be paged back through (page 1 is the newest); the rest
only have their latest items.
-}
type FeedPages
    = Paged (Int -> String)
    | LatestOnly String


{-| Most feeds don't allow cross-origin requests from a browser, so they go
through a CORS proxy; the few that do are fetched directly.
-}
type Access
    = ViaProxy
    | Direct


{-| In alphabetical order, which is the order their sections are shown in.
How far back the latest-only feeds reach was measured in October 2026.
-}
outlets : List Outlet
outlets =
    [ -- ~100 items, about a week
      { name = "Axios", pages = LatestOnly "https://api.axios.com/feed/", access = ViaProxy }
    , { name = "Common Dreams"
      , pages = Paged (\page -> "https://www.commondreams.org/feeds/feed.rss?page=" ++ String.fromInt page)
      , access = ViaProxy
      }

    -- ~40 items, about 12 days
    , { name = "Democracy Now!", pages = LatestOnly "https://www.democracynow.org/democracynow.rss", access = ViaProxy }

    -- Atom; ~20 items, about 4 days
    , { name = "Jacobin", pages = LatestOnly "https://jacobin.com/feed/", access = ViaProxy }
    , { name = "Mother Jones"
      , pages = Paged (\page -> "https://www.motherjones.com/feed/?paged=" ++ String.fromInt page)
      , access = ViaProxy
      }

    -- ~10 items, about a day
    , { name = "NPR", pages = LatestOnly "https://feeds.npr.org/1001/rss.xml", access = ViaProxy }

    -- ~30 items, about 10 days
    , { name = "Politico", pages = LatestOnly "https://rss.politico.com/politics-news.xml", access = ViaProxy }

    -- ~20 items, about 2 weeks
    , { name = "ProPublica", pages = LatestOnly "https://www.propublica.org/feeds/propublica/main", access = ViaProxy }

    -- Atom; ~25 items, about 2 days
    , { name = "The Atlantic", pages = LatestOnly "https://www.theatlantic.com/feed/all/", access = ViaProxy }

    -- ~35 items, about 2 days
    , { name = "The Guardian (US)", pages = LatestOnly "https://www.theguardian.com/us-news/rss", access = ViaProxy }
    , { name = "The Intercept"
      , pages = Paged (\page -> "https://theintercept.com/feed/?lang=en&paged=" ++ String.fromInt page)
      , access = ViaProxy
      }
    , { name = "The Nation"
      , pages = Paged (\page -> "https://www.thenation.com/feed/?post_type=article&paged=" ++ String.fromInt page)
      , access = ViaProxy
      }

    -- ~20 items, about 2 days; allows cross-origin requests
    , { name = "The New York Times", pages = LatestOnly "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", access = Direct }

    -- ~100 items, about 10 days
    , { name = "Truthout", pages = LatestOnly "https://truthout.org/feed/", access = ViaProxy }

    -- Atom; ~10 items, about 3 days
    , { name = "Vox", pages = LatestOnly "https://www.vox.com/rss/index.xml", access = ViaProxy }
    ]


{-| Each page is a request through the CORS proxy, so paging is capped.
Pages hold 10 (Mother Jones), 20 (The Intercept), 30 (Common Dreams) or 50
(The Nation) articles, so 10 pages cover roughly 2 weeks, 3 months, 6
months, and 3 months respectively (measured in October 2026).
-}
maxPagesPerOutlet : Int
maxPagesPerOutlet =
    10


{-| Pages through an outlet's feed (one page at a time, newest first) until
it reaches the start date. The task can't fail; failures are reported in
the result.
-}
fetchOutlet : String -> Date -> Outlet -> Task Never OutletResult
fetchOutlet corsProxyKey startDate outlet =
    let
        urlBuilders =
            case outlet.access of
                ViaProxy ->
                    proxies corsProxyKey

                Direct ->
                    [ identity ]

        ( pageUrl, lastPage ) =
            case outlet.pages of
                Paged urlForPage ->
                    ( urlForPage, maxPagesPerOutlet )

                LatestOnly url ->
                    ( \_ -> url, 1 )

        result stories complete =
            { outletName = outlet.name
            , stories = Result.map (List.map (\story -> { story | sourceName = outlet.name })) stories
            , complete = complete
            }

        -- Deciding when to stop paging only needs approximate dates, so UTC
        -- is used rather than the viewer's time zone.
        isBeforeStartDate story =
            Date.compare (Story.publishedDate Time.utc story) startDate == LT

        fetchPage page storiesSoFar =
            fetchViaProxies urlBuilders (pageUrl page)
                |> Task.andThen (Rss.parse >> resultToTask)
                |> Task.map Ok
                |> Task.onError (Err >> Task.succeed)
                |> Task.andThen
                    (\pageResult ->
                        case pageResult of
                            Ok pageStories ->
                                if List.isEmpty pageStories || List.any isBeforeStartDate pageStories then
                                    Task.succeed (result (Ok (storiesSoFar ++ pageStories)) True)

                                else if page >= lastPage then
                                    -- No more pages, but the start date wasn't reached.
                                    Task.succeed (result (Ok (storiesSoFar ++ pageStories)) False)

                                else
                                    fetchPage (page + 1) (storiesSoFar ++ pageStories)

                            Err problem ->
                                if page == 1 then
                                    Task.succeed (result (Err problem) False)

                                else
                                    -- Keep the pages that did load.
                                    Task.succeed (result (Ok storiesSoFar) False)
                    )
    in
    fetchPage 1 []


resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err error ->
            Task.fail error


{-| Each proxy wraps a feed URL in its own URL. Proxies are tried in this
order. corsproxy.io comes first because the free allorigins.win often fails
or hangs until the request times out; corsproxy.io is only used when an API
key was provided at build time.
-}
proxies : String -> List (String -> String)
proxies corsProxyKey =
    let
        allOrigins feedUrl =
            "https://api.allorigins.win/raw?url=" ++ Url.percentEncode feedUrl

        -- Format from https://corsproxy.io/docs/how-to-use/
        corsProxyIo feedUrl =
            "https://corsproxy.io/?key="
                ++ Url.percentEncode corsProxyKey
                ++ "&url="
                ++ Url.percentEncode feedUrl
    in
    if String.isEmpty corsProxyKey then
        [ allOrigins ]

    else
        [ corsProxyIo, allOrigins ]


{-| Tries each URL builder (each proxy, or `identity` for a direct request)
until one returns something that looks like XML. If they all fail, the
last one's error is reported.
-}
fetchViaProxies : List (String -> String) -> String -> Task String String
fetchViaProxies proxyUrlBuilders feedUrl =
    List.foldl
        (\buildProxyUrl previousAttempt ->
            previousAttempt
                |> Task.onError (\_ -> fetchText (buildProxyUrl feedUrl))
        )
        (Task.fail "no CORS proxies configured")
        proxyUrlBuilders


fetchText : String -> Task String String
fetchText url =
    Http.task
        { method = "GET"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , resolver = Http.stringResolver checkResponse
        , timeout = Just 20000
        }


checkResponse : Http.Response String -> Result String String
checkResponse response =
    case response of
        Http.BadUrl_ url ->
            Err ("bad URL: " ++ url)

        Http.Timeout_ ->
            Err "request timed out"

        Http.NetworkError_ ->
            Err "network error"

        Http.BadStatus_ metadata _ ->
            Err ("HTTP " ++ String.fromInt metadata.statusCode)

        Http.GoodStatus_ _ body ->
            let
                start =
                    String.toLower (String.left 20 (String.trimLeft body))
            in
            -- Proxies sometimes return an empty body or an HTML error page
            -- with a 200 status.
            if String.isEmpty (String.trim body) then
                Err "empty response"

            else if String.startsWith "<!doctype" start || String.startsWith "<html" start then
                Err "got HTML instead of XML"

            else
                Ok body



-- WIKIPEDIA


{-| The Wikipedia API returns at most 50 pages per request.
-}
wikipediaPagesPerRequest : Int
wikipediaPagesPerRequest =
    50


fetchWikipedia : Date -> Date -> Task Never FeedResult
fetchWikipedia startDate today =
    -- Date.range excludes its end date, so end the day after today.
    Date.range Date.Day 1 startDate (Date.add Date.Days 1 today)
        |> List.Extra.greedyGroupsOf wikipediaPagesPerRequest
        |> List.map fetchWikipediaDays
        |> Task.sequence
        |> Task.map (List.concat >> Ok)
        |> Task.onError (Err >> Task.succeed)
        |> Task.map (\stories -> { feedName = "Wikipedia Current Events", stories = stories })


{-| Days without a page yet (typically today, early on) are skipped.
-}
fetchWikipediaDays : List Date -> Task String (List Story)
fetchWikipediaDays dates =
    let
        datesByTitle =
            List.map (\date -> ( WikipediaCurrentEvents.pageTitle date, date )) dates

        url =
            Url.Builder.crossOrigin "https://en.wikipedia.org"
                [ "w", "api.php" ]
                [ Url.Builder.string "action" "query"
                , Url.Builder.string "prop" "revisions"
                , Url.Builder.string "rvprop" "content"
                , Url.Builder.string "rvslots" "main"
                , Url.Builder.string "titles" (String.join "|" (List.map Tuple.first datesByTitle))
                , Url.Builder.string "format" "json"
                , Url.Builder.string "formatversion" "2"

                -- Required for anonymous cross-origin requests.
                , Url.Builder.string "origin" "*"
                ]

        storiesFromPage page =
            case ( page.content, List.Extra.find (Tuple.first >> (==) page.title) datesByTitle ) of
                ( Just wikitext, Just ( _, date ) ) ->
                    WikipediaCurrentEvents.parse date wikitext

                _ ->
                    []
    in
    fetchText url
        |> Task.andThen
            (Decode.decodeString wikipediaPagesDecoder
                >> Result.mapError (\_ -> "unexpected response from Wikipedia")
                >> resultToTask
            )
        |> Task.map (List.concatMap storiesFromPage)


wikipediaPagesDecoder : Decode.Decoder (List { title : String, content : Maybe String })
wikipediaPagesDecoder =
    Decode.at [ "query", "pages" ]
        (Decode.list
            (Decode.map2 (\title content -> { title = title, content = content })
                (Decode.field "title" Decode.string)
                -- Missing pages have no "revisions" field.
                (Decode.maybe
                    (Decode.field "revisions"
                        (Decode.index 0 (Decode.at [ "slots", "main", "content" ] Decode.string))
                    )
                )
            )
        )
