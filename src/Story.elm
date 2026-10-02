module Story exposing (PublishedAt(..), Story, publishedDate, publishedPosix)

import Date exposing (Date)
import Time


{-| One news item: a headline from an RSS feed, or an event summary from
Wikipedia's Current Events portal.

`sourceHost` is the hostname of the outlet that published the story (e.g.
"nbcnews.com"). It is kept separate from `url` because Google News links all
point at news.google.com redirects, which would hide the real outlet.

`topics` names the ongoing stories an item belongs to (e.g. "2026 Iran
war"). Only Wikipedia provides these; RSS items have none.

-}
type alias Story =
    { title : String
    , url : String
    , sourceName : String
    , sourceHost : String
    , publishedAt : PublishedAt
    , topics : List String
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


{-| A single moment for comparing ages. Date-only stories are treated as
published at noon UTC on their date, the midpoint of the day.
-}
publishedPosix : Story -> Time.Posix
publishedPosix story =
    case story.publishedAt of
        ExactTime posix ->
            posix

        DateOnly date ->
            let
                millisPerDay =
                    24 * 60 * 60 * 1000

                unixEpochRataDie =
                    Date.toRataDie (Date.fromCalendarDate 1970 Time.Jan 1)
            in
            Time.millisToPosix ((Date.toRataDie date - unixEpochRataDie) * millisPerDay + millisPerDay // 2)
