module OutletMatch exposing (EventIndex, attachToRanked, bestMatch, eventIndex, similarity)

{-| Match a news outlet's article (from its RSS feed) to the Wikipedia event
it reports, if any.

The article's title and summary are compared with each event's text and
linked article titles, as sets of words. Words used by many events (like
"the" or "president") count for little: each word is weighted by how rare it
is among the events (its inverse document frequency), and the similarity is
the cosine of the two weighted word sets, from 0 (nothing in common) to 1.

This is deliberately strict. It was evaluated on 142 real headlines from
the BBC, The Nation, Common Dreams and Mother Jones, hand-checked against
the Wikipedia events within 3 days: only 12 had a matching event (these
outlets mostly publish opinion and investigations, which Wikipedia doesn't
list as events). At the 0.25 threshold it found 2 of those 12 and made no
wrong matches; the highest-scoring wrong match scored 0.19. Looser
thresholds found more but quickly became unreliable, because headlines like
"Revolution or No Revolution" share a word or two with unrelated events.

-}

import Date
import Dict exposing (Dict)
import Rank exposing (RankedStory)
import Regex
import Set exposing (Set)
import Story exposing (Story)
import Time


matchThreshold : Float
matchThreshold =
    0.25


maxDaysApart : Int
maxDaysApart =
    3


{-| The Wikipedia events with their words, and how many events use each
word. (Plain data rather than a weighting function, so it can be kept in
the model, which is compared with `==`.)
-}
type EventIndex
    = EventIndex
        { events : List ( Story, Set String )
        , eventsUsingWord : Dict String Int
        , eventCount : Int
        }


eventIndex : List Story -> EventIndex
eventIndex events =
    let
        eventsWithWords =
            List.map (\event -> ( event, words (String.join " " (event.title :: event.linkedArticles)) )) events

        eventsUsing =
            eventsWithWords
                |> List.concatMap (Tuple.second >> Set.toList)
                |> List.foldl (\word -> Dict.update word (Maybe.withDefault 0 >> (+) 1 >> Just)) Dict.empty
    in
    EventIndex
        { events = eventsWithWords
        , eventsUsingWord = eventsUsing
        , eventCount = List.length events
        }


{-| Rarer words weigh more: log((events + 1) / (events using the word + 1)).
A word no event uses gets the highest weight, because an article's
distinctive words that no event mentions are evidence against it matching
any of them.
-}
wordWeight : { a | eventsUsingWord : Dict String Int, eventCount : Int } -> String -> Float
wordWeight { eventsUsingWord, eventCount } word =
    logBase e ((toFloat eventCount + 1) / (toFloat (Dict.get word eventsUsingWord |> Maybe.withDefault 0) + 1))


{-| The most similar event published within `maxDaysApart` days of the
article, if it's similar enough.
-}
bestMatch : Time.Zone -> EventIndex -> Story -> Maybe Story
bestMatch zone (EventIndex index) article =
    let
        articleWords =
            words (article.title ++ " " ++ article.summary)

        articleDay =
            Date.toRataDie (Story.publishedDate zone article)

        isNearby event =
            abs (Date.toRataDie (Story.publishedDate zone event) - articleDay) <= maxDaysApart
    in
    index.events
        |> List.filter (Tuple.first >> isNearby)
        |> List.map (\( event, eventWords ) -> ( similarity (wordWeight index) articleWords eventWords, event ))
        |> List.filter (\( score, _ ) -> score >= matchThreshold)
        |> List.sortBy (Tuple.first >> negate)
        |> List.head
        |> Maybe.map Tuple.second


{-| Cosine similarity of two word sets, each word weighted by `weightOf`.
-}
similarity : (String -> Float) -> Set String -> Set String -> Float
similarity weightOf wordsA wordsB =
    let
        sumOfSquaredWeights wordSet =
            wordSet
                |> Set.toList
                |> List.map (\word -> weightOf word ^ 2)
                |> List.sum

        denominator =
            sqrt (sumOfSquaredWeights wordsA * sumOfSquaredWeights wordsB)
    in
    if denominator <= 0 then
        0

    else
        sumOfSquaredWeights (Set.intersect wordsA wordsB) / denominator


{-| Lowercased words of 3 or more letters or digits, plus shorter ones that
contain a digit or are all capitals, so "G7", "UK" and "EU" count.
-}
words : String -> Set String
words text =
    Regex.find wordPattern text
        |> List.map .match
        |> List.filter
            (\word ->
                String.length word > 2 || String.any Char.isDigit word || (String.length word == 2 && String.all Char.isUpper word)
            )
        |> List.map String.toLower
        |> Set.fromList


wordPattern : Regex.Regex
wordPattern =
    Regex.fromString "[A-Za-z0-9]+" |> Maybe.withDefault Regex.never


{-| Adds each article that reports one of the ranked stories' events to
that story's related reports. Articles about anything else (including
Wikipedia events that didn't make the list) are returned as unmatched.
-}
attachToRanked : Time.Zone -> EventIndex -> List RankedStory -> List Story -> { ranked : List RankedStory, unmatched : List Story }
attachToRanked zone index ranked articles =
    let
        reportsEvent event rankedStory =
            rankedStory.story == event || List.member event rankedStory.relatedReports

        attach article state =
            case bestMatch zone index article of
                Just event ->
                    if List.any (reportsEvent event) state.ranked then
                        { state
                            | ranked =
                                List.map
                                    (\rankedStory ->
                                        if reportsEvent event rankedStory then
                                            { rankedStory
                                                | relatedReports =
                                                    (article :: rankedStory.relatedReports)
                                                        |> List.sortBy (Story.publishedDate zone >> Date.toRataDie)
                                            }

                                        else
                                            rankedStory
                                    )
                                    state.ranked
                        }

                    else
                        { state | unmatched = article :: state.unmatched }

                Nothing ->
                    { state | unmatched = article :: state.unmatched }
    in
    List.foldl attach { ranked = ranked, unmatched = [] } articles
        |> (\state -> { state | unmatched = List.reverse state.unmatched })
