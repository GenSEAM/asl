(module aslMem/test :x [testShortcodeCreation testRuleAndLedger testScanAndVerify runTests main] :i [(records :a r)])

fn testShortcodeCreation -> Bool
  (let [(sc (r/makeShortcode (r/pDec) "d-1eed"))] (assert (= sc.code "d-1eed") "Shortcode code must be d-1eed") (assert (= (r/shortcodeTypeToString sc.kind) "d") "Shortcode kind must be d") true)

fn testRuleAndLedger -> Bool
  (let [(rule1 (r/makeRule "d-1eed" "Standard Format" "Compact token ceiling" "unspecified" "active")) (rule2 (r/makeRule "l-a250" "Notes Invariant" "Comments are notes" "unspecified" "active")) (ledger (r/makeLedger (list rule1 rule2) (list "d-1eed" "l-a250"))) (q1 (r/queryRule ledger "d-1eed")) (q2 (r/queryRule ledger "@rule:l-a250"))] (assert (mt q1 ((some _) true) ((none) false)) "Query for d-1eed must find rule") (assert (mt q2 ((some _) true) ((none) false)) "Query for @rule:l-a250 must find rule") true)

fn testScanAndVerify -> Bool
  (let [(sample "This module respects @adr:d-1eed and invariant @rule:l-a250") (scs (r/scanShortcodes sample)) (rule1 (r/makeRule "d-1eed" "Standard Format" "Compact token ceiling" "unspecified" "active")) (rule2 (r/makeRule "l-a250" "Notes Invariant" "Comments are notes" "unspecified" "active")) (ledger (r/makeLedger (list rule1 rule2) (list "d-1eed" "l-a250"))) (res (r/verifyModule ledger "test-mod" sample))] (assert (= (listLength scs) 2) "Should find exactly 2 shortcodes in sample") (assert (listEmpty? res.missing) "No missing rules should be detected") true)

fn runTests -> Bool
  (let [(t1 (testShortcodeCreation)) (t2 (testRuleAndLedger)) (t3 (testScanAndVerify))] (and t1 (and t2 t3)))

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runTests) (let [(u (println "asl-mem records tests passed cleanly"))] (ok ())) (let [(u (eprintln "asl-mem records test failure"))] (err (other))))
