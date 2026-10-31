(module asl-checker/tests/stampKeyTest
  :x [runTests]
  :i [(asl-checker/checkCached :a cc) (asl-tools/fleet/run :a fr)])

; (:m :ref LEONSERVE-COLD-START :do "the clean-closure stamp key is base-relative and cannot alias: the same relative path and bytes under two bases share a key; other bytes, another checker id, or a file outside the base (kept absolute) give another key")
fn ! tempDir! -> String
  (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/stampKeyTest.XXXXXX" 5000) ""))

fn ! put! root: String text: String -> String
  (do (fr/shellOut (str "/bin/mkdir -p " root "/m") 5000)
      (fileWrite (str root "/m/x.asl") text)
      (str root "/m/x.asl"))

fn ! runTests -> Bool
  (let [(a (tempDir!))
        (b (tempDir!))
        (c (tempDir!))
        (pa (put! a "(module m/x :x [] :i [])"))
        (pb (put! b "(module m/x :x [] :i [])"))
        (pc (put! c "(module m/x :x [f] :i [])"))
        (kA (cc/stampKeyIn! a "cli-1" (list pa)))
        (kB (cc/stampKeyIn! b "cli-1" (list pb)))
        (kText (cc/stampKeyIn! c "cli-1" (list pc)))
        (kId (cc/stampKeyIn! a "cli-2" (list pa)))
        (kOutA (cc/stampKeyIn! c "cli-1" (list pa)))
        (kOutB (cc/stampKeyIn! c "cli-1" (list pb)))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " a " " b " " c) 5000)))]
    (do
      (assert (and (some? kA) (= kA kB)) "the same relative path and bytes under two bases share one stamp key")
      (assert (!= kA kText) "other bytes at the same relative path give another key")
      (assert (!= kA kId) "another checker id gives another key")
      (assert (!= kOutA kOutB) "two files outside the base keep their absolute paths apart")
      (assert removed "temp dirs removed")
      true))
