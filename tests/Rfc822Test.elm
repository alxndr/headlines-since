module Rfc822Test exposing (suite)

import Expect
import Rfc822
import Test exposing (Test, describe, test)
import Time


expectMillis : Int -> String -> Expect.Expectation
expectMillis millis input =
    Rfc822.toPosix input
        |> Maybe.map Time.posixToMillis
        |> Expect.equal (Just millis)


suite : Test
suite =
    describe "Rfc822.toPosix"
        [ test "parses the format both feeds use" <|
            \_ ->
                -- `date -u -j -f '%Y-%m-%d %H:%M:%S' '2026-10-02 19:40:05' +%s` = 1790970005
                expectMillis 1790970005000 "Fri, 02 Oct 2026 19:40:05 GMT"
        , test "the day name is optional" <|
            \_ -> expectMillis 1790970005000 "02 Oct 2026 19:40:05 GMT"
        , test "seconds are optional" <|
            \_ -> expectMillis 1790970000000 "Fri, 02 Oct 2026 19:40 GMT"
        , test "a missing zone means GMT" <|
            \_ -> expectMillis 1790970005000 "Fri, 02 Oct 2026 19:40:05"
        , test "numeric zone offsets" <|
            \_ -> expectMillis 1790970005000 "Fri, 02 Oct 2026 21:40:05 +0200"
        , test "negative numeric zone offsets" <|
            \_ -> expectMillis 1790970005000 "Fri, 02 Oct 2026 15:40:05 -0400"
        , test "named US zones" <|
            \_ -> expectMillis 1790970005000 "Fri, 02 Oct 2026 15:40:05 EDT"
        , test "two-digit years" <|
            \_ -> expectMillis 1790970005000 "Fri, 02 Oct 26 19:40:05 GMT"
        , test "extra whitespace" <|
            \_ -> expectMillis 1790970005000 "  Fri,  02 Oct 2026   19:40:05 GMT "
        , test "the Unix epoch" <|
            \_ -> expectMillis 0 "Thu, 01 Jan 1970 00:00:00 GMT"
        , test "a leap day" <|
            \_ ->
                -- `date -u -j -f '%Y-%m-%d %H:%M:%S' '2028-02-29 12:00:00' +%s` = 1835438400
                expectMillis 1835438400000 "Tue, 29 Feb 2028 12:00:00 GMT"
        , describe "rejects invalid input"
            (List.map
                (\input ->
                    test ("\"" ++ input ++ "\"") <|
                        \_ -> Rfc822.toPosix input |> Expect.equal Nothing
                )
                [ ""
                , "not a date"
                , "2026-10-02T19:40:05Z"
                , "Fri, 31 Feb 2026 19:40:05 GMT"
                , "Fri, 02 Foo 2026 19:40:05 GMT"
                , "Fri, 02 Oct 2026 24:00:00 GMT"
                , "Fri, 02 Oct 2026 19:40:05 XYZ"
                , "Fri, 02 Oct 2026 19:40:05 +02"
                ]
            )
        ]
