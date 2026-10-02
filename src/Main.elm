module Main exposing (main)

import Browser
import Date exposing (Date)
import Dict
import Feeds exposing (FeedResult, OutletResult)
import Html exposing (Html, article, button, details, div, h1, h2, h3, input, label, li, p, section, summary, text, ul)
import Html.Attributes as Attr exposing (attribute, class, disabled, for, href, id, name, rel, required, target, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Html.Lazy
import OutletMatch
import PageViews exposing (AverageDailyViews)
import Rank exposing (RankedStory)
import Story exposing (Story)
import Task
import Time


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }


{-| Passed in from index.js. The key comes from the VITE\_CORSPROXY\_API\_KEY
build-time environment variable, and may be empty.
-}
type alias Flags =
    { corsProxyKey : String }



-- MODEL


{-| The app needs the current date and time zone before it can show the
form (for the default start date and the allowed date range), so it waits
for the clock first.
-}
type Model
    = WaitingForClock Flags
    | Ready ReadyModel


type alias ReadyModel =
    { corsProxyKey : String
    , zone : Time.Zone
    , today : Date

    -- Form inputs are kept as the raw text the user typed, and only
    -- validated on submit, so typing isn't interrupted mid-number.
    , startDateInput : String
    , countInput : String
    , request : Request

    -- Incremented on each search, so responses to an earlier search that
    -- arrive late are ignored.
    , searchCount : Int
    }


type Request
    = NotRequested
    | Invalid String
    | Searching Search


{-| The Wikipedia ranking and each outlet load independently: outlets'
feeds are slow (many pages through the CORS proxy), so the ranked stories
are shown as soon as they're ready, and each outlet fills in when it
arrives.
-}
type alias Search =
    { number : Int
    , query : Query
    , ranking : Ranking
    , outlets : List OutletState
    }


type Ranking
    = RankingPending
    | RankingFailed String
    | Ranked
        { stories : List RankedStory
        , eventsInRange : OutletMatch.EventIndex
        , pageViewsProblem : Maybe String
        }


type OutletState
    = OutletLoading String
    | OutletLoaded OutletResult


{-| An outlet's articles in the date range that weren't attached to a
ranked story, newest first. `oldestLoaded` is set when paging stopped
before the start date, so older articles are missing.
-}
type alias OutletSection =
    { outletName : String
    , articles : List Story
    , oldestLoaded : Maybe Date
    }


type alias Query =
    { startDate : Date
    , count : Int
    }


defaultCount : Int
defaultCount =
    10


minCount : Int
minCount =
    5


maxCount : Int
maxCount =
    20


defaultDaysBack : Int
defaultDaysBack =
    7


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( WaitingForClock flags
    , Task.map2 GotClock Time.here Time.now
        |> Task.perform identity
    )


earliestStartDate : Date -> Date
earliestStartDate today =
    Date.add Date.Years -1 today



-- UPDATE


type Msg
    = GotClock Time.Zone Time.Posix
    | StartDateChanged String
    | CountChanged String
    | FormSubmitted
    | WikipediaFetched Int FeedResult (Result String AverageDailyViews)
    | OutletFetched Int OutletResult


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( model, msg ) of
        ( WaitingForClock flags, GotClock zone now ) ->
            let
                today =
                    Date.fromPosix zone now
            in
            ( Ready
                { corsProxyKey = flags.corsProxyKey
                , zone = zone
                , today = today
                , startDateInput = Date.toIsoString (Date.add Date.Days -defaultDaysBack today)
                , countInput = String.fromInt defaultCount
                , request = NotRequested
                , searchCount = 0
                }
            , Cmd.none
            )

        ( WaitingForClock _, _ ) ->
            ( model, Cmd.none )

        ( Ready readyModel, _ ) ->
            updateReady msg readyModel
                |> Tuple.mapFirst Ready


updateReady : Msg -> ReadyModel -> ( ReadyModel, Cmd Msg )
updateReady msg model =
    case msg of
        GotClock _ _ ->
            ( model, Cmd.none )

        StartDateChanged dateString ->
            ( { model | startDateInput = dateString }, Cmd.none )

        CountChanged countString ->
            ( { model | countInput = countString }, Cmd.none )

        FormSubmitted ->
            case validateQuery model of
                Err problem ->
                    ( { model | request = Invalid problem }, Cmd.none )

                Ok query ->
                    let
                        searchNumber =
                            model.searchCount + 1
                    in
                    ( { model
                        | searchCount = searchNumber
                        , request =
                            Searching
                                { number = searchNumber
                                , query = query
                                , ranking = RankingPending
                                , outlets = List.map (.name >> OutletLoading) Feeds.outlets
                                }
                      }
                      -- Separate commands run in parallel.
                    , Cmd.batch
                        (fetchAndRank model.today searchNumber query
                            :: List.map
                                (Feeds.fetchOutlet model.corsProxyKey query.startDate
                                    >> Task.perform (OutletFetched searchNumber)
                                )
                                Feeds.outlets
                        )
                    )

        WikipediaFetched searchNumber wikipedia pageViews ->
            ( updateSearch searchNumber (\search -> { search | ranking = rank model.zone model.today search.query wikipedia pageViews }) model
            , Cmd.none
            )

        OutletFetched searchNumber outletResult ->
            let
                replaceLoading outletState =
                    case outletState of
                        OutletLoading name ->
                            if name == outletResult.outletName then
                                OutletLoaded outletResult

                            else
                                outletState

                        OutletLoaded _ ->
                            outletState
            in
            ( updateSearch searchNumber (\search -> { search | outlets = List.map replaceLoading search.outlets }) model
            , Cmd.none
            )


{-| Applies the change only if the search is still the current one.
-}
updateSearch : Int -> (Search -> Search) -> ReadyModel -> ReadyModel
updateSearch searchNumber change model =
    case model.request of
        Searching search ->
            if search.number == searchNumber then
                { model | request = Searching (change search) }

            else
                model

        _ ->
            model


fetchAndRank : Date -> Int -> Query -> Cmd Msg
fetchAndRank today searchNumber query =
    Feeds.fetchWikipedia query.startDate today
        |> Task.andThen
            (\wikipedia ->
                PageViews.fetch
                    { startDate = query.startDate, today = today }
                    (topicArticlesByEventCount (Result.withDefault [] wikipedia.stories))
                    |> Task.map Ok
                    |> Task.onError (Err >> Task.succeed)
                    |> Task.map (WikipediaFetched searchNumber wikipedia)
            )
        |> Task.perform identity


validateQuery : ReadyModel -> Result String Query
validateQuery model =
    case ( Date.fromIsoString model.startDateInput, String.toInt model.countInput ) of
        ( Err _, _ ) ->
            Err "Please enter a valid start date."

        ( _, Nothing ) ->
            Err "Please enter a whole number of stories."

        ( Ok startDate, Just count ) ->
            if Date.compare startDate model.today == GT then
                Err "The start date can't be in the future."

            else if Date.compare startDate (earliestStartDate model.today) == LT then
                Err "The start date can't be more than a year ago."

            else
                Ok { startDate = startDate, count = clamp minCount maxCount count }


{-| The articles to look up page views for, most frequently cited first,
since for old date ranges only the first few are looked up.
-}
topicArticlesByEventCount : List Story -> List String
topicArticlesByEventCount wikipediaEvents =
    wikipediaEvents
        |> List.concatMap .topicArticles
        |> List.foldl (\article -> Dict.update article (Maybe.withDefault 0 >> (+) 1 >> Just)) Dict.empty
        |> Dict.toList
        |> List.sortBy (\( _, eventCount ) -> negate eventCount)
        |> List.map Tuple.first


{-| Compares calendar dates in the user's time zone, so "since Monday"
includes everything published on their Monday. Some feeds include items
dated in the future (e.g. event announcements), so those are excluded.
-}
isInRange : Time.Zone -> Date -> Query -> Story -> Bool
isInRange zone today query story =
    Date.isBetween query.startDate today (Story.publishedDate zone story)


rank : Time.Zone -> Date -> Query -> Feeds.FeedResult -> Result String AverageDailyViews -> Ranking
rank zone today query wikipedia pageViews =
    case wikipedia.stories of
        Err problem ->
            RankingFailed ("Couldn't load Wikipedia's Current Events (" ++ problem ++ "), which the ranking is based on.")

        Ok wikipediaEvents ->
            let
                eventsInRange =
                    List.filter (isInRange zone today query) wikipediaEvents
            in
            Ranked
                { stories = Rank.topStories zone (Result.withDefault Dict.empty pageViews) query.count eventsInRange
                , eventsInRange = OutletMatch.eventIndex eventsInRange
                , pageViewsProblem =
                    case pageViews of
                        Ok _ ->
                            Nothing

                        Err problem ->
                            Just ("Couldn't load Wikipedia page views (" ++ problem ++ "), so stories are ranked without them.")
                }


{-| What the results show so far: the ranked stories with any matching
outlet articles attached, and each loaded outlet's remaining articles.
-}
searchResults : Time.Zone -> Date -> Search -> { stories : List RankedStory, outletSections : List OutletSection }
searchResults zone today search =
    case search.ranking of
        Ranked ranked ->
            List.foldl
                (\outletState results ->
                    case outletState of
                        OutletLoaded outlet ->
                            let
                                attached =
                                    outlet.stories
                                        |> Result.withDefault []
                                        |> List.filter (isInRange zone today search.query)
                                        |> OutletMatch.attachToRanked zone ranked.eventsInRange results.stories
                            in
                            { stories = attached.ranked
                            , outletSections = results.outletSections ++ [ toOutletSection zone outlet attached.unmatched ]
                            }

                        OutletLoading _ ->
                            results
                )
                { stories = ranked.stories, outletSections = [] }
                search.outlets

        _ ->
            { stories = [], outletSections = [] }


toOutletSection : Time.Zone -> OutletResult -> List Story -> OutletSection
toOutletSection zone outlet unmatchedArticles =
    let
        newestFirst =
            List.sortBy (Story.publishedDate zone >> Date.toRataDie >> negate) unmatchedArticles
    in
    { outletName = outlet.outletName
    , articles = newestFirst
    , oldestLoaded =
        if outlet.complete then
            Nothing

        else
            outlet.stories
                |> Result.withDefault []
                |> List.map (Story.publishedDate zone)
                |> List.sortBy Date.toRataDie
                |> List.head
    }


searchWarnings : Search -> List String
searchWarnings search =
    let
        failedOutlets =
            List.filterMap
                (\outletState ->
                    case outletState of
                        OutletLoaded { outletName, stories } ->
                            case stories of
                                Err problem ->
                                    Just (outletName ++ ": " ++ problem)

                                Ok _ ->
                                    Nothing

                        OutletLoading _ ->
                            Nothing
                )
                search.outlets
    in
    List.filterMap identity
        [ case search.ranking of
            Ranked { pageViewsProblem } ->
                pageViewsProblem

            _ ->
                Nothing
        , if List.isEmpty failedOutlets then
            Nothing

          else
            Just ("Some outlets couldn't be loaded. " ++ String.join "; " failedOutlets)
        ]



-- VIEW


view : Model -> Html Msg
view model =
    div []
        (h1 [] [ text "Headlines Since" ]
            :: p [] [ text "After being away, catch up on the biggest stories since a date you choose." ]
            :: (case model of
                    WaitingForClock _ ->
                        []

                    Ready readyModel ->
                        viewReady readyModel
               )
            ++ [ section []
                    [ p [] [ text "Stories come from Wikipedia's Current Events portal, ranked by how many people read about each one on Wikipedia." ] ]
               ]
        )


viewReady : ReadyModel -> List (Html Msg)
viewReady model =
    [ viewForm model

    -- The status element stays in place for every request state, because
    -- screen readers only announce changes to an aria-live region that
    -- already exists.
    , div [ id "hs-status", attribute "aria-live" "polite" ] [ text (statusText model.request) ]
    , viewProblems model.request
    , case model.request of
        Searching search ->
            -- Matching outlet articles to stories takes a moment for long
            -- date ranges, so it's skipped when only the form changed.
            Html.Lazy.lazy3 viewSearchResults model.zone model.today search

        _ ->
            text ""
    ]


viewSearchResults : Time.Zone -> Date -> Search -> Html Msg
viewSearchResults zone today search =
    let
        results =
            searchResults zone today search

        stillLoading =
            List.filterMap
                (\outletState ->
                    case outletState of
                        OutletLoading name ->
                            Just name

                        OutletLoaded _ ->
                            Nothing
                )
                search.outlets
    in
    div []
        [ div [ id "hs-results" ] (List.map (viewStory zone) results.stories)
        , case search.ranking of
            Ranked _ ->
                viewOutletSections zone results.outletSections stillLoading

            _ ->
                text ""
        ]


{-| Outlets' articles that weren't matched to a ranked story. They can't be
ranked against Wikipedia events, so each outlet's are listed newest first.
-}
viewOutletSections : Time.Zone -> List OutletSection -> List String -> Html Msg
viewOutletSections zone outletSections stillLoading =
    let
        sectionsWithArticles =
            List.filter (.articles >> List.isEmpty >> not) outletSections
    in
    if List.isEmpty sectionsWithArticles && List.isEmpty stillLoading then
        text ""

    else
        section [ id "hs-outlets" ]
            (h2 [] [ text "More from other outlets" ]
                :: p [ class "outlets-note" ] [ text "Not ranked: these couldn't be matched to the stories above." ]
                :: List.map (viewOutletSection zone) sectionsWithArticles
                ++ (if List.isEmpty stillLoading then
                        []

                    else
                        [ p [ class "outlets-note" ] [ text ("Loading " ++ String.join ", " stillLoading ++ "...") ] ]
                   )
            )


viewOutletSection : Time.Zone -> OutletSection -> Html Msg
viewOutletSection zone outletSection =
    details [ class "outlet" ]
        [ summary []
            [ text (outletSection.outletName ++ " (" ++ String.fromInt (List.length outletSection.articles) ++ ")") ]
        , case outletSection.oldestLoaded of
            Just oldestDate ->
                p [ class "outlets-note" ]
                    [ text ("Only articles back to " ++ Date.format "EEE d MMM y" oldestDate ++ " could be loaded.") ]

            Nothing ->
                text ""
        , ul []
            (List.map
                (\article ->
                    li []
                        [ text (formatPublishedAt zone article.publishedAt ++ ": ")
                        , Html.a [ href article.url, target "_blank", rel "noopener noreferrer" ] [ text article.title ]
                        ]
                )
                outletSection.articles
            )
        ]


isRanking : Request -> Bool
isRanking request =
    case request of
        Searching { ranking } ->
            ranking == RankingPending

        _ ->
            False


viewForm : ReadyModel -> Html Msg
viewForm model =
    Html.form [ onSubmit FormSubmitted, id "hs-form" ]
        [ label [ for "start-date" ] [ text "Start date (up to 1 year ago)" ]
        , input
            [ type_ "date"
            , id "start-date"
            , name "start-date"
            , Attr.min (Date.toIsoString (earliestStartDate model.today))
            , Attr.max (Date.toIsoString model.today)
            , value model.startDateInput
            , required True
            , onInput StartDateChanged
            ]
            []
        , label [ for "count" ] [ text "Number of stories" ]
        , input
            [ type_ "number"
            , id "count"
            , name "count"
            , Attr.min (String.fromInt minCount)
            , Attr.max (String.fromInt maxCount)
            , value model.countInput
            , required True
            , onInput CountChanged
            ]
            []
        , button [ type_ "submit", disabled (isRanking model.request) ] [ text "Find headlines" ]
        ]


statusText : Request -> String
statusText request =
    case request of
        Searching search ->
            case search.ranking of
                RankingPending ->
                    "Fetching headlines..."

                RankingFailed _ ->
                    ""

                Ranked { stories } ->
                    if List.isEmpty stories then
                        "No stories found for this range."

                    else
                        "Found " ++ String.fromInt (List.length stories) ++ " biggest stories"

        _ ->
            ""


viewProblems : Request -> Html Msg
viewProblems request =
    case request of
        Invalid problem ->
            div [ class "error" ] [ text problem ]

        Searching search ->
            div []
                [ case search.ranking of
                    RankingFailed problem ->
                        div [ class "error" ] [ text problem ]

                    _ ->
                        text ""
                , case searchWarnings search of
                    [] ->
                        text ""

                    warnings ->
                        div [ class "warning" ] (List.map (\warning -> p [] [ text warning ]) warnings)
                ]

        NotRequested ->
            text ""


viewStory : Time.Zone -> RankedStory -> Html Msg
viewStory zone { story, relatedReports } =
    let
        sourcePrefix =
            if String.isEmpty story.sourceName then
                ""

            else
                story.sourceName ++ " • "
    in
    article [ class "story" ]
        [ h3 []
            [ Html.a [ href story.url, target "_blank", rel "noopener noreferrer" ] [ text story.title ] ]
        , if List.isEmpty story.topics then
            text ""

          else
            div [ class "story-topics" ] [ text (String.join " › " story.topics) ]
        , div [ class "story-meta" ]
            [ text (sourcePrefix ++ formatPublishedAt zone story.publishedAt) ]
        , viewRelatedReports zone relatedReports
        ]


{-| Other reports of the same event, e.g. later updates to a death toll,
collapsed by default.
-}
viewRelatedReports : Time.Zone -> List Story -> Html Msg
viewRelatedReports zone relatedReports =
    case relatedReports of
        [] ->
            text ""

        _ ->
            details [ class "related-reports" ]
                [ summary []
                    [ text
                        (String.fromInt (List.length relatedReports)
                            ++ (if List.length relatedReports == 1 then
                                    " more report"

                                else
                                    " more reports"
                               )
                            ++ " of this event"
                        )
                    ]
                , ul []
                    (List.map
                        (\report ->
                            li []
                                [ text (formatPublishedAt zone report.publishedAt ++ ": ")
                                , Html.a [ href report.url, target "_blank", rel "noopener noreferrer" ] [ text report.title ]
                                , text (" (" ++ report.sourceName ++ ")")
                                ]
                        )
                        relatedReports
                    )
                ]


{-| e.g. "Fri 2 Oct 2026, 19:40" in the user's time zone, or just
"Fri 2 Oct 2026" for date-only stories.
-}
formatPublishedAt : Time.Zone -> Story.PublishedAt -> String
formatPublishedAt zone publishedAt =
    let
        twoDigits number =
            String.padLeft 2 '0' (String.fromInt number)

        dateFormat =
            "EEE d MMM y"
    in
    case publishedAt of
        Story.ExactTime posix ->
            Date.format dateFormat (Date.fromPosix zone posix)
                ++ ", "
                ++ twoDigits (Time.toHour zone posix)
                ++ ":"
                ++ twoDigits (Time.toMinute zone posix)

        Story.DateOnly date ->
            Date.format dateFormat date
