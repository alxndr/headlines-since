module RankTest exposing (suite)

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
            , test "impact keywords add up to 0.25" <|
                \_ ->
                    scoreWithoutViews (titled "Earthquake and tsunami: dozens dead, hundreds injured")
                        |> expectScore 0.25
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
        , describe "impact keyword matching"
            [ test "matches whole words only" <|
                \_ ->
                    -- Each of these contains an impact term inside a longer word.
                    [ "Storm warning issued"
                    , "Award-winning lawyer files billion-dollar claim"
                    , "Deadline nears for courtesy visit"
                    ]
                        |> List.map (titled >> scoreWithoutViews)
                        |> Expect.equal
                            [ 0.25 * (1 / 4) -- only "storm"
                            , 0
                            , 0
                            ]
            , test "different forms of one concept count once" <|
                \_ ->
                    scoreWithoutViews (titled "Attack follows attacks")
                        |> expectScore (0.25 * (1 / 4))
            , test "present-tense Wikipedia phrasing matches" <|
                \_ ->
                    scoreWithoutViews (titled "A car bombing kills 31 people and injures 100")
                        |> expectScore (0.25 * (3 / 4))
            , test "non-violent news counts too" <|
                \_ ->
                    scoreWithoutViews (titled "Prime minister resigns after trade deal collapses")
                        |> expectScore (0.25 * (2 / 4))
            , test "multi-word terms match as phrases" <|
                \_ ->
                    ( scoreWithoutViews (titled "The central bank announces a rate hike")
                    , scoreWithoutViews (titled "Hike in the rate of growth")
                    )
                        |> Expect.equal ( 0.25 * (1 / 4), 0 )
            , test "hyphenated words are split" <|
                \_ ->
                    scoreWithoutViews (titled "Talks on a cease-fire")
                        |> expectScore (0.25 * (1 / 4))
            ]
        , describe "topStories"
            [ test "highest score first, limited to the count" <|
                \_ ->
                    [ { baseStory | title = "small", url = "https://example.com/small", topicArticles = [ "Small" ] }
                    , { baseStory | title = "big", url = "https://example.com/big", topicArticles = [ "Big" ] }
                    , { baseStory | title = "medium", url = "https://example.com/medium", topicArticles = [ "Medium" ] }
                    ]
                        |> Rank.topStories (Dict.fromList [ ( "Small", 2000 ), ( "Big", 200000 ), ( "Medium", 20000 ) ]) 2
                        |> List.map .title
                        |> Expect.equal [ "big", "medium" ]
            , test "duplicate URLs are kept only once" <|
                \_ ->
                    [ { baseStory | title = "first", sourceCount = 2 }
                    , { baseStory | title = "same url" }
                    ]
                        |> Rank.topStories Dict.empty 10
                        |> List.map .title
                        |> Expect.equal [ "first" ]
            ]
        ]
