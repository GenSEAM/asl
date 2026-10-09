(module asl-intel/tests/intelTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/model :a m)
      (asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/tab :a tb)
      (asl-intel/stubs :a st)
      (asl-intel/sweep :a sw)
      (asl-intel/fixture :a fx)
      (asl-intel/graph :a g)
      (asl-intel/complexity :a cx)])

fn span rex: r/Rex s: String -> (Pair Int64 Int64)
  (let [(b (stringToBytes s))]
    (mt (r/rexSearch rex b (bytesLength b) 0)
      ((some c) (pair (optionOr (listGet c 0) -1) (optionOr (listGet c 1) -1)))
      ((none) (pair -1 -1))))

fn span2 rex: r/Rex s: String -> (Option (List Int64))
  (let [(b (stringToBytes s))] (r/rexSearch rex b (bytesLength b) 0))

fn lit s: String -> r/Rx
  (r/rxLit (stringToBytes s))

fn testRegex! -> Bool
  (let [(greedy (r/rexCompile! (r/rxSeq (list (r/rxRep (r/clsSet! "a") 0 true) (lit "ab"))) 0 (r/preAny) 0))
        (lazy (r/rexCompile! (r/rxSeq (list (lit "a") (r/rxRep (r/clsAny) 0 false) (lit "b"))) 0 (r/preAny) 0))
        (alts (r/rexCompile! (r/rxSeq (list (r/rxGroup 1 (r/rxAlt (list (lit "a") (lit "ab"))))
                                           (r/rxGroup 2 (r/rxAlt (list (lit "c") (lit "bcd"))))
                                           (r/rxGroup 3 (r/rxRep (r/clsSet! "d") 0 true))))
                            3 (r/preAny) 0))
        (look (r/rexCompile! (r/rxSeq (list (lit "x") (r/rxLook (r/rxSeq (list (lit "\n") (r/rxRep (r/clsSpace!) 0 true) (lit "fn")))))) 0 (r/preAny) 0))
        (ab (stringToBytes "abcd"))
        (caps (optionOr (r/rexSearch alts ab 4 0) (list)))
        (word (r/rexCompile! (r/rxSeq (list (r/rxWordB) (lit "if") (r/rxWordB))) 0 (r/preAny) 0))
        (wb (stringToBytes "if éif if_x if-y"))]
    (do
      (assert (= (span greedy "xaaab") (pair 1 5)) "a*ab on xaaab spans 1..5")
      (assert (= (span lazy "axbyb") (pair 0 3)) "a.*?b stops at the first b")
      (refute (= (span lazy "axbyb") (pair 0 5)) "lazy repetition never runs to the last b")
      (refute (some? (span2 word "if_x iff")) "no whole-word if inside if_x or iff")
      (assert (= caps (list 0 4 0 1 1 4 4 4)) "(a|ab)(c|bcd)(d*) groups as Python")
      (assert (= (span look "ax\n  fn") (pair 1 2)) "lookahead is zero width")
      (assert (= (r/rexCount word wb (bytesLength wb)) 2) "\\bif\\b counts two whole words, not after a Unicode letter")
      (and (= caps (list 0 4 0 1 1 4 4 4)) (= (span lazy "axbyb") (pair 0 3)))))

fn testNumbers -> Bool
  (do
    (assert (= (t/floatStr (t/pyRound 2.675 2)) "2.67") "round(2.675, 2)")
    (assert (= (t/floatStr (t/pyRound 0.125 2)) "0.12") "round(0.125, 2)")
    (assert (= (t/floatStr (t/pyRound 0.375 2)) "0.38") "round(0.375, 2)")
    (assert (= (t/floatStr (t/pyRound 1.25 1)) "1.2") "round(1.25, 1)")
    (assert (= (t/floatStr (t/pyRound 0.5 1)) "0.5") "round(0.5, 1)")
    (= (t/floatStr (t/pyRound 2.675 2)) "2.67"))

fn testJson -> Bool
  (let [(v (j/jObj (list (pair "a" (j/jArr (list (j/jStr "é\n\"") (j/jInt 1) (j/jFloat 2.5) (j/jNull) (j/jBool true))))
                         (pair "b" (j/jObj (list))))))
        (want "{\n  \"a\": [\n    \"\\u00e9\\n\\\"\",\n    1,\n    2.5,\n    null,\n    true\n  ],\n  \"b\": {}\n}")]
    (do (assert (= (j/dumps v) want) "dumps matches json.dumps(indent=2)")
        (= (j/dumps v) want)))

fn testPaths -> Bool
  (do
    (assert (= (t/relPath "/a/b/c" "/a/x" "/") "../b/c") "relpath climbs")
    (assert (= (t/normPath "/a/./b/../c//d/") "/a/c/d") "normpath")
    (assert (= (t/pyReprList (list "it's" "q\"x" "tab\t")) "[\"it's\", 'q\"x', 'tab\\t']") "list repr")
    (assert (= (t/pyStrip "  hi  ") "hi") "strip removes Unicode spaces")
    (= (t/relPath "/a/b/c" "/a/x" "/") "../b/c"))

fn testSweep -> Bool
  (do
    (assert (= (sw/balanceError "(a [b) ]") (some "unexpected ) at byte 5")) "mismatched close")
    (assert (= (sw/balanceError "é)") (some "unexpected ) at byte 1")) "index counts code points")
    (assert (= (sw/balanceError "(\"a)") (some "unclosed string")) "unclosed string")
    (assert (= (sw/balanceError "([{") (some "unclosed delimiters: ([{")) "stack order")
    (assert (= (sw/balanceError "(\"\\\")\")") (none)) "escaped quote inside a string")
    (assert (= (sw/pyOsError "/x/y" "notFound: /x/y: No such file or directory") "[Errno 2] No such file or directory: '/x/y'") "ENOENT text")
    (= (sw/balanceError "([{") (some "unclosed delimiters: ([{")))

fn testReader! -> Bool
  (mt (fx/readAsn ";; c\n(:case :id \"a\\\"b\\n\" :n -3 :v [1 x \"y\"] :k :init)")
    ((err e) (do (eprintln "reader parses:" e) false))
    ((ok forms)
      (let [(c (optionOr (listHead forms) (fx/aList (list))))]
        (do
          (assert (= (fx/headKw c) "case") "head keyword")
          (assert (= (fx/kwStr c "id") (ok "a\"b\n")) "string escapes")
          (assert (= (fx/kwInt c "n") (ok -3)) "negative integer")
          (assert (= (listLength (resultOr (fx/kwItems c "v") (list))) 3) "vector items")
          (assert (= (fx/kwKw c "k") (ok "init")) "keyword value")
          (= (fx/kwKw c "k") (ok "init"))))))

fn testModel -> Bool
  (let [(item (m/makeOutlineItem "dispatchIntel" "fn" "String -> String" true))
        (outl (m/makeModuleOutline "asl-intel" "src/main.asl" (list item item)))]
    (do (assert (= outl.totalSymbols 2) "outline counts its items")
        (assert (= item.name "dispatchIntel") "item name")
        (= outl.totalSymbols 2)))

fn msSince! t0: Int64 -> Int64
  (/ (- (monotonicNs) t0) 1000000)

fn synthSource k: Int64 -> String
  (t/concatAll (map (fn [(i Int64)] -> String
                      (str "fn f" (t/intStr i) " a: Int64 b: (List Int64) -> Int64\n  (if (> a " (t/intStr i) ") (fold (fn [(x Int64) (y Int64)] -> Int64 (+ x y)) a b) (mt (some a) ((some v) v) ((none) 0)))\n\n"))
                    (range 0 k)))

fn testLargeInputs! -> Bool
  (let [(src (synthSource 20000)) (b (stringToBytes src)) (n (bytesLength b))
        (t0 (monotonicNs))
        (hs (st/headersOf! src b n))
        (tHeaders (msSince! t0))
        (longLine (str "fn g " (stringRepeat "abc " 50000) "\n"))
        (lb (stringToBytes longLine))
        (t1 (monotonicNs))
        (none1 (r/rexFindAll (p/patFnHeader!) lb (bytesLength lb)))
        (tLong (msSince! t1))
        (t2 (monotonicNs))
        (tab (fold (fn [(acc tb/Strtab) (i Int64)] -> tb/Strtab (pairFirst (tb/internStr! acc (str "k" (t/intStr i))))) (tb/strtabNew 16) (range 0 50000)))
        (found (listLength (filter (fn [(i Int64)] -> Bool (= (tb/lookupStr tab (str "k" (t/intStr i))) i)) (range 0 50000))))
        (tTab (msSince! t2))]
    (do
      (println "large inputs:" n "bytes of headers in" tHeaders "ms; 200 KB line in" tLong "ms; 50000 keys in" tTab "ms")
      (assert (= (listLength hs) 20000) "every synthetic header found")
      (assert (= (optionOr (listGet hs 19999) (optionOr (listHead hs) (st/Header :rawName "" :params "" :ret "" :start 0 :bodyStart 0 :bodyEnd 0))).rawName "f19999") "last header name")
      (assert (< tHeaders 60000) "2 MB header scan under 60 s")
      (assert (listEmpty? none1) "a line without -> holds no header")
      (assert (< tLong 20000) "200 KB arrowless line under 20 s: no quadratic backtracking")
      (assert (= found 50000) "every interned key looks up to its id")
      (assert (< tTab 30000) "50000 keys under 30 s")
      (and (= found 50000) (listEmpty? none1))))

fn testDispatch! -> Bool
  (let [(o (intel/runIntel! (intel/makeCtx!) (list "nope")))]
    (do (assert (= o.code 1) "unknown subcommand exits 1")
        (assert (= o.err "Unknown intel subcommand: nope\n") "unknown subcommand message")
        (= o.code 1)))

fn testWholeRepo! -> Bool
  (let [(ctx (intel/makeCtx!))
        (t0 (monotonicNs))
        (gr (g/analyzeGraph! ctx "hotspots" 10 "" ""))
        (tGraph (msSince! t0))
        (t1 (monotonicNs))
        (cxr (cx/analyzeComplexity! ctx "" 10))
        (tCx (msSince! t1))
        (nodes (mt gr ((ok r) r.totalNodes) ((err _) 0)))
        (fns (mt cxr ((ok r) r.total) ((err _) 0)))]
    (do
      (println "whole repo:" nodes "graph nodes in" tGraph "ms;" fns "functions ranked in" tCx "ms")
      (assert (> nodes 1000) "the repo graph holds over 1000 nodes")
      (assert (> fns 1000) "complexity ranks over 1000 functions")
      (assert (< tGraph 60000) "whole-repo graph under 60 s")
      (assert (< tCx 60000) "whole-repo complexity under 60 s")
      (and (> nodes 1000) (< tGraph 60000))))

fn ! runTests -> Bool
  (let [(rs (list (testRegex!) (testNumbers) (testJson) (testPaths) (testSweep) (testReader!) (testModel) (testDispatch!) (testLargeInputs!) (testWholeRepo!)))]
    (fold (fn [(acc Bool) (x Bool)] -> Bool (and acc x)) true rs))
