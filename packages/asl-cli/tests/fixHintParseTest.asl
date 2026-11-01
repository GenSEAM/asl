(module asl-cli/tests/fixHintParseTest :x [runTests] :i [(asl/packages/asl-cli/src/verify :a verify) (asl-forms/kernel :a k) (asl-forms/gate :a g)])

; (:m :ref FIX-HINT-BY-ORDER :do "the (:fix ...) hint asl check prints must parse to the keys the fix op knows and run there: :by :indent followed by :apply true read :indent as a key and the op refused it with ERR_UNKNOWN_KEY")
fn ! tempRoot -> String
  (str "/tmp/fixHintParseTest_" (stringFromInt64 (monotonicNs)))

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

fn ! runTests -> Bool
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
