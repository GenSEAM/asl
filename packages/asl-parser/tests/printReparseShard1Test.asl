(module asl-parser/tests/printReparseShard1Test
  :x [runTests]
  :i [(asl-parser/tests/printReparseLib :a lib)])

fn runShardFiles! files: (List String) stats: lib/CorpusStats -> lib/CorpusStats
  (if (listEmpty? files)
    stats
    (let [(f (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (runShardFiles! rest (lib/verifyCorpusFile! f stats))))

fn ! runTests -> Bool
  (mt (lib/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok allFiles)
     (let [(total (listLength allFiles))
           (n 8)
           (k 1)
           (shard (lib/shardFiles allFiles n k))
           (expected (lib/expectedShardCount total n k))
           (shardLen (listLength shard))]
       (do
         (assert (= shardLen expected) (str "shard " (stringFromInt64 k) " of " (stringFromInt64 n) " has expected share " (stringFromInt64 expected)))
         (let [(stats (runShardFiles! shard (lib/emptyCorpusStats!)))]
           (do
             (assert (= stats.checked shardLen) "checked count equals shard size")
             (lib/reportCorpusStats! "printReparseShard1Test" stats)))))))
