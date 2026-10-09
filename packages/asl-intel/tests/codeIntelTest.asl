(module aslIntel/tests/intel_test :x [testIntelVersion testIntelBanner testExtractAslSymbols testIntelImportsSymbolGraph runTests] :i [(aslIntel/intel :a int) (extractor :a ext) (aslIntel/symbolGraph :a sg)])

fn testIntelVersion -> Bool
  (let [(v (int/intelVersion))] (assert (= v "0.1.0") "Intel version must be 0.1.0") (assert (not (= v "0.0.0")) "Intel version must not be 0.0.0") true)

fn testIntelBanner -> Bool
  (let [(b (int/intelBanner))] (assert (stringContains? b "GenSEAM ASL-Intel") "Intel banner must contain GenSEAM ASL-Intel") (assert (stringContains? b "0.1.0") "Intel banner must contain version 0.1.0") true)

fn testExtractAslSymbols -> Bool
  (let [(src (str "(module sample-mod :x [worker])\n" "(fn worker [(arg Str)] -> Str\n" "  (sys/log! arg))\n" "(schema Job (:f id Str \"id\"))\n" "(enum Priority (:c high [] \"high\"))\n")) (fs (ext/extractAslSymbols "sample.asl" src))] (assert (= fs.language "asl") "Language must be asl") (assert (= (listLength fs.symbols) 3) "Must extract 3 symbols") (assert (= (listLength fs.refs) 1) "Must extract 1 call reference") (let [(s1 (optionOr (listHead fs.symbols) (ext/SymbolDef :name "" :kind (ext/symFn) :file "" :startLine 0 :endLine 0 :signature "" :exported false :doc "")))] (assert (= s1.name "sample-mod/worker") "First symbol must be sample-mod/worker") (assert s1.exported "worker must be marked exported") true))

fn testIntelImportsSymbolGraph -> Bool
  (let [(g0 (sg/graphCreate)) (n (sg/GraphNode :id "a" :name "a" :kind "fn" :file "f.asl" :startLine 1 :endLine 2 :signature "" :exported true)) (g1 (sg/graphAddNode g0 n))]
    (do
      (assert (= (sg/graphNodeCount g0) 0) "Fresh symbol graph is empty")
      (assert (= (sg/graphNodeCount g1) 1) "Symbol graph counts an added node")
      (assert (some? (sg/graphFind g1 "a")) "Symbol graph finds the added node")
      true))

fn runTests -> Bool
  (let [(t1 (testIntelVersion)) (t2 (testIntelBanner)) (t3 (testExtractAslSymbols)) (t4 (testIntelImportsSymbolGraph))] (and t1 (and t2 (and t3 t4))))
