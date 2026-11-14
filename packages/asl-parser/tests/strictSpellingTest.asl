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

fn rendered src: String -> String
  (match (a/parse src) ((ok forms) (stringJoin (map a/renderNode forms) "\n")) ((err e) (str "ERR " e.msg)))

fn checkRendered src: String -> String
  (match (a/parseForTypeCheck src) ((ok forms) (stringJoin (map a/renderNode forms) "\n")) ((err e) (str "ERR " e.msg)))

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
      (assert (listEmpty? (messages "fn ! sh c: String -> Int64\n  0\n")) "fn ! name stays (SYN-ARMS-DECISION-20261016 E9): not retired")
      (assert (listEmpty? (messages "fn tailrec ! go n: Int64 -> Int64\n  n\n")) "the mark after tailrec is also not retired")
      (assert (listEmpty? (messages "fn ! main args: (List String) -> Int64\n  0\n")) "an entry point's mark is not retired either")
      (assert (listEmpty? (messages "(fn ! f [] -> Int64 0)\n")) "the paren form is not retired")
      (assert (listEmpty? (messages "fn run! -> Int64\n  0\n")) "fn name! still reads clean too")
      (assert (listEmpty? (messages "(schema H (:f run (fn ! [Int64] -> Bool)))\n")) "an effectful fn type is not a definition")
      (assert (listEmpty? (messages "fn f -> Int64\n  (let [(mt 1)] mt)\n")) "a let binder named mt is an ordinary name")
      (assert (= (listLength (messages "fn f -> Int64\n  (let [a (mt x (_ 1))] (== a 1))\n")) 2) "values of flat bindings are checked")
      (assert (listEmpty? (messages "fn f -> String\n  \"(mt x) fn ! y (== 1 2)\"\n")) "strings are not code")
      (assert (not (= (parseMsg oldMatch) "ok")) "strict spelling is always on: an ordinary module has no way to keep mt")
      (assert (= (parseMsg oldMatch) "ERR_READ_SPELLING (mt subject arm ...) is retired: write (match subject arm ...)") "a module rejects mt on parse")
      (assert (= (checkMsg "fn ! f -> Int64\n  0\n") "ok") "fn ! f also reads clean on the checker parse")
      (assert (= (parseMsg newMatch) "ok") "a module reads with the new spellings")
      (assert (= (match (a/parse oldMatch) ((ok _) 0) ((err e) e.line)) 2) "the error points at the line")
      (assert (= (armCount "(match x ((some v) (f v)))") 1) "a one-arm match whose body is a call keeps one arm")
      (assert (= (armCount "(match x ((some v) (f v)) ((none) 0))") 2) "a two-arm match keeps two arms")
      (assert (listEmpty? (messages "fn f! -> Unit\n  (println \"x\")\n")) "builtins stay bare (SYN-ARMS-DECISION-20261016 E10): an unbanged effectful builtin is not retired")
      (assert (listEmpty? (messages "fn f! -> Unit\n  (println! \"x\")\n")) "a banged call also still reads clean")
      (assert (listEmpty? (messages "fn print x: Int64 -> Int64\n  x\nfn g -> Int64\n  (print 1)\n")) "a module defining its own name calls it unbanged")
      (assert (= (listLength (messages "fn f! -> Unit\n  (do (fileReadString \"a\") (mt x (_ 1)))\n")) 1) "only the mt head is flagged now, not the bare builtin")
      (assert (= (first "fn f! -> Unit\n  (do (fileReadString \"a\") (mt x (_ 1)))\n") "ERR_READ_SPELLING (mt subject arm ...) is retired: write (match subject arm ...)") "in source order")
      (assert (= (parseMsg "fn f! -> Unit\n  (eprintln \"x\")\n") "ok") "a module still accepts a bare builtin call")
      (assert (= (parseMsg "fn f! -> Unit\n  (eprintln \"x\")\n") "ok") "and an ordinary module reads it too")
      (assert (listContains? (a/bangedBuiltins) "procAlive?") "the hint list still carries predicate builtins, for the opt-in --bang codemod")
      (assert (= (parseMsg "fn f -> Bool\n  (== 1 2)\n") "ok") "MISS-ABSORB: the reader takes (== a b) as (= a b)")
      (assert (= (checkMsg "fn f a: Int64 -> Int64\n  (cond ((== a 0) 1) (else (% a 2)))\n") "ok") "MISS-ABSORB: and (% a b) as (mod a b), on the checker parse too")
      (assert (= (first "fn f a: Int64 -> Int64\n  (% a 2)\n") "ERR_READ_SPELLING (% a b) is not ASL: write (mod a b)") "the audit of stored text still names % and its canonical form")
      (assert (= (parseMsg "fn f -> Bool\n  (not= 1 2)\n") "ERR_READ_SPELLING (not= a b) is retired: write (!= a b)") "not= stays retired: no model of the bench wrote it")
      (assert (= (match (a/parse "fn f x: Int64 -> Bool\n  (== 1 (mt x (_ 1)))\n") ((ok _) 0) ((err e) (+ (* e.line 100) e.col))) 210) "an accepted == keeps the columns of what follows it")
      (assert (= (parseMsg "fn f -> String\n  \"(== 1 2) (% 3 4)\"\n") "ok") "strings are not rewritten")
      (assert (= (rendered "fn f a: Int64 b: Int64 -> Bool\n  (== a b)\n") (rendered "fn f a: Int64 b: Int64 -> Bool\n  (= a b)\n")) "meaning: (== a b) is the program (= a b), node for node")
      (assert (= (rendered "fn f a: Int64 b: Int64 -> Int64\n  (% a b)\n") (rendered "fn f a: Int64 b: Int64 -> Int64\n  (mod a b)\n")) "meaning: (% a b) is the program (mod a b), node for node")
      (assert (= (checkRendered "fn f a: Int64 b: Int64 -> Int64\n  (if (== a b) 0 (% a b))\n") (checkRendered "fn f a: Int64 b: Int64 -> Int64\n  (if (= a b) 0 (mod a b))\n")) "meaning: the checker parse reads the same canonical program")
      (assert (stringContains? (rendered "fn f a: Int64 b: Int64 -> Int64\n  (mod a b)\n") "mod") (str "the rendering names the head it compares: " (rendered "fn f a: Int64 b: Int64 -> Int64\n  (mod a b)\n")))
      (assert (= (rendered "fn f a: Int64 -> Int64\n  ( % a 2)\n") (rendered "fn f a: Int64 -> Int64\n  ( mod a 2)\n")) "a space after the paren does not hide the head")
      (assert (listEmpty? (messages "fn % a: Int64 b: Int64 -> Int64\n  (+ a b)\n\nfn g -> Int64\n  (% 2 3)\n")) "a module that defines % owns the name: nothing is reported")
      (assert (not (stringContains? (rendered "fn % a: Int64 b: Int64 -> Int64\n  (+ a b)\n\nfn g -> Int64\n  (% 2 3)\n") "mod")) "and its call is not read as mod: the user definition wins")
      (assert (not (stringContains? (rendered "fn g -> Int64\n  (let [(% 5)] (+ % 1))\n") "mod")) "a let binder named % and its uses stay as written")
      (assert (not (stringContains? (rendered "fn g f: (fn [Int64 Int64] -> Int64) -> Int64\n  (let [(% f)] (% 7 3))\n") "mod")) "a call of a bound % is the bound value, not mod")
      (assert (= (a/canonicalSpelling "fn == a: Int64 b: Int64 -> Bool\n  (< a b)\n\nfn g -> Bool\n  (== 2 3)\n") "fn == a: Int64 b: Int64 -> Bool\n  (< a b)\n\nfn g -> Bool\n  (== 2 3)\n") "a module that defines == keeps its own ==")
      (assert (= (a/canonicalSpelling "fn g -> Int64\n  (let [(% 5)] (+ % 1))\n") "fn g -> Int64\n  (let [(% 5)] (+ % 1))\n") "heal's spelling pass leaves a bound % alone, binder and uses")
      (assert (= (a/canonicalSpelling "fn f a: Int64 -> Int64\n  (if (== a 1) (% a 2) (mt a (_ (if (not= a 3) 4 5))))\n") "fn f a: Int64 -> Int64\n  (if (= a 1) (mod a 2) (match a (_ (if (!= a 3) 4 5))))\n") "heal's spelling pass writes every reported head canonically")
      (assert (= (a/canonicalSpelling "fn f -> String\n  \"(== 1 2) (% 3 4)\"\n") "fn f -> String\n  \"(== 1 2) (% 3 4)\"\n") "and leaves strings alone")
      (assert (= (rendered "fn f a: Int64 -> Bool\n  (if (= (stringLength \"привет, мир\") 0) false (== a 1))\n") (rendered "fn f a: Int64 -> Bool\n  (if (= (stringLength \"привет, мир\") 0) false (= a 1))\n")) "Cyrillic before the head on its line: == is still swapped")
      (assert (= (rendered "fn f a: Int64 -> Int64\n  (if (= (stringLength \"ok 𝔸 𠀀\") 0) 0 (% a 3))\n") (rendered "fn f a: Int64 -> Int64\n  (if (= (stringLength \"ok 𝔸 𠀀\") 0) 0 (mod a 3))\n")) "four-byte characters before the head on its line: % is still swapped")
      (assert (= (a/canonicalSpelling "fn f a: Int64 -> Bool\n  (if (= \"жёлтый 𝔸𠀀\" \"\") (== a 1) (== (% a 2) 0))\n") "fn f a: Int64 -> Bool\n  (if (= \"жёлтый 𝔸𠀀\" \"\") (= a 1) (= (mod a 2) 0))\n") "several heads after multi-byte text on one line all land")
      true))
