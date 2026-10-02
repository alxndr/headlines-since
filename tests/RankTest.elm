module RankTest exposing (suite)

import Date
import Dict
import Expect
import Rank
import Story exposing (Story)
import Test exposing (Test, describe, test)
import Time


baseStory : Story
baseStory =
    { title = "Local bakery opens"
    , url = "https://example.com/bakery"
    , sourceName = "Example"
    , sourceHost = "example.com"
    , publishedAt = Story.ExactTime (Time.millisToPosix 0)
    , topics = []
    , topicArticles = []
    , section = Nothing
    , sourceCount = 1
    , linkedArticles = []
    , summary = ""
    }


titled : String -> Story
titled title =
    { baseStory | title = title }


{-| Scores a story about the topic article "Topic", which got the given
average daily page views.
-}
scoreWithViews : Float -> Float
scoreWithViews averageDailyViews =
    Rank.score (Dict.fromList [ ( "Topic", averageDailyViews ) ]) { baseStory | topicArticles = [ "Topic" ] }


scoreWithoutViews : Story -> Float
scoreWithoutViews =
    Rank.score Dict.empty


{-| One of several reports of the same earthquake, on the given day of June,
citing `sourceCount` sources (more sources rank higher).
-}
quakeReport : Int -> Int -> Story
quakeReport dayOfMonth sourceCount =
    { baseStory
        | title = "Earthquake toll update"
        , url = "https://example.com/quake-" ++ String.fromInt dayOfMonth
        , publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Jun dayOfMonth)
        , sourceCount = sourceCount
        , linkedArticles = [ "Venezuela", "Earthquake" ]
    }


otherEvent : String -> Story
otherEvent linkedArticle =
    { baseStory
        | title = linkedArticle
        , url = "https://example.com/" ++ linkedArticle
        , publishedAt = Story.DateOnly (Date.fromCalendarDate 2026 Time.Jun 25)
        , linkedArticles = [ linkedArticle ]
    }


expectScore : Float -> Float -> Expect.Expectation
expectScore expected actual =
    Expect.within (Expect.Absolute 0.0001) expected actual


suite : Test
suite =
    describe "Rank"
        [ describe "score"
            [ test "a story with no signals scores zero" <|
                \_ -> scoreWithoutViews baseStory |> expectScore 0
            , test "publication date doesn't matter" <|
                \_ ->
                    scoreWithoutViews { baseStory | publishedAt = Story.ExactTime (Time.millisToPosix 1790970005000) }
                        |> expectScore 0
            , describe "public interest (page views) is worth up to 0.5, on a log scale"
                [ test "1,000 views a day or fewer scores nothing" <|
                    \_ -> ( scoreWithViews 1000, scoreWithViews 50 ) |> Expect.equal ( 0, 0 )
                , test "100,000 views a day scores 0.4 of 0.5" <|
                    \_ -> scoreWithViews 100000 |> expectScore (0.5 * 0.8)
                , test "the score maxes out around 316,000 views a day" <|
                    \_ -> ( scoreWithViews (10 ^ 5.5), scoreWithViews 5000000 ) |> Expect.equal ( 0.5, 0.5 )
                , test "a story in several topics uses the most-viewed one" <|
                    \_ ->
                        Rank.score
                            (Dict.fromList [ ( "Small", 1000 ), ( "Big", 100000 ) ])
                            { baseStory | topicArticles = [ "Small", "Big" ] }
                            |> expectScore (0.5 * 0.8)
                , test "articles without page view data score nothing" <|
                    \_ ->
                        Rank.score (Dict.fromList [ ( "Other", 100000 ) ]) { baseStory | topicArticles = [ "Topic" ] }
                            |> expectScore 0
                ]
            , test "the title's words don't affect the score" <|
                \_ ->
                    scoreWithoutViews (titled "Earthquake and tsunami: dozens dead, hundreds injured")
                        |> expectScore 0
            , test "each extra cited source adds 0.075, up to 0.15" <|
                \_ ->
                    [ 1, 2, 3, 5 ]
                        |> List.map (\sourceCount -> scoreWithoutViews { baseStory | sourceCount = sourceCount })
                        |> List.map (\storyScore -> toFloat (round (storyScore * 1000)) / 1000)
                        |> Expect.equal [ 0, 0.075, 0.15, 0.15 ]
            , test "authoritative outlets get 0.1" <|
                \_ ->
                    scoreWithoutViews { baseStory | sourceHost = "apnews.com" }
                        |> expectScore 0.1
            , test "sports and arts stories score half" <|
                \_ ->
                    [ Just "Sports", Just "Arts and culture", Just "Politics and elections", Nothing ]
                        |> List.map (\section -> scoreWithoutViews { baseStory | sourceHost = "apnews.com", section = section })
                        |> Expect.equal [ 0.05, 0.05, 0.1, 0.1 ]
            ]
        , describe "topStories"
            [ test "reports of the same event are merged under the best one, oldest first, and don't use up the count" <|
                \_ ->
                    [ quakeReport 26 3
                    , quakeReport 25 1
                    , quakeReport 27 2
                    , otherEvent "Kish Island"
                    ]
                        |> Rank.topStories Time.utc Dict.empty 2
                        |> List.map (\ranked -> ( ranked.story.url, List.map .url ranked.relatedReports ))
                        |> Expect.equal
                            [ ( "https://example.com/quake-26", [ "https://example.com/quake-25", "https://example.com/quake-27" ] )
                            , ( "https://example.com/Kish Island", [] )
                            ]
            , test "a chain of daily updates stays together, even beyond 3 days from the first" <|
                \_ ->
                    [ quakeReport 21 3, quakeReport 23 1, quakeReport 25 1, quakeReport 27 1, otherEvent "Kish Island" ]
                        |> Rank.topStories Time.utc Dict.empty 1
                        |> List.map (\ranked -> List.length ranked.relatedReports)
                        |> Expect.equal [ 3 ]
            , test "each further story from the same topic is penalised 15%" <|
                \_ ->
                    let
                        views =
                            -- Scores: big topic 0.5, other topic about 0.45.
                            Dict.fromList [ ( "Big topic", 10 ^ 5.5 ), ( "Other topic", 10 ^ 5.25 ) ]

                        onTopic topic name =
                            { baseStory | title = name, url = "https://example.com/" ++ name, topicArticles = [ topic ] }
                    in
                    [ onTopic "Big topic" "big 1"
                    , onTopic "Big topic" "big 2"
                    , onTopic "Big topic" "big 3"
                    , onTopic "Other topic" "other 1"
                    ]
                        |> Rank.topStories Time.utc views 3
                        |> List.map (.story >> .title)
                        -- big 2 drops to 0.425, below other 1 (0.45)
                        |> Expect.equal [ "big 1", "other 1", "big 2" ]
            , test "highest score first, limited to the count" <|
                \_ ->
                    [ { baseStory | title = "small", url = "https://example.com/small", topicArticles = [ "Small" ] }
                    , { baseStory | title = "big", url = "https://example.com/big", topicArticles = [ "Big" ] }
                    , { baseStory | title = "medium", url = "https://example.com/medium", topicArticles = [ "Medium" ] }
                    ]
                        |> Rank.topStories Time.utc (Dict.fromList [ ( "Small", 2000 ), ( "Big", 200000 ), ( "Medium", 20000 ) ]) 2
                        |> List.map (.story >> .title)
                        |> Expect.equal [ "big", "medium" ]
            , test "duplicate URLs are kept only once" <|
                \_ ->
                    [ { baseStory | title = "first", sourceCount = 2 }
                    , { baseStory | title = "same url" }
                    ]
                        |> Rank.topStories Time.utc Dict.empty 10
                        |> List.map (.story >> .title)
                        |> Expect.equal [ "first" ]
            ]
        ]
