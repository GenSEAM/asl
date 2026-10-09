(module asl-compiler/tests/tryMacroTest
  :x [runTests RunTests testHasTryForm testExpandTryMacro testExpandTryInSource testDualPolarityRefutations]
  :i [(asl-compiler/tryMacro :a tm)])

fn testHasTryForm -> Bool
  (let [(codeWithTry "(let [(res (try (readSocket fd)))] res)")
        (codeWithoutTry "(let [(res (readSocket fd))] res)")]
    (assert (tm/hasTryForm? codeWithTry) "codeWithTry contains try form")
    (refute (not (tm/hasTryForm? codeWithTry)) "codeWithTry refutes false")
    (assert (not (tm/hasTryForm? codeWithoutTry)) "codeWithoutTry does not contain try form")
    (refute (tm/hasTryForm? codeWithoutTry) "codeWithoutTry refutes true"))
  true

fn testExpandTryMacro -> Bool
  (let [(expanded (tm/expandTryMacro "(readSocket fd)"))]
    (assert (stringContains? expanded "(mt (readSocket fd)") "expanded contains mt on inner expr")
    (assert (stringContains? expanded "((ok __try_val) __try_val)") "expanded contains ok branch")
    (assert (stringContains? expanded "((err __try_err) (err __try_err))") "expanded contains err propagation")
    (refute (stringContains? expanded "(try ") "expanded refutes unexpanded try"))
  true

fn testExpandTryInSource -> Bool
  (let [(src "fn process sock: I64 -> (Result Str Str) (let [(msg (try (recv sock)))] (ok msg))")
        (expanded (tm/expandTryInSource src))]
    (assert (stringContains? expanded "(mt (recv sock)") "expanded source transforms try into mt")
    (assert (not (stringContains? expanded "(try ")) "expanded source contains no remaining try forms")
    (refute (stringContains? expanded "(try ") "expanded source refutes unlowered try"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(plain "fn add a: I64 b: I64 -> I64 (+ a b)")
        (res (tm/expandTryInSource plain))]
    (assert (= res plain) "plain source without try remains byte-identical")
    (refute (!= res plain) "plain source refutes modification"))
  true

fn runTests -> Bool
  (do
    (assert (testHasTryForm) "testHasTryForm passed")
    (assert (testExpandTryMacro) "testExpandTryMacro passed")
    (assert (testExpandTryInSource) "testExpandTryInSource passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
