module RankTest exposing (suite)

import Expect
import Rank
import Story exposing (Story)
import Test exposing (Test, describe, test)
import Time


now : Time.Posix
now =
    Time.millisToPosix (1000 * 60 * 60 * 24 * 365)


hoursBeforeNow : Int -> Time.Posix
hoursBeforeNow hours =
    Time.millisToPosix (Time.posixToMillis now - hours * 60 * 60 * 1000)


baseStory : Story
baseStory =
    { title = "Local bakery opens"
    , url = "https://example.com/bakery"
    , sourceName = "Example"
    , sourceHost = "example.com"
    , publishedAt = now
    }


suite : Test
suite =
    describe "Rank"
        [ describe "score"
            [ test "a brand-new story with no other signals scores just the recency weight" <|
                \_ ->
                    Rank.score now 0 baseStory
                        |> Expect.within (Expect.Absolute 0.0001) 0.3
            , test "recency falls to 1/e after three days" <|
                \_ ->
                    Rank.score now 0 { baseStory | publishedAt = hoursBeforeNow 72 }
                        |> Expect.within (Expect.Absolute 0.0001) (0.3 / e)
            , test "coverage maxes out at 10 similar stories" <|
                \_ ->
                    [ Rank.score now 10 baseStory, Rank.score now 50 baseStory ]
                        |> List.map (\storyScore -> abs (storyScore - 0.7) < 0.0001)
                        |> Expect.equal [ True, True ]
            , test "impact keywords add up to 0.2" <|
                \_ ->
                    Rank.score now 0 { baseStory | title = "Earthquake and tsunami: dozens dead, hundreds injured" }
                        |> Expect.within (Expect.Absolute 0.0001) 0.5
            , test "authoritative outlets get 0.1" <|
                \_ ->
                    Rank.score now 0 { baseStory | sourceHost = "apnews.com" }
                        |> Expect.within (Expect.Absolute 0.0001) 0.4
            ]
        , describe "topStories"
            [ test "highest score first, limited to the count" <|
                \_ ->
                    [ ( { baseStory | title = "small", url = "https://example.com/small" }, 1 )
                    , ( { baseStory | title = "big", url = "https://example.com/big" }, 8 )
                    , ( { baseStory | title = "medium", url = "https://example.com/medium" }, 4 )
                    ]
                        |> Rank.topStories now 2
                        |> List.map .title
                        |> Expect.equal [ "big", "medium" ]
            , test "duplicate URLs are kept only once" <|
                \_ ->
                    [ ( { baseStory | title = "first" }, 2 )
                    , ( { baseStory | title = "same url" }, 1 )
                    ]
                        |> Rank.topStories now 10
                        |> List.map .title
                        |> Expect.equal [ "first" ]
            ]
        ]
