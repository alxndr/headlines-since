module OutletMatchTest exposing (suite)

import Date
import Expect
import OutletMatch
import Rank exposing (RankedStory)
import Story exposing (Story)
import Test exposing (Test, describe, test)
import Time


wikipediaEvent : Int -> String -> List String -> Story
wikipediaEvent dayOfMonth text linkedArticles =
    { title = text
    , url = "https://example.com/" ++ String.left 20 text
    , sourceName = "Wikipedia"
    , sourceHost = "example.com"
    , publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Oct dayOfMonth)
    , topics = []
    , topicArticles = []
    , section = Nothing
    , sourceCount = 1
    , linkedArticles = linkedArticles
    , summary = ""
    }


outletArticle : Int -> String -> String -> Story
outletArticle dayOfMonth title summary =
    { title = title
    , url = "https://outlet.example.com/" ++ String.left 20 title
    , sourceName = "Example Outlet"
    , sourceHost = "outlet.example.com"
    , publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Oct dayOfMonth)
    , topics = []
    , topicArticles = []
    , section = Nothing
    , sourceCount = 1
    , linkedArticles = []
    , summary = summary
    }


{-| Real events from late September / early October 2026 (abridged).
-}
g7OilRelease : Story
g7OilRelease =
    wikipediaEvent 2
        "The G7 countries announce a plan to release 100 million barrels of diesel and crude oil to combat rising fuel prices caused by the Iran war."
        [ "G7", "Diesel fuel", "Petroleum", "2026 Iran war fuel crisis" ]


events : List Story
events =
    [ g7OilRelease
    , wikipediaEvent 1 "Twenty-one people are arrested in Myanmar for allegedly donating to the in-exile National Unity Government, which leads the revolution against the military junta." [ "Myanmar", "National Unity Government of Myanmar" ]
    , wikipediaEvent 2 "Spain's parliament rejects two government housing decrees that would have expanded protections against evictions." [ "Cortes Generales", "Spain", "Eviction" ]
    , wikipediaEvent 1 "A medical helicopter transporting a patient crashes off the coast of Santa Catalina Island in Los Angeles County, California." [ "Air ambulance", "Santa Catalina Island (California)" ]
    , wikipediaEvent 30 "American troops complete their withdrawal from Iraq, ending their 23-year presence in the country." [ "Iraq", "United States Armed Forces" ]
    , wikipediaEvent 30 "The U.S. Court of Appeals for the Sixth Circuit halts Christa Pike's execution in Tennessee." [ "Christa Pike", "Capital punishment in Tennessee" ]
    ]


g7Headline : Story
g7Headline =
    outletArticle 2
        "G7 to release 100 million barrels of oil and diesel after Trump export ban threat"
        "The group of seven wealthy nations will release oil and diesel from emergency stocks to bring down fuel prices."


bestMatch : Story -> Maybe Story
bestMatch article =
    OutletMatch.bestMatch Time.utc (OutletMatch.eventIndex events) article


suite : Test
suite =
    describe "OutletMatch"
        [ test "a news report matches the Wikipedia event it covers" <|
            \_ -> bestMatch g7Headline |> Expect.equal (Just g7OilRelease)
        , test "an opinion headline sharing one word with an event doesn't match" <|
            \_ ->
                bestMatch (outletArticle 2 "Revolution or No Revolution" "Thoughts on political change.")
                    |> Expect.equal Nothing
        , test "events more than 3 days from the article don't match" <|
            \_ ->
                bestMatch { g7Headline | publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Oct 9) }
                    |> Expect.equal Nothing
        , describe "attachToRanked"
            [ test "matched articles join their event's related reports; others are unmatched" <|
                \_ ->
                    let
                        ranked =
                            [ { story = g7OilRelease, relatedReports = [] } ]

                        opinion =
                            outletArticle 2 "Revolution or No Revolution" "Thoughts on political change."

                        result =
                            OutletMatch.attachToRanked Time.utc (OutletMatch.eventIndex events) ranked [ g7Headline, opinion ]
                    in
                    ( List.map (.relatedReports >> List.map .title) result.ranked, List.map .title result.unmatched )
                        |> Expect.equal ( [ [ g7Headline.title ] ], [ opinion.title ] )
            , test "an article about an event that isn't in the list stays unmatched" <|
                \_ ->
                    let
                        ranked : List RankedStory
                        ranked =
                            []
                    in
                    OutletMatch.attachToRanked Time.utc (OutletMatch.eventIndex events) ranked [ g7Headline ]
                        |> .unmatched
                        |> List.map .title
                        |> Expect.equal [ g7Headline.title ]
            ]
        ]
