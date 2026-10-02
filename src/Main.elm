module Main exposing (main)

import Browser
import Cluster
import Date exposing (Date)
import Feeds exposing (FeedResult)
import Html exposing (Html, article, button, div, h1, h3, input, label, p, section, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, for, href, id, name, rel, required, target, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Rank
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
    }


type Request
    = NotRequested
    | Loading
    | Failed String
    | Loaded
        { stories : List Story
        , failedFeeds : List ( String, String )
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
    | FeedsFetched Query Time.Posix (List FeedResult)


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
                    ( { model | request = Failed problem }, Cmd.none )

                Ok query ->
                    ( { model | request = Loading }
                    , Feeds.fetchAll model.corsProxyKey
                        -- Read the clock after fetching, so recency is
                        -- measured from when the stories arrived.
                        |> Task.andThen (\feedResults -> Task.map (\now -> ( now, feedResults )) Time.now)
                        |> Task.perform (\( now, feedResults ) -> FeedsFetched query now feedResults)
                    )

        FeedsFetched query now feedResults ->
            ( { model | request = rankFeedResults model.zone query now feedResults }, Cmd.none )


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


rankFeedResults : Time.Zone -> Query -> Time.Posix -> List FeedResult -> Request
rankFeedResults zone query now feedResults =
    let
        loadedStories =
            List.concatMap (.stories >> Result.withDefault []) feedResults

        failedFeeds =
            List.filterMap
                (\feedResult ->
                    case feedResult.stories of
                        Ok _ ->
                            Nothing

                        Err problem ->
                            Just ( feedResult.feedName, problem )
                )
                feedResults

        -- Compare calendar dates in the user's time zone, so "since
        -- Monday" includes everything published on their Monday.
        isOnOrAfterStartDate story =
            Date.compare (Date.fromPosix zone story.publishedAt) query.startDate /= LT
    in
    if List.length failedFeeds == List.length feedResults then
        Failed ("Couldn't load any news feeds. " ++ describeFailedFeeds failedFeeds)

    else
        Loaded
            { stories =
                loadedStories
                    |> List.filter isOnOrAfterStartDate
                    |> Cluster.withClusterSizes
                    |> Rank.topStories now query.count
            , failedFeeds = failedFeeds
            }


describeFailedFeeds : List ( String, String ) -> String
describeFailedFeeds failedFeeds =
    failedFeeds
        |> List.map (\( feedName, problem ) -> feedName ++ ": " ++ problem)
        |> String.join "; "



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
                    [ p [] [ text "Biggest individual stories ranked by significance (no forced topic diversification)." ] ]
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
    , div [ id "hs-results" ]
        (case model.request of
            Loaded { stories } ->
                List.map (viewStory model.zone) stories

            _ ->
                []
        )
    ]


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
        , button [ type_ "submit", disabled (model.request == Loading) ] [ text "Find headlines" ]
        ]


statusText : Request -> String
statusText request =
    case request of
        NotRequested ->
            ""

        Loading ->
            "Fetching headlines..."

        Failed _ ->
            ""

        Loaded { stories } ->
            if List.isEmpty stories then
                "No stories found for this range."

            else
                "Found " ++ String.fromInt (List.length stories) ++ " biggest stories"


viewProblems : Request -> Html Msg
viewProblems request =
    case request of
        Failed problem ->
            div [ class "error" ] [ text problem ]

        Loaded { failedFeeds } ->
            if List.isEmpty failedFeeds then
                text ""

            else
                div [ class "warning" ]
                    [ text ("Some feeds couldn't be loaded, so results may be incomplete. " ++ describeFailedFeeds failedFeeds) ]

        _ ->
            text ""


viewStory : Time.Zone -> Story -> Html Msg
viewStory zone story =
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
        , div [ class "story-meta" ]
            [ text (sourcePrefix ++ formatDateTime zone story.publishedAt) ]
        ]


{-| e.g. "Fri 2 Oct 2026, 19:40" in the user's time zone.
-}
formatDateTime : Time.Zone -> Time.Posix -> String
formatDateTime zone posix =
    let
        twoDigits number =
            String.padLeft 2 '0' (String.fromInt number)
    in
    Date.format "EEE d MMM y" (Date.fromPosix zone posix)
        ++ ", "
        ++ twoDigits (Time.toHour zone posix)
        ++ ":"
        ++ twoDigits (Time.toMinute zone posix)
