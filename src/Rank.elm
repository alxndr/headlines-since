module Rank exposing (score, topStories)

{-| Score stories by significance and pick the top ones.
-}

import Dict
import PageViews exposing (AverageDailyViews)
import Set exposing (Set)
import Story exposing (Story)


{-| The highest-scoring stories, at most one per URL.
-}
topStories : AverageDailyViews -> Int -> List Story -> List Story
topStories averageDailyViews count stories =
    stories
        |> List.map (\story -> ( score averageDailyViews story, story ))
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


{-| A weighted sum of three signals, each scaled to 0..1:

  - public interest (weight 0.5): page views of the story's Wikipedia topic
    article (see `interestScore`)
  - sources (weight 0.15): how many news reports Wikipedia cites, maxing out
    at 3 (one source scores 0)
  - authority (weight 0.1): 1 if the outlet is in the authority list

Sports and arts stories get half the score, because they draw far more page
views than their significance warrants (the 2026 Asian Games had 8 times the
views of the 2026 Iran war).

There is deliberately no recency signal: when catching up after time away,
a big story from the first day matters as much as one from today.

Nor is there a list of "impact" keywords: page views measure significance
more directly. (Removing the keywords changed 2 of the top 10 stories for
18 Sept to 2 Oct 2026.)

The weights add up to 0.75 rather than 1; only the stories' relative order
matters.

-}
score : AverageDailyViews -> Story -> Float
score averageDailyViews story =
    let
        interest =
            story.topicArticles
                |> List.filterMap (\article -> Dict.get article averageDailyViews)
                |> List.maximum
                |> Maybe.map interestScore
                |> Maybe.withDefault 0

        sources =
            clamp 0 1 (toFloat (story.sourceCount - 1) / 2)

        authority =
            if Set.member story.sourceHost authoritativeHosts then
                1

            else
                0

        sectionMultiplier =
            case story.section of
                Just "Sports" ->
                    0.5

                Just "Arts and culture" ->
                    0.5

                _ ->
                    1
    in
    sectionMultiplier * ((interest * 0.5) + (sources * 0.15) + (authority * 0.1))


{-| Daily page views on a log scale, since they range from hundreds to
millions: 1,000 a day or fewer scores 0, and about 316,000 a day (10^5.5) or
more scores 1. For reference, in late September 2026 a minor topic got about
1,000 a day, the 2026 Iran war about 20,000 (0.52), and the 2026 Asian Games
about 200,000 (0.92).
-}
interestScore : Float -> Float
interestScore averageDailyViews =
    if averageDailyViews <= 0 then
        0

    else
        clamp 0 1 ((logBase 10 averageDailyViews - 3) / 2.5)


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
