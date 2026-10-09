(module asl-compiler/tests/monadTest
  :x [runTests RunTests testOptionMap testOptionAndThen testOptionUnwrapOr testResultMap testResultMapErr testResultAndThen testResultUnwrapOr]
  :i [(asl-compiler/monad :a m)])

fn testOptionMap -> Bool
  (let [(someVal (some 10))
        (noneVal (none))
        (incFn (fn [(x Int64)] (+ x 1)))
        (mappedSome (m/optionMap someVal incFn))
        (mappedNone (m/optionMap noneVal incFn))]
    (assert (= (optionOr mappedSome 0) 11) "optionMap transforms some value")
    (refute (!= (optionOr mappedSome 0) 11) "optionMap refutes untransformed some")
    (assert (none? mappedNone) "optionMap preserves none")
    (refute (some? mappedNone) "optionMap refutes some for none input"))
  true

fn testOptionAndThen -> Bool
  (let [(someVal (some 4))
        (noneVal (none))
        (halfFn (fn [(x Int64)] (if (= (mod x 2) 0) (some (/ x 2)) (none))))
        (resSome (m/option-and-then someVal halfFn))
        (resNone (m/option-and-then noneVal halfFn))]
    (assert (= (optionOr resSome 0) 2) "option-and-then chains some")
    (refute (!= (optionOr resSome 0) 2) "option-and-then refutes incorrect chain")
    (assert (none? resNone) "option-and-then preserves none")
    (refute (some? resNone) "option-and-then refutes some on none"))
  true

fn testOptionUnwrapOr -> Bool
  (let [(someVal (some "hello"))
        (noneVal (none))]
    (assert (= (m/option-unwrap-or someVal "default") "hello") "option-unwrap-or returns inner value on some")
    (refute (!= (m/option-unwrap-or someVal "default") "hello") "option-unwrap-or refutes fallback on some")
    (assert (= (m/option-unwrap-or noneVal "default") "default") "option-unwrap-or returns fallback on none")
    (refute (!= (m/option-unwrap-or noneVal "default") "default") "option-unwrap-or refutes non-fallback on none"))
  true

fn testResultMap -> Bool
  (let [(okVal (ok 21))
        (errVal (err "network_down"))
        (doubleFn (fn [(x Int64)] (* x 2)))
        (mappedOk (m/resultMap okVal doubleFn))
        (mappedErr (m/resultMap errVal doubleFn))]
    (assert (ok? mappedOk) "resultMap on ok produces ok")
    (assert (err? mappedErr) "resultMap on err preserves err")
    (refute (err? mappedOk) "resultMap on ok refutes err")
    (refute (ok? mappedErr) "resultMap on err refutes ok"))
  true

fn testResultMapErr -> Bool
  (let [(okVal (ok 42))
        (errVal (err "e01"))
        (prefixFn (fn [(e Str)] (str "FATAL_" e)))
        (mappedOk (m/resultMapErr okVal prefixFn))
        (mappedErr (m/resultMapErr errVal prefixFn))]
    (assert (ok? mappedOk) "resultMapErr on ok preserves ok")
    (assert (err? mappedErr) "resultMapErr on err produces err")
    (refute (err? mappedOk) "resultMapErr on ok refutes err"))
  true

fn testResultAndThen -> Bool
  (let [(okVal (ok 10))
        (errVal (err "initial_fail"))
        (divSafe (fn [(x Int64)] (if (= x 0) (err "div_zero") (ok (/ 100 x)))))
        (chainedOk (m/result-and-then okVal divSafe))
        (chainedErr (m/result-and-then errVal divSafe))]
    (assert (ok? chainedOk) "result-and-then chains ok result")
    (assert (err? chainedErr) "result-and-then short-circuits err")
    (refute (err? chainedOk) "result-and-then refutes err on success"))
  true

fn testResultUnwrapOr -> Bool
  (let [(okVal (ok 100))
        (errVal (err "corrupted"))]
    (assert (= (m/result-unwrap-or okVal 0) 100) "result-unwrap-or returns inner value on ok")
    (refute (!= (m/result-unwrap-or okVal 0) 100) "result-unwrap-or refutes fallback on ok")
    (assert (= (m/result-unwrap-or errVal 0) 0) "result-unwrap-or returns fallback on err")
    (refute (!= (m/result-unwrap-or errVal 0) 0) "result-unwrap-or refutes non-fallback on err"))
  true

fn runTests -> Bool
  (do
    (assert (testOptionMap) "testOptionMap passed")
    (assert (testOptionAndThen) "testOptionAndThen passed")
    (assert (testOptionUnwrapOr) "testOptionUnwrapOr passed")
    (assert (testResultMap) "testResultMap passed")
    (assert (testResultMapErr) "testResultMapErr passed")
    (assert (testResultAndThen) "testResultAndThen passed")
    (assert (testResultUnwrapOr) "testResultUnwrapOr passed")
    true)

fn RunTests -> Bool
  (runTests)
