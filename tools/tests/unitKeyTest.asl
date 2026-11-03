(module asl-tools/tests/unitKeyTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr) (asl-ir/link :a lk)])

; (:m :ref LEONSERVE-COLD-START :do "the module cache key is root-relative inside a workspace and cannot alias: the same relative path and text under two roots shares a key; other text, another import interface or another toolchain fingerprint at the same relative path gets another key; two files outside the root keep their absolute paths apart")
fn unitAt path: String imports: (List (Pair String String)) -> lk/LinkUnit
  (lk/LinkUnit :path path :name "m/x" :forms (list) :positions (mapEmpty) :imports imports)

fn ! tempDir! -> String
  (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/unitKeyTest.XXXXXX" 5000) ""))

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
        (noIface (mapEmpty))
        (i1 (mapSet (mapEmpty) "dep" "iface1"))
        (i2 (mapSet (mapEmpty) "dep" "iface2"))
        (dep (list (pair "dep" "dep")))
        (kA (nt/unitKeyIn a "fp1" (unitAt pa (list)) noIface false (list)))
        (kB (nt/unitKeyIn b "fp1" (unitAt pb (list)) noIface false (list)))
        (kText (nt/unitKeyIn c "fp1" (unitAt pc (list)) noIface false (list)))
        (kI1 (nt/unitKeyIn a "fp1" (unitAt pa dep) i1 false (list)))
        (kI2 (nt/unitKeyIn a "fp1" (unitAt pa dep) i2 false (list)))
        (kImA (nt/unitKeyIn a "fp1" (unitAt pa (list (pair "dep" (str a "/m/d.asl")))) (mapSet (mapEmpty) (str a "/m/d.asl") "iface1") false (list)))
        (kImB (nt/unitKeyIn b "fp1" (unitAt pb (list (pair "dep" (str b "/m/d.asl")))) (mapSet (mapEmpty) (str b "/m/d.asl") "iface1") false (list)))
        (kFp (nt/unitKeyIn a "fp2" (unitAt pa (list)) noIface false (list)))
        (kOutA (nt/unitKeyIn c "fp1" (unitAt pa (list)) noIface false (list)))
        (kOutB (nt/unitKeyIn c "fp1" (unitAt pb (list)) noIface false (list)))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " a " " b " " c) 5000)))]
    (do
      (assert (= kA kB) "the same relative path and text under two roots shares one key")
      (assert (= kImA kImB) "an imported module is named by its root-relative path too, so importers share a key across roots")
      (assert (!= kA kText) "other module text at the same relative path gets another key")
      (assert (!= kI1 kI2) "another import interface at the same relative path gets another key")
      (assert (!= kA kFp) "another toolchain fingerprint gets another key")
      (assert (!= kOutA kOutB) "two files outside the given root keep their absolute paths apart")
      (assert removed "temp dirs removed")
      true))
