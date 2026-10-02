port module Headlines exposing (main)

import Browser
import Html exposing (Html, article, button, div, form, h1, h3, input, label, p, section, text)
import Html.Attributes as Attr exposing (attribute, class, for, href, id, name, rel, required, target, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Json.Decode as Decode
import Json.Encode as Encode


type alias Story =
    { title : String
    , url : String
    , sourceName : String
    , publishedAt : String
    }


type alias Model =
    { startDate : String
    , count : Int
    , status : String
    , stories : List Story
    , error : Maybe String
    }


type Msg
    = UpdateStartDate String
    | UpdateCount Int
    | SubmitForm
    | FetchResponse Decode.Value
    | GotResultsFromJS (List Story)
    | GotErrorFromJS String
    | NoOp


port fetchRequest : Encode.Value -> Cmd msg


port fetchResponse : (Decode.Value -> msg) -> Sub msg


init : () -> ( Model, Cmd Msg )
init _ =
    let
        defaultStart =
            "2026-09-18"
    in
    ( { startDate = defaultStart
      , count = 10
      , status = ""
      , stories = []
      , error = Nothing
      }
    , Cmd.none
    )


encodeFetchRequest : String -> Int -> Encode.Value
encodeFetchRequest startDate count =
    Encode.object
        [ ( "startDate", Encode.string startDate )
        , ( "count", Encode.int count )
        ]


storyDecoder : Decode.Decoder Story
storyDecoder =
    Decode.map4 Story
        (Decode.field "title" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "sourceName" Decode.string)
        (Decode.field "publishedAt" Decode.string)


responseDecoder : Decode.Decoder Msg
responseDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "success" ->
                        Decode.field "stories" (Decode.list storyDecoder)
                            |> Decode.map GotResultsFromJS

                    "error" ->
                        Decode.field "error" Decode.string
                            |> Decode.map GotErrorFromJS

                    _ ->
                        Decode.succeed NoOp
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateStartDate date ->
            ( { model | startDate = date }, Cmd.none )

        UpdateCount n ->
            ( { model | count = Basics.max 5 (Basics.min 20 n) }, Cmd.none )

        SubmitForm ->
            ( { model | status = "Fetching headlines...", stories = [], error = Nothing }
            , fetchRequest (encodeFetchRequest model.startDate model.count)
            )

        FetchResponse value ->
            case Decode.decodeValue responseDecoder value of
                Ok innerMsg ->
                    update innerMsg model

                Err _ ->
                    ( { model | error = Just "Failed to parse response", status = "" }, Cmd.none )

        GotResultsFromJS stories ->
            ( { model
                | status =
                    if List.isEmpty stories then
                        "No stories found for this range."

                    else
                        "Found " ++ String.fromInt (List.length stories) ++ " biggest stories"
                , stories = stories
                , error = Nothing
              }
            , Cmd.none
            )

        GotErrorFromJS err ->
            ( { model | error = Just err, status = "", stories = [] }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


viewStory : Story -> Html Msg
viewStory story =
    article [ class "story" ]
        [ h3 []
            [ Html.a [ href story.url, target "_blank", rel "noopener noreferrer" ] [ text story.title ] ]
        , div [ class "story-meta" ]
            [ text (story.sourceName ++ (if String.isEmpty story.sourceName then "" else " • ") ++ story.publishedAt) ]
        ]


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Headlines Since" ]
        , p [] [ text "After being away, catch up on the biggest stories since a date you choose." ]
        , Html.form [ onSubmit SubmitForm, id "hs-form" ]
            [ label [ for "start-date" ] [ text "Start date (up to 1 year ago)" ]
            , input
                [ type_ "date"
                , id "start-date"
                , name "start-date"
                , value model.startDate
                , required True
                , onInput UpdateStartDate
                ]
                []
            , label [ for "count" ] [ text "Number of stories" ]
            , input
                [ type_ "number"
                , id "count"
                , name "count"
                , Attr.min "5"
                , Attr.max "20"
                , value (String.fromInt model.count)
                , required True
                , onInput (\s -> UpdateCount (Maybe.withDefault 10 (String.toInt s)))
                ]
                []
            , button [ type_ "submit" ] [ text "Find headlines" ]
            ]
        , div [ id "hs-status", attribute "aria-live" "polite" ] [ text model.status ]
        , case model.error of
            Just err ->
                div [ class "error" ] [ text err ]

            Nothing ->
                text ""
        , div [ id "hs-results" ] (List.map viewStory model.stories)
        , section []
            [ p [] [ text "Biggest individual stories ranked by significance (no forced topic diversification)." ] ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> fetchResponse FetchResponse
        }
