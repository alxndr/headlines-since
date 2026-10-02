module Feeds exposing (FeedResult, fetchAll)

{-| Download and parse every RSS feed, via CORS proxies (the feeds don't
allow direct cross-origin requests from a browser).
-}

import Http
import Rss
import Story exposing (Story)
import Task exposing (Task)
import Url


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


feeds : List Feed
feeds =
    [ { name = "Google News", url = "https://news.google.com/rss" }
    , { name = "BBC News", url = "https://feeds.bbci.co.uk/news/rss.xml" }
    ]


{-| Fetches the feeds one after another. The task can't fail; failures are
reported per feed in the results.
-}
fetchAll : String -> Task Never (List FeedResult)
fetchAll corsProxyKey =
    feeds
        |> List.map (fetchFeed (proxies corsProxyKey))
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
order; corsproxy.io is only used when an API key was provided at build time.
-}
proxies : String -> List (String -> String)
proxies corsProxyKey =
    let
        allOrigins feedUrl =
            "https://api.allorigins.win/raw?url=" ++ Url.percentEncode feedUrl

        corsProxyIo feedUrl =
            "https://corsproxy.io/?url="
                ++ Url.percentEncode feedUrl
                ++ "&api-key="
                ++ Url.percentEncode corsProxyKey
    in
    if String.isEmpty corsProxyKey then
        [ allOrigins ]

    else
        [ allOrigins, corsProxyIo ]


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
