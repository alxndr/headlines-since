module ArchiveLink exposing (archived)

{-| Links to articles go through archive.today (archive.ph), which keeps
copies of web pages, so paywalled articles can be read.

`https://archive.ph/newest/<article URL>` redirects to the newest archived
copy of the article. If there isn't one yet, archive.ph shows a "No results"
page with a button to archive the article there and then.

The article URL is passed as it is, not percent-encoded: archive.ph reads a
raw URL's query string as part of the article's address, but takes an
encoded URL literally (checked in October 2026).

-}


archived : String -> String
archived articleUrl =
    if String.isEmpty articleUrl then
        ""

    else
        "https://archive.ph/newest/" ++ withoutTrackingParameters articleUrl


{-| Archived copies are usually of the article's plain address, so tracking
parameters added by feeds and newsletters (e.g. the BBC's
"?at\_medium=RSS&at\_campaign=rss") would stop the newest copy from being
found. Other parameters are kept, because some identify the article itself
(e.g. Politico's "?id=...", NPR's "?storyId=...").

The fragment ("#...") is kept too; browsers don't send it to the server.

-}
withoutTrackingParameters : String -> String
withoutTrackingParameters url =
    let
        ( beforeFragment, fragment ) =
            splitOnce "#" url

        ( base, query ) =
            splitOnce "?" beforeFragment

        keptParameters =
            query
                |> Maybe.map (String.split "&")
                |> Maybe.withDefault []
                |> List.filter (\parameter -> not (String.isEmpty parameter) && not (isTrackingParameter parameter))
    in
    base
        ++ (if List.isEmpty keptParameters then
                ""

            else
                "?" ++ String.join "&" keptParameters
           )
        ++ (fragment |> Maybe.map ((++) "#") |> Maybe.withDefault "")


{-| The tracking parameters seen in this app's links (from the outlets'
feeds and four months of Wikipedia citations), plus a few widespread ones.
-}
isTrackingParameter : String -> Bool
isTrackingParameter parameter =
    let
        name =
            parameter
                |> String.split "="
                |> List.head
                |> Maybe.withDefault ""
    in
    List.any (\prefix -> String.startsWith prefix name) [ "utm_", "at_" ]
        || List.member name
            [ "maca" -- DW
            , "CMP" -- The Guardian
            , "cmpid"
            , "smid" -- The New York Times
            , "smtyp" -- The New York Times
            , "ref"
            , "msockid"
            , "_gl"
            , "WT.mc_id"
            , "dcmp" -- Sky News
            , "fbclid"
            , "gclid"
            , "mc_cid"
            , "mc_eid"
            ]


{-| Splits at the first occurrence of the separator, if there is one.
-}
splitOnce : String -> String -> ( String, Maybe String )
splitOnce separator text =
    case String.indexes separator text of
        index :: _ ->
            ( String.left index text, Just (String.dropLeft (index + String.length separator) text) )

        [] ->
            ( text, Nothing )
