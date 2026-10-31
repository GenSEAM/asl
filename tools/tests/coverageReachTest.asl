(module aslTools/coverageReachTest
  :x [runTests]
  :i [(asl-tools/coverageReach :a cr)])

fn srcText -> String
  "(module p/m\n  :x [alpha beta gamma delta]\n  :i [])\nfn alpha x: Int64 -> Int64\n  (beta x)\n\nfn beta x: Int64 -> Int64\n  x\n\nfn gamma x: Int64 -> Int64\n  (delta x)\n\ntailrec fn delta x: Int64 -> Int64\n  x\n\nfn hidden x: Int64 -> Int64\n  x\n"

fn detachedText -> String
  "(module p/m\n  :x [alpha beta gamma delta]\n  :i [])\nfn alpha x: Int64 -> Int64\n  x\n\nfn beta x: Int64 -> Int64\n  x\n\nfn gamma x: Int64 -> Int64\n  (delta x)\n\ntailrec fn delta x: Int64 -> Int64\n  x\n"

fn chainText -> String
  "fn a x: Int64 -> Int64\n  (b x)\n\nfn b x: Int64 -> Int64\n  (c x)\n\nfn c x: Int64 -> Int64\n  (d x)\n\nfn d x: Int64 -> Int64\n  x\n\nfn e x: Int64 -> Int64\n  x\n"

fn testText -> String
  "(module p/mTest :x [runTests] :i [(p/m :a m)])\nfn ! runTests -> Bool\n  (= (m/alpha 1) 1)\n"

fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! build! root: String -> Bool
  (and (ok? (dirCreate root))
       (ok? (dirCreate (str root "/asl")))
       (ok? (dirCreate (str root "/asl/packages")))
       (ok? (dirCreate (str root "/asl/packages/p")))
       (ok? (dirCreate (str root "/asl/packages/p/src")))
       (ok? (dirCreate (str root "/asl/packages/p/tests")))
       (put! (str root "/asl/packages/p/src/m.asl") (srcText))
       (put! (str root "/asl/packages/p/tests/mTest.asl") (testText)))

fn names rows: (List cr/Row) -> (List String)
  (map (fn [(r cr/Row)] -> String r.name) rows)

fn edgesOf src: String -> (Map String (Map String Bool))
  (cr/scanLines (mapEmpty) src)

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/coverageReachTest-" (stringFromInt64 (monotonicNs))))
        (made (build! base))
        (rows (cr/unreachedRows! base))
        (detached (put! (str base "/asl/packages/p/src/m.asl") (detachedText)))
        (rowsDetached (cr/unreachedRows! base))
        (edges (edgesOf (srcText)))
        (seen (cr/reachable edges (mapSet (mapEmpty) "alpha" true)))
        (chain (cr/reachable (edgesOf (chainText)) (mapSet (mapEmpty) "a" true)))
        (cleaned (pathRemove base))]
    (do
      (assert made "the fixture tree is written")
      (assert (= (cr/headerName "fn foo x: Int64 -> Int64") "foo") "a plain header names the fn")
      (assert (= (cr/headerName "fn ! bar! x: Int64 -> Unit") "bar!") "an effect header names the fn after the bang")
      (assert (= (cr/headerName "tailrec fn loop a: Int64 -> Int64") "loop") "a tailrec header names the fn")
      (assert (= (cr/headerName "  fn nested") "") "an indented fn is not a header")
      (assert (= (cr/headerName "(fn [x] x)") "") "a lambda is not a header")
      (assert (= (cr/headerName "fnord x") "") "a name that starts with fn is not a header")
      (assert (= (mapSize edges) 5) "five fns are defined, comments and module lines are not")
      (assert (mapHas? (mapGetOr edges "alpha" (mapEmpty)) "beta") "alpha's body mentions beta")
      (assert (not (mapHas? (mapGetOr edges "alpha" (mapEmpty)) "gamma")) "alpha's body does not mention gamma")
      (assert (not (mapHas? (mapGetOr edges "beta" (mapEmpty)) "x:")) "header tokens are not body tokens")
      (assert (mapHas? seen "alpha") "a seed fn is reachable")
      (assert (mapHas? seen "beta") "a callee of a seed is reachable")
      (assert (not (mapHas? seen "gamma")) "an uncalled fn is not reachable")
      (assert (not (mapHas? seen "hidden")) "an unexported uncalled fn is not reachable")
      (assert (= (names rows) (list "delta" "gamma")) "gamma and its callee delta are unreached, most-called first")
      (assert (= (match (listHead rows) ((some r) r.callers) ((none) 0)) 1) "delta has one caller")
      (assert (= (match (listHead rows) ((some r) r.pkg) ((none) "")) "p") "the row names the package")
      (assert (stringEndsWith? (match (listHead rows) ((some r) r.file) ((none) "")) "asl/packages/p/src/m.asl") "the row names the file")
      (assert (mapHas? chain "d") "reachability follows a chain of three calls")
      (assert (not (mapHas? chain "e")) "a fn outside the chain is not reached")
      (assert detached "the fixture is rewritten without alpha's call")
      (assert (= (listLength rowsDetached) 3) "cutting alpha's call leaves beta unreached too")
      (assert (ok? cleaned) "the fixture tree is removed")
      true))
