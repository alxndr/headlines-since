module Rank exposing (score, topStories)

{-| Score stories by significance and pick the top ones.
-}

import Set exposing (Set)
import Story exposing (Story)
import Time


{-| The highest-scoring stories, at most one per URL.
-}
topStories : Time.Posix -> Int -> List ( Story, Int ) -> List Story
topStories now count storiesWithClusterSizes =
    storiesWithClusterSizes
        |> List.map (\( story, clusterSize ) -> ( score now clusterSize story, story ))
        -- Negate to sort highest score first; List.sortBy is stable, so
        -- equal scores keep their feed order.
        |> List.sortBy (\( storyScore, _ ) -> negate storyScore)
        |> List.map Tuple.second
        |> dedupeByUrl
        |> List.take count


{-| Stories without a URL are compared by title instead.
-}
dedupeByUrl : List Story -> List Story
dedupeByUrl stories =
    let
        dedupeKey story =
            if String.isEmpty story.url then
                String.toLower story.title

            else
                story.url
    in
    List.foldl
        (\story ( seenKeys, kept ) ->
            if Set.member (dedupeKey story) seenKeys then
                ( seenKeys, kept )

            else
                ( Set.insert (dedupeKey story) seenKeys, story :: kept )
        )
        ( Set.empty, [] )
        stories
        |> Tuple.second
        |> List.reverse


{-| A weighted sum of four signals, each scaled to 0..1:

  - recency (weight 0.3): decays exponentially, falling to about 37% after 3 days
  - coverage (weight 0.4): cluster size, maxing out at 10 similar stories
  - impact (weight 0.2): count of impact keywords in the title, maxing out at 4
  - authority (weight 0.1): 1 if the outlet is in the authority list

-}
score : Time.Posix -> Int -> Story -> Float
score now clusterSize story =
    let
        hoursOld =
            toFloat (Time.posixToMillis now - Time.posixToMillis story.publishedAt)
                / (1000 * 60 * 60)
                |> max 0

        recency =
            e ^ (-hoursOld / (24 * 3))

        coverage =
            min (toFloat clusterSize / 10) 1

        lowercaseTitle =
            String.toLower story.title

        impactTermCount =
            List.length (List.filter (\term -> String.contains term lowercaseTitle) impactTerms)

        impact =
            min (toFloat impactTermCount / 4) 1

        authority =
            if Set.member story.sourceHost authoritativeHosts then
                1

            else
                0
    in
    (recency * 0.3) + (coverage * 0.4) + (impact * 0.2) + (authority * 0.1)


authoritativeHosts : Set String
authoritativeHosts =
    Set.fromList
        [ "apnews.com"
        , "reuters.com"
        , "bbc.co.uk"
        , "bbc.com"
        , "theguardian.com"
        , "nytimes.com"
        , "wsj.com"
        , "washingtonpost.com"
        , "npr.org"
        , "ft.com"
        , "aljazeera.com"
        , "cnn.com"
        ]


{-| Matched as substrings of the lowercased title, so "war" also matches
"warning" (same as the original JS implementation).
TODO why do we want "war" to match "warning"?
-}
impactTerms : List String
impactTerms =
    [ "dead"
    , "killed"
    , "deaths"
    , "injured"
    , "attack"
    , "attacks"
    , "war"
    , "ceasefire"
    , "bomb"
    , "bombing"
    , "earthquake"
    , "hurricane"
    , "storm"
    , "flood"
    , "flooding"
    , "election"
    , "elections"
    , "vote"
    , "court"
    , "ruling"
    , "supreme court"
    , "law"
    , "bill"
    , "passed"
    , "sanction"
    , "sanctions"
    , "market"
    , "crash"
    , "recession"
    , "inflation"
    , "rate hike"
    , "strike"
    , "unrest"
    , "protest"
    , "protests"
    , "mass shooting"
    , "tornado"
    , "tsunami"
    , "outbreak"
    , "pandemic"
    ]
