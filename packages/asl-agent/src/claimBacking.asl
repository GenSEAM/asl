(module aslAgent/claimBacking
  :x [executedAsserts claimedCounts suiteTokens claimSentences unbackedGateClaims]
  :i [(aslAgent/gates :a g)])

; (:m :ref LEON-CAPS :do "a sentence of the final reply that names a gate (a *Test suite token or a declared gate command) or a count of assertions, and says it ran or passed, is backed only by the latest run of a named gate this session whose stdout executed exactly that many assertions; no named gate run, or no run with that count, makes it unbacked")
fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn charAt s: String i: Int64 -> String
  (cut s i (+ i 1))

fn isDigitChar ch: String -> Bool
  (and (>= ch "0") (<= ch "9"))

fn trailingStart seg: String i: Int64 -> Int64
  (if (and (> i 0) (isDigitChar (charAt seg (- i 1)))) (trailingStart seg (- i 1)) i)

fn trailingInt seg: String -> (Option Int64)
  (let [n (stringLength seg)
        st (trailingStart seg n)]
    (if (< st n) (stringToInt64 (cut seg st n)) none))

fn leadingEnd seg: String i: Int64 -> Int64
  (if (and (< i (stringLength seg)) (isDigitChar (charAt seg i))) (leadingEnd seg (+ i 1)) i)

fn leadingInt seg: String -> (Option Int64)
  (let [e (leadingEnd seg 0)]
    (if (> e 0) (stringToInt64 (cut seg 0 e)) none))

fn somes xs: (List (Option Int64)) -> (List Int64)
  (fold (fn [acc x] (match x ((some n) (listAppend acc (list n))) ((none) acc))) (list) xs)

fn dropLast xs: (List String) -> (List String)
  (listTake xs (max 0 (- (listLength xs) 1)))

; (:m :ref LEON-CAPS :do "the assertions a gate stdout says it executed: every N assertion(s) executed summed, else every :asserts N summed, else none")
fn executedAsserts stdout: String -> (Option Int64)
  (let [runner (somes (map trailingInt (dropLast (stringSplit stdout " assertion(s) executed"))))
        anchored (somes (map leadingInt (listDrop (stringSplit stdout ":asserts ") 1)))]
    (cond
      ((not (listEmpty? runner)) (some (listSum runner)))
      ((not (listEmpty? anchored)) (some (listSum anchored)))
      (else none)))

; (:m :ref LEON-CAPS :do "the counts a sentence attaches to assertions: N assertion, N asserts, :asserts N")
fn claimedCounts sentence: String -> (List Int64)
  (listAppend
    (somes (map trailingInt (dropLast (stringSplit sentence " assert"))))
    (somes (map leadingInt (listDrop (stringSplit sentence ":asserts ") 1))))

fn spaced sentence: String -> String
  (fold (fn [acc p] (stringReplace acc p " ")) sentence
    (list "`" "," ";" "(" ")" "\"" "'" ":" "*" "[" "]" "{" "}"))

fn baseName token: String -> String
  (let [t0 (if (stringEndsWith? token ".") (cut token 0 (- (stringLength token) 1)) token)
        t1 (if (stringEndsWith? t0 ".asl") (cut t0 0 (- (stringLength t0) 4)) t0)]
    (match (listLast (stringSplit t1 "/")) ((some b) b) ((none) t1)))

; (:m :ref LEON-CAPS :do "the Test-suffixed suite names a sentence mentions, path and .asl suffix removed")
fn suiteTokens sentence: String -> (List String)
  (filter (fn [b] (and (> (stringLength b) 4) (stringEndsWith? b "Test")))
    (map baseName (filter (fn [t] (not (stringEmpty? t))) (stringSplit (spaced sentence) " "))))

fn resultWords -> (List String)
  (list "executed" "passed" "passes" "pass" "green" "succeed" "ran " "verified" "exit 0")

fn saysResult sentence: String -> Bool
  (let [low (stringLower sentence)]
    (listAny? (fn [w] (stringContains? low w)) (resultWords)))

fn latestRuns runs: (List g/GateResult) -> (List g/GateResult)
  (fold (fn [acc r] (listAppend (filter (fn [x] (!= (g/gateCmd x) (g/gateCmd r))) acc) (list r))) (list) runs)

fn declaredNamed sentence: String declared: (List String) -> (List String)
  (filter (fn [d] (and (>= (stringLength d) 6) (stringContains? sentence d))) declared)

fn suiteRuns suite: String runs: (List g/GateResult) -> (List g/GateResult)
  (filter (fn [r] (stringContains? (g/gateCmd r) suite)) runs)

fn declaredRuns cmd: String runs: (List g/GateResult) -> (List g/GateResult)
  (filter (fn [r] (= (g/gateCmd r) cmd)) runs)

fn countBacked n: Int64 runs: (List g/GateResult) -> Bool
  (listAny? (fn [r] (= (executedAsserts (g/gateStdout r)) (some n))) runs)

; (:m :ref LEON-CAPS :do "true when the sentence is a gate or count claim with nothing in this session runs behind it")
fn sentenceUnbacked sentence: String declared: (List String) runs: (List g/GateResult) -> Bool
  (let [suites (suiteTokens sentence)
        cmds (declaredNamed sentence declared)
        counts (claimedCounts sentence)
        isClaim (and (saysResult sentence) (or (not (listEmpty? suites)) (or (not (listEmpty? cmds)) (not (listEmpty? counts)))))
        namedRuns (listAppend
                    (fold (fn [acc s] (listAppend acc (suiteRuns s runs))) (list) suites)
                    (fold (fn [acc d] (listAppend acc (declaredRuns d runs))) (list) cmds))
        candidates (if (and (listEmpty? suites) (listEmpty? cmds)) runs namedRuns)
        namesOk (and (listAll? (fn [s] (not (listEmpty? (suiteRuns s runs)))) suites)
                     (listAll? (fn [d] (not (listEmpty? (declaredRuns d runs)))) cmds))
        countsOk (listAll? (fn [n] (countBacked n candidates)) counts)]
    (and isClaim (not (and namesOk countsOk))))

fn claimSentences reply: String -> (List String)
  (filter (fn [s] (not (stringEmpty? s)))
    (map stringTrim
      (fold (fn [acc line] (listAppend acc (stringSplit line ". "))) (list) (stringSplit reply "\n"))))

; (:m :ref LEON-CAPS :do "the final reply's unbacked gate or count claims, each cut to 120 chars, against the latest run of every gate of the session, counted only when it exited 0, and the declared gate commands")
fn unbackedGateClaims reply: String declared: (List String) runs: (List g/GateResult) -> (List String)
  (let [green (filter (fn [r] (= (g/gateExit r) 0)) (latestRuns runs))]
    (map (fn [s] (cut s 0 (min 120 (stringLength s))))
      (filter (fn [s] (sentenceUnbacked s declared green)) (claimSentences reply))))
