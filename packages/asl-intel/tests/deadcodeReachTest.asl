(module asl-intel/tests/deadcodeReachTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/deadcode :a dc)])

fn ! fixtureDir! -> String
  (let [(base (optionOr (envGet "TMPDIR") "/tmp"))
        (dir (str base "/asl-intel-deadcode-reach-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (do (assert (ok? made) (str "dirCreate failed for fixture " dir))
        dir))

fn ! writeIn! dir: String rel: String text: String -> Bool
  (let [(path (str dir "/" rel))
        (parts (stringSplit rel "/"))
        (sub (stringJoin (listTake parts (- (listLength parts) 1)) "/"))
        (made (dirCreate (str dir "/" sub)))
        (written (fileWrite path text))]
    (do (assert (ok? made) (str "mkdir " sub))
        (assert (ok? written) (str "write " rel))
        true))

fn ! testReachability -> Bool
  (let [(dir (fixtureDir!))
        (prod "(module app :x [main exportedUnused testOnly viaDispatch] :i [])\n\nfn main -> Int64\n  (liveCommand)\n\nfn liveCommand -> Int64\n  1\n\nfn exportedUnused -> Int64\n  2\n\nfn testOnly -> Int64\n  3\n\nfn viaDispatch -> Int64\n  4\n\nfn unusedCaller -> Int64\n  (exportedUnused)\n\nfn tableHolder -> Int64\n  (let [(table (list (pair \"dispatch\" viaDispatch)))]\n    1)\n")
        (tests "(module appTest :x [runTests] :i [(app :a a)])\n\nfn runTests -> Bool\n  (do (assert (= (a/testOnly) 3) \"test-only fixture\") true)\n")
        (w1 (writeIn! dir "src/app.asl" prod))
        (w2 (writeIn! dir "tests/appTest.asl" tests))
        (r (dc/analyzeDeadcode! (intel/makeCtx!) dir ""))
        (cleaned (pathRemove dir))]
    (let [(reach (match r ((ok s) s.reach) ((err e) (list))))
          (asn (match r ((ok s) (dc/formatDeadcodeAsn s)) ((err e) (str "analyzeDeadcode! failed: " e))))
          (unused (filter (fn [(d dc/Def)] -> Bool (= d.kind "exportedUnused")) reach))
          (testOnly (filter (fn [(d dc/Def)] -> Bool (= d.kind "testOnly")) reach))]
      (do (assert (ok? r) asn)
          (assert (= (listLength unused) 1) (str "exactly one exported-unused symbol: " asn))
          (assert (= (optionOr (listHead (map (fn [(d dc/Def)] -> String d.name) unused)) "") "exportedUnused") "the exported-unused symbol is named")
          (assert (= (listLength testOnly) 1) (str "exactly one test-only symbol: " asn))
          (assert (= (optionOr (listHead (map (fn [(d dc/Def)] -> String d.name) testOnly)) "") "testOnly") "the test-only symbol is named")
          (assert (= (listLength reach) 2) (str "the string dispatch root is live and no other exported symbol is reported: " asn))
          (assert (not (stringContains? asn ":name \"viaDispatch\"")) "the dispatch-table-only function is a production root")
          (assert (stringContains? asn ":kind \"exportedUnused\"") "the intel ASN reports exportedUnused")
          (assert (stringContains? asn ":kind \"testOnly\"") "the intel ASN reports testOnly")
          (assert (ok? cleaned) "fixture removed")
          true)))

fn ! runTests -> Bool
  (do (assert (testReachability) "deadcode reports exported-unused and test-only reachability with dispatch roots")
      true)
