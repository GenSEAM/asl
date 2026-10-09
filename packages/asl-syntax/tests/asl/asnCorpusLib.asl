(module asl-syntax/tests/asl/asnCorpusLib
  :x [runTrackedAsnShard!]
  :i [(asl-syntax/asl/asn :a asn)
      (asl-transpile/asn :a at)])

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn excludedAsnReason path: String -> String
  (if (= path "tests/harnessBench/ledger.asn")
    "at/asnRead does not terminate on this 668KB multi-form ledger, measured over 240s and killed; asn/asnRead rejects it in under a second"
    "")

fn checkOneAsnFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (mt (fileReadString path)
      ((err e)
       (do
         (assert false (str "read error for " path ": " e))
         (pair (+ checked 1) (+ mismatches 1))))
      ((ok src)
       (if (not (stringEmpty? (excludedAsnReason path)))
         (do
           (println (str "asn sweep: excluding " path " from transpile parity: " (excludedAsnReason path)))
           (assert (err? (asn/asnRead src)) (str "asn sweep: " path " excluded from parity but asn/asnRead must still reject it"))
           (pair (+ checked 1) mismatches))
         (let [(r1 (asn/asnRead src))
               (r2 (at/asnRead src))]
           (mt r2
             ((ok v2)
              (mt r1
                ((ok v1)
                 (let [(s1 (asn/asnWrite v1))
                       (s2 (at/asnWrite v2))]
                   (assert (= s1 s2) (str "asn sweep: " path " renders differ between asl-syntax and asl-transpile"))
                   (pair (+ checked 1) (+ mismatches (if (= s1 s2) 0 1)))))
                ((err _)
                 (do
                   (assert false (str "asn sweep: " path " asl-syntax rejected but asl-transpile accepted"))
                   (pair (+ checked 1) (+ mismatches 1))))))
             ((err _)
              (mt r1
                ((ok _)
                 (do
                   (assert false (str "asn sweep: " path " asl-syntax accepted but asl-transpile rejected"))
                   (pair (+ checked 1) (+ mismatches 1))))
                ((err _) (pair (+ checked 1) mismatches))))))))))


fn shardIndices n: Int64 shard: Int64 -> (List Int64)
  (filter (fn [(i Int64)] -> Bool (= (mod i 2) shard)) (range 0 n))

fn shardsPartition? n: Int64 -> Bool
  (= (listSort (listAppend (shardIndices n 0) (shardIndices n 1))) (range 0 n))

fn runTrackedAsnShard! shard: Int64 -> Bool
  (let [(cmdRes (processRun "git ls-files '*.asn' '*.asn.sample'"))
        (files (parseFileList cmdRes.stdout))
        (fileCount (listLength files))
        (indices (shardIndices fileCount shard))
        (expectedCount (if (< shard (mod fileCount 2)) (+ (/ fileCount 2) 1) (/ fileCount 2)))
        (stats (fold (fn [(acc (Pair Int64 Int64)) (i Int64)] -> (Pair Int64 Int64) (checkOneAsnFile! acc (optionOr (listGet files i) ""))) (pair 0 0) indices))
        (totalChecked (pairFirst stats))
        (mismatches (pairSecond stats))
        (label (str "shard " (stringFromInt64 shard) ": "))]
    (do
      (assert (= cmdRes.exitCode 0) (str label "git ls-files asn exited 0"))
      (assert (> fileCount 0) (str label "git ls-files listed tracked asn files"))
      (assert (shardsPartition? fileCount) (str label "the two shards are disjoint and cover all " (stringFromInt64 fileCount) " files"))
      (assert (and (= totalChecked expectedCount) (= mismatches 0)) (str label "checked " (stringFromInt64 expectedCount) " files with zero mismatches"))
      true))
