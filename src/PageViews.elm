module PageViews exposing (AverageDailyViews, fetch)

{-| How many people read each Wikipedia topic article during the date
range: a measure of public interest in a story.

Recent ranges use the Wikipedia API's page view counts, which cover the
last 60 days and can be fetched for 50 articles per request. Older ranges
need one request per article to the Wikimedia REST API, so only the
`maxArticlesForOldRanges` highest-priority articles are looked up.

Both APIs allow direct requests from the browser (no CORS proxy).

-}

import Date exposing (Date)
import Dict exposing (Dict)
import Http
import Json.Decode as Decode
import List.Extra
import Task exposing (Task)
import Url
import Url.Builder


{-| Average daily views, keyed by the article title as it was requested.
Articles with no data are absent.
-}
type alias AverageDailyViews =
    Dict String Float


{-| The Wikipedia API only reports page views for the last 60 days.
-}
recentDaysAvailable : Int
recentDaysAvailable =
    60


articlesPerRequest : Int
articlesPerRequest =
    50


maxArticlesForOldRanges : Int
maxArticlesForOldRanges =
    50


{-| `articles` should be in priority order (most important first), since
for old date ranges only the first few are looked up.
-}
fetch : { startDate : Date, today : Date } -> List String -> Task String AverageDailyViews
fetch { startDate, today } articles =
    let
        isRecentRange =
            Date.compare startDate (Date.add Date.Days -recentDaysAvailable today) /= LT

        articlesToLookUp =
            if isRecentRange then
                List.Extra.unique articles

            else
                List.take maxArticlesForOldRanges (List.Extra.unique articles)
    in
    articlesToLookUp
        |> List.Extra.greedyGroupsOf articlesPerRequest
        |> List.map queryArticles
        |> Task.sequence
        |> Task.map mergeQueryResults
        |> Task.andThen
            (\queryResult ->
                if isRecentRange then
                    Task.succeed (averagesFromRecentViews startDate queryResult articlesToLookUp)

                else
                    averagesFromRestApi startDate today queryResult articlesToLookUp
            )



-- WIKIPEDIA API: resolves redirects, and has the last 60 days of views


type alias QueryResult =
    { canonicalTitles : Dict String String
    , recentViews : Dict String (List ( String, Maybe Int ))
    }


{-| Topic links often point at redirects (e.g. "Sudanese civil war" redirects
to "Sudanese civil war (2023–present)"), and views are counted on the page
the redirect leads to, so redirects are followed.
-}
queryArticles : List String -> Task String QueryResult
queryArticles articles =
    let
        url =
            Url.Builder.crossOrigin "https://en.wikipedia.org"
                [ "w", "api.php" ]
                [ Url.Builder.string "action" "query"
                , Url.Builder.string "prop" "pageviews"
                , Url.Builder.string "pvipdays" (String.fromInt recentDaysAvailable)
                , Url.Builder.string "redirects" "1"
                , Url.Builder.string "titles" (String.join "|" articles)
                , Url.Builder.string "format" "json"
                , Url.Builder.string "formatversion" "2"

                -- Required for anonymous cross-origin requests.
                , Url.Builder.string "origin" "*"
                ]
    in
    getJson url queryResponseDecoder
        |> Task.map
            (\response ->
                { canonicalTitles =
                    articles
                        |> List.map (\article -> ( article, followRenames response.renames article ))
                        |> Dict.fromList
                , recentViews = Dict.fromList response.pages
                }
            )


type alias QueryResponse =
    { renames : List ( String, String )
    , pages : List ( String, List ( String, Maybe Int ) )
    }


queryResponseDecoder : Decode.Decoder QueryResponse
queryResponseDecoder =
    let
        renameDecoder =
            Decode.map2 Tuple.pair
                (Decode.field "from" Decode.string)
                (Decode.field "to" Decode.string)

        optionalRenames field =
            Decode.maybe (Decode.field field (Decode.list renameDecoder))
                |> Decode.map (Maybe.withDefault [])
    in
    Decode.field "query"
        (Decode.map3 (\normalized redirects pages -> { renames = normalized ++ redirects, pages = pages })
            -- Title normalisation, e.g. "2026_Iran_war" to "2026 Iran war".
            (optionalRenames "normalized")
            (optionalRenames "redirects")
            (Decode.field "pages"
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.field "title" Decode.string)
                        -- Missing pages have no "pageviews" field. Days without
                        -- data are null.
                        (Decode.maybe (Decode.field "pageviews" (Decode.keyValuePairs (Decode.nullable Decode.int)))
                            |> Decode.map (Maybe.withDefault [])
                        )
                    )
                )
            )
        )


{-| Applies normalisation, then redirects. The step limit guards against a
redirect loop.
-}
followRenames : List ( String, String ) -> String -> String
followRenames renames title =
    let
        follow stepsLeft current =
            case ( stepsLeft, List.Extra.find (Tuple.first >> (==) current) renames ) of
                ( 0, _ ) ->
                    current

                ( _, Just ( _, next ) ) ->
                    follow (stepsLeft - 1) next

                ( _, Nothing ) ->
                    current
    in
    follow 5 title


mergeQueryResults : List QueryResult -> QueryResult
mergeQueryResults results =
    { canonicalTitles = List.foldl (.canonicalTitles >> Dict.union) Dict.empty results
    , recentViews = List.foldl (.recentViews >> Dict.union) Dict.empty results
    }


{-| Averages the days from the start date onwards. If the range has no days
with data yet (e.g. it starts today, and today's views aren't published
until tomorrow), the most recent day with data is used instead.
-}
averagesFromRecentViews : Date -> QueryResult -> List String -> AverageDailyViews
averagesFromRecentViews startDate queryResult articles =
    let
        averageFor dailyViews =
            let
                daysWithData =
                    List.filterMap
                        (\( isoDate, views ) -> Maybe.map (\count -> ( isoDate, count )) views)
                        dailyViews

                daysInRange =
                    List.filter (\( isoDate, _ ) -> isoDate >= Date.toIsoString startDate) daysWithData
            in
            case daysInRange of
                [] ->
                    daysWithData
                        |> List.sortBy Tuple.first
                        |> List.reverse
                        |> List.head
                        |> Maybe.map (Tuple.second >> toFloat)

                _ ->
                    Just (average (List.map Tuple.second daysInRange))
    in
    articles
        |> List.filterMap
            (\article ->
                Dict.get article queryResult.canonicalTitles
                    |> Maybe.andThen (\canonicalTitle -> Dict.get canonicalTitle queryResult.recentViews)
                    |> Maybe.andThen averageFor
                    |> Maybe.map (Tuple.pair article)
            )
        |> Dict.fromList



-- WIKIMEDIA REST API: any date range, one article per request


averagesFromRestApi : Date -> Date -> QueryResult -> List String -> Task String AverageDailyViews
averagesFromRestApi startDate today queryResult articles =
    articles
        |> List.map
            (\article ->
                let
                    canonicalTitle =
                        Dict.get article queryResult.canonicalTitles |> Maybe.withDefault article
                in
                restApiDailyViews startDate today canonicalTitle
                    |> Task.map (\dailyViews -> Maybe.map (Tuple.pair article) (maybeAverage dailyViews))
                    -- One article failing (e.g. it was created after the
                    -- range began, so has no data) shouldn't fail the rest.
                    |> Task.onError (\_ -> Task.succeed Nothing)
            )
        |> Task.sequence
        |> Task.map (List.filterMap identity >> Dict.fromList)


{-| Views per day from the start date through yesterday (today's count isn't
published yet).
-}
restApiDailyViews : Date -> Date -> String -> Task String (List Int)
restApiDailyViews startDate today canonicalTitle =
    let
        compactDate date =
            Date.format "yyyyMMdd" date

        url =
            String.join "/"
                [ "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user"
                , Url.percentEncode (String.replace " " "_" canonicalTitle)
                , "daily"
                , compactDate startDate
                , compactDate (Date.add Date.Days -1 today)
                ]
    in
    getJson url (Decode.field "items" (Decode.list (Decode.field "views" Decode.int)))



-- HELPERS


getJson : String -> Decode.Decoder a -> Task String a
getJson url decoder =
    Http.task
        { method = "GET"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.GoodStatus_ _ body ->
                            Decode.decodeString decoder body
                                |> Result.mapError (\_ -> "unexpected response from " ++ url)

                        Http.BadStatus_ metadata _ ->
                            Err ("HTTP " ++ String.fromInt metadata.statusCode)

                        Http.Timeout_ ->
                            Err "request timed out"

                        Http.NetworkError_ ->
                            Err "network error"

                        Http.BadUrl_ badUrl ->
                            Err ("bad URL: " ++ badUrl)
                )
        , timeout = Just 20000
        }


average : List Int -> Float
average numbers =
    toFloat (List.sum numbers) / toFloat (max 1 (List.length numbers))


maybeAverage : List Int -> Maybe Float
maybeAverage numbers =
    if List.isEmpty numbers then
        Nothing

    else
        Just (average numbers)
