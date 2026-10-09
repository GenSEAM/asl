(module asl-transpile/shTranspileTest :x [testEscapeSafe testEscapeSpecial testMakeCmd testMakePipe testMakeScript testAsnToSh testShToAsn testShSavings runTests] :i [(asl-transpile/shTranspile :a sh) (asl-text/escape :a esc)])

fn testEscapeSafe -> Bool
  (let [(r1 (esc/escapeShCompact "status")) (r2 (esc/escapeShCompact "--depth=1")) (r3 (esc/escapeShCompact "packages/asl-transpile"))] (assert (= r1 "status") "Safe status arg must remain bare") (assert (= r2 "--depth=1") "Safe flag arg must remain bare") (assert (= r3 "packages/asl-transpile") "Safe path arg must remain bare") true)

fn testEscapeSpecial -> Bool
  (let [(r1 (esc/escapeShCompact "hello world")) (r2 (esc/escapeShCompact "val with $VAR and 'quotes'"))] (assert (= r1 "'hello world'") "Spaces must be wrapped in single quotes") (assert (stringContains? r2 "'\\''quotes'\\''") "Embedded single quotes must be escaped") true)

fn testMakeCmd -> Bool
  (let [(c (sh/makeCmd "git" (list "status" "-s")))] (assert (stringContains? c "(:cmd \"git\"") "Command must have binary git") (assert (stringContains? c ":args [\"status\" \"-s\"]") "Command must have status args") true)

fn testMakePipe -> Bool
  (let [(c1 (sh/makeCmd "find" (list "packages" "-name" "*.asl"))) (c2 (sh/makeCmd "wc" (list "-l"))) (p (sh/makePipe (list c1 c2)))] (assert (stringStartsWith? p "(:pipe") "Pipeline must start with :pipe") (assert (stringContains? p "find") "Pipeline must contain find") (assert (stringContains? p "wc") "Pipeline must contain wc") true)

fn testMakeScript -> Bool
  (let [(c1 (sh/makeCmd "asl" (list "check" "src/main.asl"))) (c2 (sh/makeCmd "asl" (list "test" "tests/main-test.asl"))) (scr (sh/makeScript (list c1 c2) true))] (assert (stringContains? scr ":strict true") "Script must have strict true") (assert (stringContains? scr "asl") "Script must have asl commands") true)

fn testAsnToSh -> Bool
  (let [(cmdAsn "(:cmd \"git\" :args [\"status\" \"-s\"])") (res (sh/asnToSh cmdAsn)) (resSh (sh/asnToSh "(:sh \"echo \\\"hello world\\\"\")")) (resQuoted (sh/asnToSh "(:cmd \"echo\" :args [\"\\\"hello world\\\"\"])"))] (assert res.success "Transpilation must succeed") (assert (stringContains? res.output "git") "Output must contain git") (assert resSh.success "Transpilation of :sh form must succeed") (assert (stringContains? resSh.output "\"hello world\"") "Sh form must preserve quotes") (assert resQuoted.success "Transpilation of :cmd form with quotes must succeed") (assert (stringContains? resQuoted.output "\"hello world\"") "Cmd form must preserve quotes") true)

fn testShToAsn -> Bool
  (let [(res (sh/shToAsn "git commit -m initial"))] (assert res.success "Conversion must succeed") (assert (stringStartsWith? res.output "(:cmd") "Output must be :cmd") true)

fn testShSavings -> Bool
  (let [(res (sh/asnToSh "(:cmd \"ls\" :args [\"-la\"])"))] (assert res.success "Transpilation must succeed") (assert (>= res.savingsPercent 0.0) "Savings percent must be non-negative") true)

fn runTests -> Bool
  (and (testEscapeSafe) (and (testEscapeSpecial) (and (testMakeCmd) (and (testMakePipe) (and (testMakeScript) (and (testAsnToSh) (and (testShToAsn) (testShSavings))))))))
