(module asl-checker/tests/fnHeaderDiagTest
  :x [runTests]
  :i [(asl-checker/hints :a hn) (asl-checker/check :a c) (asl-checker/types :a ty)])

; (:m :ref FABLE-LANG-02 :do "each non-canonical fn header shape is still rejected by check and maps to the canonical header line of that very function; canonical and legal paren forms map to nothing")

fn headers src: String -> String
  (stringJoin (map (fn [(f (Pair Int64 String))] -> String (str (stringFromInt64 (pairFirst f)) "=" (pairSecond f))) (hn/headerFixes src)) "|")

fn rejected? src: String -> Bool
  (not (listEmpty? (c/checkSource src (mapEmpty) "m.asl")))

fn runTests -> Bool
  (let [(defn "(defn add [a b]\n  (+ a b))\n")
        (define "(define (add a b)\n  (+ a b))\n")
        (def "(def add [a b]\n  (+ a b))\n")
        (wrapped "(fn add [a: Int64 b: String] -> Bool\n  true)\n")
        (pyDef "def add(a: Int64, b: String) -> Bool:\n  return true\n")
        (pyFn "fn add(a: Int64, b: (List String)) -> Bool:\n  return true\n")
        (body0 "fn add a: Int64 b: String -> Bool\nreturn true\n")
        (canon "fn add a: Int64 b: String -> Bool\n  true\n\nfn two -> Int64\n  2\n")
        (legal "(fn add [(a Int64)] -> Int64 a)\n")]
    (do (assert (rejected? defn) "defn is rejected by check")
        (assert (rejected? pyDef) "python def is rejected by check")
        (assert (rejected? body0) "column-0 body is rejected by check")
        (assert (stringContains? (headers defn) "1=fn add a: T b: T -> R") (str "defn header, got " (headers defn)))
        (assert (stringContains? (headers define) "1=fn add a: T b: T -> R") (str "define header, got " (headers define)))
        (assert (stringContains? (headers def) "1=fn add a: T b: T -> R") (str "def header, got " (headers def)))
        (assert (stringContains? (headers wrapped) "1=fn add a: Int64 b: String -> Bool") (str "wrapped header, got " (headers wrapped)))
        (assert (stringContains? (headers pyDef) "1=fn add a: Int64 b: String -> Bool") (str "python def header, got " (headers pyDef)))
        (assert (stringContains? (headers pyFn) "1=fn add a: Int64 b: (List String) -> Bool") (str "python fn header, got " (headers pyFn)))
        (assert (stringContains? (headers body0) "1=fn add a: Int64 b: String -> Bool") (str "column-0 body header, got " (headers body0)))
        (assert (stringEmpty? (headers canon)) (str "canonical file maps to nothing, got " (headers canon)))
        (assert (stringEmpty? (headers legal)) (str "legal paren fn maps to nothing, got " (headers legal)))
        true))
