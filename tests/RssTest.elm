module RssTest exposing (suite)

import Expect
import Rss
import Story
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


{-| Abridged from Jacobin's real Atom feed.
-}
atomFeed : String
atomFeed =
    """<?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Jacobin</title><link href="https://jacobin.com/feed/" rel="self"/><entry><title>The Stakes Are High in Brazil’s Upcoming Election</title><link rel="alternate" type="text/html" href="https://jacobin.com/2026/10/brazil-election"/><link rel="enclosure" type="image/jpeg" href="https://media.jacobin.com/images/x.jpg"/><published>2026-10-02T21:47:17.872283Z</published><updated>2026-10-02T21:50:00Z</updated><summary type="text">During Jair Bolsonaro’s term as president, he faced a liberal establishment.</summary><content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>For a time this summer...</p></div></content></entry></feed>"""


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
                              , publishedAt = Story.ExactTime (Time.millisToPosix 1790971708000)
                              , topics = []
                              , topicArticles = []
                              , section = Nothing
                              , sourceCount = 1
                              , linkedArticles = []
                              , summary = "Christa Pike unconscious NBC News"
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
                              , publishedAt = Story.ExactTime (Time.millisToPosix 1790970005000)
                              , topics = []
                              , topicArticles = []
                              , section = Nothing
                              , sourceCount = 1
                              , linkedArticles = []
                              , summary = "Counter terror police say the further charge comes after a \"hugely intensive and complex investigation\"."
                              }
                            ]
                        )
        , test "HTML tags in titles are stripped" <|
            \_ ->
                Rss.parse "<rss><channel><item><title>&lt;b&gt;Bold&lt;/b&gt; news </title><link>https://example.com/a</link><pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate></item></channel></rss>"
                    |> Result.map (List.map .title)
                    |> Expect.equal (Ok [ "Bold news" ])
        , test "HTML and character references in descriptions become plain text" <|
            \_ ->
                Rss.parse "<rss><channel><item><title>T</title><link>https://example.com/a</link><pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate><description><![CDATA[<p>Trump&#8217;s rule &amp; <b>guns</b>&nbsp;&#x2014; more</p>]]></description></item></channel></rss>"
                    |> Result.map (List.map .summary)
                    |> Expect.equal (Ok [ "Trump’s rule & guns — more" ])
        , test "Atom feeds: alternate link, published date, and summary" <|
            \_ ->
                Rss.parse atomFeed
                    |> Result.map (List.map (\story -> ( story.title, story.url, story.summary )))
                    |> Expect.equal
                        (Ok
                            [ ( "The Stakes Are High in Brazil’s Upcoming Election"
                              , "https://jacobin.com/2026/10/brazil-election"
                              , "During Jair Bolsonaro’s term as president, he faced a liberal establishment."
                              )
                            ]
                        )
        , test "Atom dates are ISO 8601" <|
            \_ ->
                Rss.parse atomFeed
                    |> Result.map (List.map .publishedAt)
                    |> Expect.equal (Ok [ Story.ExactTime (Time.millisToPosix 1790977637872) ])
        , test "RSS 1.0 feeds: items beside the channel, with ISO 8601 dc:date" <|
            \_ ->
                Rss.parse """<?xml version="1.0" encoding="UTF-8"?><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel rdf:about="https://www.dw.com"><title>DW</title></channel><item rdf:about="https://www.dw.com/en/a"><title>Pakistan vs. Afghanistan</title><link>https://www.dw.com/en/a</link><description>For years, Pakistan supported the Taliban.</description><dc:date>2026-10-03T18:52:44Z</dc:date></item></rdf:RDF>"""
                    |> Result.map (List.map (\story -> ( story.title, story.url, story.publishedAt )))
                    |> Expect.equal (Ok [ ( "Pakistan vs. Afghanistan", "https://www.dw.com/en/a", Story.ExactTime (Time.millisToPosix 1791053564000) ) ])
        , test "an empty description falls back to the full content" <|
            \_ ->
                Rss.parse "<rss><channel><item><title>T</title><link>https://example.com/a</link><pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate><description></description><content:encoded><![CDATA[<p>The article text.</p>]]></content:encoded></item></channel></rss>"
                    |> Result.map (List.map .summary)
                    |> Expect.equal (Ok [ "The article text." ])
        , test "summaries are cut to 400 characters" <|
            \_ ->
                Rss.parse ("<rss><channel><item><title>T</title><link>https://example.com/a</link><pubDate>Fri, 02 Oct 2026 19:40:05 GMT</pubDate><description>" ++ String.repeat 500 "x" ++ "</description></item></channel></rss>")
                    |> Result.map (List.map (.summary >> String.length))
                    |> Expect.equal (Ok [ 400 ])
        , test "a document that isn't XML is an error" <|
            \_ ->
                Rss.parse "<html><body>Rate limited"
                    |> Expect.err
        ]
