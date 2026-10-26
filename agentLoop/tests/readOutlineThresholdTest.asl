(module asl/agentLoop/tests/readOutlineThresholdTest
  :x [runTests]
  :i [(asl/agentLoop/aslOps :a o)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

; (:m :ref LEON-CAPS :do "the fake run answers every read with a short body and every outline with one item, so these asserts prove only which of the two the read op chooses from the file's byte size and the configured limit; the real outline text is the engine's and is not exercised here")
fn ! tempDir -> String
  (let [path (str "/tmp/asl-read-outline-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn fakeRun form: String root: String -> t/AslRun
  (if (stringContains? form ":intel :op outline")
    (t/aslRun 0 "(:intel :op outline (:item :name \"foo\" :kind \"fn\" :start 3 :end 5))" "")
    (t/aslRun 0 "(:read :file \"f\" :start 1 :content \"BODY\")" ""))

fn receiptFor op: String root: String -> String
  (o/serReceipt (o/execAslOpCustom! (c/parseKv op) (list) root (fn [] "rid") (fn [f] true) fakeRun 8000 none))

fn ! runTests -> Bool
  (let [root (tempDir)
        big (stringJoin (map (fn [i] (str "line " (stringFromInt64 i) " filler filler filler\n")) (range 1 800)) "")
        small (stringJoin (map (fn [i] (str "line " (stringFromInt64 i) "\n")) (range 1 60)) "")
        _a (fileWrite (str root "/big.txt") big)
        _b (fileWrite (str root "/small.txt") small)
        defaultBig (receiptFor "(:step :op \"read\" :file \"big.txt\")" root)
        defaultSmall (receiptFor "(:step :op \"read\" :file \"small.txt\")" root)
        bySymbol (receiptFor "(:step :op \"read\" :file \"big.txt\" :symbol \"foo\")" root)
        byRange (receiptFor "(:step :op \"read\" :file \"big.txt\" :start 1 :end 5)" root)
        _c (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:readOutlineBytes 100))\n")
        tuned (receiptFor "(:step :op \"read\" :file \"small.txt\")" root)
        tunedRange (receiptFor "(:step :op \"read\" :file \"small.txt\" :start 1 :end 5)" root)
        _d (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:readOutlineBytes 1000000))\n")
        raised (receiptFor "(:step :op \"read\" :file \"big.txt\")" root)]
    (do
      (assert (> (stringLength big) 16384) "the large fixture is above the default limit")
      (assert (< (stringLength small) 16384) "the small fixture is below the default limit")
      (assert (= (o/readOutlineBytes) 16384) "the default limit is 16 KB")
      (assert (and (stringContains? defaultBig "3-5 fn foo") (stringContains? defaultBig "whole-file limit")
                   (stringContains? defaultBig ":symbol")) "a whole-file read above 16 KB returns the outline and a read-by-symbol hint")
      (assert (and (stringContains? defaultSmall "BODY") (not (stringContains? defaultSmall "3-5 fn foo"))) "a whole-file read below the limit returns the body")
      (assert (and (stringContains? bySymbol "BODY") (not (stringContains? bySymbol "3-5 fn foo"))) "a read by symbol of a large file returns the section, not the outline")
      (assert (and (stringContains? byRange "BODY") (not (stringContains? byRange "3-5 fn foo"))) "a ranged read of a large file returns the range")
      (assert (stringContains? tuned "3-5 fn foo") "the configured limit makes a small file outline")
      (assert (and (stringContains? tunedRange "BODY") (not (stringContains? tunedRange "3-5 fn foo"))) "the configured limit leaves a ranged read alone")
      (assert (and (stringContains? raised "BODY") (not (stringContains? raised "3-5 fn foo"))) "a raised limit returns the large file whole")
      (assert (= (o/readOutlineBytesIn "(:agentLoop (:readOutlineBytes 321))") (some 321)) "the config key parses")
      (assert (none? (o/readOutlineBytesIn "(:agentLoop (:other 1))")) "an absent key falls back")
      (assert (ok? (pathRemove root)) "the scratch root is removed")
      true))
