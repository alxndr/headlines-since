module Story exposing (PublishedAt(..), Story, publishedDate)

import Date exposing (Date)
import Time


{-| One news item: a headline from an RSS feed, or an event summary from
Wikipedia's Current Events portal.

`sourceHost` is the hostname of the outlet that published the story (e.g.
"nbcnews.com"), used to recognise major outlets.

The remaining fields only carry information for Wikipedia events; RSS
items have no topics or section, and count as one source:

  - `topics`: the ongoing stories an event is filed under, outermost first
    (e.g. "2026 Iran war", then "2026 Strait of Hormuz crisis")
  - `topicArticles`: the Wikipedia article titles of the innermost of those
    topics, whose page views measure public interest in the story
  - `section`: the portal's section heading, e.g. "Sports"
  - `sourceCount`: how many news reports the event cites

-}
type alias Story =
    { title : String
    , url : String
    , sourceName : String
    , sourceHost : String
    , publishedAt : PublishedAt
    , topics : List String
    , topicArticles : List String
    , section : Maybe String
    , sourceCount : Int
    }


{-| RSS items have an exact time; Wikipedia events only have a date.
-}
type PublishedAt
    = ExactTime Time.Posix
    | DateOnly Date


{-| The calendar date the story was published, in the given time zone.
Date-only stories keep their date regardless of zone.
-}
publishedDate : Time.Zone -> Story -> Date
publishedDate zone story =
    case story.publishedAt of
        ExactTime posix ->
            Date.fromPosix zone posix

        DateOnly date ->
            date
