module Rss exposing (parse)

{-| Turn an RSS 2.0 document into a list of stories.
-}

import Regex
import Rfc822
import Story exposing (Story)
import Time
import Url
import Xml.Decode as XD


{-| Items that can't be used (e.g. no parseable `<pubDate>`) are skipped
rather than failing the whole feed. Only a malformed document is an error.
-}
parse : String -> Result String (List Story)
parse xml =
    XD.run (XD.path [ "channel", "item" ] (XD.leakyList itemDecoder)) xml


itemDecoder : XD.Decoder Story
itemDecoder =
    XD.map4 toStory
        (XD.path [ "title" ] (XD.single XD.string) |> XD.withDefault "")
        (XD.path [ "link" ] (XD.single XD.string) |> XD.withDefault "")
        (XD.path [ "pubDate" ] (XD.single pubDateDecoder))
        (XD.maybe (XD.path [ "source" ] (XD.single sourceDecoder)))


{-| Google News items name the original outlet in an element like
`<source url="https://www.nbcnews.com">NBC News</source>`. BBC items don't
have one.
-}
sourceDecoder : XD.Decoder { name : String, url : Maybe String }
sourceDecoder =
    XD.map2 (\name url -> { name = name, url = url })
        XD.string
        (XD.maybe (XD.stringAttr "url"))


{-| Fails for an unparseable date, which makes `leakyList` skip the item.
-}
pubDateDecoder : XD.Decoder Time.Posix
pubDateDecoder =
    XD.string
        |> XD.andThen
            (\pubDate ->
                case Rfc822.toPosix pubDate of
                    Just posix ->
                        XD.succeed posix

                    Nothing ->
                        XD.fail ("unparseable pubDate: " ++ pubDate)
            )


toStory : String -> String -> Time.Posix -> Maybe { name : String, url : Maybe String } -> Story
toStory rawTitle rawLink publishedAt source =
    let
        link =
            String.trim rawLink

        -- Prefer the outlet's own URL; fall back to the article link.
        sourceHost =
            source
                |> Maybe.andThen .url
                |> Maybe.withDefault link
                |> hostOf

        sourceName =
            case Maybe.map (.name >> String.trim) source of
                Just name ->
                    if String.isEmpty name then
                        sourceHost

                    else
                        name

                Nothing ->
                    sourceHost
    in
    { title = stripTags rawTitle |> String.trim
    , url = link
    , sourceName = sourceName
    , sourceHost = sourceHost
    , publishedAt = Story.ExactTime publishedAt
    , topics = []
    , topicArticles = []
    , section = Nothing
    , sourceCount = 1
    }


{-| "<https://www.bbc.co.uk/news/x"> becomes "bbc.co.uk"; unparseable URLs
become "".
-}
hostOf : String -> String
hostOf urlString =
    case Url.fromString (String.trim urlString) of
        Just url ->
            if String.startsWith "www." url.host then
                String.dropLeft 4 url.host

            else
                url.host

        Nothing ->
            ""


stripTags : String -> String
stripTags =
    Regex.replace htmlTag (\_ -> "")


htmlTag : Regex.Regex
htmlTag =
    Regex.fromString "<[^>]+>" |> Maybe.withDefault Regex.never
