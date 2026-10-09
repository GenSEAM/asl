(module asl/packages/asl-agent/tests/anchorLinkerTest
  :x [runTests]
  :i [(aslAgent/anchorLinker :a al)])

fn testFormatAndValidateRef -> Bool
  (let [(ref (al/formatMemoryRef "asl/packages/asl-agent/src/core.asl" "runStep" "step-init"))]
    (assert (al/validateAnchorReference ref) "valid memory ref must validate")
    (assert (stringContains? ref ":anchor \"step-init\"") "ref must contain anchor tag")
    (assert (stringContains? ref ":symbol \"runStep\"") "ref must contain symbol")
    (refute (al/validateAnchorReference "(:ref :file \"a\" :symbol \"b\" :anchor \"c\" :line 12)") "line numbers must be rejected")
    true)

fn testResolveAnchorFoundAndNotFound -> Bool
  (let [(src "(fn calculate :anchor \"calc-core\" [(x Int64)] -> Int64 (+ x 1))\n")
        (found (al/resolveAnchor src "calc-core"))
        (missing (al/resolveAnchor src "missing-tag"))]
    (assert (some? found) "existing anchor must be found")
    (assert (= (optionOr found "") "calc-core") "resolved tag name must match")
    (assert (none? missing) "missing anchor must return none")
    true)

fn testExtractMultipleAnchors -> Bool
  (let [(src "(fn step1 :anchor \"init\" ...)\n(fn step2 :anchor \"exec\" ...)\n(fn step3 ...)\n")
        (tags (al/extractAnchors src))]
    (assert (= (listLength tags) 2) "must extract exactly 2 anchors")
    (assert (stringContains? (stringJoin tags " ") "init") "tags must include init")
    (assert (stringContains? (stringJoin tags " ") "exec") "tags must include exec")
    true)

fn runTests -> Bool
  (and (testFormatAndValidateRef)
       (and (testResolveAnchorFoundAndNotFound)
            (testExtractMultipleAnchors)))
