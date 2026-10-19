(module asl-tz/zone
  :x [utcToLocal localToUtc zoneOffset zoneAbbreviation zoneIsDst]
  :i [(asl-tz/tzif :a tz)])

enum ZoneResult
  (zoneResult offsetSeconds: Int64 isDst: Bool abbreviation: String)

fn zoneTypeAt data: TzifData index: Int64 -> ZoneResult
  (mt data
    ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer)
      (zoneResult (optionOr (listGet offsets index) 0) (optionOr (listGet dstFlags index) false) (optionOr (listGet abbreviations index) ""))))

fn posixNameEndLoop text: String i: Int64 -> Int64
  (if (>= i (stringLength text)) i
    (if (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" (optionOr (stringSlice text i (+ i 1)) "")) (posixNameEndLoop text (+ i 1)) i))

fn posixNameEnd text: String start: Int64 -> Int64
  (if (>= start (stringLength text)) start
    (if (= (optionOr (stringSlice text start (+ start 1)) "") "<")
      (+ start (+ (optionOr (stringIndexOf (optionOr (stringSlice text start (stringLength text)) "") ">") (- (stringLength text) start)) 1))
      (posixNameEndLoop text start)))

fn posixNumEndLoop text: String i: Int64 -> Int64
  (if (>= i (stringLength text)) i
    (if (stringContains? "0123456789:+-" (optionOr (stringSlice text i (+ i 1)) "")) (posixNumEndLoop text (+ i 1)) i))

fn posixNumEnd text: String start: Int64 -> Int64
  (posixNumEndLoop text start)

fn posixClock text: String fallback: Int64 -> Int64
  (let [(negative (stringStartsWith? text "-")) (positive (stringStartsWith? text "+"))
        (body (if (or negative positive) (optionOr (stringSlice text 1 (stringLength text)) "") text))
        (parts (stringSplit body ":"))
        (hours (optionOr (stringToInt64 (optionOr (listGet parts 0) "")) 0))
        (minutes (optionOr (stringToInt64 (optionOr (listGet parts 1) "0")) 0))
        (seconds (optionOr (stringToInt64 (optionOr (listGet parts 2) "0")) 0))
        (value (+ (* hours 3600) (+ (* minutes 60) seconds)))]
    (if (= text "") fallback (if negative (- value) value)))

fn posixOffset text: String -> Int64
  (- (posixClock text 0))

fn posixFooterOffsets footer: String -> (List Int64)
  (let [(head (optionOr (listGet (stringSplit footer ",") 0) ""))
        (stdEnd (posixNameEnd head 0)) (stdNumEnd (posixNumEnd head stdEnd))
        (stdOffset (posixOffset (optionOr (stringSlice head stdEnd stdNumEnd) "")))
        (dstEnd (posixNameEnd head stdNumEnd)) (dstNumEnd (posixNumEnd head dstEnd))]
    (if (= stdNumEnd (stringLength head)) [stdOffset]
      [stdOffset (if (= dstNumEnd dstEnd) (+ stdOffset 3600) (posixOffset (optionOr (stringSlice head dstEnd dstNumEnd) "")))]))

fn posixYearAtLoop unixDay: Int64 y: Int64 start: Int64 -> Int64
  (if (and (>= unixDay start) (< unixDay (+ start (if (posixLeap? y) 366 365)))) y
    (if (< unixDay start) (posixYearAtLoop unixDay (- y 1) (- start (if (posixLeap? (- y 1)) 366 365)))
      (posixYearAtLoop unixDay (+ y 1) (+ start (if (posixLeap? y) 366 365)))))

fn posixYearAt instant: Int64 -> Int64
  (posixYearAtLoop (/ instant 86400) 1970 0)

fn posixLeap? year: Int64 -> Bool
  (and (= (mod year 4) 0) (or (!= (mod year 100) 0) (= (mod year 400) 0)))

fn posixYearDaysLoop target: Int64 y: Int64 days: Int64 -> Int64
  (if (= y target) days
    (if (< y target) (posixYearDaysLoop target (+ y 1) (+ days (if (posixLeap? y) 366 365)))
      (posixYearDaysLoop target (- y 1) (- days (if (posixLeap? (- y 1)) 366 365)))))

fn posixYearDays year: Int64 -> Int64
  (posixYearDaysLoop year 1970 0)

fn posixMonthDays year: Int64 month: Int64 -> Int64
  (if (or (= month 1) (or (= month 3) (or (= month 5) (or (= month 7) (or (= month 8) (or (= month 10) (= month 12))))))) 31
    (if (= month 2) (if (posixLeap? year) 29 28) 30))

fn posixRuleDayBeforeLoop year: Int64 m: Int64 i: Int64 days: Int64 -> Int64
  (if (>= i m) days (posixRuleDayBeforeLoop year m (+ i 1) (+ days (posixMonthDays year i))))

fn posixRuleDay year: Int64 rule: String -> Int64
  (let [(fields (stringSplit rule "."))]
    (if (stringStartsWith? rule "J")
      (let [(ordinal (optionOr (stringToInt64 (optionOr (stringSlice rule 1 (stringLength rule)) "")) 1))]
        (+ (- ordinal 1) (if (and (posixLeap? year) (>= ordinal 60)) 1 0)))
      (if (not (stringStartsWith? rule "M")) (optionOr (stringToInt64 rule) 0)
      (let [(m (optionOr (stringToInt64 (optionOr (stringSlice (optionOr (listGet fields 0) "M0") 1 (stringLength (optionOr (listGet fields 0) "M0"))) "")) 1))
            (week (optionOr (stringToInt64 (optionOr (listGet fields 1) "1")) 1))
            (weekday (optionOr (stringToInt64 (optionOr (listGet fields 2) "0")) 0))
            (before (posixRuleDayBeforeLoop year m 1 0))
            (firstDay (+ (posixYearDays year) before))
            (firstWeekday (mod (+ firstDay 4) 7))
            (date (+ 1 (+ (mod (+ weekday (- firstWeekday) 7) 7) (* 7 (- week 1)))))
            (finalDate (if (> date (posixMonthDays year m)) (- date 7) date))]
        (+ before (- finalDate 1))))))

fn posixRuleInstant year: Int64 rule: String offset: Int64 -> Int64
  (let [(fields (stringSplit rule "/")) (dateRule (optionOr (listGet fields 0) "M1.1.0"))
        (clock (posixClock (optionOr (listGet fields 1) "") 7200))]
    (- (+ (* (+ (posixYearDays year) (posixRuleDay year dateRule)) 86400) clock) offset))

fn posixFooterTypeYearLoop unixDay: Int64 y: Int64 start: Int64 -> Int64
  (if (or (and (>= unixDay start) (< unixDay (+ start (if (posixLeap? y) 366 365)))) (and (< y -10000) false)) y
    (if (< unixDay start) (posixFooterTypeYearLoop unixDay (- y 1) (- start (if (posixLeap? (- y 1)) 366 365)))
      (posixFooterTypeYearLoop unixDay (+ y 1) (+ start (if (posixLeap? y) 366 365)))))

fn posixFooterType footer: String instant: Int64 -> (Option ZoneResult)
  (let [(commaParts (stringSplit footer ",")) (head (optionOr (listGet commaParts 0) ""))
        (stdEnd (posixNameEnd head 0)) (stdName (optionOr (stringSlice head 0 stdEnd) ""))
        (stdNumEnd (posixNumEnd head stdEnd))
        (stdOffset (posixOffset (optionOr (stringSlice head stdEnd stdNumEnd) "")))]
    (if (or (= stdName "") (= stdNumEnd stdEnd)) (none)
      (let [(dstStart stdNumEnd) (dstEnd (posixNameEnd head dstStart))
            (dstName (optionOr (stringSlice head dstStart dstEnd) ""))
            (dstNumEnd (posixNumEnd head dstEnd))
            (dstOffset (if (= dstEnd (stringLength head)) (+ stdOffset 3600)
              (if (= dstNumEnd dstEnd) (+ stdOffset 3600) (posixOffset (optionOr (stringSlice head dstEnd dstNumEnd) "")))))]
        (if (= dstName "") (some (zoneResult stdOffset false stdName))
          (if (< (listLength commaParts) 3) (none)
            (let [(unixDay (/ instant 86400)) (year (posixFooterTypeYearLoop unixDay 1970 0))
                  (start (posixRuleInstant year (optionOr (listGet commaParts 1) "") stdOffset))
                  (end (posixRuleInstant year (optionOr (listGet commaParts 2) "") dstOffset))
                  (daylight (if (< start end) (and (>= instant start) (< instant end)) (or (>= instant start) (< instant end))))]
              (some (if daylight (zoneResult dstOffset true dstName) (zoneResult stdOffset false stdName)))))))))

fn zoneTransitionIndexLoop transitions: (List Int64) instant: Int64 i: Int64 latest: Int64 -> Int64
  (if (>= i (listLength transitions)) latest
    (let [(t (optionOr (listGet transitions i) 0))]
      (if (<= t instant) (zoneTransitionIndexLoop transitions instant (+ i 1) i) latest)))

fn zoneTransitionIndex transitions: (List Int64) instant: Int64 -> Int64
  (zoneTransitionIndexLoop transitions instant 0 -1)

fn utcToLocal data: TzifData instantSeconds: Int64 -> ZoneResult
  (mt data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer)
    (let [(i (zoneTransitionIndex transitions instantSeconds))
          (afterTable (or (= (listLength transitions) 0) (> instantSeconds (optionOr (listGet transitions (- (listLength transitions) 1)) 0))))]
      (if (and afterTable (not (stringEmpty? footer)))
        (mt (posixFooterType footer instantSeconds)
          ((some result) result)
          ((none) (if (< i 0) (zoneTypeAt data 0) (zoneTypeAt data (optionOr (listGet typeIndexes i) 0)))))
        (if (< i 0) (zoneTypeAt data 0) (zoneTypeAt data (optionOr (listGet typeIndexes i) 0)))))))

fn zoneOffset data: TzifData instantSeconds: Int64 -> Int64
  (mt (utcToLocal data instantSeconds) ((zoneResult offset isDst abbreviation) offset))

fn zoneAbbreviation data: TzifData instantSeconds: Int64 -> String
  (mt (utcToLocal data instantSeconds) ((zoneResult offset isDst abbreviation) abbreviation))

fn zoneIsDst data: TzifData instantSeconds: Int64 -> Bool
  (mt (utcToLocal data instantSeconds) ((zoneResult offset isDst abbreviation) isDst))

fn zoneCandidatesAppendLoop footer: String i: Int64 out: (List Int64) -> (List Int64)
  (if (>= i (listLength (posixFooterOffsets footer))) out (zoneCandidatesAppendLoop footer (+ i 1) (listAppend out [(optionOr (listGet (posixFooterOffsets footer) i) 0)])))

fn zoneCandidatesLoop data: TzifData local: Int64 allOffsets: (List Int64) i: Int64 out: (List Int64) -> (List Int64)
  (if (>= i (listLength allOffsets)) out
    (let [(candidate (- local (optionOr (listGet allOffsets i) 0)))
          (at (utcToLocal data candidate))]
      (mt at ((zoneResult off dst abbr)
        (if (and (= (+ candidate off) local) (not (listContains? out candidate))) (zoneCandidatesLoop data local allOffsets (+ i 1) (listAppend out [candidate])) (zoneCandidatesLoop data local allOffsets (+ i 1) out))))))

fn zoneCandidates data: TzifData local: Int64 -> (List Int64)
  (mt data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer)
    (let [(allOffsets (zoneCandidatesAppendLoop footer 0 offsets))]
      (listSort (zoneCandidatesLoop data local allOffsets 0 [])))))

fn zoneInGap? local: Int64 at: Int64 oldOffset: Int64 newOffset: Int64 -> Bool
  (and (> newOffset oldOffset) (and (>= local (+ at oldOffset)) (< local (+ at newOffset))))

fn zoneFooterGapMapLoop rules: (List String) standard: Int64 daylight: Int64 last: Int64 local: Int64 policy: String year: Int64 i: Int64 -> (Option Int64)
  (if (>= i 3) (none)
    (let [(y (+ (- year 1) i))
          (start (posixRuleInstant y (optionOr (listGet rules 1) "") standard))
          (end (posixRuleInstant y (optionOr (listGet rules 2) "") daylight))
          (startMap (if (and (> start last) (zoneInGap? local start standard daylight)) (some (- local (if (= policy "earlier") standard daylight))) (none)))
          (endMap (if (and (> end last) (zoneInGap? local end daylight standard)) (some (- local (if (= policy "earlier") daylight standard))) (none)))]
      (mt startMap ((some value) (some value))
        ((none) (mt endMap ((some value) (some value)) ((none) (zoneFooterGapMapLoop rules standard daylight last local policy year (+ i 1))))))))

fn zoneFooterGapMap footer: String transitions: (List Int64) local: Int64 policy: String -> (Option Int64)
  (if (< (listLength (stringSplit footer ",")) 3) (none)
    (let [(rules (stringSplit footer ",")) (offsets (posixFooterOffsets footer))
          (standard (optionOr (listGet offsets 0) 0)) (daylight (optionOr (listGet offsets 1) 0))
          (year (posixYearAt local)) (last (optionOr (listGet transitions (- (listLength transitions) 1)) -9223372036854775807))]
      (zoneFooterGapMapLoop rules standard daylight last local policy year 0)))

fn zoneGapMapLoop transitions: (List Int64) typeIndexes: (List Int64) offsets: (List Int64) local: Int64 policy: String i: Int64 -> (Option Int64)
  (if (>= i (listLength transitions)) (none)
    (let [(at (optionOr (listGet transitions i) 0))
          (oldType (if (= i 0) 0 (optionOr (listGet typeIndexes (- i 1)) 0)))
          (newType (optionOr (listGet typeIndexes i) 0))
          (oldOffset (optionOr (listGet offsets oldType) 0))
          (newOffset (optionOr (listGet offsets newType) 0))
          (gapStart (+ at oldOffset))
          (gapEnd (+ at newOffset))]
      (if (and (> newOffset oldOffset) (and (>= local gapStart) (< local gapEnd)))
        (some (- local (if (= policy "earlier") oldOffset newOffset)))
        (zoneGapMapLoop transitions typeIndexes offsets local policy (+ i 1)))))

fn zoneGapMap data: TzifData local: Int64 policy: String -> (Option Int64)
  (mt data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer)
    (mt (zoneGapMapLoop transitions typeIndexes offsets local policy 0) ((some value) (some value)) ((none) (zoneFooterGapMap footer transitions local policy)))))

fn localToUtc data: TzifData localSeconds: Int64 policy: String -> (Result Int64 String)
  (let [(candidates (zoneCandidates data localSeconds)) (count (listLength (zoneCandidates data localSeconds)))]
    (if (= count 1) (ok (optionOr (listGet candidates 0) 0))
      (if (> count 1)
        (if (= policy "first") (ok (optionOr (listGet candidates 0) 0))
          (if (= policy "second") (ok (optionOr (listGet candidates (- count 1)) 0)) (err "fold")))
        (if (= policy "err") (err "gap")
          (if (or (= policy "earlier") (= policy "later"))
            (mt (zoneGapMap data localSeconds policy)
              ((some instant) (ok instant))
              ((none) (err "localTimeNotCovered")))
            (err (str "unsupportedGapPolicy:" policy)))))))
