module Rank exposing (score, topStories)

{-| Score stories by significance and pick the top ones.
-}

import Regex
import Set exposing (Set)
import Story exposing (Story)


{-| The highest-scoring stories, at most one per URL.
-}
topStories : Int -> List ( Story, Int ) -> List Story
topStories count storiesWithClusterSizes =
    storiesWithClusterSizes
        |> List.map (\( story, clusterSize ) -> ( score clusterSize story, story ))
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

  - coverage (weight 0.4): cluster size, maxing out at 10 similar stories
  - impact (weight 0.2): how many impact concepts the title mentions, maxing out at 4
  - authority (weight 0.1): 1 if the outlet is in the authority list

There is deliberately no recency signal: when catching up after time away,
a big story from the first day matters as much as one from today.

-}
score : Int -> Story -> Float
score clusterSize story =
    let
        coverage =
            min (toFloat clusterSize / 10) 1

        impact =
            min (toFloat (impactConceptCount story.title) / 4) 1

        authority =
            if Set.member story.sourceHost authoritativeHosts then
                1

            else
                0
    in
    (coverage * 0.4) + (impact * 0.2) + (authority * 0.1)


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
-}
impactConcepts : List (List String)
impactConcepts =
    [ [ "dead" ]
    , [ "kill", "kills", "killed", "killing", "killings" ]
    , [ "death", "deaths", "die", "dies", "died" ]
    , [ "injure", "injures", "injured", "injuring", "injury", "injuries" ]
    , [ "attack", "attacks", "attacked", "attacking" ]
    , [ "war", "wars" ]
    , [ "ceasefire", "ceasefires", "cease fire" ]
    , [ "bomb", "bombs", "bombed", "bombing", "bombings" ]
    , [ "earthquake", "earthquakes" ]
    , [ "hurricane", "hurricanes" ]
    , [ "storm", "storms" ]
    , [ "flood", "floods", "flooded", "flooding" ]
    , [ "election", "elections" ]
    , [ "vote", "votes", "voted", "voting" ]
    , [ "court", "courts", "supreme court" ]
    , [ "ruling", "rulings", "ruled" ]
    , [ "law", "laws" ]
    , [ "bill", "bills" ]
    , [ "pass", "passes", "passed" ]
    , [ "sanction", "sanctions", "sanctioned" ]
    , [ "market", "markets" ]
    , [ "crash", "crashes", "crashed" ]
    , [ "recession" ]
    , [ "inflation" ]
    , [ "rate hike", "rate hikes" ]
    , [ "strike", "strikes", "struck" ]
    , [ "unrest" ]
    , [ "protest", "protests", "protested", "protesters" ]
    , [ "mass shooting", "mass shootings" ]
    , [ "tornado", "tornadoes" ]
    , [ "tsunami", "tsunamis" ]
    , [ "outbreak", "outbreaks" ]
    , [ "pandemic" ]
    ]
