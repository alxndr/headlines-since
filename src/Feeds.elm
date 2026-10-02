module Feeds exposing (FeedResult, fetchAll)

{-| Download and parse every news source:

  - RSS feeds, via CORS proxies (the feeds don't allow direct cross-origin
    requests from a browser). These only cover the last day or two.
  - Wikipedia's Current Events portal, which the browser can fetch directly,
    and which covers any date range.

-}

import Date exposing (Date)
import Http
import Json.Decode as Decode
import List.Extra
import Rss
import Story exposing (Story)
import Task exposing (Task)
import Url
import Url.Builder
import WikipediaCurrentEvents


type alias Feed =
    { name : String
    , url : String
    }


{-| Each feed succeeds or fails on its own, so one broken feed doesn't hide
the stories from the others.
-}
type alias FeedResult =
    { feedName : String
    , stories : Result String (List Story)
    }


{-| Currently empty; the RSS and CORS proxy code is kept for adding outlets.

Removed sources:

  - Google News (<https://news.google.com/rss>): Google answers requests from
    CORS proxies with a "Sorry..." block page (HTTP 503).
  - BBC News (<https://feeds.bbci.co.uk/news/rss.xml>): its headlines can't
    be matched to Wikipedia events reliably, so they couldn't be ranked or
    merged with them, and its significant stories were already on Wikipedia.

-}
rssFeeds : List Feed
rssFeeds =
    []


{-| Fetches the sources one after another. The task can't fail; failures
are reported per source in the results.
-}
fetchAll : { corsProxyKey : String, startDate : Date, today : Date } -> Task Never (List FeedResult)
fetchAll { corsProxyKey, startDate, today } =
    (fetchWikipedia startDate today
        :: List.map (fetchFeed (proxies corsProxyKey)) rssFeeds
    )
        |> Task.sequence


fetchFeed : List (String -> String) -> Feed -> Task Never FeedResult
fetchFeed proxyUrlBuilders feed =
    fetchViaProxies proxyUrlBuilders feed.url
        |> Task.andThen (Rss.parse >> resultToTask)
        |> Task.map Ok
        |> Task.onError (Err >> Task.succeed)
        |> Task.map (\stories -> { feedName = feed.name, stories = stories })


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


{-| Tries each proxy until one returns something that looks like XML. If
they all fail, the last proxy's error is reported.
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
