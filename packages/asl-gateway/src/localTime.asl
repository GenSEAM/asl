(module aslGateway/localTime
  :x [Zone PosixRule RuleDate DstRule utcZone zoneLoad! zoneFromTzif zoneFromPosix posixParse localOffset
      daysFromCivil civilFromDays floorSeconds formatLocal formatUtcTouch]
  :i [])

(enum RuleDate
  (:c julianNoLeap [(day Int64)])
  (:c julianZero [(day Int64)])
  (:c monthWeekDay [(month Int64) (week Int64) (weekday Int64)]))

(schema DstRule
  (:f dstOff Int64)
  (:f start RuleDate)
  (:f startTime Int64)
  (:f end RuleDate)
  (:f endTime Int64))

(schema PosixRule
  (:f stdOff Int64)
  (:f dst (Option DstRule)))

(schema Zone
  (:f transitions (List (Pair Int64 Int64)))
  (:f firstOff Int64)
  (:f rule (Option PosixRule)))

fn utcZone -> Zone
  (Zone :transitions (list) :firstOff 0 :rule (some (PosixRule :stdOff 0 :dst (none))))

fn daysFromCivil y: Int64 m: Int64 d: Int64 -> Int64
  (let [(yy (if (<= m 2) (- y 1) y))
        (era (/ yy 400))
        (yoe (- yy (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (* yoe 365) (/ yoe 4) (- 0 (/ yoe 100)) doy))]
    (+ (* era 146097) doe -719468))

fn civilFromDays z0: Int64 -> (List Int64)
  (let [(z (+ z0 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ (- doe (/ doe 1460)) (/ doe 36524)) (/ doe 146096)) 365))
        (y (+ yoe (* era 400)))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))]
    (list (if (<= m 2) (+ y 1) y) m d))

fn leapYear? y: Int64 -> Bool
  (and (= (mod y 4) 0) (or (not (= (mod y 100) 0)) (= (mod y 400) 0)))

fn monthLength y: Int64 m: Int64 -> Int64
  (cond ((= m 2) (if (leapYear? y) 29 28))
        ((or (= m 4) (= m 6) (= m 9) (= m 11)) 30)
        (else 31))

fn floorSeconds t: Float64 -> Int64
  (let [(i (optionOr (float64ToInt64 t) 0))]
    (if (< t (int64ToFloat64 i)) (- i 1) i))

fn be32 bs: Bytes at: Int64 -> Int64
  (let [(u (+ (* (bytesGet bs at) 16777216) (* (bytesGet bs (+ at 1)) 65536) (* (bytesGet bs (+ at 2)) 256) (bytesGet bs (+ at 3))))]
    (if (>= u 2147483648) (- u 4294967296) u))

fn be64Step bs: Bytes at: Int64 k: Int64 neg: Bool acc: Int64 -> Int64
  (if (>= k 8)
    (if neg (- 0 (+ acc 1)) acc)
    (let [(b (bytesGet bs (+ at k)))]
      (be64Step bs at (+ k 1) neg (+ (* acc 256) (if neg (- 255 b) b)))))

fn be64 bs: Bytes at: Int64 -> Int64
  (be64Step bs at 0 (>= (bytesGet bs at) 128) 0)

fn tzifCounts bs: Bytes at: Int64 -> (List Int64)
  (map (fn [(k Int64)] -> Int64 (be32 bs (+ at 20 (* 4 k)))) (list 0 1 2 3 4 5))

fn tzifDataSize counts: (List Int64) timeSize: Int64 -> Int64
  (let [(isut (nth counts 0)) (isstd (nth counts 1)) (leap (nth counts 2))
        (timecnt (nth counts 3)) (typecnt (nth counts 4)) (charcnt (nth counts 5))]
    (+ (* timecnt timeSize) timecnt (* typecnt 6) charcnt (* leap (+ timeSize 4)) isstd isut))

fn tzifTransitions bs: Bytes timesAt: Int64 idxAt: Int64 typesAt: Int64 timeSize: Int64 i: Int64 n: Int64 typecnt: Int64 acc: (List (Pair Int64 Int64)) -> (Result (List (Pair Int64 Int64)) String)
  (if (>= i n)
    (ok (listReverse acc))
    (let [(t (if (= timeSize 8) (be64 bs (+ timesAt (* i 8))) (be32 bs (+ timesAt (* i 4)))))
          (ty (bytesGet bs (+ idxAt i)))]
      (if (>= ty typecnt)
        (err (str "TZif transition " (stringFromInt64 i) " names type " (stringFromInt64 ty) " of " (stringFromInt64 typecnt)))
        (tzifTransitions bs timesAt idxAt typesAt timeSize (+ i 1) n typecnt (cons (pair t (be32 bs (+ typesAt (* ty 6)))) acc)))))

fn asciiRun bs: Bytes i: Int64 n: Int64 acc: (List String) -> (Result String String)
  (if (>= i n)
    (ok (stringJoin (listReverse acc) ""))
    (let [(b (bytesGet bs i))]
      (if (or (< b 32) (> b 126))
        (err (str "TZif footer byte " (stringFromInt64 b) " is not printable ASCII"))
        (asciiRun bs (+ i 1) n (cons (asciiOf b) acc)))))

fn asciiOf b: Int64 -> String
  (optionOr (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- b 32) (- b 31)) "")

fn newlineAfter bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (newlineAfter bs (+ i 1) n))

fn tzifFooter bs: Bytes from: Int64 -> (Result String String)
  (let [(n (bytesLength bs))]
    (if (or (>= from n) (not (= (bytesGet bs from) 10)))
      (err "TZif v2+ footer missing")
      (let [(j (newlineAfter bs (+ from 1) n))]
        (if (>= j n) (err "TZif footer unterminated") (asciiRun bs (+ from 1) j (list))))))

fn nth xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn zoneFromTzif bs: Bytes -> (Result Zone String)
  (let [(n (bytesLength bs))]
    (if (or (< n 44) (not (= (bytesGet bs 0) 84)) (not (= (bytesGet bs 1) 90)) (not (= (bytesGet bs 2) 105)) (not (= (bytesGet bs 3) 102)))
      (err "not a TZif file")
      (let [(version (bytesGet bs 4))
            (c1 (tzifCounts bs 0))
            (v1End (+ 44 (tzifDataSize c1 4)))]
        (if (> v1End n)
          (err "TZif v1 block truncated")
          (if (= version 0)
            (tzifBlock bs 44 c1 4 n)
            (if (> (+ v1End 44) n)
              (err "TZif v2 header truncated")
              (let [(c2 (tzifCounts bs v1End))]
                (tzifBlock bs (+ v1End 44) c2 8 n))))))))

fn tzifBlock bs: Bytes at: Int64 counts: (List Int64) timeSize: Int64 n: Int64 -> (Result Zone String)
  (let [(leap (nth counts 2)) (timecnt (nth counts 3)) (typecnt (nth counts 4))
        (end (+ at (tzifDataSize counts timeSize)))
        (idxAt (+ at (* timecnt timeSize)))
        (typesAt (+ idxAt timecnt))]
    (cond
      ((> end n) (err "TZif data block truncated"))
      ((< typecnt 1) (err "TZif file has no local time types"))
      ((> leap 0) (err "TZif leap-second tables are not supported"))
      (else
        (mt (tzifTransitions bs at idxAt typesAt timeSize 0 timecnt typecnt (list))
          ((err e) (err e))
          ((ok trans)
            (mt (if (= timeSize 8) (tzifFooter bs end) (ok ""))
              ((err e) (err e))
              ((ok footer)
                (if (stringEmpty? footer)
                  (ok (Zone :transitions trans :firstOff (be32 bs typesAt) :rule (none)))
                  (mt (posixParse footer)
                    ((err e) (err (str "TZif footer: " e)))
                    ((ok r) (ok (Zone :transitions trans :firstOff (be32 bs typesAt) :rule (some r)))))))))))))

fn zoneFromPosix s: String -> (Result Zone String)
  (mt (posixParse s)
    ((err e) (err e))
    ((ok r) (ok (Zone :transitions (list) :firstOff r.stdOff :rule (some r)))))

fn zoneFile! path: String -> (Result Zone String)
  (mt (fileReadBytes path)
    ((err e) (err e))
    ((ok bs) (zoneFromTzif bs)))

fn zoneLoad! tz: (Option String) -> (Result Zone String)
  (mt tz
    ((none) (zoneOrUtc! "/etc/localtime" ""))
    ((some s)
      (cond
        ((stringEmpty? s) (ok (utcZone)))
        ((stringStartsWith? s ":")
          (let [(name (optionOr (stringSlice s 1 (stringLength s)) ""))]
            (zoneOrUtc! (if (stringStartsWith? name "/") name (str "/usr/share/zoneinfo/" name)) "")))
        (else (zoneOrUtc! (if (stringStartsWith? s "/") s (str "/usr/share/zoneinfo/" s)) s)))))

fn zoneOrUtc! path: String posix: String -> (Result Zone String)
  (let [(fromFile (mt (fileStat path) ((ok st) (if st.isFile (zoneFile! path) (err "not a file"))) ((err e) (err e))))]
    (mt fromFile
      ((ok z) (ok z))
      ((err _)
        (if (stringEmpty? posix)
          (ok (utcZone))
          (mt (zoneFromPosix posix) ((ok z) (ok z)) ((err _) (ok (utcZone))))))))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn isAlpha? c: String -> Bool
  (and (= (stringLength c) 1) (let [(k (charCode c))] (or (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)))))

fn isDigit? c: String -> Bool
  (and (= (stringLength c) 1) (let [(k (charCode c))] (and (>= k 48) (<= k 57))))

fn scanWhile s: String i: Int64 pred: (fn [String] -> Bool) -> Int64
  (if (and (< i (stringLength s)) (pred (charAt s i))) (scanWhile s (+ i 1) pred) i)

fn quotedNameChar? c: String -> Bool
  (and (not (= c ">")) (not (stringEmpty? c)))

fn posixName s: String i: Int64 -> (Result Int64 String)
  (if (= (charAt s i) "<")
    (let [(j (scanWhile s (+ i 1) quotedNameChar?))]
      (if (and (= (charAt s j) ">") (>= (- (- j i) 1) 3)) (ok (+ j 1)) (err (str "bad quoted zone name at " (stringFromInt64 i)))))
    (let [(j (scanWhile s i isAlpha?))]
      (if (>= (- j i) 3) (ok j) (err (str "zone name shorter than 3 letters at " (stringFromInt64 i))))))

fn posixNumber s: String i: Int64 -> (Result (Pair Int64 Int64) String)
  (let [(j (scanWhile s i isDigit?))]
    (if (= j i)
      (err (str "digits expected at " (stringFromInt64 i)))
      (mt (stringToInt64 (optionOr (stringSlice s i j) ""))
        ((some v) (ok (pair v j)))
        ((none) (err (str "number out of range at " (stringFromInt64 i)))))))

fn posixClockPart s: String i: Int64 acc: Int64 -> (Result (Pair Int64 Int64) String)
  (if (= (charAt s i) ":")
    (mt (posixNumber s (+ i 1))
      ((err e) (err e))
      ((ok p) (if (> (pairFirst p) 59) (err (str "minutes or seconds above 59 at " (stringFromInt64 i))) (ok (pair (+ (* acc 60) (pairFirst p)) (pairSecond p))))))
    (ok (pair acc i)))

fn posixClock s: String i: Int64 maxHours: Int64 -> (Result (Pair Int64 Int64) String)
  (let [(sign (charAt s i))
        (neg (= sign "-"))
        (at (if (or neg (= sign "+")) (+ i 1) i))]
    (mt (posixNumber s at)
      ((err e) (err e))
      ((ok hp)
        (if (> (pairFirst hp) maxHours)
          (err (str "hours above " (stringFromInt64 maxHours) " at " (stringFromInt64 at)))
          (mt (posixClockPart s (pairSecond hp) (pairFirst hp))
            ((err e) (err e))
            ((ok mp)
              (mt (posixClockPart s (pairSecond mp) (pairFirst mp))
                ((err e) (err e))
                ((ok sp)
                  (let [(secs (if (= (pairSecond mp) (pairSecond hp)) (* (pairFirst hp) 3600) (if (= (pairSecond sp) (pairSecond mp)) (* (pairFirst mp) 60) (pairFirst sp))))]
                    (ok (pair (if neg (- 0 secs) secs) (pairSecond sp))))))))))))

fn posixDate s: String i: Int64 -> (Result (Pair RuleDate Int64) String)
  (cond
    ((= (charAt s i) "J")
      (mt (posixNumber s (+ i 1))
        ((err e) (err e))
        ((ok p) (if (or (< (pairFirst p) 1) (> (pairFirst p) 365)) (err "Jn day outside 1..365") (ok (pair (julianNoLeap (pairFirst p)) (pairSecond p)))))))
    ((= (charAt s i) "M")
      (mt (posixNumber s (+ i 1))
        ((err e) (err e))
        ((ok mp)
          (if (not (= (charAt s (pairSecond mp)) "."))
            (err "Mm.w.d expects . after the month")
            (mt (posixNumber s (+ (pairSecond mp) 1))
              ((err e) (err e))
              ((ok wp)
                (if (not (= (charAt s (pairSecond wp)) "."))
                  (err "Mm.w.d expects . after the week")
                  (mt (posixNumber s (+ (pairSecond wp) 1))
                    ((err e) (err e))
                    ((ok dp)
                      (if (or (< (pairFirst mp) 1) (> (pairFirst mp) 12) (< (pairFirst wp) 1) (> (pairFirst wp) 5) (> (pairFirst dp) 6))
                        (err "Mm.w.d field out of range")
                        (ok (pair (monthWeekDay (pairFirst mp) (pairFirst wp) (pairFirst dp)) (pairSecond dp)))))))))))))
    (else
      (mt (posixNumber s i)
        ((err e) (err e))
        ((ok p) (if (> (pairFirst p) 365) (err "n day outside 0..365") (ok (pair (julianZero (pairFirst p)) (pairSecond p))))))))

fn posixDateTime s: String i: Int64 -> (Result (List Int64) String)
  (mt (posixDate s i)
    ((err e) (err e))
    ((ok dp)
      (if (= (charAt s (pairSecond dp)) "/")
        (mt (posixClock s (+ (pairSecond dp) 1) 167)
          ((err e) (err e))
          ((ok tp) (ok (list (pairSecond tp) (pairFirst tp)))))
        (ok (list (pairSecond dp) 7200)))))

fn posixDateAt s: String i: Int64 -> RuleDate
  (mt (posixDate s i) ((ok dp) (pairFirst dp)) ((err _) (julianZero 0)))

fn posixRules s: String i: Int64 stdOff: Int64 dstOff: Int64 -> (Result PosixRule String)
  (if (not (= (charAt s i) ","))
    (err (str "rule expects , at " (stringFromInt64 i)))
    (mt (posixDateTime s (+ i 1))
      ((err e) (err e))
      ((ok st)
        (let [(afterStart (nth st 0))]
          (if (not (= (charAt s afterStart) ","))
            (err (str "rule expects , before the end date at " (stringFromInt64 afterStart)))
            (mt (posixDateTime s (+ afterStart 1))
              ((err e) (err e))
              ((ok en)
                (if (not (= (nth en 0) (stringLength s)))
                  (err (str "trailing text at " (stringFromInt64 (nth en 0))))
                  (ok (PosixRule :stdOff stdOff
                        :dst (some (DstRule :dstOff dstOff :start (posixDateAt s (+ i 1)) :startTime (nth st 1)
                                            :end (posixDateAt s (+ afterStart 1)) :endTime (nth en 1)))))))))))))

fn posixParse s: String -> (Result PosixRule String)
  (mt (posixName s 0)
    ((err e) (err e))
    ((ok i)
      (mt (posixClock s i 24)
        ((err e) (err e))
        ((ok op)
          (let [(stdOff (- 0 (pairFirst op))) (j (pairSecond op))]
            (if (= j (stringLength s))
              (ok (PosixRule :stdOff stdOff :dst (none)))
              (mt (posixName s j)
                ((err e) (err e))
                ((ok k)
                  (let [(c (charAt s k))
                        (hasOff (or (isDigit? c) (= c "+") (= c "-")))]
                    (if hasOff
                      (mt (posixClock s k 24)
                        ((err e) (err e))
                        ((ok dp) (posixDstTail s (pairSecond dp) stdOff (- 0 (pairFirst dp)))))
                      (posixDstTail s k stdOff (+ stdOff 3600))))))))))))

fn posixDstTail s: String i: Int64 stdOff: Int64 dstOff: Int64 -> (Result PosixRule String)
  (if (= i (stringLength s))
    (posixRules ",M3.2.0,M11.1.0" 0 stdOff dstOff)
    (posixRules s i stdOff dstOff))

fn ruleDays y: Int64 rd: RuleDate -> Int64
  (let [(jan1 (daysFromCivil y 1 1))]
    (mt rd
      ((julianNoLeap n) (+ jan1 (- n 1) (if (and (leapYear? y) (>= n 60)) 1 0)))
      ((julianZero n) (+ jan1 n))
      ((monthWeekDay m w d)
        (let [(first (daysFromCivil y m 1))
              (wd1 (mod (+ first 4) 7))
              (day1 (+ 1 (mod (- d wd1) 7)))
              (dayW (+ day1 (* 7 (- w 1))))
              (dayOk (if (> dayW (monthLength y m)) (- dayW 7) dayW))]
          (+ first (- dayOk 1))))))

fn yearOf t: Int64 -> Int64
  (nth (civilFromDays (/ t 86400)) 0)

fn ruleOffset r: PosixRule t: Int64 -> Int64
  (mt r.dst
    ((none) r.stdOff)
    ((some d)
      (let [(y (yearOf (+ t r.stdOff)))
            (startUtc (- (+ (* (ruleDays y d.start) 86400) d.startTime) r.stdOff))
            (endUtc (- (+ (* (ruleDays y d.end) 86400) d.endTime) d.dstOff))
            (inDst (if (< startUtc endUtc)
                     (and (<= startUtc t) (< t endUtc))
                     (not (and (<= endUtc t) (< t startUtc)))))]
        (if inDst d.dstOff r.stdOff))))

fn lastAtOrBefore trans: (List (Pair Int64 Int64)) t: Int64 cur: Int64 -> Int64
  (if (listEmpty? trans)
    cur
    (let [(p (preludeHead trans))]
      (if (> (pairFirst p) t) cur (lastAtOrBefore (preludeTail trans) t (pairSecond p)))))

fn lastTransitionTime trans: (List (Pair Int64 Int64)) -> Int64
  (pairFirst (preludeHead (listReverse trans)))

fn localOffset z: Zone t: Int64 -> Int64
  (let [(trans z.transitions)]
    (cond
      ((and (listEmpty? trans) (some? z.rule)) (ruleOffset (optionOr z.rule (PosixRule :stdOff 0 :dst (none))) t))
      ((listEmpty? trans) z.firstOff)
      ((< t (pairFirst (preludeHead trans))) z.firstOff)
      ((and (>= t (lastTransitionTime trans)) (some? z.rule)) (ruleOffset (optionOr z.rule (PosixRule :stdOff 0 :dst (none))) t))
      (else (lastAtOrBefore trans t z.firstOff))))

fn pad2 n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

fn civilText t: Int64 withSeconds: Bool dateSep: String mid: String timeSep: String -> String
  (let [(days (/ t 86400))
        (secs (- t (* days 86400)))
        (ymd (civilFromDays days))
        (hh (/ secs 3600))
        (mm (/ (mod secs 3600) 60))
        (ss (mod secs 60))
        (base (str (stringFromInt64 (nth ymd 0)) dateSep (pad2 (nth ymd 1)) dateSep (pad2 (nth ymd 2)) mid (pad2 hh) timeSep (pad2 mm)))]
    (if withSeconds (str base (if (stringEmpty? timeSep) "." ":") (pad2 ss)) base))

fn formatLocal z: Zone t: Int64 withSeconds: Bool -> String
  (civilText (+ t (localOffset z t)) withSeconds "-" " " ":")

fn formatUtcTouch t: Int64 -> String
  (civilText t true "" "" "")
