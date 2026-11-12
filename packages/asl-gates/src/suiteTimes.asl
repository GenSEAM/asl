(module asl-gates/suiteTimes
  :x [SuiteTime timesPath! parseTimes renderTimes readTimes! writeTimes! writeTimesIn! mergeTimes startOrder]
  :i [])

(schema SuiteTime
  (:f suite String)
  (:f ms Int64)
  (:f samples (List Int64) :default (list)))

fn rowPrefix -> String
  "(:suiteTime :suite \""

fn ! timesPath! -> (Result String String)
  (let [(override (optionOr (envGet "ASL_GATE_TIMES") ""))
        (home (optionOr (envGet "HOME") ""))]
    (cond
      ((not (stringEmpty? override)) (ok override))
      ((not (stringEmpty? home)) (ok (str home "/.asl/run/gateTimes.asn")))
      (else (err "gateTimes: neither ASL_GATE_TIMES nor HOME is set"))))

fn escSuite s: String -> String
  (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"")

; (:m :ref GATETIMES-MEDIAN :do "a row keeps the last 5 measured times, newest last, and :ms is their lower median, written first so a reader of :ms alone (gates.asl gateParseRow) works; a row without samples renders as the single sample :ms")
fn samplesOf t: SuiteTime -> (List Int64)
  (if (listEmpty? t.samples) (list t.ms) t.samples)

fn renderRow t: SuiteTime -> String
  (str (rowPrefix) (escSuite t.suite) "\" :ms " (stringFromInt64 t.ms) " :samples (" (stringJoin (map stringFromInt64 (samplesOf t)) " ") "))\n")

fn renderTimes times: (Map String SuiteTime) -> String
  (stringJoin (map (fn [(k String)] -> String (match (mapGet times k) ((some t) (renderRow t)) ((none) ""))) (listSort (mapKeys times))) "")

fn allDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789" c)) (stringChars s)))

fn quotedLoop chars: (List String) acc: (List String) -> (Option (Pair String (List String)))
  (match (listHead chars)
    ((none) (none))
    ((some c)
     (let [(rest (optionOr (listTail chars) (list)))]
       (cond
         ((= c "\"") (some (pair (stringJoin (listReverse acc) "") rest)))
         ((= c "\\")
          (match (listHead rest)
            ((some n) (if (or (= n "\\") (= n "\"")) (quotedLoop (optionOr (listTail rest) (list)) (cons n acc)) (none)))
            ((none) (none))))
         ((= c "\n") (none))
         (else (quotedLoop rest (cons c acc)))))))

; (:m :ref GATETIMES-MEDIAN :do "the text after :samples, (a b c)) with the row's closing paren: the integers inside, none when it is not that shape or holds a non-integer")
fn parseSamples text: String -> (Option (List Int64))
  (if (and (stringStartsWith? text "(") (stringEndsWith? text "))"))
    (let [(toks (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (optionOr (stringSlice text 1 (- (stringLength text) 2)) "") " ")))
          (vals (map stringToInt64 toks))]
      (if (and (not (listEmpty? toks)) (listAll? (fn [(v (Option Int64))] -> Bool (some? v)) vals))
        (some (map (fn [(v (Option Int64))] -> Int64 (optionOr v 0)) vals))
        (none)))
    (none))

fn parseRow line: String -> (Result SuiteTime String)
  (if (not (stringStartsWith? line (rowPrefix)))
    (err "not a (:suiteTime :suite \"S\" :ms N) row")
    (match (quotedLoop (stringChars (optionOr (stringSlice line (stringLength (rowPrefix)) (stringLength line)) "")) (list))
      ((none) (err "unterminated or badly escaped :suite string"))
      ((some p)
       (let [(suite (pairFirst p))
             (tail (stringJoin (pairSecond p) ""))
             (rest (if (stringStartsWith? tail " :ms ") (optionOr (stringSlice tail 5 (stringLength tail)) "") ""))
             (parts (stringSplit rest " :samples "))
             (head (optionOr (listGet parts 0) ""))
             (old (= (listLength parts) 1))
             (digits (if (and old (stringEndsWith? head ")")) (optionOr (stringSlice head 0 (- (stringLength head) 1)) "") head))
             (sampleText (optionOr (listGet parts 1) ""))
             (samples (if old (some (list)) (parseSamples sampleText)))]
         (cond
           ((stringEmpty? suite) (err "empty :suite"))
           ((> (listLength parts) 2) (err "expected one :samples after :ms"))
           ((not (allDigits? digits)) (err "expected :ms <digits>) after :suite"))
           ((none? samples) (err "expected :samples (<digits> ...)) after :ms"))
           (else
            (match (stringToInt64 digits)
              ((none) (err (str ":ms " digits " is not an Int64")))
              ((some ms) (ok (SuiteTime :suite suite :ms ms :samples (optionOr samples (list))))))))))))

fn parseLoop lines: (List String) n: Int64 acc: (Map String SuiteTime) -> (Result (Map String SuiteTime) String)
  (match (listHead lines)
    ((none) (ok acc))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))]
       (if (stringEmpty? line)
         (parseLoop rest (+ n 1) acc)
         (match (parseRow line)
           ((err e) (err (str "line " (stringFromInt64 n) ": " e)))
           ((ok t)
            (if (mapHas? acc t.suite)
              (err (str "line " (stringFromInt64 n) ": duplicate :suite \"" t.suite "\""))
              (parseLoop rest (+ n 1) (mapSet acc t.suite t)))))))))

fn parseRows text: String -> (Result (Map String SuiteTime) String)
  (parseLoop (stringSplit text "\n") 1 (mapEmpty))

fn msOf rows: (Map String SuiteTime) -> (Map String Int64)
  (mapFromPairs (map (fn [(p (Pair String SuiteTime))] -> (Pair String Int64) (let [(t (pairSecond p))] (pair (pairFirst p) t.ms))) (mapPairs rows)))

fn parseTimes text: String -> (Result (Map String Int64) String)
  (match (parseRows text) ((err e) (err e)) ((ok r) (ok (msOf r))))

fn ! readRows! path: String -> (Result (Map String SuiteTime) String)
  (if (not (fileExists? path))
    (ok (mapEmpty))
    (match (fileReadString path)
      ((err e) (err (str "gateTimes " path ": " e)))
      ((ok text) (match (parseRows text) ((ok m) (ok m)) ((err e) (err (str "gateTimes " path ": " e)))))))

fn ! readTimes! path: String -> (Result (Map String Int64) String)
  (match (readRows! path) ((err e) (err e)) ((ok r) (ok (msOf r))))

; (:m :ref GATETIMES-MEDIAN :do "lowerMedian: the element at index (n-1)/2 of the sorted samples (the lower one for an even count); 0 for none")
fn lowerMedian xs: (List Int64) -> Int64
  (optionOr (listGet (listSortBy (fn [(x Int64)] -> Int64 x) xs) (/ (- (listLength xs) 1) 2)) 0)

fn lastN xs: (List Int64) n: Int64 -> (List Int64)
  (listDrop xs (max 0 (- (listLength xs) n)))

fn sampleCap -> Int64
  5

; (:m :ref GATETIMES-MEDIAN :do "mergeTimes appends each new measurement (its :ms) to the suite's old samples, keeps the last 5, and sets :ms to their lower median, so one run under load does not rank a suite; an old row without samples counts as one sample")
fn mergeTimes old: (Map String SuiteTime) rows: (List SuiteTime) -> (Map String SuiteTime)
  (fold (fn [(acc (Map String SuiteTime)) (t SuiteTime)] -> (Map String SuiteTime)
          (let [(prior (match (mapGet acc t.suite) ((some o) (samplesOf o)) ((none) (list))))
                (next (lastN (listAppend prior (list t.ms)) (sampleCap)))]
            (mapSet acc t.suite (SuiteTime :suite t.suite :ms (lowerMedian next) :samples next))))
        old rows)

fn parentDir p: String -> String
  (let [(parts (stringSplit p "/"))
        (n (listLength parts))]
    (cond
      ((<= n 1) ".")
      ((and (= n 2) (stringStartsWith? p "/")) "/")
      (else (stringJoin (listTake parts (- n 1)) "/"))))

; (:m :ref GATETIMES-STALE-ROWS-20261022 :do "writeTimesIn! writes the ledger like writeTimes! but drops every row whose suite file no longer exists under root, so a deleted suite stops ranking as known-heavy in startOrder; rows of suites the run did not select stay, they are only judged by whether their file exists")
fn ! writeWith! path: String rows: (List SuiteTime) keep: (fn [String] -> Bool) -> (Result Unit String)
  (match (readRows! path)
    ((err e) (err e))
    ((ok old)
     (let [(tmp (str path ".tmp." (stringFromInt64 (procSelf))))
           (merged (mapFromPairs (filter (fn [(p (Pair String SuiteTime))] -> Bool (keep (pairFirst p))) (mapPairs (mergeTimes old rows)))))]
       (match (dirCreate (parentDir path))
         ((err e) (err (str "gateTimes " (parentDir path) ": " e)))
         ((ok _)
          (match (fileWrite tmp (renderTimes merged))
            ((err e) (err (str "gateTimes " tmp ": " e)))
            ((ok _)
             (match (pathRename tmp path)
               ((ok _) (ok ()))
               ((err e) (do (pathRemove tmp) (err (str "gateTimes rename " tmp ": " e))))))))))))

fn ! writeTimes! path: String rows: (List SuiteTime) -> (Result Unit String)
  (writeWith! path rows (fn [(s String)] -> Bool true))

fn ! writeTimesIn! path: String rows: (List SuiteTime) root: String -> (Result Unit String)
  (writeWith! path rows (fn [(s String)] -> Bool (fileExists? (str root "/" s))))

fn padLeft s: String width: Int64 -> String
  (if (>= (stringLength s) width) s (padLeft (str "0" s) width))

fn padMs ms: Int64 -> String
  (padLeft (stringFromInt64 ms) 19)

fn startKey times: (Map String Int64) name: String -> String
  (match (mapGet times name)
    ((none) (str "0 " name))
    ((some ms) (str "1 " (padMs (- 9223372036854775807 (max 0 ms))) " " name)))

fn startOrder suites: (List String) times: (Map String Int64) -> (List Int64)
  (map (fn [(p (Pair Int64 String))] -> Int64 (pairFirst p))
       (listSortBy (fn [(p (Pair Int64 String))] -> String (startKey times (pairSecond p))) (enumerate suites)))
