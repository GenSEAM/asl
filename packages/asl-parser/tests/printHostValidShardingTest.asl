(module asl-parser/tests/printHostValidShardingTest
  :x [runTests]
  :i [(asl-parser/tests/printReparseLib :a prl)
      (asl-parser/tests/printHostValidScope :a scope)
      (asl-syntax/tests/asl/layoutCorpusLib :a lcl)])

fn slotsOf files: (List String) n: Int64 -> (List (Pair String Int64))
  (map (fn [(p String)] -> (Pair String Int64) (pair p (lcl/pathShard p n))) files)

fn allShards files: (List String) n: Int64 -> (List String)
  (fold (fn [(acc (List String)) (k Int64)] -> (List String) (listAppend acc (lcl/shardFilesByPath files n k))) (list) (range 1 (+ n 1)))

fn sample -> (List String)
  (list "asl/prelude/prelude.asl" "asl/packages/asl-parser/src/ast.asl" "tools/preCommit.asl" "tests/acceptance/d81/Task44002.asl" "asl/packages/asl-http/src/http2.asl")

; (:m :ref PRINT-SHARD-BASE-RED :do "the corpus assertions run on the tracked tree: a file added to it moves no other file, the sixteen shards hold every file once, and none is empty or more than twice the mean")
fn ! runTests -> Bool
  (match (prl/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok files)
     (let [(n 16)
           (total (listLength files))
           (sizes (lcl/shardSizesByPath files n))
           (grown (listAppend (list "aaa/newFirst.asl") (listAppend files (list "zzz/newLast.asl"))))
           (before (slotsOf files n))
           (after (filter (fn [(x (Pair String Int64))] -> Bool (listContains? files (pairFirst x))) (slotsOf grown n)))
           (rejected (filter (fn [(p String)] -> Bool (listContains? files p)) (scope/intentionallyRejectedPaths)))]
       (do
         (print (str "(:printHostValidSharding :corpus " (stringFromInt64 total) " :shardSizes (" (stringJoin (map stringFromInt64 sizes) " ") "))\n"))
         (assert (= (map (fn [(p String)] -> Int64 (lcl/pathShard p 16)) (sample)) (list 8 3 15 0 3)) (str "a path's shard is a fixed function of the path: " (stringJoin (map (fn [(p String)] -> String (stringFromInt64 (lcl/pathShard p 16))) (sample)) " ")))
         (assert (= before after) "adding tracked files before and after the corpus moves no file to another shard")
         (assert (= (listSort (allShards files n)) (listSort files)) "the sixteen shards together are the corpus, each file once")
         (assert (= (listSum sizes) total) (str "shard sizes add up to the corpus: " (stringFromInt64 (listSum sizes)) " of " (stringFromInt64 total)))
         (assert (listAll? (fn [(s Int64)] -> Bool (and (> s 0) (<= (* s n) (* 2 total)))) sizes) (str "no shard is empty or above twice the mean: " (stringJoin (map stringFromInt64 sizes) " ")))
         (assert (listEmpty? rejected) (str "an intentionally rejected fixture is outside the corpus: " (stringJoin rejected " ")))
         true))))
