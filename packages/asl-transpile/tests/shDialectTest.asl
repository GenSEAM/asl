(module asl-transpile/shDialectTest :x [testShellDialectParity testBashProcessSubstTranspile testPosixStrictCompliance runTests] :i [(asl-transpile/shTranspile :a sh) (asl-text/escape :a esc)])

fn testShellDialectParity -> Bool
  (let [(cmd1 (sh/makeCmd "echo" (list "hello"))) (cmd2 (sh/makeCmd "grep" (list "hello"))) (pipe (sh/makePipe (list cmd1 cmd2))) (resCmd (sh/asnToSh cmd1)) (resPipe (sh/asnToSh pipe))] (assert resCmd.success "Command transpilation must succeed") (assert (stringContains? resCmd.output "echo") "Command output must contain echo") (assert resPipe.success "Pipeline transpilation must succeed") (assert (stringContains? resPipe.output "grep") "Pipeline output must contain grep") (assert (>= resPipe.savingsPercent 0.0) "Savings percentage must be non-negative") true)

fn testBashProcessSubstTranspile -> Bool
  (let [(arg1 (esc/escapeShCompact "<(cat file.txt)")) (arg2 (esc/escapeShCompact "arg with spaces")) (c1 (sh/makeCmd "diff" (list "<(sort a.txt)" "<(sort b.txt)")))] (assert (stringStartsWith? arg1 "'") "Special process substitution character must be wrapped in quotes") (assert (= arg2 "'arg with spaces'") "Spaced argument must be single-quoted") (assert (stringContains? c1 "diff") "Command must preserve binary name") (assert (stringContains? c1 "sort") "Command must preserve nested commands in args") true)

fn testPosixStrictCompliance -> Bool
  (let [(c1 (sh/makeCmd "mkdir" (list "-p" "build"))) (c2 (sh/makeCmd "cp" (list "src/main.asl" "build/"))) (scr (sh/makeScript (list c1 c2) true)) (res (sh/asnToSh scr)) (safe (esc/escapeShCompact "var_name_123"))] (assert (stringContains? scr ":strict true") "Script must have strict true declaration") (assert res.success "Strict script transpilation must succeed") (assert (stringContains? res.output "set -euo pipefail") "Strict script must prepend set -euo pipefail") (assert (= safe "var_name_123") "Safe identifier must remain bare without quoting") true)

fn runTests -> Bool
  (and (testShellDialectParity) (and (testBashProcessSubstTranspile) (testPosixStrictCompliance)))
