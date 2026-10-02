module Cluster exposing (jaccardSimilarity, titleTokens, withClusterSizes)

{-| Group stories that are about the same event, by how many words their
titles share. The size of a story's group estimates how many outlets
covered it.
-}

import Regex
import Set exposing (Set)
import Story exposing (Story)


{-| Two titles count as the same event when their Jaccard similarity is at
least this much.
-}
similarityThreshold : Float
similarityThreshold =
    0.4


{-| Pairs each story with the size of its cluster, keeping the input order.

Clustering is greedy: the first unclustered story becomes a seed, and every
later unclustered story similar enough to that seed joins its cluster.

-}
withClusterSizes : List Story -> List ( Story, Int )
withClusterSizes stories =
    let
        indexedTokens =
            List.indexedMap (\index story -> ( index, titleTokens story.title )) stories

        clusterSizeByIndex =
            buildClusters indexedTokens []
                |> List.concatMap
                    (\memberIndexes ->
                        List.map (\index -> ( index, List.length memberIndexes )) memberIndexes
                    )
                |> List.sortBy Tuple.first
                |> List.map Tuple.second
    in
    List.map2 Tuple.pair stories clusterSizeByIndex


buildClusters : List ( Int, Set String ) -> List (List Int) -> List (List Int)
buildClusters remaining clustersSoFar =
    case remaining of
        [] ->
            List.reverse clustersSoFar

        ( seedIndex, seedTokens ) :: rest ->
            let
                ( similar, dissimilar ) =
                    List.partition
                        (\( _, tokens ) -> jaccardSimilarity seedTokens tokens >= similarityThreshold)
                        rest
            in
            buildClusters dissimilar ((seedIndex :: List.map Tuple.first similar) :: clustersSoFar)


{-| Lowercased words longer than two characters.
-}
titleTokens : String -> Set String
titleTokens title =
    Regex.split nonWordCharacters (String.toLower title)
        |> List.filter (\word -> String.length word > 2)
        |> Set.fromList


nonWordCharacters : Regex.Regex
nonWordCharacters =
    Regex.fromString "\\W+" |> Maybe.withDefault Regex.never


{-| Shared words divided by total distinct words: 0 means no overlap, 1
means identical word sets.
-}
jaccardSimilarity : Set String -> Set String -> Float
jaccardSimilarity tokensA tokensB =
    let
        unionSize =
            Set.size (Set.union tokensA tokensB)
    in
    if unionSize == 0 then
        0

    else
        toFloat (Set.size (Set.intersect tokensA tokensB)) / toFloat unionSize
