(module aslAgent/tests/autofixCloserTest
  :x [runTests]
  :i [(aslAgent/aslOps :a o)
      (aslAgent/txn :a t)
      (aslAgent/core :a c)])

; (:m :ref LEON-AUTOFIX-CLOSER :do "node2 2026-11-03: 11 of 18 repeatFailure sessions resent byte-identical content after a hint naming the one stray closer; exactly one stray closer is deleted, or one unclosed opener at the end closed, only when the result balances and the quotes pair")

fn gateRun form: String root: String -> t/AslRun
  (if (stringContains? form "(f 1)\\n\"")
    (t/aslRun 0 "(:receipt :op txn :status :ok)" "")
    (t/aslRun 1 "(:receipt :op txn :status :aborted :error :ERR_UNBALANCED :balanced false :byte 000040)" ""))

fn ! recOf op: String -> String
  (o/serReceipt (o/execAslOpMemo! (c/parseKv op) (list) "/nonexistent-autofixCloser" "s" (fn [] "rid") (fn [f] true) (fn [form r] (gateRun form r)) 8000 none))

fn wr content: String -> String
  (str "(:step :op \"write\" :file \"x.asl\" :content \"" (c/escapeAsn content) "\")")

fn ! runTests -> Bool
  (let [extra "fn a -> Int64\n  (f 1))\n"
        open "fn a -> Int64\n  (f 1\n"
        two "fn a -> Int64\n  (f 1)))\n"
        twoOpen "fn a -> Int64\n  (f (g 1\n"
        quote "fn a -> Int64\n  (f \"x)\n"
        mid "fn a -> Int64\n  (f 1\n\nfn b -> Int64\n  2\n"
        okText "fn a -> Int64\n  (f 1)\n"
        recExtra (recOf (wr extra))
        recTwo (recOf (wr two))]
    (do
      (assert (= (optionOr (t/balanceRepair extra) "") okText) "one stray closer is deleted")
      (assert (= (optionOr (t/balanceRepair open) "") okText) "one unclosed opener at the end is closed")
      (assert (none? (t/balanceRepair two)) "two stray closers are not repaired")
      (assert (none? (t/balanceRepair twoOpen)) "two unclosed openers are not repaired")
      (assert (none? (t/balanceRepair quote)) "an unpaired quote is not repaired")
      (assert (none? (t/balanceRepair mid)) "an opener cut by the next top-level form is not repaired")
      (assert (none? (t/balanceRepair okText)) "balanced text needs no repair")
      (assert (stringContains? recExtra "repaired") "the write receipt carries repaired")
      (assert (stringContains? recExtra "persisted true") "the repaired write persisted")
      (assert (not (stringContains? recExtra "ERR_TXN_FLUSH_FAILED")) "no refusal for the repaired write")
      (assert (stringContains? recTwo "persisted false") "an ambiguous write keeps the refusal")
      (assert (not (stringContains? recTwo "repaired")) "an ambiguous write has no repaired")
      true))
