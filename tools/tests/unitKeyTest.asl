(module asl-tools/tests/unitKeyTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr) (asl-ir/link :a lk) (asl-parser/ast :a ast)])

; (:m :ref LEONSERVE-COLD-START :do "the module cache key is root-relative inside a workspace and cannot alias: the same relative path and text under two roots shares a key; other text, another import interface or another toolchain fingerprint or opt level at the same relative path gets another key; two files outside the root keep their absolute paths apart")
fn unitAt path: String imports: (List (Pair String String)) -> lk/LinkUnit
  (lk/LinkUnit :path path :name "m/x" :forms (list) :positions (mapEmpty) :imports imports)

fn ! tempDir! -> String
  (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/unitKeyTest.XXXXXX" 5000) ""))

fn ! put! root: String text: String -> String
  (do (fr/shellOut (str "/bin/mkdir -p " root "/m") 5000)
      (fileWrite (str root "/m/x.asl") text)
      (str root "/m/x.asl"))

; (:m :ref NATIVETEST-CACHE-KEY-IMPORTS-20261022 :do "the digest a unit key takes per import covers the import closure: a imports b imports c, and an interface edit in c moves a's digest and a's object key, a body edit in c moves neither, and the digest does not depend on the root or on the order of the units")
fn unitOf root: String leaf: String text: String imports: (List String) -> lk/LinkUnit
  (lk/LinkUnit :path (str root "/m/" leaf ".asl") :name (str "m/" leaf) :forms (resultOr (ast/parse text) (list)) :positions (mapEmpty)
               :imports (map (fn [(i String)] -> (Pair String String) (pair (str "m/" i) (str root "/m/" i ".asl"))) imports))

fn recC fieldType: String extra: String -> String
  (str "(module m/c\n  :x [Rec]\n  :i [])\n\n(schema Rec\n  (:f x " fieldType "))\n" extra)

fn chain root: String cText: String -> (List lk/LinkUnit)
  (list (unitOf root "c" cText (list))
        (unitOf root "b" "(module m/b\n  :x [make]\n  :i [(m/c :a oc)])\n\nfn make -> oc/Rec\n  (oc/Rec :x 1)\n" (list "c"))
        (unitOf root "a" "(module m/a\n  :x [run]\n  :i [(m/b :a ob)])\n\nfn run -> Int64\n  1\n" (list "b")))

fn digestOf units: (List lk/LinkUnit) path: String -> String
  (optionOr (mapGet (nt/ifaceMapOf units) path) "absent")

fn ! testImportClosure -> Bool
  (let [(intC (chain "/r" (recC "Int64" "")))
        (strC (chain "/r" (recC "String" "")))
        (bodyC (chain "/r" (recC "Int64" "\nfn hidden -> Int64\n  2\n")))
        (otherRoot (chain "/elsewhere/w" (recC "Int64" "")))
        (a "/r/m/a.asl")
        (b "/r/m/b.asl")
        (aUnit (optionOr (listGet intC 2) (lk/emptyUnit "")))
        (kInt (nt/unitKeyIn "/r" "fp1" "-O1" aUnit (nt/ifaceMapOf intC) false (list)))
        (kStr (nt/unitKeyIn "/r" "fp1" "-O1" aUnit (nt/ifaceMapOf strC) false (list)))
        (kBody (nt/unitKeyIn "/r" "fp1" "-O1" aUnit (nt/ifaceMapOf bodyC) false (list)))
        (loop (list (unitOf "/r" "p" "(module m/p\n  :x []\n  :i [(m/q :a q)])\n" (list "q"))
                    (unitOf "/r" "q" "(module m/q\n  :x []\n  :i [(m/p :a p)])\n" (list "p"))))]
    (do
      (assert (= (listLength aUnit.forms) 2) "the fixture modules parse")
      (assert (!= (digestOf intC b) (digestOf strC b)) "a direct importer's digest moves with the imported interface")
      (assert (!= (digestOf intC a) (digestOf strC a)) "an interface edit two imports away moves the digest of the unit that reaches it")
      (assert (!= kInt kStr) "and gives that unit another object key")
      (assert (= (digestOf intC a) (digestOf bodyC a)) "a body edit two imports away keeps the digest")
      (assert (= kInt kBody) "and keeps the object key")
      (assert (= (digestOf intC a) (digestOf (listReverse intC) a)) "the digest does not depend on the order of the units")
      (assert (= (digestOf intC a) (digestOf otherRoot "/elsewhere/w/m/a.asl")) "the digest holds no absolute path, so another root shares it")
      (assert (!= (digestOf intC a) "absent") "every unit has a digest")
      (assert (!= (digestOf loop "/r/m/p.asl") (digestOf loop "/r/m/q.asl")) "an import cycle ends with a digest per unit")
      (assert (= (nt/initsInUnitOrder (list "/r/m/c.asl" "/r/m/b.asl" "/r/m/a.asl") (list (pair "/r/m/a.asl" "m/a") (pair "/r/m/b.asl" "") (pair "/r/m/c.asl" "m/c"))) (list "m/c" "m/a"))
              "inits follow the closure order of their units whatever order the objects settled in, and a unit without an init adds none")
      (assert (= (nt/initsInUnitOrder (list "/r/m/c.asl" "/r/m/b.asl" "/r/m/a.asl") (list (pair "/r/m/c.asl" "m/c") (pair "/r/m/a.asl" "m/a"))) (list "m/c" "m/a"))
              "the same units settled in closure order give the same inits")
      true))

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
        (kA (nt/unitKeyIn a "fp1" "-O2" (unitAt pa (list)) noIface false (list)))
        (kB (nt/unitKeyIn b "fp1" "-O2" (unitAt pb (list)) noIface false (list)))
        (kText (nt/unitKeyIn c "fp1" "-O2" (unitAt pc (list)) noIface false (list)))
        (kI1 (nt/unitKeyIn a "fp1" "-O2" (unitAt pa dep) i1 false (list)))
        (kI2 (nt/unitKeyIn a "fp1" "-O2" (unitAt pa dep) i2 false (list)))
        (kImA (nt/unitKeyIn a "fp1" "-O2" (unitAt pa (list (pair "dep" (str a "/m/d.asl")))) (mapSet (mapEmpty) (str a "/m/d.asl") "iface1") false (list)))
        (kImB (nt/unitKeyIn b "fp1" "-O2" (unitAt pb (list (pair "dep" (str b "/m/d.asl")))) (mapSet (mapEmpty) (str b "/m/d.asl") "iface1") false (list)))
        (kFp (nt/unitKeyIn a "fp2" "-O2" (unitAt pa (list)) noIface false (list)))
        (kOutA (nt/unitKeyIn c "fp1" "-O2" (unitAt pa (list)) noIface false (list)))
        (kOutB (nt/unitKeyIn c "fp1" "-O2" (unitAt pb (list)) noIface false (list)))
        (kO1 (nt/unitKeyIn a "fp1" "-O1" (unitAt pa (list)) noIface false (list)))
        (kO1Again (nt/unitKeyIn a "fp1" "-O1" (unitAt pa (list)) noIface false (list)))
        (kEntryO1 (nt/unitKeyIn a "fp1" "-O1" (unitAt pa (list)) noIface true (list "i")))
        (kEntryO2 (nt/unitKeyIn a "fp1" "-O2" (unitAt pa (list)) noIface true (list "i")))
        (rc (nt/rcTag (nt/rcModeFor! "t/x.asl")))
        (slotO1 (nt/suiteSlotKeyIn "/w/a" "test" "-O1" rc "t/x.asl" "aa"))
        (slotO2 (nt/suiteSlotKeyIn "/w/a" "test" "-O2" rc "t/x.asl" "aa"))
        (slotO1Again (nt/suiteSlotKeyIn "/w/a" "test" "-O1" rc "t/x.asl" "aa"))
        (slotLive (nt/suiteSlotKey "test" "t/x.asl" pa))
        (slotLiveExpect (nt/suiteSlotKeyIn (nt/treeOf ".") "test" (nt/optLevelFor "test") rc "t/x.asl" (nt/fileDigest pa)))
        (slotLiveOther (nt/suiteSlotKeyIn (nt/treeOf ".") "test" (if (= (nt/optLevelFor "test") "-O3") "-O2" "-O3") rc "t/x.asl" (nt/fileDigest pa)))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " a " " b " " c) 5000)))]
    (do
      (assert (= kA kB) "the same relative path and text under two roots shares one key")
      (assert (= kImA kImB) "an imported module is named by its root-relative path too, so importers share a key across roots")
      (assert (!= kA kText) "other module text at the same relative path gets another key")
      (assert (!= kI1 kI2) "another import interface at the same relative path gets another key")
      (assert (!= kA kFp) "another toolchain fingerprint gets another key")
      (assert (!= kOutA kOutB) "two files outside the given root keep their absolute paths apart")
      (assert (!= kA kO1) "an -O1 object (test mode) and an -O2 object (run mode) of the same module get different keys")
      (assert (= kO1 kO1Again) "the same opt level gives the same key")
      (assert (!= kEntryO1 kEntryO2) "the entry object is keyed by opt level too")
      (assert (= (nt/optLevelFor "test") (optionOr (envGet "ASL_NATIVE_OPT") "-O1")) "test mode compiles at -O1 unless ASL_NATIVE_OPT says otherwise")
      (assert (= (nt/optLevelFor "run") (optionOr (envGet "ASL_NATIVE_OPT") "-O2")) "run mode compiles at -O2 unless ASL_NATIVE_OPT says otherwise")
      (assert (!= slotO1 slotO2) "suite slot keys differ when the opt level (ASL_NATIVE_OPT) differs")
      (assert (= slotO1 slotO1Again) "the same opt level gives the same suite slot key")
      (assert (= slotLive slotLiveExpect) "suiteSlotKey keys the slot by optLevelFor of its mode")
      (assert (!= slotLive slotLiveOther) "suiteSlotKey under another opt level is another slot")
      (assert removed "temp dirs removed")
      (testImportClosure)))
