module Rank exposing (RankedStory, score, topStories)

{-| Score stories by significance and pick the top ones.
-}

import Date
import Dict
import PageViews exposing (AverageDailyViews)
import SameEvent exposing (LinkWeights)
import Set exposing (Set)
import Story exposing (Story)
import Time


{-| A chosen story, plus any other reports of the same event (oldest
first), such as later updates to a death toll.
-}
type alias RankedStory =
    { story : Story
    , relatedReports : List Story
    }


{-| Each further story from a topic that's already in the list scores this
much of the one before (so the 2nd scores 85%, the 3rd 72%, ...). Big topics
can still appear several times, but can't crowd out everything else.
-}
repeatedTopicMultiplier : Float
repeatedTopicMultiplier =
    0.85


{-| The highest-scoring stories, picked one at a time:

1.  Take the story with the best score, after the repeated-topic penalty.
2.  If it reports the same event as a story already picked, add it to that
    story's related reports instead (it doesn't count toward `count`).
3.  Repeat until `count` stories are picked.

Finally, every remaining report of a picked event is added to its related
reports. Stories with the same URL are only considered once.

-}
topStories : Time.Zone -> AverageDailyViews -> Int -> List Story -> List RankedStory
topStories zone averageDailyViews count stories =
    let
        uniqueStories =
            dedupeByUrl stories

        weights =
            SameEvent.linkWeights uniqueStories

        candidates =
            List.map (\story -> ( score averageDailyViews story, story )) uniqueStories
    in
    pickStories zone weights count candidates []
        |> attachRemainingReports zone weights
        |> List.map
            (\picked ->
                { story = picked.story
                , relatedReports = List.sortBy (Story.publishedDate zone >> Date.toRataDie) picked.relatedReports
                }
            )


{-| The stories picked so far, and the candidates not yet used.
-}
type alias Picking =
    { picked : List RankedStory
    , remaining : List ( Float, Story )
    }


pickStories : Time.Zone -> LinkWeights -> Int -> List ( Float, Story ) -> List RankedStory -> Picking
pickStories zone weights count remaining picked =
    if List.length picked >= count then
        { picked = picked, remaining = remaining }

    else
        case bestCandidate picked remaining of
            Nothing ->
                { picked = picked, remaining = remaining }

            Just ( _, candidate ) ->
                let
                    otherCandidates =
                        List.filter (\( _, story ) -> story /= candidate) remaining
                in
                pickStories zone weights count otherCandidates (addReport zone weights candidate picked)


{-| The highest-scoring candidate, after penalising topics already picked.
Ties go to the earlier candidate.
-}
bestCandidate : List RankedStory -> List ( Float, Story ) -> Maybe ( Float, Story )
bestCandidate picked remaining =
    let
        penalised ( baseScore, story ) =
            ( baseScore * (repeatedTopicMultiplier ^ toFloat (pickedFromSameTopic picked story)), story )
    in
    List.foldl
        (\candidate best ->
            let
                ( candidateScore, _ ) =
                    penalised candidate
            in
            case best of
                Just ( bestScore, _ ) ->
                    if candidateScore > bestScore then
                        Just ( candidateScore, Tuple.second candidate )

                    else
                        best

                Nothing ->
                    Just ( candidateScore, Tuple.second candidate )
        )
        Nothing
        remaining


{-| How many picked stories share a topic article with this story. Stories
without topics are never penalised.
-}
pickedFromSameTopic : List RankedStory -> Story -> Int
pickedFromSameTopic picked story =
    let
        topics =
            Set.fromList story.topicArticles
    in
    picked
        |> List.filter (\rankedStory -> not (Set.isEmpty (Set.intersect topics (Set.fromList rankedStory.story.topicArticles))))
        |> List.length


{-| Adds the story to the picked event it reports, if any (compared with
every report already in that event, so a chain of daily updates stays
together); otherwise picks it as a new story.
-}
addReport : Time.Zone -> LinkWeights -> Story -> List RankedStory -> List RankedStory
addReport zone weights story picked =
    case findSameEvent zone weights story picked of
        Just index ->
            List.indexedMap
                (\pickedIndex rankedStory ->
                    if pickedIndex == index then
                        { rankedStory | relatedReports = story :: rankedStory.relatedReports }

                    else
                        rankedStory
                )
                picked

        Nothing ->
            picked ++ [ { story = story, relatedReports = [] } ]


findSameEvent : Time.Zone -> LinkWeights -> Story -> List RankedStory -> Maybe Int
findSameEvent zone weights story picked =
    picked
        |> List.indexedMap Tuple.pair
        |> List.filter
            (\( _, rankedStory ) ->
                List.any (SameEvent.areSameEvent zone weights story) (rankedStory.story :: rankedStory.relatedReports)
            )
        |> List.head
        |> Maybe.map Tuple.first


{-| Lower-scoring reports of picked events weren't reached while picking,
so add them now. Repeats until nothing more is added, so a report that only
matches another newly-added report is still found.
-}
attachRemainingReports : Time.Zone -> LinkWeights -> Picking -> List RankedStory
attachRemainingReports zone weights { picked, remaining } =
    let
        ( matching, unmatched ) =
            List.partition (\( _, story ) -> findSameEvent zone weights story picked /= Nothing) remaining
    in
    if List.isEmpty matching then
        picked

    else
        attachRemainingReports zone
            weights
            { picked = List.foldl (\( _, story ) -> addReport zone weights story) picked matching
            , remaining = unmatched
            }


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
