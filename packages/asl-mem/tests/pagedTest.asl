(module aslMem/test :x [main runTests] :i [(paged :a p)])

fn testTierDecision -> Bool
  (do (assert (p/shouldPage? 100000000 50000000) "should page on large footprint") (assert (not (p/shouldPage? 10000000 50000000)) "should not page on small footprint") true)

fn testPagedLruLifecycle -> Bool
  (let [(mgr (p/makePagedManager 2 1000 true)) (s1 (p/makeSegment "seg-1" "asl-core" 200 100 10)) (s2 (p/makeSegment "seg-2" "asl-vdom" 300 105 15)) (s3 (p/makeSegment "seg-3" "asl-mem" 400 110 20)) (m1 (p/loadSegment mgr s1 100)) (m2 (p/loadSegment m1 s2 105)) (m3 (p/loadSegment m2 s3 110))] (assert (= m3.maxResidentSegments 2) "max resident segments is 2") (assert (> m3.currentBytes 0) "current bytes positive") true)

fn runTests -> Bool
  (and (testTierDecision) (testPagedLruLifecycle))

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runTests) (let [(u (println "asl-mem paged tests passed cleanly"))] (ok ())) (let [(u (eprintln "asl-mem paged test failure"))] (err (other))))
