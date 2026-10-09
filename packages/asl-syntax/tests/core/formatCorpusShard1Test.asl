(module asl-syntax/tests/core/formatCorpusShard1Test
  :x [runTests ShardVerdict formatShard! knownMisparseSet]
  :i [(asl-syntax/core/format :a fmt)
      (asl-syntax/tests/asl/layoutCorpusLib :a lib)])

fn knownMisparseSet -> (List String)
  (list "asl/grammar/tests/corpusTest.asl"
        "asl/packages/asl-regex/src/regex.asl"
        "asl/packages/asl-syntax/src/core/corpus.asl"
        "asl/packages/asl-syntax/src/xml.asl"
        "asl/packages/asl-transpile/src/yamlTranspile.asl"
        "tests/acceptance/r1Host/reader/surfaceTest.asl"
        "tests/host/tailrecTest.asl")

(schema ShardVerdict
  (:f corpusMatches Bool)
  (:f excludedMatches Bool)
  (:f expectedShare Int64)
  (:f size Int64)
  (:f identical Int64))

fn ! formatIdentical? path: String -> Bool
  (let [(verdict (mt (fileReadString path)
                   ((err e) (err (str "read error: " e)))
                   ((ok content)
                    (mt (fmt/formatRepair content "asl")
                      ((err e) (err (str "formatter error: " e)))
                      ((ok out) (if (= out content) (ok true) (err "output differs from input")))))))]
    (mt verdict
      ((ok _) true)
      ((err e) (do (print (str path ": " e "\n")) false))))

fn countIdentical! files: (List String) acc: Int64 -> Int64
  (if (listEmpty? files)
    acc
    (let [(f (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (countIdentical! rest (if (formatIdentical? f) (+ acc 1) acc))))

fn formatShard! allFiles: (List String) n: Int64 k: Int64 label: String -> ShardVerdict
  (let [(corpus (filter (fn [(p String)] -> Bool (none? (lib/knownMisparseReason p))) allFiles))
        (excluded (filter (fn [(p String)] -> Bool (some? (lib/knownMisparseReason p))) allFiles))
        (listed (knownMisparseSet))
        (shard (lib/shardFiles corpus n k))
        (identical (countIdentical! shard 0))]
    (do
      (print (str label ": corpus=" (stringFromInt64 (listLength corpus)) " shard=" (stringFromInt64 (listLength shard)) " identical=" (stringFromInt64 identical) "\n"))
      (ShardVerdict :corpusMatches (= (listLength corpus) (- (listLength allFiles) (listLength listed)))
                    :excludedMatches (and (= (listLength excluded) (listLength listed))
                                          (fold (fn [(acc Bool) (p String)] -> Bool (and acc (listContains? listed p))) true excluded))
                    :expectedShare (lib/expectedShardCount (listLength corpus) n k)
                    :size (listLength shard)
                    :identical identical)))

fn ! runTests -> Bool
  (mt (lib/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok allFiles)
     (let [(v (formatShard! allFiles 4 1 "formatCorpusShard1Test"))]
       (do
         (assert v.corpusMatches "corpus is the tracked corpus minus exactly the seven listed misparse files")
         (assert v.excludedMatches "excluded files are exactly the listed seven")
         (assert (= v.size v.expectedShare) "shard 1 holds its exact share")
         (assert (= v.identical v.size) "every shard 1 file formats byte-identical through formatRepair")
         (= v.identical v.size)))))
