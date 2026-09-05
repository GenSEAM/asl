(module asl-mem/test
  :d "Unit tests for asl-mem/records: ADR rules, shortcode scanning, and ledger verification."
  :x [main]
  :i [(records :a r)])

(df test-shortcode-creation [] -> Bool
  (let [(sc (r/make-shortcode (r/p-dec) "d-1eed"))]
    (and (= (.-code sc) "d-1eed")
         (= (r/shortcode-type-to-string (.-kind sc)) "d"))))

(df test-rule-and-ledger [] -> Bool
  (let [(rule1 (r/make-rule "d-1eed" "Standard Format" "Compact token ceiling" "active"))
        (rule2 (r/make-rule "l-a250" "Notes Invariant" "Comments are notes" "active"))
        (ledger (r/make-ledger (list rule1 rule2) (list "d-1eed" "l-a250")))
        (q1 (r/query-rule ledger "d-1eed"))
        (q2 (r/query-rule ledger "@rule:l-a250"))]
    (and (mt q1 ((some _) true) ((none) false))
         (mt q2 ((some _) true) ((none) false)))))

(df test-scan-and-verify [] -> Bool
  (let [(sample "This module respects @adr:d-1eed and invariant @rule:l-a250.")
        (scs (r/scan-shortcodes sample))
        (rule1 (r/make-rule "d-1eed" "Standard Format" "Compact token ceiling" "active"))
        (rule2 (r/make-rule "l-a250" "Notes Invariant" "Comments are notes" "active"))
        (ledger (r/make-ledger (list rule1 rule2) (list "d-1eed" "l-a250")))
        (res (r/verify-module ledger "test-mod" sample))]
    (and (= (list-length scs) 2)
         (list-empty? (.-missing res)))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Runs unit tests for asl-mem records."
  (if (and (test-shortcode-creation)
           (and (test-rule-and-ledger)
                (test-scan-and-verify)))
    (let [(u (println "asl-mem records tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-mem records test failure"))]
      (err (other)))))
