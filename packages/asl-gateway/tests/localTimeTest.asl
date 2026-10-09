(module aslGateway/tests/localTimeTest
  :x [runTests]
  :i [(localTime :a lt)
      (cockpit :a ck)])

fn propIn props: (List (Pair String ck/AsnVal)) key: String -> (Option ck/AsnVal)
  (if (listEmpty? props)
    (none)
    (if (= (pairFirst (preludeHead props)) key) (some (pairSecond (preludeHead props))) (propIn (preludeTail props) key)))

fn atomOf v: (Option ck/AsnVal) -> String
  (mt v ((some x) (mt x ((ck/asnAtom s) s) (_ ""))) ((none) ""))

fn textOf v: (Option ck/AsnVal) -> String
  (mt v ((some x) (mt x ((ck/asnText s) s) (_ ""))) ((none) ""))

fn intsOf v: (Option ck/AsnVal) -> (List Int64)
  (mt v
    ((some x) (mt x ((ck/asnList items) (map (fn [(i ck/AsnVal)] -> Int64 (optionOr (stringToInt64 (atomOf (some i))) -1)) items)) (_ (list))))
    ((none) (list)))

fn pad n: Int64 width: Int64 -> String
  (let [(s (stringFromInt64 n))]
    (if (< (stringLength s) width) (str (stringRepeat "0" (- width (stringLength s))) s) s))

fn dayLine d: Int64 -> String
  (let [(ymd (lt/civilFromDays d))]
    (str (stringFromInt64 d) " " (pad (optionOr (listGet ymd 0) 0) 4) "-" (pad (optionOr (listGet ymd 1) 0) 2) "-" (pad (optionOr (listGet ymd 2) 0) 2)))

fn roundTripMisses d: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= d n)
    acc
    (let [(ymd (lt/civilFromDays d))
          (back (lt/daysFromCivil (optionOr (listGet ymd 0) 0) (optionOr (listGet ymd 1) 0) (optionOr (listGet ymd 2) 0)))]
      (roundTripMisses (+ d 1) n (if (= back d) acc (+ acc 1)))))

fn yearStartMisses starts: (List Int64) y: Int64 acc: Int64 -> Int64
  (if (listEmpty? starts)
    acc
    (let [(s (preludeHead starts))
          (good (and (= (lt/daysFromCivil y 1 1) s) (= (lt/civilFromDays s) (list y 1 1))))]
      (yearStartMisses (preludeTail starts) (+ y 1) (if good acc (+ acc 1)))))

fn testCivilDays! -> Bool
  (mt (fileReadString "asl/packages/asl-gateway/tests/localTimeFixture.asn")
    ((err e) (do (println (str "fixture: " e)) false))
    ((ok text)
      (mt (ck/asnReadText text)
        ((err e) (do (println (str "fixture: " e)) false))
        ((ok forms)
          (let [(p (mt (ck/asnProps (optionOr (listGet forms 0) (ck/asnList (list))) (some ":civilDays")) ((ok x) x) ((err _) (list))))
                (count (optionOr (stringToInt64 (atomOf (propIn p "count"))) 0))
                (starts (intsOf (propIn p "yearStarts")))
                (lines (map (fn [(d Int64)] -> String (str (dayLine d) "\n")) (range 0 count)))
                (digest (bytesSha256 (stringToBytes (stringJoin lines ""))))
                (misses (roundTripMisses 0 count 0))
                (startMisses (yearStartMisses starts 1970 0))]
            (do
              (assert (> count 49000) (str "fixture covers " (stringFromInt64 count) " days"))
              (assert (= (listLength starts) 137) "fixture lists the Jan 1 of 137 years 1970-2106")
              (assert (= startMisses 0) (str (stringFromInt64 startMisses) " years whose Jan 1 day number differs from libc"))
              (assert (= (dayLine (- count 1)) (textOf (propIn p "lastLine"))) "last day equals libc 2106-12-31")
              (assert (= misses 0) (str (stringFromInt64 misses) " days fail daysFromCivil (civilFromDays d) = d"))
              (assert (= digest (textOf (propIn p "sha256"))) "every day 1970-2106 renders as libc gmtime renders it (sha256 of all lines)")
              true))))))

fn showIn! tz: String t: Int64 -> String
  (mt (lt/zoneLoad! (some tz)) ((ok z) (lt/formatLocal z t true)) ((err e) (str "err " e)))

fn testUnknownZoneIsUtc! -> Bool
  (let [(t 1772953200)
        (utc (lt/formatLocal (lt/utcZone) t true))]
    (do
      (assert (= (showIn! "Foo/Bar" t) utc) "TZ=Foo/Bar (no zoneinfo file, not a POSIX string) is UTC as in libc")
      (assert (= (showIn! ":Foo/Bar" t) utc) "TZ=:Foo/Bar with a missing file is UTC as in libc")
      (assert (not (= (showIn! "Europe/Berlin" t) utc)) "a real zone still differs from UTC")
      true))

fn ! runTests -> Bool
  (do
    (assert (testCivilDays!) "testCivilDays")
    (assert (testUnknownZoneIsUtc!) "testUnknownZoneIsUtc")
    true)
