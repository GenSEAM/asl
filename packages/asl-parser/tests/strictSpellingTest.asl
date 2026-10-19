(module asl-parser/tests/strictSpellingTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-parser/astConverter :a cv) (asl-parser/reader :a rd)])

fn messages src: String -> (List String)
  (map (fn [(e a/ParseError)] -> String e.msg) (a/spellingErrors src))

fn first src: String -> String
  (optionOr (listHead (messages src)) "")

fn parseMsg src: String -> String
  (match (a/parse src) ((ok _) "ok") ((err e) e.msg))

fn checkMsg src: String -> String
  (match (a/parseForTypeCheck src) ((ok _) "ok") ((err e) e.msg))

fn strictHeader -> String
  "(module m :spelling strict :x [f])\n"

fn armCount src: String -> Int64
  (match (cv/lift (rd/parseSexpr src)) ((a/exprMatch _ arms) (listLength arms)) (_ -1))

fn ! runTests -> Bool
  (let [(oldMatch "fn f x: Int64 -> Int64\n  (mt x (1 2) (_ 3))\n")
        (newMatch "fn f x: Int64 -> Int64\n  (match x (1 2) (_ 3))\n")]
    (do
      (assert (= (first oldMatch) "ERR_READ_SPELLING (mt subject arm ...) is retired: write (match subject arm ...)") (str "mt names match: " (first oldMatch)))
      (assert (listEmpty? (messages newMatch)) "match is the spelling")
      (assert (= (first "fn f -> Bool\n  (== 1 2)\n") "ERR_READ_SPELLING (== a b) is retired: write (= a b)") "== names =")
      (assert (= (first "fn f -> Bool\n  (not= 1 2)\n") "ERR_READ_SPELLING (not= a b) is retired: write (!= a b)") "not= names !=")
      (assert (= (first "fn ! sh c: String -> Int64\n  0\n") "ERR_READ_SPELLING fn ! sh is retired: write fn sh!") "fn ! name names fn name!")
      (assert (= (first "fn ! run! -> Int64\n  0\n") "ERR_READ_SPELLING fn ! run! is retired: write fn run!") "an already banged name keeps its spelling in the hint")
      (assert (= (first "fn tailrec ! go n: Int64 -> Int64\n  n\n") "ERR_READ_SPELLING fn ! go is retired: write fn go!") "the mark after tailrec is found")
      (assert (= (first "fn ! main args: (List String) -> Int64\n  0\n") "ERR_READ_SPELLING fn ! main is retired: write fn main") "an entry point drops the mark")
      (assert (= (first "(fn ! f [] -> Int64 0)\n") "ERR_READ_SPELLING fn ! f is retired: write fn f!") "the paren form is found")
      (assert (listEmpty? (messages "fn run! -> Int64\n  0\n")) "fn name! is the spelling")
      (assert (listEmpty? (messages "(schema H (:f run (fn ! [Int64] -> Bool)))\n")) "an effectful fn type is not a definition")
      (assert (listEmpty? (messages "fn f -> Int64\n  (let [(mt 1)] mt)\n")) "a let binder named mt is an ordinary name")
      (assert (= (listLength (messages "fn f -> Int64\n  (let [a (mt x (_ 1))] (== a 1))\n")) 2) "values of flat bindings are checked")
      (assert (listEmpty? (messages "fn f -> String\n  \"(mt x) fn ! y (== 1 2)\"\n")) "strings are not code")
      (assert (= (parseMsg oldMatch) "ok") "strict spelling is off by default")
      (assert (not (a/strictSpellingDefault)) "the global switch is off until the codemod lands")
      (assert (= (parseMsg (str (strictHeader) oldMatch)) "ERR_READ_SPELLING (mt subject arm ...) is retired: write (match subject arm ...)") "a module opting in rejects mt on parse")
      (assert (= (checkMsg (str (strictHeader) "fn ! f -> Int64\n  0\n")) "ERR_READ_SPELLING fn ! f is retired: write fn f!") "and on the checker parse")
      (assert (= (parseMsg (str (strictHeader) newMatch)) "ok") "the opted-in module reads with the new spellings")
      (assert (= (match (a/parse (str (strictHeader) oldMatch)) ((ok _) 0) ((err e) e.line)) 3) "the error points at the line")
      (assert (= (armCount "(match x ((some v) (f v)))") 1) "a one-arm match whose body is a call keeps one arm")
      (assert (= (armCount "(match x ((some v) (f v)) ((none) 0))") 2) "a two-arm match keeps two arms")
      (assert (= (first "fn f! -> Unit\n  (println \"x\")\n") "ERR_READ_SPELLING (println ...) is retired: an effectful builtin carries !, write (println! ...)") (str "an unbanged effectful builtin names its banged spelling: " (first "fn f! -> Unit\n  (println \"x\")\n")))
      (assert (listEmpty? (messages "fn f! -> Unit\n  (println! \"x\")\n")) "the banged builtin is the spelling")
      (assert (listEmpty? (messages "fn print x: Int64 -> Int64\n  x\nfn g -> Int64\n  (print 1)\n")) "a module defining its own name calls it unbanged")
      (assert (= (listLength (messages "fn f! -> Unit\n  (do (fileReadString \"a\") (mt x (_ 1)))\n")) 2) "builtin and head hints are reported together")
      (assert (= (first "fn f! -> Unit\n  (do (fileReadString \"a\") (mt x (_ 1)))\n") "ERR_READ_SPELLING (fileReadString ...) is retired: an effectful builtin carries !, write (fileReadString! ...)") "in source order")
      (assert (= (parseMsg (str (strictHeader) "fn f! -> Unit\n  (eprintln \"x\")\n")) "ERR_READ_SPELLING (eprintln ...) is retired: an effectful builtin carries !, write (eprintln! ...)") "a module opting in rejects an unbanged builtin on parse")
      (assert (= (parseMsg "fn f! -> Unit\n  (eprintln \"x\")\n") "ok") "and an ordinary module still reads it")
      (assert (listContains? (a/bangedBuiltins) "procAlive?") "the hint list carries predicate builtins")
      true))
