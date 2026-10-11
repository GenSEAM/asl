(module asl-checker/tests/typeParityBucketsTest
  :x [runTests]
  :i [(types :a ty) (check :a c)])

fn typeDiags src: String -> (List ty/Diagnostic)
  (filter (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "type") (= d.code "rule-6"))) (c/checkSource src (mapEmpty) "bucket.asl"))

fn texts ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code "@" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " " d.message)) ds) "; ")

fn accepts? src: String -> Bool
  (let [(ds (typeDiags src))] (do (assert (listEmpty? ds) (str "host-accepted source type-checks: " (texts ds))) true))

fn rejects? src: String needle: String -> Bool
  (let [(ds (typeDiags src))] (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message needle)) ds) (str "a real mismatch still reports " needle ": " (texts ds))) true))

fn testUnknownTypeName -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f -> (Pair Int64 Int64)\n  (fold (fn [(acc (pair Int64 Int64)) (x Int64)] -> (pair Int64 Int64) (pair (+ (pairFirst acc) x) 0)) (pair 0 0) (list 1 2))\n") "a fold accumulator annotated (pair Int64 Int64) takes a Pair")
      (assert (accepts? "(module b :x [g])\nfn g p: (pair String Int64) -> (Pair String Int64)\n  p\n") "(pair String Int64) is accepted where (Pair String Int64) is wanted")
      (assert (accepts? "(module b :x [h k])\nfn h a: Any b: Any -> Int64\n  0\nfn k -> Int64\n  (h \"s\" 1)\n") "two Any parameters take a String and an Int64")
      (assert (accepts? "(module b :x [h k])\nfn h f: (Fn Int64 Bool) -> Bool\n  true\nfn k -> Bool\n  (h (fn [(x Int64)] -> Bool (> x 0)))\n") "an (Fn Int64 Bool) parameter takes a lambda")
      (assert (accepts? "(module b :x [f])\nfn f a: Any -> String\n  (.-name a)\n") "a field of an Any value is unknown, not a missing record")
      (assert (accepts? "(module b :x [f])\nfn f -> List\n  (list 1 2)\n") "a bare List, without its argument, takes a (List Int64)")
      (assert (rejects? "(module b :x [g])\nfn g p: String -> Int64\n  p\n" "expected Int64, found String") "a resolved String is still not an Int64")
      (assert (rejects? "(module b :x [g])\nfn g p: (Pair String Int64) -> (Pair Int64 Int64)\n  p\n" "expected Int64, found String") "(Pair String Int64) is still not (Pair Int64 Int64)")
      true)

fn testAssertTrap -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f o: (Option Int64) -> Bool\n  (mt o ((some _) true) ((none) (assert false \"no value\")))\n") "an assert false arm joins a Bool arm")
      (assert (accepts? "(module b :x [f])\nfn f o: (Option Int64) -> Bool\n  (mt o ((none) (refute true \"no value\")) ((some _) true))\n") "a refute true arm joins a Bool arm")
      (assert (rejects? "(module b :x [f])\nfn f o: (Option Int64) -> Bool\n  (mt o ((some _) true) ((none) (assert true \"value\")))\n" "Unit") "an assert that can pass is Unit, not Bool")
      true)

fn testPrintReturnsUnit -> Bool
  (do (assert (accepts? "(module b :x [h])\nfn ! h -> Unit\n  (println \"x\")\n") "println is Unit")
      (assert (accepts? "(module b :x [h])\nfn ! h n: Int64 -> Unit\n  (if (> n 0) (eprintln n) ())\n") "eprintln of an Int64 joins a Unit branch")
      (assert (rejects? "(module b :x [h])\nfn ! h -> Bool\n  (println \"x\")\n" "Unit") "println is still not a Bool")
      true)

fn testNullaryCaseValue -> Bool
  (let [(enumSrc "(module b :x [f])\n(enum Ev (:c start [] \"s\") (:c stop [(n Int64)] \"t\"))\nfn take e: Ev -> Bool\n  true\n")]
    (do (assert (accepts? (str enumSrc "fn f -> Bool\n  (take start)\n")) "a bare nullary constructor is an Ev")
        (assert (accepts? (str enumSrc "fn f -> Bool\n  (take (start))\n")) "a called nullary constructor is an Ev")
        (assert (accepts? (str enumSrc "fn f -> Bool\n  (take (stop 1))\n")) "a constructor with a field still takes its argument")
        (assert (rejects? (str enumSrc "fn zero -> Ev\n  start\nfn f -> Bool\n  (take zero)\n") "found (fn [] -> Ev)") "a zero-argument function named as a value stays a function")
        true))

fn testEffectfulFnType -> Bool
  (let [(src "(module b :x [run k])\n(schema H (:f run (fn ! [Int64] -> Bool)))\nfn ! run h: H -> Bool\n  (h.run 1)\nfn k f: (fn ! [Int64] -> Bool) -> H\n  (H :run f)\n")]
    (do (assert (accepts? src) "a (fn ! [Int64] -> Bool) field is called with one Int64 and filled by a matching parameter")
        (assert (accepts? "(module b :x [k g])\nfn k f: (fn ! [Int64] -> Bool) -> Bool\n  true\nfn g -> Bool\n  (k (fn ! [(x Int64)] -> Bool true))\n") "an effectful lambda fills a (fn ! [Int64] -> Bool) parameter")
        (assert (rejects? "(module b :x [k g])\nfn k f: (fn ! [Int64] -> Bool) -> Bool\n  true\nfn g -> Bool\n  (k (fn ! [(x String)] -> Bool true))\n" "expected Int64, found String") "its parameter type is still checked")
        true))

fn testUnitParensAnnotation -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn ! f xs: (List Int64) -> (List Unit)\n  (map (fn [(x Int64)] -> () (println x)) xs)\n") "a lambda returning () takes a println body")
      (assert (accepts? "(module b :x [f])\nfn f p: (Pair () Int64) -> Unit\n  (pairFirst p)\n") "() nested in a type argument is Unit")
      (assert (rejects? "(module b :x [f])\nfn f -> Bool\n  ((fn [(x Int64)] -> () ()) 1)\n" "Unit") "a () result is still not a Bool")
      true)

fn ! fileCodes path: String -> (List String)
  (mt (c/checkFile! path (list "."))
    ((ok ds) (map (fn [(d ty/Diagnostic)] -> String d.code) ds))
    ((err _) (list "READ_ERROR")))

fn ! testTypeBoundary -> Bool
  (let [(both (fileCodes "tests/conformance/check/compileErrorKeepsTypeBoundary.asl"))
        (dir (optionOr (envGet "TMPDIR") "/tmp"))
        (path (str dir "/typeBoundaryOnly" (stringFromInt64 (procSelf)) ".asl"))
        (written (fileWrite path "(module typeBoundaryOnly :x [mismatched])\n\nfn mismatched -> Bool\n  (if 1 true false)\n"))
        (only (fileCodes path))
        (removed (pathRemove path))]
    (do (assert (ok? written) "the type-only fixture is written")
        (assert (= both (list "ERR_UNKNOWN_SYMBOL")) (str "an unknown symbol keeps the type mismatch behind it: " (stringJoin both " ")))
        (assert (= only (list "ERR_TYPE_MISMATCH")) (str "a file with only a type error reports it: " (stringJoin only " ")))
        (assert (ok? removed) "the type-only fixture is removed")
        true))

fn testIoErrorPayloads -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn ! f p: String -> (Result String String)\n  (mt (fileReadString p) ((ok s) (ok s)) ((err e) (err e)))\n") "a fileReadString error is a String")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> (Result Int64 String)\n  (mt (fileReadBytes p) ((ok b) (ok (bytesLength b))) ((err e) (err e)))\n") "a fileReadBytes error is a String")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> (Result Unit String)\n  (mt (fileWrite p \"x\") ((ok u) (ok u)) ((err e) (err (str \"write: \" e))))\n") "a fileWrite error is a String")
      (assert (rejects? "(module b :x [f])\nfn ! f p: String -> (Result String String)\n  (mt (fileRead p) ((ok s) (ok s)) ((err e) (err e)))\n" "IoError") "a fileRead error is still an IoError")
      true)

fn testTextKind -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn ! f p: String b: Bytes -> (Result Unit String)\n  (fileWrite p b)\n") "fileWrite takes Bytes content")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> (Result Unit String)\n  (fileAppend p \"line\")\n") "fileAppend takes String content")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> (Result Unit String)\n  (fileAppend p (stringToBytes \"line\"))\n") "fileAppend takes Bytes content")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String xs: (List Bytes) -> Bool\n  (fold (fn [(acc Bool) (b Bytes)] -> Bool (and acc (ok? (fileWrite p b)))) true xs)\n") "fileWrite of Bytes inside a fold over (List Bytes)")
      (assert (rejects? "(module b :x [f])\nfn ! f p: String n: Int64 -> (Result Unit String)\n  (fileWrite p n)\n" "expected String or Bytes, found Int64") "fileWrite of an Int64 is still a mismatch")
      (assert (rejects? "(module b :x [f])\nfn ! f p: String -> (Result Unit String)\n  (fileAppend p (list \"a\"))\n" "expected String or Bytes") "fileAppend of a List is still a mismatch")
      (assert (rejects? "(module b :x [f])\nfn ! f p: String -> (Result Unit String)\n  (fileWrite p (fn [(x Int64)] -> Int64 x))\n" "found a function") "fileWrite of a function is still a mismatch")
      true)

fn testMiscChecker -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f -> Int64\n  (let [(none 5)] (+ none 1))\n") "a local none is the bound value")
      (assert (rejects? "(module b :x [f])\nfn f -> Int64\n  none\n" "Option") "an unbound none is still the Option")
      (assert (accepts? "(module b :x [quote g])\nfn quote s: String -> String\n  s\nfn g -> Int64\n  (stringLength (quote \"a\"))\n") "a module fn quote is called, not quoted")
      (assert (rejects? "(module b :x [g])\nfn g -> Int64\n  (stringLength (quote a))\n" "SExpr") "without a fn quote, quote is still the SExpr form")
      (assert (accepts? "(module b :x [f])\nfn f fs: (List (fn [] -> Int64)) -> (List Int64)\n  (map (fn [g] (g)) fs)\n") "(g) of an unannotated g yields the closure result")
      (assert (rejects? "(module b :x [f])\nfn f fs: (List (fn [] -> Int64)) -> (List String)\n  (map (fn [g] (g)) fs)\n" "Int64") "the closure result still has its type")
      (assert (accepts? "(module b :x [f])\nfn ! f -> Int64\n  (mt (procSpawnv (list \"true\") (none) (none)) ((ok p) p.pid) ((err _) 0))\n") "SpawnedProc has pid")
      (assert (rejects? "(module b :x [f])\nfn ! f -> Int64\n  (mt (procSpawnv (list \"true\") (none) (none)) ((ok p) p.name) ((err _) 0))\n" "no field name") "SpawnedProc has no field name")
      (assert (accepts? "(module b :x [f])\nfn ! f -> Int64\n  (resultOr (cpuCount) 1)\n") "cpuCount is a Result")
      (assert (rejects? "(module b :x [f])\nfn ! f -> Int64\n  (cpuCount)\n" "Result") "cpuCount is not a bare Int64")
      true)

fn ! runTests -> Bool
  (do (assert (testUnknownTypeName) "bucket unknownType")
      (assert (testAssertTrap) "bucket assertTrap")
      (assert (testPrintReturnsUnit) "bucket printUnit")
      (assert (testNullaryCaseValue) "bucket nullaryCase")
      (assert (testEffectfulFnType) "bucket fnBang")
      (assert (testUnitParensAnnotation) "bucket unitParens")
      (assert (testTypeBoundary) "bucket typeBoundary")
      (assert (testIoErrorPayloads) "bucket ioErrString")
      (assert (testTextKind) "bucket textKind")
      (assert (testMiscChecker) "bucket misc")
      true)
