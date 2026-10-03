module ArchiveLinkTest exposing (suite)

import ArchiveLink
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "ArchiveLink.archived"
        [ test "links to the newest archived copy, passing the URL unencoded" <|
            \_ ->
                ArchiveLink.archived "https://www.nytimes.com/2026/10/02/us/politics/trump-ads.html"
                    |> Expect.equal "https://archive.ph/newest/https://www.nytimes.com/2026/10/02/us/politics/trump-ads.html"
        , test "removes tracking parameters" <|
            \_ ->
                ArchiveLink.archived "https://www.bbc.co.uk/news/articles/cv1j3lgrl6gko?at_medium=RSS&at_campaign=rss"
                    |> Expect.equal "https://archive.ph/newest/https://www.bbc.co.uk/news/articles/cv1j3lgrl6gko"
        , test "keeps parameters that identify the article" <|
            \_ ->
                ArchiveLink.archived "https://www.politico.com/f/?id=000001a0-cf7a-d2df-a1f4-ffffb2910000&utm_source=rss"
                    |> Expect.equal "https://archive.ph/newest/https://www.politico.com/f/?id=000001a0-cf7a-d2df-a1f4-ffffb2910000"
        , test "removes DW's feed parameter" <|
            \_ ->
                ArchiveLink.archived "https://www.dw.com/en/pakistan-vs-afghanistan/a-123?maca=en-rss-en-all-1573-rdf"
                    |> Expect.equal "https://archive.ph/newest/https://www.dw.com/en/pakistan-vs-afghanistan/a-123"
        , test "keeps the fragment" <|
            \_ ->
                ArchiveLink.archived "https://example.com/live?smid=tw&update=5#post-12"
                    |> Expect.equal "https://archive.ph/newest/https://example.com/live?update=5#post-12"
        , test "no URL, no link" <|
            \_ -> ArchiveLink.archived "" |> Expect.equal ""
        ]
