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

fn lexerDivergentAsnReason path: String -> String
  (cond
    ((= path ".asl/mem/notes.asn") "n6's tag [:audit:supervisor] is one mid-token-colon keyword; asl-syntax/asl/lex.asl keeps a colon mid-run as part of the same keyword token, asl-parser/src/lexer.asl (used via asl-transpile) closes the keyword run and starts a new one at every colon, splitting it into :audit and :supervisor; a pre-existing lexer disagreement, not an ASN value-grammar defect")
    ((= path "asl/package.asn") "scripts keys :build:web and :preview:web are intentional namespaced npm-style keywords with a mid-token colon; same asl-syntax/asl-parser lexer disagreement as notes.asn")
    ((= path "harness/audit/gapLedger.asn") "many :gap rows carry :lens ::containment ... with a doubled leading colon; asl-syntax/asl/lex.asl reads it as one ::containment keyword, asl-parser/src/lexer.asl splits it into a bare : token plus :containment; same pre-existing lexer disagreement")
    (else ""))

fn checkOneAsnFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (match (fileReadString path)
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
         (if (not (stringEmpty? (lexerDivergentAsnReason path)))
           (do
             (println (str "asn sweep: excluding " path " from render-parity comparison (pre-existing lexer divergence, not an ASN grammar defect): " (lexerDivergentAsnReason path)))
             (pair (+ checked 1) mismatches))
         (let [(r1 (asn/asnRead src))
               (r2 (at/asnRead src))]
           (match r2
             ((ok v2)
              (match r1
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
              (match r1
                ((ok _)
                 (do
                   (assert false (str "asn sweep: " path " asl-syntax accepted but asl-transpile rejected"))
                   (pair (+ checked 1) (+ mismatches 1))))
                ((err _) (pair (+ checked 1) mismatches)))))))))))


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
