(module asl-cli/tests/fixHintParseTest :x [runTests] :i [(asl/packages/asl-cli/src/verify :a verify) (asl-forms/kernel :a k) (asl-forms/gate :a g)])

; (:m :ref FIX-HINT-BY-ORDER :do "the (:fix ...) hint asl check prints must parse to the keys the fix op knows and run there: :by :indent followed by :apply true read :indent as a key and the op refused it with ERR_UNKNOWN_KEY")
fn ! tempRoot -> String
  (str (resultOr (realPath (optionOr (envGet "TMPDIR") "/tmp")) "/tmp") "/fixHintParseTest_" (stringFromInt64 (monotonicNs)))

fn unq s: String i: Int64 acc: String -> String
  (let [(ch (optionOr (stringSlice s i (+ i 1)) ""))]
    (cond
      ((= ch "") acc)
      ((= ch "\"") acc)
      ((= ch "\\") (unq s (+ i 2) (str acc (optionOr (stringSlice s (+ i 1) (+ i 2)) ""))))
      (else (unq s (+ i 1) (str acc ch)))))

fn hintOf r: String -> String
  (match (stringIndexOf r ":fix \"")
    ((none) "")
    ((some at) (unq r (+ at 6) "")))

fn keysOf p: k/ParsedStep -> (List String)
  (listSort (mapKeys p.kwargs))

; (:m :ref FIX-HINT-BY-ORDER :do "every (:fix ...) hint the tool catalogue, the fix op and the doc ledger print, read from those files: the set must equal the table below, so a new hint fails here until its keys are listed")
fn hintSources -> (List String)
  (list "asl/grammar/tools.asn" "asl/packages/asl-forms/src/gate.asl" "asl/packages/asl-cli/doc.asn")

fn printedHints text: String -> (List String)
  (filter (fn [(h String)] -> Bool (not (stringContains? h "<")))
    (map (fn [(p String)] -> String (stringReplace (str "(:fix " (optionOr (stringSlice p 0 (+ (optionOr (stringIndexOf p ")") (- (stringLength p) 1)) 1)) p)) "\\\"" "\""))
         (optionOr (listTail (stringSplit text "(:fix ")) (list))))

fn hintKeys -> (List (Pair String String))
  (list (pair "(:fix :file \"asl/grammar/rules.asn\")" "file")
        (pair "(:fix :file \"src/a.asl\" :by :indent :apply true)" "apply by file")
        (pair "(:fix :file F :by :indent :apply true)" "apply by file")
        (pair "(:fix :by :indent)" "by"))

fn dedup xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn ! testPrintedHints! -> Bool
  (let [(found (dedup (fold (fn [(acc (List String)) (f String)] -> (List String) (listAppend acc (printedHints (resultOr (fileReadString f) "")))) (list) (hintSources))))
        (table (hintKeys))]
    (do
      (assert (= (listSort found) (listSort (map (fn [(e (Pair String String))] -> String (pairFirst e)) table))) (str "the printed hints are exactly the tabled ones: " (stringJoin found " | ")))
      (assert (listAll? (fn [(e (Pair String String))] -> Bool (let [(p (k/parseStep (pairFirst e)))] (and (= p.op "fix") (= (stringJoin (keysOf p) " ") (pairSecond e))))) table) "each hint parses to the fix op with exactly its keys")
      (assert (listAll? (fn [(e (Pair String String))] -> Bool (let [(p (k/parseStep (pairFirst e)))] (match (mapGet p.kwargs "by") ((none) true) ((some v) (= (k/lstripColons v) "indent"))))) table) "every :by in a hint reads indent")
      true))

; (:m :ref FIX-HINT-BY-ORDER :do ":by followed by a key that has its own value stays a flag")
fn testByFlag -> Bool
  (let [(p (k/parseStep "(:op :by :apply true)"))]
    (do
      (assert (= (optionOr (mapGet p.kwargs "by") "") "true") (str ":by before :apply true is a flag: " (optionOr (mapGet p.kwargs "by") "")))
      (assert (= (optionOr (mapGet p.kwargs "apply") "") "true") ":apply keeps its value")
      true))

fn ! testCheckHint! -> Bool
  (let [(dir (tempRoot))
        (made (ok? (dirCreate dir)))
        (path (str dir "/stray.asl"))
        (wrote (ok? (fileWrite path "(module t/stray :x [f g] :i [])\n\nfn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n")))
        (hint (hintOf (verify/balanceReceipt! path)))
        (p (k/parseStep hint))
        (env (g/GateEnv :root dir :rootDir dir :binDir "" :host "" :staged (list)))
        (o (g/runGate! env (fn [(i Int64) (f String)] -> (Pair (List String) Int64) (pair (list) 0)) 1 p.op p.kwargs p.args))
        (line (stringJoin o.lines "\n"))
        (gp (k/parseStep "(:fix :file \"F\" :by :indent :apply true)"))
        (gone (ok? (pathRemove dir)))]
    (do
      (assert (and made wrote) "fixture written")
      (assert gone "the scratch directory is removed")
      (assert (stringStartsWith? hint "(:fix :file ") (str "check prints a fix hint: " hint))
      (assert (= p.op "fix") (str "the hint names the fix op: " p.op))
      (assert (= (keysOf p) (list "apply" "by" "file")) (str "the hint parses to exactly :file :by :apply: " (stringJoin (keysOf p) " ")))
      (assert (= (k/lstripColons (optionOr (mapGet p.kwargs "by") "")) "indent") (str ":by takes the keyword :indent as its value: " (optionOr (mapGet p.kwargs "by") "")))
      (assert (= (optionOr (mapGet p.kwargs "apply") "") "true") "the :apply true after it is kept")
      (assert (= o.errCount 0) (str "the fix op runs the hint: " line))
      (assert (stringContains? line ":by :indent") (str "as an indent repair: " line))
      (assert (stringContains? line ":balanced true") (str "whose edits balance the file: " line))
      (assert (some? o.stage) (str "and :apply true stages the result: " line))
      (assert (= (keysOf gp) (list "apply" "by" "file")) (str "the rejected-repair hint gate.asl prints parses the same: " (stringJoin (keysOf gp) " ")))
      true))

fn ! runTests -> Bool
  (and (testCheckHint!) (testPrintedHints!) (testByFlag))
