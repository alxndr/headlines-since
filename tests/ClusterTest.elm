module ClusterTest exposing (suite)

import Cluster
import Expect
import Set
import Story exposing (Story)
import Test exposing (Test, describe, test)
import Time


storyTitled : String -> Story
storyTitled title =
    { title = title
    , url = "https://example.com/" ++ title
    , sourceName = "Example"
    , sourceHost = "example.com"
    , publishedAt = Story.ExactTime (Time.millisToPosix 0)
    , topics = []
    }


suite : Test
suite =
    describe "Cluster"
        [ describe "titleTokens"
            [ test "lowercases, splits on non-word characters, and drops short words" <|
                \_ ->
                    Cluster.titleTokens "U.S. Senate passes the bill, 52-48"
                        |> Expect.equal (Set.fromList [ "senate", "passes", "the", "bill" ])
            ]
        , describe "jaccardSimilarity"
            [ test "identical sets" <|
                \_ ->
                    Cluster.jaccardSimilarity (Set.fromList [ "a", "b" ]) (Set.fromList [ "a", "b" ])
                        |> Expect.within (Expect.Absolute 0.0001) 1
            , test "half overlap" <|
                \_ ->
                    Cluster.jaccardSimilarity (Set.fromList [ "a", "b", "c" ]) (Set.fromList [ "b", "c", "d" ])
                        |> Expect.within (Expect.Absolute 0.0001) 0.5
            , test "two empty sets" <|
                \_ ->
                    Cluster.jaccardSimilarity Set.empty Set.empty
                        |> Expect.within (Expect.Absolute 0.0001) 0
            ]
        , describe "withClusterSizes"
            [ test "similar titles share a cluster size, and input order is kept" <|
                \_ ->
                    [ storyTitled "Earthquake strikes northern Japan coast"
                    , storyTitled "Local bakery wins award"
                    , storyTitled "Strong earthquake strikes northern Japan"
                    ]
                        |> Cluster.withClusterSizes
                        |> List.map (\( story, size ) -> ( story.title, size ))
                        |> Expect.equal
                            [ ( "Earthquake strikes northern Japan coast", 2 )
                            , ( "Local bakery wins award", 1 )
                            , ( "Strong earthquake strikes northern Japan", 2 )
                            ]
            , test "no stories" <|
                \_ -> Cluster.withClusterSizes [] |> Expect.equal []
            ]
        ]
