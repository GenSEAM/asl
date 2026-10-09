(module asl-gates/suiteTimes
  :x [SuiteTime timesPath! parseTimes renderTimes readTimes! writeTimes! mergeTimes startOrder]
  :i [])

(schema SuiteTime
  (:f suite String)
  (:f ms Int64))

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

fn renderRow t: SuiteTime -> String
  (str (rowPrefix) (escSuite t.suite) "\" :ms " (stringFromInt64 t.ms) ")\n")

fn renderTimes times: (Map String Int64) -> String
  (stringJoin (map (fn [(k String)] -> String (renderRow (SuiteTime :suite k :ms (optionOr (mapGet times k) 0)))) (listSort (mapKeys times))) "")

fn allDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789" c)) (stringChars s)))

fn quotedLoop chars: (List String) acc: (List String) -> (Option (Pair String (List String)))
  (mt (listHead chars)
    ((none) (none))
    ((some c)
     (let [(rest (optionOr (listTail chars) (list)))]
       (cond
         ((= c "\"") (some (pair (stringJoin (listReverse acc) "") rest)))
         ((= c "\\")
          (mt (listHead rest)
            ((some n) (if (or (= n "\\") (= n "\"")) (quotedLoop (optionOr (listTail rest) (list)) (cons n acc)) (none)))
            ((none) (none))))
         ((= c "\n") (none))
         (else (quotedLoop rest (cons c acc)))))))

fn parseRow line: String -> (Result SuiteTime String)
  (if (not (stringStartsWith? line (rowPrefix)))
    (err "not a (:suiteTime :suite \"S\" :ms N) row")
    (mt (quotedLoop (stringChars (optionOr (stringSlice line (stringLength (rowPrefix)) (stringLength line)) "")) (list))
      ((none) (err "unterminated or badly escaped :suite string"))
      ((some p)
       (let [(suite (pairFirst p))
             (tail (stringJoin (pairSecond p) ""))
             (digits (if (and (stringStartsWith? tail " :ms ") (stringEndsWith? tail ")"))
                       (optionOr (stringSlice tail 5 (- (stringLength tail) 1)) "")
                       ""))]
         (cond
           ((stringEmpty? suite) (err "empty :suite"))
           ((not (allDigits? digits)) (err "expected :ms <digits>) after :suite"))
           (else
            (mt (stringToInt64 digits)
              ((none) (err (str ":ms " digits " is not an Int64")))
              ((some ms) (ok (SuiteTime :suite suite :ms ms))))))))))

fn parseLoop lines: (List String) n: Int64 acc: (Map String Int64) -> (Result (Map String Int64) String)
  (mt (listHead lines)
    ((none) (ok acc))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))]
       (if (stringEmpty? line)
         (parseLoop rest (+ n 1) acc)
         (mt (parseRow line)
           ((err e) (err (str "line " (stringFromInt64 n) ": " e)))
           ((ok t)
            (if (mapHas? acc t.suite)
              (err (str "line " (stringFromInt64 n) ": duplicate :suite \"" t.suite "\""))
              (parseLoop rest (+ n 1) (mapSet acc t.suite t.ms)))))))))

fn parseTimes text: String -> (Result (Map String Int64) String)
  (parseLoop (stringSplit text "\n") 1 (mapEmpty))

fn ! readTimes! path: String -> (Result (Map String Int64) String)
  (if (not (fileExists? path))
    (ok (mapEmpty))
    (mt (fileReadString path)
      ((err e) (err (str "gateTimes " path ": " e)))
      ((ok text) (mt (parseTimes text) ((ok m) (ok m)) ((err e) (err (str "gateTimes " path ": " e)))))))

fn mergeTimes old: (Map String Int64) rows: (List SuiteTime) -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (t SuiteTime)] -> (Map String Int64) (mapSet acc t.suite t.ms)) old rows)

fn parentDir p: String -> String
  (let [(parts (stringSplit p "/"))
        (n (listLength parts))]
    (cond
      ((<= n 1) ".")
      ((and (= n 2) (stringStartsWith? p "/")) "/")
      (else (stringJoin (listTake parts (- n 1)) "/"))))

fn ! writeTimes! path: String rows: (List SuiteTime) -> (Result Unit String)
  (mt (readTimes! path)
    ((err e) (err e))
    ((ok old)
     (let [(tmp (str path ".tmp." (stringFromInt64 (procSelf))))]
       (mt (dirCreate (parentDir path))
         ((err e) (err (str "gateTimes " (parentDir path) ": " e)))
         ((ok _)
          (mt (fileWrite tmp (renderTimes (mergeTimes old rows)))
            ((err e) (err (str "gateTimes " tmp ": " e)))
            ((ok _)
             (mt (pathRename tmp path)
               ((ok _) (ok ()))
               ((err e) (do (pathRemove tmp) (err (str "gateTimes rename " tmp ": " e))))))))))))

fn padLeft s: String width: Int64 -> String
  (if (>= (stringLength s) width) s (padLeft (str "0" s) width))

fn padMs ms: Int64 -> String
  (padLeft (stringFromInt64 ms) 19)

fn startKey times: (Map String Int64) name: String -> String
  (mt (mapGet times name)
    ((none) (str "0 " name))
    ((some ms) (str "1 " (padMs (- 9223372036854775807 (max 0 ms))) " " name)))

fn startOrder suites: (List String) times: (Map String Int64) -> (List Int64)
  (map (fn [(p (Pair Int64 String))] -> Int64 (pairFirst p))
       (listSortBy (fn [(p (Pair Int64 String))] -> String (startKey times (pairSecond p))) (enumerate suites)))
