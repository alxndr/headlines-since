module Rss exposing (parse)

{-| Turn a news feed into a list of stories. Both common feed formats are
read: RSS 2.0 (`<rss><channel><item>`) and Atom (`<feed><entry>`, used by
e.g. Vox, Jacobin and The Atlantic).
-}

import Hex
import Iso8601
import Regex
import Rfc822
import Story exposing (Story)
import Time
import Url
import Xml.Decode as XD


{-| Items that can't be used (e.g. no parseable date) are skipped rather
than failing the whole feed. Only a malformed document is an error.

Looking for RSS items in an Atom feed finds none rather than failing, so
Atom entries are looked for when there are no RSS items.

-}
parse : String -> Result String (List Story)
parse xml =
    XD.run
        (XD.path [ "channel", "item" ] (XD.leakyList rssItemDecoder)
            |> XD.andThen
                (\rssItems ->
                    if List.isEmpty rssItems then
                        XD.path [ "entry" ] (XD.leakyList atomEntryDecoder)

                    else
                        XD.succeed rssItems
                )
        )
        xml


rssItemDecoder : XD.Decoder Story
rssItemDecoder =
    XD.map5 toStory
        (optionalText "title")
        (optionalText "link")
        (XD.path [ "pubDate" ] (XD.single pubDateDecoder))
        (XD.maybe (XD.path [ "source" ] (XD.single sourceDecoder)))
        -- Some feeds (e.g. Truthout) leave the description empty and put the
        -- article in <content:encoded>.
        (XD.map2 firstNonEmpty (optionalText "description") (optionalText "content:encoded"))


atomEntryDecoder : XD.Decoder Story
atomEntryDecoder =
    XD.map5 toStory
        (optionalText "title")
        (XD.path [ "link" ] (XD.list atomLinkDecoder) |> XD.map pickAtomLink |> XD.withDefault "")
        (XD.oneOf
            [ XD.path [ "published" ] (XD.single isoDateDecoder)
            , XD.path [ "updated" ] (XD.single isoDateDecoder)
            ]
        )
        (XD.succeed Nothing)
        -- Vox leaves <summary> empty and puts the article in <content>.
        (XD.map2 firstNonEmpty (optionalText "summary") (optionalText "content"))


{-| Text of a child element, or "" if it's missing or isn't plain text
(e.g. Atom content given as XHTML elements).
-}
optionalText : String -> XD.Decoder String
optionalText elementName =
    XD.path [ elementName ] (XD.single XD.string) |> XD.withDefault ""


firstNonEmpty : String -> String -> String
firstNonEmpty first second =
    if String.isEmpty (toPlainText first) then
        second

    else
        first


{-| Atom entries can have several links (the article, images, comments);
the article's has rel="alternate", or no rel at all.
-}
atomLinkDecoder : XD.Decoder { rel : String, href : String }
atomLinkDecoder =
    XD.map2 (\rel href -> { rel = rel, href = href })
        (XD.stringAttr "rel" |> XD.withDefault "alternate")
        (XD.stringAttr "href")


pickAtomLink : List { rel : String, href : String } -> String
pickAtomLink links =
    links
        |> List.filter (\link -> link.rel == "alternate")
        |> List.head
        |> Maybe.map .href
        |> Maybe.withDefault ""


{-| Atom dates are ISO 8601, e.g. "2026-10-02T17:14:00-04:00".
-}
isoDateDecoder : XD.Decoder Time.Posix
isoDateDecoder =
    XD.string
        |> XD.andThen
            (\date ->
                case Iso8601.toTime (String.trim date) of
                    Ok posix ->
                        XD.succeed posix

                    Err _ ->
                        XD.fail ("unparseable date: " ++ date)
            )


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


toStory : String -> String -> Time.Posix -> Maybe { name : String, url : Maybe String } -> String -> Story
toStory rawTitle rawLink publishedAt source rawDescription =
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
    { title = toPlainText rawTitle
    , url = link
    , sourceName = sourceName
    , sourceHost = sourceHost
    , publishedAt = Story.ExactTime publishedAt
    , topics = []
    , topicArticles = []
    , section = Nothing
    , sourceCount = 1
    , linkedArticles = []
    , summary = String.left maxSummaryLength (toPlainText rawDescription)
    }


{-| Summaries are only used to match articles to Wikipedia events, and the
matcher was evaluated on summaries cut to this length. Some feeds give the
whole article, which would otherwise dilute the match.
-}
maxSummaryLength : Int
maxSummaryLength =
    400


{-| The URL's host without any leading "www.", e.g. "bbc.co.uk"; "" for an
unparseable URL.
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


{-| Titles and descriptions can contain HTML, whose tags and character
references (like `&#8217;` for ’) survive XML decoding.
-}
toPlainText : String -> String
toPlainText html =
    html
        |> Regex.replace htmlTag (\_ -> " ")
        |> Regex.replace characterReference decodeCharacterReference
        |> Regex.replace whitespaceRun (\_ -> " ")
        |> String.trim


{-| `&#8217;`, `&#x2019;`, and a few common named references.
-}
decodeCharacterReference : Regex.Match -> String
decodeCharacterReference match =
    let
        name =
            match.match |> String.dropLeft 1 |> String.dropRight 1
    in
    case name of
        "amp" ->
            "&"

        "lt" ->
            "<"

        "gt" ->
            ">"

        "quot" ->
            "\""

        "apos" ->
            "'"

        "nbsp" ->
            " "

        _ ->
            (if String.startsWith "#x" name || String.startsWith "#X" name then
                Hex.fromString (String.toLower (String.dropLeft 2 name)) |> Result.toMaybe

             else if String.startsWith "#" name then
                String.toInt (String.dropLeft 1 name)

             else
                Nothing
            )
                |> Maybe.map (Char.fromCode >> String.fromChar)
                |> Maybe.withDefault match.match


characterReference : Regex.Regex
characterReference =
    Regex.fromString "&#?[A-Za-z0-9]+;" |> Maybe.withDefault Regex.never


whitespaceRun : Regex.Regex
whitespaceRun =
    Regex.fromString "\\s+" |> Maybe.withDefault Regex.never


htmlTag : Regex.Regex
htmlTag =
    Regex.fromString "<[^>]+>" |> Maybe.withDefault Regex.never
