module Story exposing (Story)

import Time


{-| One headline from an RSS feed.

`sourceHost` is the hostname of the outlet that published the story (e.g.
"nbcnews.com"). It is kept separate from `url` because Google News links all
point at news.google.com redirects, which would hide the real outlet.

-}
type alias Story =
    { title : String
    , url : String
    , sourceName : String
    , sourceHost : String
    , publishedAt : Time.Posix
    }
