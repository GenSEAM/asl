(module asl-compiler/tests/threadMacroTest
  :x [runTests RunTests testHasThreadForm testThreadFirstStep testThreadLastStep testExpandThreadMacro testExpandThreadInSource]
  :i [(asl-compiler/threadMacro :a thm)])

fn testHasThreadForm -> Bool
  (let [(codeWithFirst "(-> x (foo a) bar)")
        (codeWithLast "(->> items (filter pred) (map fn))")
        (codeWithoutThread "(let [(x 42)] (+ x 1))")]
    (assert (thm/hasThreadForm? codeWithFirst) "codeWithFirst is recognized")
    (refute (not (thm/hasThreadForm? codeWithFirst)) "codeWithFirst refutes false")
    (assert (thm/hasThreadForm? codeWithLast) "codeWithLast is recognized")
    (refute (not (thm/hasThreadForm? codeWithLast)) "codeWithLast refutes false")
    (assert (not (thm/hasThreadForm? codeWithoutThread)) "codeWithoutThread is rejected")
    (refute (thm/hasThreadForm? codeWithoutThread) "codeWithoutThread refutes true"))
  true

fn testThreadFirstStep -> Bool
  (let [(bare (thm/threadFirstStep "x" "foo"))
        (withArgs (thm/threadFirstStep "x" "(bar a b)"))]
    (assert (= bare "(foo x)") "bare symbol threads as single arg")
    (refute (!= bare "(foo x)") "bare symbol refutes incorrect position")
    (assert (= withArgs "(bar x a b)") "form threads as first arg after head")
    (refute (!= withArgs "(bar x a b)") "form refutes non-first position"))
  true

fn testThreadLastStep -> Bool
  (let [(bare (thm/threadLastStep "x" "foo"))
        (withArgs (thm/threadLastStep "x" "(bar a b)"))]
    (assert (= bare "(foo x)") "bare symbol threads as single arg")
    (refute (!= bare "(foo x)") "bare symbol refutes incorrect position")
    (assert (= withArgs "(bar a b x)") "form threads as last arg")
    (refute (!= withArgs "(bar a b x)") "form refutes non-last position"))
  true

fn testExpandThreadMacro -> Bool
  (let [(chainFirst (thm/expandThreadMacro "x foo (bar 1 2)"))
        (chainLast (thm/expandThreadMacro "> items (filter pred) (map fn)"))]
    (assert (stringContains? chainFirst "(bar (foo x) 1 2)") "thread-first expands nested pipeline")
    (refute (stringContains? chainFirst "(-> ") "thread-first refutes unlowered macro")
    (assert (stringContains? chainLast "(map fn (filter pred items))") "thread-last expands nested pipeline")
    (refute (stringContains? chainLast "(->> ") "thread-last refutes unlowered macro"))
  true

fn testExpandThreadInSource -> Bool
  (let [(src "fn process x: I64 -> I64 (-> x inc (mul 2))")
        (expanded (thm/expandThreadInSource src))
        (plain "fn plain x: I64 -> I64 (+ x 1)")
        (unchanged (thm/expandThreadInSource plain))]
    (assert (stringContains? expanded "(mul (inc x) 2)") "expanded source transforms thread form")
    (assert (not (stringContains? expanded "(-> ")) "expanded source contains no thread sigil")
    (assert (= unchanged plain) "plain source remains unchanged")
    (refute (!= unchanged plain) "plain source refutes modification"))
  true

fn runTests -> Bool
  (do
    (assert (testHasThreadForm) "testHasThreadForm passed")
    (assert (testThreadFirstStep) "testThreadFirstStep passed")
    (assert (testThreadLastStep) "testThreadLastStep passed")
    (assert (testExpandThreadMacro) "testExpandThreadMacro passed")
    (assert (testExpandThreadInSource) "testExpandThreadInSource passed")
    true)

fn RunTests -> Bool
  (runTests)
