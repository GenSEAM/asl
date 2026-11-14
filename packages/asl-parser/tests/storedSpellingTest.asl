(module asl-parser/tests/storedSpellingTest
  :x [runTests]
  :i [(asl-parser/ast :a a)])

; (:m :ref MISS-ABSORB :do "stored text stays canonical: the reader takes (== a b) and (% a b) from a model, asl heal writes them as = and mod, and this audit fails on any stored source that still holds one; the trees are walked in process, model replies kept as fixtures are not stored code")
fn roots -> (List String)
  (list "asl/packages" "asl/prelude" "asl/tools" "asl/grammar" "asl/examples" "asl/web" "asl/bench" "tools" "harness")

fn skippedDir? name: String -> Bool
  (listContains? (list "out" "node_modules" ".git" "dist" "results" "misses") name)

fn keeps -> (List String)
  (list "asl/packages/asl-parser/tests/acceptedHeadMeaningTest.asl")

fn ! isDir? path: String -> Bool
  (match (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! sourcesUnder dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (listFlatMap (fn [(n String)] -> (List String)
                     (let [(p (str dir "/" n))]
                       (cond
                         ((isDir? p) (if (skippedDir? n) (list) (sourcesUnder p)))
                         ((stringEndsWith? n ".asl") (list p))
                         (else (list)))))
                   (listSort names))))

fn foreignHead? e: a/ParseError -> Bool
  (or (stringStartsWith? e.msg "ERR_READ_SPELLING (== ") (stringStartsWith? e.msg "ERR_READ_SPELLING (% "))

fn held path: String text: String -> (List String)
  (if (not (or (stringContains? text "==") (stringContains? text "%")))
    (list)
    (map (fn [(e a/ParseError)] -> String (str path ":" (stringFromInt64 e.line) ":" (stringFromInt64 e.col)))
         (filter foreignHead? (a/spellingErrors text))))

fn ! heldIn path: String -> (List String)
  (match (fileReadString path) ((ok t) (held path t)) ((err _) (list)))

fn ! runTests -> Bool
  (let [(files (listFlatMap sourcesUnder (roots)))
        (stored (filter (fn [(p String)] -> Bool (not (listContains? (keeps) p))) files))
        (found (listFlatMap heldIn stored))]
    (do
      (assert (listContains? files "asl/packages/asl-parser/src/ast.asl") "the walk reaches the package sources")
      (assert (listContains? files "asl/packages/asl-parser/tests/storedSpellingTest.asl") "and the tests, this file among them")
      (assert (listContains? files "asl/prelude/prelude.asl") "and the prelude")
      (assert (= (held "x.asl" "fn f a: Int64 -> Bool\n  (== (% a 2) 0)\n") (list "x.asl:2:4" "x.asl:2:8")) "a planted (== ...) and (% ...) are both named with their place")
      (assert (listEmpty? (held "x.asl" "fn f a: Int64 -> Bool\n  (= (mod a 2) 0)\n")) "the canonical text is clean")
      (assert (listEmpty? (held "x.asl" "fn f -> String\n  \"(== 1 2) 50%\"\n")) "strings are not code")
      (assert (listEmpty? found) (str "stored sources hold a foreign head; run asl heal on them: " (stringJoin (listTake found 20) " ")))
      (assert (not (listEmpty? (listFlatMap heldIn (keeps)))) "the one kept file still holds the heads its test executes; drop it from keeps when it stops")
      true))
