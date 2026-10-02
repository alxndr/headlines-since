module RssTest exposing (suite)

import Expect
import Rss
import Test exposing (Test, describe, test)
import Time


{-| Trimmed-down copies of real items from each feed.
-}
googleNewsFeed : String
googleNewsFeed =
    """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Top stories - Google News</title><link>https://news.google.com/?hl=en-US&amp;gl=US&amp;ceid=US:en</link><item><title>Christa Pike unconscious, on a ventilator at Nashville hospital, her lawyers say - NBC News</title><link>https://news.google.com/rss/articles/CBMitAFBVV95?oc=5</link><guid isPermaLink="false">CBMitAFBVV95</guid><pubDate>Fri, 02 Oct 2026 20:08:28 GMT</pubDate><description>&lt;ol&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/CBMitAFBVV95?oc=5" target="_blank"&gt;Christa Pike unconscious&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;NBC News&lt;/font&gt;&lt;/li&gt;&lt;/ol&gt;</description><source url="https://www.nbcnews.com">NBC News</source></item></channel></rss>"""


bbcNewsFeed : String
bbcNewsFeed =
    """<?xml version="1.0" encoding="UTF-8"?><rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
    <channel>
        <title><![CDATA[BBC News]]></title>
        <atom:link href="https://feeds.bbci.co.uk/news/rss.xml" rel="self" type="application/rss+xml"/>
        <item>
            <title><![CDATA[Widdecombe suspect charged with planning terror act against Farage]]></title>
            <description><![CDATA[Counter terror police say the further charge comes after a "hugely intensive and complex investigation".]]></description>
            <link>https://www.bbc.co.uk/news/articles/cv1j3lgrl6gko?at_medium=RSS&amp;at_campaign=rss</link>
            <guid isPermaLink="false">https://www.bbc.co.uk/news/articles/cv1j3lgrl6gko#1</guid>
            <pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate>
            <media:thumbnail width="240" height="135" url="https://ichef.bbci.co.uk/ace/standard/240/x.png"/>
        </item>
        <item>
            <title><![CDATA[Item with a broken date is skipped]]></title>
            <link>https://www.bbc.co.uk/news/articles/broken</link>
            <pubDate>sometime last week</pubDate>
        </item>
    </channel>
</rss>"""


suite : Test
suite =
    describe "Rss.parse"
        [ test "Google News item, using the <source> element for the outlet" <|
            \_ ->
                Rss.parse googleNewsFeed
                    |> Expect.equal
                        (Ok
                            [ { title = "Christa Pike unconscious, on a ventilator at Nashville hospital, her lawyers say - NBC News"
                              , url = "https://news.google.com/rss/articles/CBMitAFBVV95?oc=5"
                              , sourceName = "NBC News"
                              , sourceHost = "nbcnews.com"
                              , publishedAt = Time.millisToPosix 1790971708000
                              }
                            ]
                        )
        , test "BBC item, with CDATA, entities, and no <source> element" <|
            \_ ->
                Rss.parse bbcNewsFeed
                    |> Expect.equal
                        (Ok
                            [ { title = "Widdecombe suspect charged with planning terror act against Farage"
                              , url = "https://www.bbc.co.uk/news/articles/cv1j3lgrl6gko?at_medium=RSS&at_campaign=rss"
                              , sourceName = "bbc.co.uk"
                              , sourceHost = "bbc.co.uk"
                              , publishedAt = Time.millisToPosix 1790970005000
                              }
                            ]
                        )
        , test "HTML tags in titles are stripped" <|
            \_ ->
                Rss.parse "<rss><channel><item><title>&lt;b&gt;Bold&lt;/b&gt; news </title><link>https://example.com/a</link><pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate></item></channel></rss>"
                    |> Result.map (List.map .title)
                    |> Expect.equal (Ok [ "Bold news" ])
        , test "a document that isn't XML is an error" <|
            \_ ->
                Rss.parse "<html><body>Rate limited"
                    |> Expect.err
        ]
