module WikipediaCurrentEventsTest exposing (suite)

import Date
import Expect
import Story
import Test exposing (Test, describe, test)
import Time
import WikipediaCurrentEvents


september18 : Date.Date
september18 =
    Date.fromCalendarDate 2026 Time.Sep 18


{-| Abridged from the real page for 2026 September 18, including its
invisible zero-width characters (written here as \\u{...} escapes).
-}
dayPage : String
dayPage =
    """{{Current events|year=2026|month=09|day=18|top=yes}}
<!-- All news items below this line -->
'''Armed conflicts and attacks'''
*[[2026 Iran war]]
**[[2026 Strait of Hormuz crisis]]
***The [[Islamic Republic News Agency|IRNA]] reports that [[Iran]]'s [[Islamic Revolutionary Guard Corps]] has [[List of ships attacked during the 2026 Iran war|hit]] the [[Togo]]-[[Flag state|flagged]] [[oil tanker]] ''Trend''. [https://www.freemalaysiatoday.com/category/world/2026/09/18/iran (AFP via ''FMT'')] [https://www.aljazeera.com/news/liveblog/2026/9/18/iran-war-live (Al Jazeera)]
*[[Mali War]]
**At least 100 [[Malian Armed Forces|Malian soldiers]] are reported killed. [https://www.arabnews.com/world/mali (AFP via ''Arab News'')]

'''Law and crime'''
*Three students are killed \u{200C}and eight others are injured \u{200B}in \u{200B}a [[Mass shooting|mass]] [[School shooting|shooting]]. [https://www.aa.com.tr/en/asia-pacific/6-st (AA)]

'''International relations'''
*[[International sanctions during the Russian invasion of Ukraine]], [[United States sanctions against Iran]]
** [[Donald Trump]] signs a sanctions act.<!-- editor note --> [https://apnews.com/article/sanctions (AP)]
<!-- All news items above this line -->
{{Current events|year=2026|month=09|day=18|bottom=yes}}"""


suite : Test
suite =
    describe "WikipediaCurrentEvents"
        [ test "pageTitle" <|
            \_ ->
                WikipediaCurrentEvents.pageTitle september18
                    |> Expect.equal "Portal:Current events/2026 September 18"
        , test "parses each cited bullet as an event, with its enclosing topics" <|
            \_ ->
                WikipediaCurrentEvents.parse september18 dayPage
                    |> List.map (\story -> ( story.title, story.topics ))
                    |> Expect.equal
                        [ ( "The IRNA reports that Iran's Islamic Revolutionary Guard Corps has hit the Togo-flagged oil tanker Trend."
                          , [ "2026 Iran war", "2026 Strait of Hormuz crisis" ]
                          )
                        , ( "At least 100 Malian soldiers are reported killed."
                          , [ "Mali War" ]
                          )
                        , ( "Three students are killed and eight others are injured in a mass shooting."
                          , []
                          )
                        , ( "Donald Trump signs a sanctions act."
                          , [ "International sanctions during the Russian invasion of Ukraine", "United States sanctions against Iran" ]
                          )
                        ]
        , test "uses the first citation for the link, and lists every citation's outlet" <|
            \_ ->
                WikipediaCurrentEvents.parse september18 dayPage
                    |> List.head
                    |> Maybe.map (\story -> ( story.url, story.sourceHost, story.sourceName ))
                    |> Expect.equal
                        (Just
                            ( "https://www.freemalaysiatoday.com/category/world/2026/09/18/iran"
                            , "freemalaysiatoday.com"
                            , "Wikipedia, citing AFP via FMT, Al Jazeera"
                            )
                        )
        , test "events are dated by their page" <|
            \_ ->
                WikipediaCurrentEvents.parse september18 dayPage
                    |> List.map .publishedAt
                    |> Expect.equal (List.repeat 4 (Story.DateOnly september18))
        , test "a page with no events" <|
            \_ ->
                WikipediaCurrentEvents.parse september18 "<!-- All news items below this line -->\n<!-- All news items above this line -->"
                    |> Expect.equal []
        , describe "toPlainText"
            [ test "templates, HTML tags, and entities" <|
                \_ ->
                    WikipediaCurrentEvents.toPlainText "A{{efn|note}} <small>B</small>&nbsp;C &ndash; D"
                        |> Expect.equal "A B C – D"
            ]
        ]
