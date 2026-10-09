(module aslHarness/tests/caseProofKit
  :x [Laid Violation layCase! runIn! outputLines gateLine? countPrefixed sourceLines sourceChars sourceModules removeLaid! scoresImplement? intAfter failingIds applyEdit solutionProof!]
  :i [(asl-forms/gate :a gate) (aslHarness/eval :a ev)])

(schema Violation
  (:f name String)
  (:f files (List String))
  (:f old String)
  (:f new String))

(schema Laid
  (:f top String)
  (:f repo String)
  (:f hidden String))

fn scored receipt: String truth: String caseId: String model: String wall: Float64 date: String -> ev/EvalRun
  (mt (ev/scoreCase receipt truth caseId model wall date)
    ((ok run) run)
    ((err e) (do (assert false e) (scored receipt truth caseId model wall "0000-00-00"))))

fn ! step r: (Result Unit String) what: String -> (Result Unit String)
  (mt r ((ok _) (ok ())) ((err e) (err (str what ": " e))))

fn ! cp! from: String into: String -> (Result Unit String)
  (let [(r (gate/runArgv! (list "cp" "-R" from into) (none) (none) 120000 0))]
    (if (= r.code 0) (ok ()) (err (str "cp -R " from ": " r.errText))))

fn ! layCase! caseDir: String tag: String -> (Result Laid String)
  (let [(made (gate/runArgv! (list "mktemp" "-d" (str "/tmp/aslCaseProof" tag ".XXXXXX")) (none) (none) 10000 0))
        (top (stringTrim made.out))
        (repo (str top "/repo"))
        (hasHidden (resultOr (mt (fileStat (str caseDir "/hidden")) ((ok st) (ok st.isDir)) ((err e) (err e))) false))
        (hidden (if hasHidden (str top "/hidden") ""))]
    (if (!= made.code 0)
      (err (str "mktemp: " made.errText))
      (mt (step (dirCreate repo) "mkdir repo")
        ((err e) (err e))
        ((ok _)
          (mt (cp! (str caseDir "/.") (str repo "/"))
            ((err e) (err e))
            ((ok _)
              (mt (step (pathRemove (str repo "/truth.asn")) "rm truth.asn")
                ((err e) (err e))
                ((ok _)
                  (if hasHidden
                    (mt (step (pathRemove (str repo "/hidden")) "rm hidden")
                      ((err e) (err e))
                      ((ok _) (mt (step (dirCreate hidden) "mkdir hidden")
                                ((err e) (err e))
                                ((ok _) (mt (cp! (str caseDir "/hidden/.") (str hidden "/"))
                                          ((err e) (err e))
                                          ((ok _) (ok (Laid :top top :repo repo :hidden hidden))))))))
                    (ok (Laid :top top :repo repo :hidden hidden)))))))))))

fn ! removeLaid! l: Laid -> Bool
  (ok? (pathRemove l.top))

fn ! runIn! argv: (List String) cwd: String extra: (List String) -> (Pair Int64 String)
  (let [(names (map (fn [(e String)] -> String (optionOr (listHead (stringSplit e "=")) e)) extra))
        (env (listAppend (filter (fn [(e String)] -> Bool (not (listContains? names (optionOr (listHead (stringSplit e "=")) e)))) (envList)) extra))
        (r (gate/runArgv! argv (some cwd) (some env) 600000 2000))]
    (pair r.code (str r.out r.errText)))

fn outputLines out: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit out "\n"))

fn gateLine? name: String line: String -> Bool
  (let [(head (str "(:gate :name \"" name "\" :asserts "))]
    (and (stringStartsWith? line head) (and (stringEndsWith? line ")") (stringContains? line " :failed "))))

fn countPrefixed lines: (List String) prefix: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l prefix)) lines))

fn ! pyFiles! dir: String -> (List String)
  (map (fn [(n String)] -> String (str dir "/" n))
       (filter (fn [(n String)] -> Bool (stringEndsWith? n ".py")) (listSort (resultOr (dirList dir) (list)))))

fn ! sourceModules dir: String -> Int64
  (listLength (pyFiles! dir))

fn ! sourceLines dir: String -> Int64
  (fold (fn [(n Int64) (p String)] -> Int64 (+ n (- (listLength (stringSplit (resultOr (fileReadString p) "") "\n")) 1))) 0 (pyFiles! dir))

fn ! sourceChars dir: String -> Int64
  (fold (fn [(n Int64) (p String)] -> Int64 (+ n (bytesLength (stringToBytes (resultOr (fileReadString p) ""))))) 0 (pyFiles! dir))

fn scoresImplement? truthText: String cmd: String -> Bool
  (let [(t (ev/parseTruth truthText))
        (green (str "(:agentReceipt :status :ok :mode :implement :turns 9 :gates ((:gate :cmd \"" cmd "\" :exit 0)))"))
        (red (stringReplace green ":exit 0" ":exit 1"))]
    (and (= t.mode "implement")
         (and (= (map (fn [(g ev/ExpectedGate)] -> String g.cmd) t.gates) (list cmd))
              (and (= (scored green truthText "proof" "test" 1.0 "2026-09-30").status "ok")
                   (= (scored red truthText "proof" "test" 1.0 "2026-09-30").status "failed")))))

fn digitsFrom s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (stringContains? "0123456789" (optionOr (stringSlice s i (+ i 1)) "x"))) (digitsFrom s (+ i 1) n) i)

fn intAfter text: String key: String -> (Option Int64)
  (mt (stringIndexOf text key)
    ((none) (none))
    ((some i) (let [(start (+ i (stringLength key)))]
                (stringToInt64 (optionOr (stringSlice text start (digitsFrom text start (stringLength text))) "")))))

fn failingIds lines: (List String) -> (List String)
  (map (fn [(l String)] -> String
         (let [(rest (optionOr (stringSlice l 5 (stringLength l)) ""))]
           (mt (stringIndexOf rest ":") ((some i) (optionOr (stringSlice rest 0 i) rest)) ((none) rest))))
       (filter (fn [(l String)] -> Bool (stringStartsWith? l "FAIL ")) lines))

fn applyEdit text: String old: String new: String -> (Option String)
  (cond
    ((= old "APPEND") (some (str text new)))
    ((stringContains? text old) (some (stringReplace text old new)))
    (else (none)))

fn ! violate! dir: String v: Violation -> Int64
  (fold (fn [(n Int64) (rel String)] -> Int64
          (mt (fileReadString (str dir "/" rel))
            ((err _) n)
            ((ok text) (mt (applyEdit text v.old v.new)
                         ((none) n)
                         ((some edited) (if (ok? (fileWrite (str dir "/" rel) edited)) (+ n 1) n))))))
        0 v.files)

fn ! report! name: String passed: Bool detail: String -> (Pair String Bool)
  (do (println (if passed (str "ok " name) (str "FAIL " name ": " detail))) (pair name passed))

fn ! solutionProof! l: Laid caseDir: String solution: String solved: (List String) gateName: String argv: (List String) extra: (List String) rows: (List Violation) -> (List (Pair String Bool))
  (let [(sol (str l.top "/solution"))
        (laidSol (and (ok? (dirCreate sol)) (ok? (cp! (str caseDir "/.") (str sol "/")))))
        (cleared (and laidSol (and (ok? (pathRemove (str sol "/truth.asn"))) (if (fileExists? (str sol "/hidden")) (ok? (pathRemove (str sol "/hidden"))) true))))
        (copied (and cleared (listAll? (fn [(rel String)] -> Bool (ok? (cp! (str solution "/" rel) (str sol "/" rel)))) solved)))
        (whole (runIn! argv sol extra))
        (passes (and (= (pairFirst whole) 0) (listContains? (outputLines (pairSecond whole)) (str "(:gate :name \"" gateName "\" :asserts 17 :failed 0)"))))]
    (listAppend
      (list (report! "solutionCopied" copied (str solution " lacks a solved file"))
            (report! "solutionPasses" passes (str "exit " (stringFromInt64 (pairFirst whole)) "; " (stringJoin (filter (fn [(x String)] -> Bool (stringStartsWith? x "FAIL")) (outputLines (pairSecond whole))) " "))))
      (map (fn [(v Violation)] -> (Pair String Bool)
             (let [(dir (str l.top "/v_" v.name))
                   (made (cp! sol dir))
                   (applied (if (ok? made) (violate! dir v) 0))]
               (if (< applied 1)
                 (report! (str "violates_" v.name) false "anchor not found in the solution")
                 (let [(r (runIn! argv dir extra))
                       (fails (failingIds (outputLines (pairSecond r))))]
                   (report! (str "violates_" v.name) (and (!= (pairFirst r) 0) (= fails (list v.name)))
                            (str "exit " (stringFromInt64 (pairFirst r)) ", failing: " (stringJoin fails " ")))))))
           rows)))
