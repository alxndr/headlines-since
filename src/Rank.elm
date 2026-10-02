module Rank exposing (score, topStories)

{-| Score stories by significance and pick the top ones.
-}

import Dict
import PageViews exposing (AverageDailyViews)
import Regex
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


{-| A weighted sum of four signals, each scaled to 0..1:

  - public interest (weight 0.5): page views of the story's Wikipedia topic
    article (see `interestScore`)
  - impact (weight 0.25): how many impact concepts the title mentions,
    maxing out at 4
  - sources (weight 0.15): how many news reports Wikipedia cites, maxing out
    at 3 (one source scores 0)
  - authority (weight 0.1): 1 if the outlet is in the authority list

Sports and arts stories get half the score, because they draw far more page
views than their significance warrants (the 2026 Asian Games had 8 times the
views of the 2026 Iran war).

There is deliberately no recency signal: when catching up after time away,
a big story from the first day matters as much as one from today.

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

        impact =
            min (toFloat (impactConceptCount story.title) / 4) 1

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
    sectionMultiplier * ((interest * 0.5) + (impact * 0.25) + (sources * 0.15) + (authority * 0.1))


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


{-| How many impact concepts the title mentions. Terms match whole words
only (so "war" doesn't match "warning", nor "bill" match "billion"), and
each concept counts once however many of its forms appear.
-}
impactConceptCount : String -> Int
impactConceptCount title =
    let
        titleWords =
            words title
    in
    impactConcepts
        |> List.filter (List.any (\term -> containsSequence (words term) titleWords))
        |> List.length


{-| Lowercased words, splitting on anything that isn't a letter or digit, so
"cease-fire" is two words and "Iran's" is "iran" and "s".
-}
words : String -> List String
words text =
    Regex.split nonWordCharacters (String.toLower text)
        |> List.filter (not << String.isEmpty)


nonWordCharacters : Regex.Regex
nonWordCharacters =
    Regex.fromString "[^a-z0-9]+" |> Maybe.withDefault Regex.never


{-| Whether `needle` appears as consecutive items in `haystack`.
-}
containsSequence : List String -> List String -> Bool
containsSequence needle haystack =
    case haystack of
        [] ->
            List.isEmpty needle

        _ :: rest ->
            startsWith needle haystack || containsSequence needle rest


startsWith : List String -> List String -> Bool
startsWith prefix list =
    List.take (List.length prefix) list == prefix


{-| Each inner list is one concept, written in the forms it appears in.
Wikipedia summaries are written in the present tense ("kills") and
headlines often in the past tense ("killed"), so both are listed.

Concepts are grouped by kind of event, so that significant non-violent news
(elections, resignations, agreements, economic shocks) can score too.

-}
impactConcepts : List (List String)
impactConcepts =
    -- Casualties
    [ [ "dead" ]
    , [ "kill", "kills", "killed", "killing", "killings" ]
    , [ "death", "deaths", "die", "dies", "died" ]
    , [ "injure", "injures", "injured", "injuring", "injury", "injuries" ]

    -- Conflict and violence
    , [ "attack", "attacks", "attacked", "attacking" ]
    , [ "war", "wars" ]
    , [ "invasion", "invade", "invades", "invaded" ]
    , [ "ceasefire", "ceasefires", "cease fire" ]
    , [ "bomb", "bombs", "bombed", "bombing", "bombings" ]
    , [ "airstrike", "airstrikes", "air strike", "air strikes" ]
    , [ "missile", "missiles" ]
    , [ "strike", "strikes", "struck" ]
    , [ "mass shooting", "mass shootings" ]
    , [ "hostage", "hostages" ]
    , [ "coup" ]
    , [ "assassination", "assassinated" ]

    -- Disasters and health
    , [ "earthquake", "earthquakes" ]
    , [ "hurricane", "hurricanes", "typhoon", "typhoons", "cyclone", "cyclones" ]
    , [ "storm", "storms" ]
    , [ "flood", "floods", "flooded", "flooding" ]
    , [ "wildfire", "wildfires" ]
    , [ "tornado", "tornadoes" ]
    , [ "tsunami", "tsunamis" ]
    , [ "crash", "crashes", "crashed" ]
    , [ "outbreak", "outbreaks" ]
    , [ "pandemic", "epidemic" ]
    , [ "state of emergency" ]

    -- Politics and law
    , [ "election", "elections", "referendum" ]
    , [ "vote", "votes", "voted", "voting" ]
    , [ "resign", "resigns", "resigned", "resignation" ]
    , [ "impeach", "impeached", "impeachment" ]
    , [ "court", "courts", "supreme court" ]
    , [ "ruling", "rulings", "ruled" ]
    , [ "convicted", "sentenced", "indicted" ]
    , [ "law", "laws" ]
    , [ "unrest" ]
    , [ "protest", "protests", "protested", "protesters" ]

    -- International relations
    , [ "agreement", "agreements", "deal", "deals", "treaty", "accord" ]
    , [ "summit" ]
    , [ "sanction", "sanctions", "sanctioned" ]

    -- Economy
    , [ "recession" ]
    , [ "inflation" ]
    , [ "interest rate", "interest rates", "rate hike", "rate hikes", "rate cut", "rate cuts" ]
    , [ "tariff", "tariffs" ]
    ]
