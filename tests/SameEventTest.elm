module SameEventTest exposing (suite)

import Date
import Expect
import SameEvent
import Story exposing (Story)
import Test exposing (Test, describe, test)
import Time


event : Int -> List String -> List String -> Story
event dayOfMonth topicArticles linkedArticles =
    { title = String.join " " linkedArticles
    , url = "https://example.com/" ++ String.fromInt dayOfMonth ++ String.join "-" linkedArticles
    , sourceName = "Wikipedia"
    , sourceHost = "example.com"
    , publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Jun dayOfMonth)
    , topics = topicArticles
    , topicArticles = topicArticles
    , section = Nothing
    , sourceCount = 1
    , linkedArticles = topicArticles ++ linkedArticles
    , summary = ""
    }


{-| Toll updates from the real 2026 Venezuela earthquake events.
-}
quakeDay1 : Story
quakeDay1 =
    event 25 [ "2026 Venezuela earthquakes" ] [ "Venezuela", "Earthquake" ]


quakeDay2 : Story
quakeDay2 =
    event 26 [ "2026 Venezuela earthquakes" ] [ "Venezuela", "Earthquake" ]


{-| Unrelated events that make "Iran" and "United States" common links.
-}
background : List Story
background =
    [ event 25 [ "2026 Iran war" ] [ "Iran", "United States", "Bandar Abbas" ]
    , event 25 [ "2026 Iran war" ] [ "Iran", "United States", "Kish Island" ]
    , event 26 [ "2026 Iran war" ] [ "Iran", "United States", "Strait of Hormuz" ]
    , event 26 [] [ "Iran", "United States", "Oman" ]
    , event 27 [] [ "Iran", "Iraq" ]
    , event 27 [] [ "United States", "Canada" ]
    ]


areSameEvent : Story -> Story -> Bool
areSameEvent storyA storyB =
    SameEvent.areSameEvent Time.utc (SameEvent.linkWeights (storyA :: storyB :: background)) storyA storyB


suite : Test
suite =
    describe "SameEvent"
        [ test "updates to the same event, a day apart, match" <|
            \_ -> areSameEvent quakeDay1 quakeDay2 |> Expect.equal True
        , test "the same links more than 3 days apart don't match" <|
            \_ ->
                areSameEvent quakeDay1 (event 29 [ "2026 Venezuela earthquakes" ] [ "Venezuela", "Earthquake" ])
                    |> Expect.equal False
        , test "different events under the same topic don't match" <|
            \_ ->
                areSameEvent
                    (event 25 [ "2026 Iran war" ] [ "Iran", "United States", "Bandar Abbas" ])
                    (event 25 [ "2026 Iran war" ] [ "Iran", "United States", "Kish Island" ])
                    |> Expect.equal False
        , test "sharing only the topic doesn't count" <|
            \_ ->
                areSameEvent
                    (event 25 [ "2026 Iran war" ] [ "Bandar Abbas" ])
                    (event 25 [ "2026 Iran war" ] [ "Kish Island" ])
                    |> Expect.equal False
        , test "sharing only common links doesn't count" <|
            \_ ->
                areSameEvent
                    (event 26 [] [ "Iran", "United States", "Oman" ])
                    (event 26 [] [ "Iran", "United States", "Qatar" ])
                    |> Expect.equal False
        , test "stories without links (e.g. RSS headlines) never match" <|
            \_ ->
                areSameEvent (event 25 [] []) (event 25 [] [])
                    |> Expect.equal False
        ]
