module RankTest exposing (suite)

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
    }


titled : String -> Story
titled title =
    { baseStory | title = title }


expectScore : Float -> Float -> Expect.Expectation
expectScore expected actual =
    Expect.within (Expect.Absolute 0.0001) expected actual


suite : Test
suite =
    describe "Rank"
        [ describe "score"
            [ test "a story with no signals scores zero" <|
                \_ -> Rank.score 0 baseStory |> expectScore 0
            , test "publication date doesn't matter" <|
                \_ ->
                    Rank.score 0 { baseStory | publishedAt = Story.ExactTime (Time.millisToPosix 1790970005000) }
                        |> expectScore 0
            , test "coverage maxes out at 10 similar stories" <|
                \_ ->
                    [ Rank.score 10 baseStory, Rank.score 50 baseStory ]
                        |> List.map (\storyScore -> abs (storyScore - 0.4) < 0.0001)
                        |> Expect.equal [ True, True ]
            , test "impact keywords add up to 0.2" <|
                \_ ->
                    Rank.score 0 (titled "Earthquake and tsunami: dozens dead, hundreds injured")
                        |> expectScore 0.2
            , test "authoritative outlets get 0.1" <|
                \_ ->
                    Rank.score 0 { baseStory | sourceHost = "apnews.com" }
                        |> expectScore 0.1
            ]
        , describe "impact keyword matching"
            [ test "matches whole words only" <|
                \_ ->
                    -- Each of these contains an impact term inside a longer word.
                    [ "Storm warning issued"
                    , "Award-winning lawyer files billion-dollar claim"
                    , "Deadline passes for courtesy visit"
                    ]
                        |> List.map (titled >> Rank.score 0)
                        |> Expect.equal
                            [ 0.2 * (1 / 4) -- only "storm"
                            , 0
                            , 0.2 * (1 / 4) -- only "passes"
                            ]
            , test "different forms of one concept count once" <|
                \_ ->
                    Rank.score 0 (titled "Attack follows attacks")
                        |> expectScore (0.2 * (1 / 4))
            , test "present-tense Wikipedia phrasing matches" <|
                \_ ->
                    Rank.score 0 (titled "A car bombing kills 31 people and injures 100")
                        |> expectScore (0.2 * (3 / 4))
            , test "multi-word terms match as phrases" <|
                \_ ->
                    ( Rank.score 0 (titled "The central bank announces a rate hike")
                    , Rank.score 0 (titled "Hike in the rate of growth")
                    )
                        |> Expect.equal ( 0.2 * (1 / 4), 0 )
            , test "hyphenated words are split" <|
                \_ ->
                    Rank.score 0 (titled "Talks on a cease-fire")
                        |> expectScore (0.2 * (1 / 4))
            ]
        , describe "topStories"
            [ test "highest score first, limited to the count" <|
                \_ ->
                    [ ( { baseStory | title = "small", url = "https://example.com/small" }, 1 )
                    , ( { baseStory | title = "big", url = "https://example.com/big" }, 8 )
                    , ( { baseStory | title = "medium", url = "https://example.com/medium" }, 4 )
                    ]
                        |> Rank.topStories 2
                        |> List.map .title
                        |> Expect.equal [ "big", "medium" ]
            , test "duplicate URLs are kept only once" <|
                \_ ->
                    [ ( { baseStory | title = "first" }, 2 )
                    , ( { baseStory | title = "same url" }, 1 )
                    ]
                        |> Rank.topStories 10
                        |> List.map .title
                        |> Expect.equal [ "first" ]
            ]
        ]
