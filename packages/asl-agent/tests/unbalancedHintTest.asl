(module aslAgent/tests/unbalancedHintTest
  :x [runTests]
  :i [(aslAgent/aslOps :a o)
      (aslAgent/txn :a t)
      (aslAgent/core :a c)])

; (:m :ref LEON-UNBALANCED-HINT :do "node2 2026-11-01: 35 writes refused for unbalanced delimiters got the same generic hint each turn (07d58b01, 0e0dd806); the hint now names the line where the unclosed form opens and the closer it expects, or the line and column of the closer with nothing to close")

fn refusedRun form: String root: String -> t/AslRun
  (t/aslRun 1 "(:receipt :op txn :status :aborted :error :ERR_UNBALANCED :balanced false :byte 000040)" "")

fn ! hintOf content: String -> String
  (let [op (str "(:step :op \"write\" :file \"x.asl\" :content \"" (c/escapeAsn content) "\")")
        rec (o/serReceipt (o/execAslOpMemo! (c/parseKv op) (list) "/nonexistent-unbalancedHint" "s" (fn [] "rid") (fn [f] true) (fn [form r] (refusedRun form r)) 8000 none))]
    rec)

fn ! runTests -> Bool
  (let [open "fn a -> Int64\n  1\n\nfn b -> Int64\n  (let [x 1]\n    (f x)\n\nfn c -> Int64\n  2\n"
        extra "fn a -> Int64\n  (f 1))\n"
        fixOpen (optionOr (t/balanceFix open) "")
        fixExtra (optionOr (t/balanceFix extra) "")
        recOpen (hintOf open)
        recExtra (hintOf extra)]
    (do
      (assert (stringContains? fixOpen "opened at line 5") "the unclosed ( is named by the line it opens on")
      (assert (stringContains? fixOpen "add the expected )") "the expected closer is named")
      (assert (stringContains? fixExtra "line 2 column") "an extra closer is named by line and column")
      (assert (stringContains? fixExtra "delete it") "the extra closer is to be deleted")
      (assert (none? (t/balanceFix "fn a -> Int64\n  1\n")) "balanced text has no fix")
      (assert (stringContains? recOpen "opened at line 5") "the receipt hint carries the opening line")
      (assert (stringContains? recExtra "has a closer with nothing open to close") "the receipt hint carries the extra closer position")
      (assert (not (stringContains? recOpen "write a large file in parts")) "the generic advice is gone from the hint")
      (assert (not (stringContains? recOpen "as decoded from your reply")) "the decoded-text advice is not repeated")
      true))
