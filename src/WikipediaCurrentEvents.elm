module WikipediaCurrentEvents exposing (pageTitle, parse, toPlainText)

{-| Parse the wikitext of a Wikipedia "Current events" day page, such as
<https://en.wikipedia.org/wiki/Portal:Current_events/2026_September_18>.

Those pages look like this (abridged):

    '''Armed conflicts and attacks'''
    *[[2026 Iran war]]
    **[[2026 Strait of Hormuz crisis]]
    ***Iran's IRGC hits the oil tanker ''Trend''. [https://example.com/a (AFP)]

Bullet lines that cite a source (an external `[url label]` link) are events.
Bullet lines without one are topic headings for the bullets nested under
them, which name the ongoing story an event belongs to.

-}

import Date exposing (Date)
import Regex exposing (Regex)
import Story exposing (Story)
import Url


{-| e.g. "Portal:Current events/2026 September 18"
-}
pageTitle : Date -> String
pageTitle date =
    "Portal:Current events/" ++ Date.format "y MMMM d" date


type alias Citation =
    { url : String
    , label : String
    }


{-| A topic heading, remembered while reading the bullets nested under it.
-}
type alias Heading =
    { depth : Int
    , topics : List Topic
    }


{-| `article` is the Wikipedia article a topic links to, if it links to
one; it can differ from the displayed `name`, as in
"[[Sudanese civil war (2023–present)|Sudanese civil war]]".
-}
type alias Topic =
    { name : String
    , article : Maybe String
    }


type alias ParseState =
    { section : Maybe String
    , headings : List Heading
    , stories : List Story
    }


parse : Date -> String -> List Story
parse date wikitext =
    wikitext
        |> newsItemsSection
        |> Regex.replace htmlComment (\_ -> "")
        |> String.lines
        |> List.foldl (parseLine date) { section = Nothing, headings = [], stories = [] }
        |> .stories
        |> List.reverse


{-| The page wraps its events in these comments; the rest is navigation.
-}
newsItemsSection : String -> String
newsItemsSection wikitext =
    let
        startMarker =
            "<!-- All news items below this line -->"

        endMarker =
            "<!-- All news items above this line -->"

        afterStart =
            case String.indexes startMarker wikitext of
                index :: _ ->
                    String.dropLeft (index + String.length startMarker) wikitext

                [] ->
                    wikitext
    in
    case String.indexes endMarker afterStart of
        index :: _ ->
            String.left index afterStart

        [] ->
            afterStart


parseLine : Date -> String -> ParseState -> ParseState
parseLine date line state =
    let
        trimmedLine =
            String.trim line

        depth =
            String.length trimmedLine - String.length (dropLeadingBullets trimmedLine)

        content =
            String.trim (dropLeadingBullets trimmedLine)
    in
    if depth == 0 then
        -- A non-bullet line, e.g. a '''Section''' heading, ends every topic.
        case Regex.find sectionHeading trimmedLine of
            [ { submatches } ] ->
                { state | section = List.head submatches |> Maybe.andThen identity, headings = [] }

            _ ->
                if String.isEmpty trimmedLine then
                    state

                else
                    { state | headings = [] }

    else
        let
            -- Headings at this depth or deeper don't contain this line.
            enclosingHeadings =
                List.filter (\heading -> heading.depth < depth) state.headings

            citations =
                Regex.find externalLink content
                    |> List.filterMap toCitation
        in
        case citations of
            [] ->
                { state | headings = enclosingHeadings ++ [ { depth = depth, topics = headingTopics content } ] }

            firstCitation :: _ ->
                { state
                    | headings = enclosingHeadings
                    , stories =
                        { title = toPlainText content
                        , url = firstCitation.url
                        , sourceName = "Wikipedia, citing " ++ String.join ", " (List.map .label citations)
                        , sourceHost = hostOf firstCitation.url
                        , publishedAt = Story.DateOnly date
                        , topics = List.concatMap (.topics >> List.map .name) enclosingHeadings
                        , topicArticles =
                            enclosingHeadings
                                |> List.reverse
                                |> List.head
                                |> Maybe.map (.topics >> List.filterMap .article)
                                |> Maybe.withDefault []
                        , section = state.section
                        , sourceCount = List.length citations
                        , linkedArticles =
                            Regex.find wikiLink content
                                |> List.filterMap (.submatches >> wikiLinkArticle)
                        , summary = ""
                        }
                            :: state.stories
                }


dropLeadingBullets : String -> String
dropLeadingBullets text =
    if String.startsWith "*" text then
        dropLeadingBullets (String.dropLeft 1 text)

    else
        text


{-| A heading like "[[A]], [[B]]" names two topics. A heading without wiki
links is used as-is.
-}
headingTopics : String -> List Topic
headingTopics content =
    case Regex.find wikiLink content of
        [] ->
            [ { name = toPlainText content, article = Nothing } ]

        links ->
            List.filterMap
                (\link ->
                    Maybe.map (\name -> { name = name, article = wikiLinkArticle link.submatches })
                        (wikiLinkText link.submatches)
                )
                links


{-| The article a wiki link points to, without any "#Section" anchor.
-}
wikiLinkArticle : List (Maybe String) -> Maybe String
wikiLinkArticle submatches =
    case submatches of
        (Just target) :: _ ->
            case String.split "#" target of
                article :: _ ->
                    if String.isEmpty (String.trim article) then
                        Nothing

                    else
                        Just (String.trim article)

                [] ->
                    Nothing

        _ ->
            Nothing


toCitation : Regex.Match -> Maybe Citation
toCitation match =
    case match.submatches of
        (Just url) :: label :: _ ->
            Just
                { url = url
                , label =
                    label
                        |> Maybe.withDefault ""
                        |> toPlainText
                        -- Labels are written like "(AP)".
                        |> removePrefix "("
                        |> removeSuffix ")"
                }

        _ ->
            Nothing


{-| Converts wikitext markup to readable text: wiki links become their
displayed text, and citations, templates, HTML tags, bold/italic quotes, and
invisible characters are removed.

Templates (`{{...}}`) are dropped entirely, so any text inside one is lost.

-}
toPlainText : String -> String
toPlainText wikitext =
    wikitext
        |> Regex.replace externalLink (\_ -> "")
        |> Regex.replace wikiLink (\match -> Maybe.withDefault "" (wikiLinkText match.submatches))
        |> Regex.replace template (\_ -> "")
        |> Regex.replace htmlTag (\_ -> "")
        |> Regex.replace boldOrItalicQuotes (\_ -> "")
        |> Regex.replace invisibleCharacters (\_ -> "")
        |> String.replace "&nbsp;" " "
        |> String.replace "&ndash;" "–"
        |> String.replace "&mdash;" "—"
        |> String.replace "&amp;" "&"
        |> Regex.replace whitespaceRun (\_ -> " ")
        -- Removing a citation can leave a space before the final period.
        |> Regex.replace spaceBeforePunctuation (\match -> String.trim match.match)
        |> String.trim


{-| "[[Target|shown text]]" shows "shown text"; "[[Target]]" shows
"Target".
-}
wikiLinkText : List (Maybe String) -> Maybe String
wikiLinkText submatches =
    case submatches of
        (Just target) :: (Just shownText) :: _ ->
            if String.isEmpty shownText then
                Just target

            else
                Just shownText

        (Just target) :: _ ->
            Just target

        _ ->
            Nothing


hostOf : String -> String
hostOf urlString =
    case Url.fromString urlString of
        Just url ->
            removePrefix "www." url.host

        Nothing ->
            ""


removePrefix : String -> String -> String
removePrefix prefix text =
    if String.startsWith prefix text then
        String.dropLeft (String.length prefix) text

    else
        text


removeSuffix : String -> String -> String
removeSuffix suffix text =
    if String.endsWith suffix text then
        String.dropRight (String.length suffix) text

    else
        text



-- PATTERNS


regex : String -> Regex
regex pattern =
    Regex.fromString pattern |> Maybe.withDefault Regex.never


{-| `[[Target]]` or `[[Target|shown text]]`; submatches are the target and
the optional shown text.
-}
wikiLink : Regex
wikiLink =
    regex "\\[\\[([^\\]|]*)(?:\\|([^\\]]*))?\\]\\]"


{-| `[https://example.com/a (AFP)]`; submatches are the URL and the label.
-}
externalLink : Regex
externalLink =
    regex "\\[(https?://[^\\s\\]]+)\\s*([^\\]]*)\\]"


template : Regex
template =
    regex "\\{\\{[^{}]*\\}\\}"


{-| A line that is entirely bold, like `'''Sports'''`.
-}
sectionHeading : Regex
sectionHeading =
    regex "^'''([^']+)'''$"


htmlComment : Regex
htmlComment =
    regex "<!--[\\s\\S]*?-->"


htmlTag : Regex
htmlTag =
    regex "<[^>]+>"


boldOrItalicQuotes : Regex
boldOrItalicQuotes =
    regex "'{2,}"


{-| Zero-width spaces and joiners, word joiners, and byte-order marks, which
Wikipedia editors sometimes paste in by accident.
-}
invisibleCharacters : Regex
invisibleCharacters =
    regex "[\\u200B-\\u200D\\u2060\\uFEFF]"


whitespaceRun : Regex
whitespaceRun =
    regex "\\s+"


spaceBeforePunctuation : Regex
spaceBeforePunctuation =
    regex "\\s+[.,;:]"
