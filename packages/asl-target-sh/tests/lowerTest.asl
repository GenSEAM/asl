(module asl-target-sh/tests/lowerTest
  :x [runTests]
  :i [(asl-target-sh/ast :a ast) (asl-target-sh/emitSh :a em) (asl-target-sh/lower :a low)])

fn testLowerExpr -> Bool
  (let [(eStr (low/lowerExpr "\"hello\""))
        (eVar (low/lowerExpr "my_var"))
        (eInt (low/lowerExpr 42))]
    (assert (= eStr.tag "litStr") "String literal must lower to litStr")
    (assert (= eStr.strVal "hello") "Lowered string literal payload must match")
    (assert (= eVar.tag "var") "Identifier must lower to var")
    (assert (= eVar.strVal "my_var") "Lowered variable identifier must match")
    (assert (= eInt.tag "litInt") "Integer must lower to litInt")
    (assert (= eInt.intVal 42) "Lowered integer value must match")
    true)

fn testSampleScriptLoweringAndEmission -> Bool
  (let [(script (low/sampleLoweredScript))
        (formatted (em/formatShScript script))]
    (assert (= (listLength script.functions) 1) "Sample script must contain 1 function")
    (assert (stringContains? formatted "main() {") "Formatted script must contain main function")
    (assert (stringContains? formatted "local status='ASL_SHELL_OK'") "Formatted script must assign status")
    (assert (stringContains? formatted "printf '%s\\n' \"${status:-}\"") "Formatted script must print status with defensive expansion")
    (assert (stringContains? formatted "return 0") "Formatted script must return 0")
    (refute (stringContains? formatted "$status ") "Unquoted variable expansions strictly forbidden")
    true)

fn runTests -> Bool
  (let [(t1 (testLowerExpr))
        (t2 (testSampleScriptLoweringAndEmission))]
    (and t1 t2))
