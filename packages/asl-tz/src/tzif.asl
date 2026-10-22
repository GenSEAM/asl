(module asl-tz/tzif :x [tzifParse loadZoneBytes loadZone safeZoneName? tzifVersion tzifFooter tzifTransitionCount TzifData tzifData] :i [])
enum TzifData
  (tzifData version: String transitions: (List Int64) typeIndexes: (List Int64) offsets: (List Int64) dstFlags: (List Bool) abbreviations: (List String) footer: String)

fn tzifError offset: Int64 reason: String -> String
  (str "offset:" (stringFromInt64 offset) ":" reason)

fn tzifU32 bytes: Bytes p: Int64 -> (Result Int64 String)
  (if (or (< p 0) (> (+ p 4) (bytesLength bytes))) (err (tzifError p "truncated"))
    (ok (+ (* (bytesGet bytes p) 16777216) (* (bytesGet bytes (+ p 1)) 65536) (* (bytesGet bytes (+ p 2)) 256) (bytesGet bytes (+ p 3)))))

fn tzifI32 bytes: Bytes p: Int64 -> (Result Int64 String)
  (match (tzifU32 bytes p) ((err e) (err e)) ((ok n) (ok (if (>= n 2147483648) (- n 4294967296) n))))

fn tzifI64Loop bytes: Bytes p: Int64 i: Int64 value: Int64 -> Int64
  (if (>= i 8) value (tzifI64Loop bytes p (+ i 1) (+ (* value 256) (bytesGet bytes (+ p i)))))

fn tzifI64 bytes: Bytes p: Int64 -> (Result Int64 String)
  (if (or (< p 0) (> (+ p 8) (bytesLength bytes))) (err (tzifError p "truncated"))
    (let [(first (bytesGet bytes p))]
      (ok (tzifI64Loop bytes p 1 (if (>= first 128) -1 0)))))

fn tzifCount counts: (List Int64) i: Int64 -> Int64
  (optionOr (listGet counts i) 0)

fn tzifMagic? bytes: Bytes p: Int64 -> Bool
  (and (= (bytesGet bytes p) 84) (and (= (bytesGet bytes (+ p 1)) 90) (and (= (bytesGet bytes (+ p 2)) 105) (= (bytesGet bytes (+ p 3)) 102))))

fn tzifHeaderLoop bytes: Bytes p: Int64 i: Int64 out: (List Int64) -> (List Int64)
  (if (>= i 6) out (match (tzifU32 bytes (+ p 20 (* i 4))) ((err _) out) ((ok n) (tzifHeaderLoop bytes p (+ i 1) (listAppend out [n])))))

fn tzifHeader bytes: Bytes p: Int64 -> (Result (List Int64) String)
  (if (or (< p 0) (> (+ p 44) (bytesLength bytes))) (err (tzifError p "truncatedHeader"))
    (if (not (tzifMagic? bytes p))
      (err (tzifError p "badMagic"))
      (ok (tzifHeaderLoop bytes p 0 []))))

fn tzifNameByte n: Int64 -> String
  (if (and (>= n 65) (<= n 90)) (optionOr (stringSlice "ABCDEFGHIJKLMNOPQRSTUVWXYZ" (- n 65) (- n 64)) "?")
    (if (and (>= n 97) (<= n 122)) (optionOr (stringSlice "abcdefghijklmnopqrstuvwxyz" (- n 97) (- n 96)) "?")
      (if (and (>= n 48) (<= n 57)) (optionOr (stringSlice "0123456789" (- n 48) (- n 47)) "?")
        (if (= n 43) "+" (if (= n 45) "-" (if (= n 47) "/" (if (= n 60) "<" (if (= n 62) ">" (if (= n 58) ":" (if (= n 44) "," (if (= n 46) "." "?")))))))))))

fn tzifAbbrLoop bytes: Bytes limit: Int64 i: Int64 out: String -> (Result String String)
  (if (>= i limit) (err (tzifError i "unterminatedAbbreviation"))
    (if (= (bytesGet bytes i) 0) (ok out)
      (tzifAbbrLoop bytes limit (+ i 1) (str out (tzifNameByte (bytesGet bytes i))))))

fn tzifAbbr bytes: Bytes p: Int64 limit: Int64 -> (Result String String)
  (if (or (< p 0) (>= p limit)) (err (tzifError p "abbreviationIndexOutOfRange"))
    (tzifAbbrLoop bytes limit p ""))

fn tzifDecodeFooter bytes: Bytes i: Int64 -> String
  (if (or (>= i (bytesLength bytes)) (= (bytesGet bytes i) 10)) ""
    (str (tzifNameByte (bytesGet bytes i)) (tzifDecodeFooter bytes (+ i 1))))

fn tzifFooterAt bytes: Bytes p: Int64 -> String
  (if (or (>= p (bytesLength bytes)) (!= (bytesGet bytes p) 10)) ""
    (tzifDecodeFooter bytes (+ p 1)))

fn tzifFooterNameEndLoop text: String i: Int64 -> Int64
  (if (>= i (stringLength text)) i
    (if (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" (optionOr (stringSlice text i (+ i 1)) "")) (tzifFooterNameEndLoop text (+ i 1)) i))

fn tzifFooterNameEnd text: String start: Int64 -> Int64
  (if (>= start (stringLength text)) start
    (if (= (optionOr (stringSlice text start (+ start 1)) "") "<")
      (+ start (+ (optionOr (stringIndexOf (optionOr (stringSlice text start (stringLength text)) "") ">") (- (stringLength text) start)) 1))
      (tzifFooterNameEndLoop text start)))

fn tzifFooterNumEndLoop text: String i: Int64 -> Int64
  (if (>= i (stringLength text)) i
    (if (stringContains? "0123456789:+-" (optionOr (stringSlice text i (+ i 1)) "")) (tzifFooterNumEndLoop text (+ i 1)) i))

fn tzifFooterNumEnd text: String start: Int64 -> Int64
  (tzifFooterNumEndLoop text start)

fn tzifFooterNameValid? text: String start: Int64 end: Int64 -> Bool
  (if (>= start (stringLength text)) false
    (if (= (optionOr (stringSlice text start (+ start 1)) "") "<")
      (and (<= end (stringLength text))
        (and (>= (- end start) 5) (= (optionOr (stringSlice text (- end 1) end) "") ">")))
      (>= (- end start) 3)))

fn tzifClockValid? text: String -> Bool
  (let [(body (if (or (stringStartsWith? text "+") (stringStartsWith? text "-")) (optionOr (stringSlice text 1 (stringLength text)) "") text))
        (parts (stringSplit body ":")) (hours (stringToInt64 (optionOr (listGet parts 0) "")))
        (minutes (stringToInt64 (optionOr (listGet parts 1) "0")))
        (seconds (stringToInt64 (optionOr (listGet parts 2) "0")))]
    (and (<= 1 (listLength parts)) (and (<= (listLength parts) 3)
      (and (some? hours) (and (some? minutes) (and (some? seconds)
        (and (>= (optionOr hours -1) 0) (and (<= (optionOr hours 999) 167)
          (and (>= (optionOr minutes -1) 0) (and (< (optionOr minutes 60) 60)
            (and (>= (optionOr seconds -1) 0) (< (optionOr seconds 60) 60))))))))))))

fn tzifMonthDayValid? m: (Option Int64) w: (Option Int64) d: (Option Int64) -> Bool
  (and (some? m) (and (some? w) (and (some? d)
    (and (>= (optionOr m 0) 1) (and (<= (optionOr m 0) 12)
      (and (>= (optionOr w 0) 1) (and (<= (optionOr w 0) 5)
        (and (>= (optionOr d -1) 0) (<= (optionOr d -1) 6)))))))))

fn tzifRuleDayValid? text: String -> Bool
  (let [(parts (stringSplit text "."))]
    (if (stringStartsWith? text "J")
      (let [(n (stringToInt64 (optionOr (stringSlice text 1 (stringLength text)) "")))]
        (and (some? n) (and (>= (optionOr n 0) 1) (<= (optionOr n 0) 365))))
      (if (stringStartsWith? text "M")
        (let [(month (optionOr (listGet parts 0) "M"))
              (m (stringToInt64 (optionOr (stringSlice month 1 (stringLength month)) "")))
              (w (stringToInt64 (optionOr (listGet parts 1) ""))) (d (stringToInt64 (optionOr (listGet parts 2) "")))]
          (and (= (listLength parts) 3) (tzifMonthDayValid? m w d)))
        (let [(n (stringToInt64 text))]
          (and (= (listLength parts) 1)
            (and (some? n) (and (>= (optionOr n -1) 0) (<= (optionOr n -1) 365))))))))

fn tzifRuleValid? text: String -> Bool
  (let [(parts (stringSplit text "/")) (day (optionOr (listGet parts 0) "")) (clock (optionOr (listGet parts 1) "2"))]
    (and (or (= (listLength parts) 1) (= (listLength parts) 2))
      (and (tzifRuleDayValid? day) (or (= (listLength parts) 1) (tzifClockValid? clock)))))

fn tzifFooterValid? footer: String -> Bool
  (if (= footer "") true
    (let [(commas (stringSplit footer ",")) (head (optionOr (listGet commas 0) ""))
          (stdEnd (tzifFooterNameEnd head 0)) (stdNumEnd (tzifFooterNumEnd head stdEnd))
          (stdOffset (optionOr (stringSlice head stdEnd stdNumEnd) ""))
          (dstEnd (tzifFooterNameEnd head stdNumEnd))
          (dstNumEnd (tzifFooterNumEnd head dstEnd))
          (dstOffset (optionOr (stringSlice head dstEnd dstNumEnd) ""))]
      (and (tzifFooterNameValid? head 0 stdEnd)
        (and (> stdNumEnd stdEnd) (and (tzifClockValid? stdOffset)
        (if (= stdNumEnd (stringLength head)) (= (listLength commas) 1)
          (and (tzifFooterNameValid? head stdNumEnd dstEnd) (and (if (= dstNumEnd dstEnd) true (tzifClockValid? dstOffset))
            (and (= (listLength commas) 3)
              (and (tzifRuleValid? (optionOr (listGet commas 1) "")) (tzifRuleValid? (optionOr (listGet commas 2) ""))))))))))))

fn tzifTimeLoop bytes: Bytes width: Int64 timeStart: Int64 times: Int64 i: Int64 out: (List Int64) -> (Result (List Int64) String)
  (if (>= i times) (ok out)
    (match (if (= width 8) (tzifI64 bytes (+ timeStart (* i 8))) (tzifI32 bytes (+ timeStart (* i 4))))
      ((err e) (err e)) ((ok n) (tzifTimeLoop bytes width timeStart times (+ i 1) (listAppend out [n])))))

fn tzifIndexLoop bytes: Bytes indexStart: Int64 types: Int64 times: Int64 i: Int64 out: (List Int64) -> (Result (List Int64) String)
  (if (>= i times) (ok out) (let [(ix (bytesGet bytes (+ indexStart i)))]
    (if (>= ix types) (err (tzifError (+ indexStart i) "typeIndexOutOfRange")) (tzifIndexLoop bytes indexStart types times (+ i 1) (listAppend out [ix])))))

fn tzifTypeLoop bytes: Bytes typeStart: Int64 types: Int64 charStart: Int64 chars: Int64 version: String footer: String i: Int64 offsets: (List Int64) dsts: (List Bool) names: (List String) transitions: (List Int64) indexes: (List Int64) -> (Result TzifData String)
  (if (>= i types) (ok (tzifData version transitions indexes offsets dsts names footer))
    (match (tzifI32 bytes (+ typeStart (* i 6))) ((err e) (err e))
      ((ok off) (let [(dst (bytesGet bytes (+ typeStart (* i 6) 4))) (ai (bytesGet bytes (+ typeStart (* i 6) 5)))]
        (if (> dst 1) (err (tzifError (+ typeStart (* i 6) 4) "invalidDstFlag"))
          (match (tzifAbbr bytes (+ charStart ai) (+ charStart chars)) ((err e) (err e))
            ((ok abbr) (tzifTypeLoop bytes typeStart types charStart chars version footer (+ i 1) (listAppend offsets [off]) (listAppend dsts [(= dst 1)]) (listAppend names [abbr]) transitions indexes))))))))

fn tzifSection bytes: Bytes p: Int64 width: Int64 version: String c: (List Int64) -> (Result TzifData String)
  (let [(leaps (tzifCount c 2)) (times (tzifCount c 3)) (types (tzifCount c 4)) (chars (tzifCount c 5))
        (timeStart (+ p 44)) (indexStart (+ timeStart (* times width))) (typeStart (+ indexStart times))
        (charStart (+ typeStart (* types 6))) (leapStart (+ charStart chars))
        (sectionEnd (+ leapStart (* leaps (+ width 4)) (tzifCount c 1) (tzifCount c 0)))
        (footer (if (= width 8) (tzifFooterAt bytes sectionEnd) ""))]
    (if (or (= types 0) (or (> types 256) (or (> times 1000000) (> chars 1000000)))) (err (tzifError (+ p 20) "invalidCounts"))
      (if (> sectionEnd (bytesLength bytes)) (err (tzifError sectionEnd "truncatedSection"))
      (if (and (= width 8) (not (tzifFooterValid? footer))) (err (tzifError sectionEnd "invalidPosixFooter"))
          (match (tzifTimeLoop bytes width timeStart times 0 []) ((err e) (err e))
            ((ok ts) (match (tzifIndexLoop bytes indexStart types times 0 []) ((err e) (err e))
              ((ok ix) (tzifTypeLoop bytes typeStart types charStart chars version footer 0 [] [] [] ts ix)))))))))

fn tzifParse bytes: Bytes -> (Result TzifData String)
  (match (tzifHeader bytes 0) ((err e) (err e))
    ((ok c) (let [(v (bytesGet bytes 4))]
      (if (not (or (= v 0) (or (= v 50) (or (= v 51) (= v 52))))) (err (tzifError 4 "unsupportedVersion"))
        (if (= v 0) (tzifSection bytes 0 4 "1" c)
          (let [(next (+ 44 (* (tzifCount c 3) 5) (* (tzifCount c 4) 6) (tzifCount c 5) (* (tzifCount c 2) 8) (tzifCount c 1) (tzifCount c 0)))]
            (match (tzifHeader bytes next) ((err e) (err e)) ((ok c2) (tzifSection bytes next 8 (tzifNameByte v) c2)))))))))

fn safeZoneName? name: String -> Bool
  (and (not (stringEmpty? name)) (and (not (stringStartsWith? name "/")) (and (not (stringContains? name "..")) (and (not (stringContains? name "\\")) (not (stringContains? name ":"))))))

fn loadZoneBytes bytes: Bytes -> (Result TzifData String)
  (tzifParse bytes)

fn tzifVersion data: TzifData -> String
  (match data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer) version))

fn tzifFooter data: TzifData -> String
  (match data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer) footer))

fn tzifTransitionCount data: TzifData -> Int64
  (match data ((tzifData version transitions typeIndexes offsets dstFlags abbreviations footer) (listLength transitions)))

fn ! loadZone name: String -> (Result TzifData String)
  (if (not (safeZoneName? name)) (err "invalidZoneName")
    (match (fileReadBytes (str "/usr/share/zoneinfo/" name)) ((err _) (err "zoneFileReadFailed")) ((ok b) (tzifParse b))))
