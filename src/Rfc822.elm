module Rfc822 exposing (toPosix)

{-| Parse the RFC 822 / RFC 2822 date-times used in RSS `<pubDate>` elements,
e.g. "Fri, 02 Oct 2026 19:40:05 GMT".

No published Elm package parses this format (the common ones only handle
ISO 8601), so this is a small hand-written parser.

-}

import Date
import Time


{-| Returns `Nothing` for anything that isn't a valid RFC 822 date-time.

The leading day name ("Fri,") is optional, seconds are optional, and a
missing zone is treated as GMT.

-}
toPosix : String -> Maybe Time.Posix
toPosix input =
    let
        -- The day name carries no information, so drop it if present.
        wordsWithoutDayName =
            case String.words (String.trim input) of
                first :: rest ->
                    if String.endsWith "," first then
                        rest

                    else
                        first :: rest

                [] ->
                    []
    in
    case wordsWithoutDayName of
        [ day, month, year, time ] ->
            fromParts day month year time "GMT"

        [ day, month, year, time, zone ] ->
            fromParts day month year time zone

        _ ->
            Nothing


fromParts : String -> String -> String -> String -> String -> Maybe Time.Posix
fromParts dayString monthString yearString timeString zoneString =
    Maybe.map3
        (\date ( hours, minutes, seconds ) offsetMinutes ->
            let
                daysSinceEpoch =
                    Date.toRataDie date - unixEpochRataDie

                secondsSinceEpoch =
                    (daysSinceEpoch * 86400)
                        + (hours * 3600)
                        + (minutes * 60)
                        + seconds
                        - (offsetMinutes * 60)
            in
            Time.millisToPosix (secondsSinceEpoch * 1000)
        )
        (parseDate dayString monthString yearString)
        (parseTime timeString)
        (parseZoneOffsetMinutes zoneString)


unixEpochRataDie : Int
unixEpochRataDie =
    Date.toRataDie (Date.fromCalendarDate 1970 Time.Jan 1)


parseDate : String -> String -> String -> Maybe Date.Date
parseDate dayString monthString yearString =
    Maybe.map3
        (\day month year ->
            let
                date =
                    Date.fromCalendarDate year month day
            in
            -- Date.fromCalendarDate clamps out-of-range days (e.g. 31 Feb
            -- becomes 28 Feb), so reject the input if clamping happened.
            if Date.day date == day then
                Just date

            else
                Nothing
        )
        (String.toInt dayString)
        (parseMonth monthString)
        (Maybe.map expandTwoDigitYear (String.toInt yearString))
        |> Maybe.andThen identity


{-| RFC 2822 section 4.3: two-digit years 00-49 are 2000-2049, and 50-99
are 1950-1999.
-}
expandTwoDigitYear : Int -> Int
expandTwoDigitYear year =
    if year < 50 then
        year + 2000

    else if year < 100 then
        year + 1900

    else
        year


parseMonth : String -> Maybe Time.Month
parseMonth monthString =
    case String.toLower monthString of
        "jan" ->
            Just Time.Jan

        "feb" ->
            Just Time.Feb

        "mar" ->
            Just Time.Mar

        "apr" ->
            Just Time.Apr

        "may" ->
            Just Time.May

        "jun" ->
            Just Time.Jun

        "jul" ->
            Just Time.Jul

        "aug" ->
            Just Time.Aug

        "sep" ->
            Just Time.Sep

        "oct" ->
            Just Time.Oct

        "nov" ->
            Just Time.Nov

        "dec" ->
            Just Time.Dec

        _ ->
            Nothing


{-| "HH:MM" or "HH:MM:SS"
-}
parseTime : String -> Maybe ( Int, Int, Int )
parseTime timeString =
    let
        inRange low high value =
            if value >= low && value <= high then
                Just value

            else
                Nothing

        build hoursString minutesString secondsString =
            Maybe.map3 (\hours minutes seconds -> ( hours, minutes, seconds ))
                (String.toInt hoursString |> Maybe.andThen (inRange 0 23))
                (String.toInt minutesString |> Maybe.andThen (inRange 0 59))
                -- 60 allows for leap seconds
                (String.toInt secondsString |> Maybe.andThen (inRange 0 60))
    in
    case String.split ":" timeString of
        [ hoursString, minutesString ] ->
            build hoursString minutesString "0"

        [ hoursString, minutesString, secondsString ] ->
            build hoursString minutesString secondsString

        _ ->
            Nothing


{-| Offset from UTC in minutes: "+0100" is 60, "EST" is -300.
-}
parseZoneOffsetMinutes : String -> Maybe Int
parseZoneOffsetMinutes zoneString =
    case String.toUpper zoneString of
        "GMT" ->
            Just 0

        "UT" ->
            Just 0

        "UTC" ->
            Just 0

        "Z" ->
            Just 0

        "EST" ->
            Just (-5 * 60)

        "EDT" ->
            Just (-4 * 60)

        "CST" ->
            Just (-6 * 60)

        "CDT" ->
            Just (-5 * 60)

        "MST" ->
            Just (-7 * 60)

        "MDT" ->
            Just (-6 * 60)

        "PST" ->
            Just (-8 * 60)

        "PDT" ->
            Just (-7 * 60)

        _ ->
            parseNumericOffset zoneString


{-| "+hhmm" or "-hhmm"
-}
parseNumericOffset : String -> Maybe Int
parseNumericOffset zoneString =
    let
        digits =
            String.dropLeft 1 zoneString

        sign =
            case String.left 1 zoneString of
                "+" ->
                    Just 1

                "-" ->
                    Just -1

                _ ->
                    Nothing
    in
    if String.length digits /= 4 || not (String.all Char.isDigit digits) then
        Nothing

    else
        Maybe.map3 (\signMultiplier hours minutes -> signMultiplier * (hours * 60 + minutes))
            sign
            (String.toInt (String.left 2 digits))
            (String.toInt (String.right 2 digits))
