(module asl/agentLoop/tests/refuseRepairTest
  :x [runTests]
  :i [(asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

; (:m :ref REFUSE-AUTOREPAIR :do "a balance-refused write heal can repair lands and its receipt carries the checker verdict: (check ok), or (:diags n :first ...) for an import the same reply writes next, which heal! cannot load (24 of 337 refused writes in node2 journals 2026-10-31 dropped their repair that way); a repair that leaves a parse error is refused with the numbered lines around the line the balance aid names")
fn wr file: String content: String -> String
  (str "(:write :file \"" file "\" :content \"" (c/escapeAsn content) "\")")

fn sameReply -> String
  "(module lib/fooTest\n  :x [runTests]\n  :i [(lib/fresh :a fr)])\n\nfn ! runTests -> Bool\n  (let [x (fr/one)]\n    (= x 1)\n"

fn cleanMissing -> String
  "(module lib/ok\n  :x [f]\n  :i [])\n\nfn f x: Int64 -> Int64\n  (let [y (+ x 1)]\n    (* y 2)\n"

fn parseLeft -> String
  "(fn g\n  (y)\n"

fn openParens -> String
  "(a\n(b\n"

fn refusal -> String
  "(:txn :status :rejected :error ERR_TXN_FLUSH_FAILED :message \"unbalanced\" :balanced false :byte 40)"

fn ! receiptOf! base: String file: String content: String -> String
  (t/serReceipt (t/execTxn! (str "(:txn :owns (\"lib\") " (wr file content) ")") (list "lib") base (list) (fn [] "rid1") (fn [p] true)
                  (fn [sent root] (t/aslRun 1 (refusal) ""))))

fn ! landed! base: String file: String -> String
  (resultOr (fileReadString (str base "/" file)) "")

fn ! runTests -> Bool
  (let [tmp (resultOr (realPath "/tmp") "/tmp")
        base (str tmp "/aslRefuseRepairTest." (stringFromInt64 (procSelf)))
        made (ok? (dirCreate (str base "/lib")))
        same (receiptOf! base "lib/fooTest.asl" (sameReply))
        sameText (landed! base "lib/fooTest.asl")
        clean (receiptOf! base "lib/ok.asl" (cleanMissing))
        parsed (receiptOf! base "lib/p.asl" (parseLeft))
        pWritten (fileExists? (str base "/lib/p.asl"))
        opened (receiptOf! base "lib/o.asl" (openParens))
        oWritten (fileExists? (str base "/lib/o.asl"))
        gone (ok? (pathRemove base))]
    (do
      (assert made "fixture dir created")
      (assert gone "fixture dir removed")
      (assert (stringContains? same "(status \"ok\")") (str "a test whose src the same reply writes lands once heal balances it: " same))
      (assert (stringContains? same "(repaired ") (str "with the repair named: " same))
      (assert (stringContains? same "(check \"(:diags ") (str "and the checker's diagnostics in the same receipt: " same))
      (assert (stringContains? sameText "(= x 1))") (str "the file holds the balanced text: " sameText))
      (assert (stringContains? clean "(check \"ok\")") (str "a repair the checker accepts says so: " clean))
      (assert (stringContains? parsed "(status \"rejected\")") (str "a repair that leaves a parse error is refused: " parsed))
      (assert (stringContains? parsed "(around \"1: (fn g") (str "naming the lines around it: " parsed))
      (assert (not pWritten) "nothing is written for it")
      (assert (stringContains? opened "(status \"ok\")") (str "a repair whose leftovers are unknown symbols, not parse errors, lands: " opened))
      (assert (stringContains? opened "(check \"(:diags 2 ") (str "and names them: " opened))
      true))
