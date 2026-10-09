(module asl-syntax/tests/core/formatCorpusShard4Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/layoutCorpusLib :a lib)
      (asl-syntax/tests/core/formatCorpusShard1Test :a sweep)])

fn ! runTests -> Bool
  (mt (lib/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok allFiles)
     (let [(v (sweep/formatShard! allFiles 4 4 "formatCorpusShard4Test"))]
       (do
         (assert v.corpusMatches "corpus is the tracked corpus minus exactly the seven listed misparse files")
         (assert v.excludedMatches "excluded files are exactly the listed seven")
         (assert (= v.size v.expectedShare) "shard 4 holds its exact share")
         (assert (= v.identical v.size) "every shard 4 file formats byte-identical through formatRepair")
         (= v.identical v.size)))))
