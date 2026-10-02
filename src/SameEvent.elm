module SameEvent exposing (LinkWeights, areSameEvent, linkWeights, similarity)

{-| Recognise different reports of the same event, such as a disaster's
death toll being updated on several days, or a shooting followed by an
arrest.

Two Wikipedia events count as the same event when they were published at
most `maxDaysApart` days apart and link to largely the same Wikipedia
articles. Articles linked from many events (e.g. "Iran", "United States")
say little about which event it is, so links are weighted by how rare they
are. A story's own topic articles are ignored, since every event under a
topic links to it.

The threshold was chosen by reviewing real pairs of events from June to
October 2026: at 0.55 and above, nearly every pair was the same event
reported again; below it, about half were different events.

-}

import Date
import Dict exposing (Dict)
import Set exposing (Set)
import Story exposing (Story)
import Time


sameEventThreshold : Float
sameEventThreshold =
    0.55


maxDaysApart : Int
maxDaysApart =
    3


{-| How informative each linked article is, from how many of the stories
link to it.
-}
type LinkWeights
    = LinkWeights (Dict String Float)


{-| Rarer links weigh more: log(number of stories / number of stories
linking to the article), so an article linked from every story weighs 0.
-}
linkWeights : List Story -> LinkWeights
linkWeights stories =
    let
        storyCount =
            toFloat (List.length stories)

        storiesLinkingTo =
            stories
                |> List.concatMap (.linkedArticles >> Set.fromList >> Set.toList)
                |> List.foldl (\article -> Dict.update article (Maybe.withDefault 0 >> (+) 1 >> Just)) Dict.empty
    in
    LinkWeights (Dict.map (\_ linkingCount -> logBase e (storyCount / toFloat linkingCount)) storiesLinkingTo)


areSameEvent : Time.Zone -> LinkWeights -> Story -> Story -> Bool
areSameEvent zone weights storyA storyB =
    let
        daysApart =
            abs
                (Date.toRataDie (Story.publishedDate zone storyA)
                    - Date.toRataDie (Story.publishedDate zone storyB)
                )
    in
    daysApart <= maxDaysApart && similarity weights storyA storyB >= sameEventThreshold


{-| Weighted Jaccard similarity of the two stories' linked articles: the
weight of the articles both link to, divided by the weight of the articles
either links to. 0 means nothing in common, 1 means identical links.
-}
similarity : LinkWeights -> Story -> Story -> Float
similarity (LinkWeights weights) storyA storyB =
    let
        distinctiveLinks story =
            Set.diff (Set.fromList story.linkedArticles) (Set.fromList story.topicArticles)

        linksA =
            distinctiveLinks storyA

        linksB =
            distinctiveLinks storyB

        totalWeight articles =
            articles
                |> Set.toList
                |> List.map (\article -> Dict.get article weights |> Maybe.withDefault 0)
                |> List.sum

        unionWeight =
            totalWeight (Set.union linksA linksB)
    in
    if unionWeight <= 0 then
        0

    else
        totalWeight (Set.intersect linksA linksB) / unionWeight
