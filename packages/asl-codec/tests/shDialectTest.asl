(module asl-codec/shDialectTest
  :d "Multi-dialect shell transpilation parity and compliance test suite"
  :x [testShellDialectParity
      testBashProcessSubstTranspile
      testPosixStrictCompliance
      runTests]
  :i [(asl-codec/shTranspile :a sh)
      (asl-text/escape :a esc)])

(df testShellDialectParity [] -> Bool
  :d "Verifies dialect parity across command and pipeline transpilation"
  (let [(cmd1 (sh/makeCmd "echo" (list "hello")))
        (cmd2 (sh/makeCmd "grep" (list "hello")))
        (pipe (sh/makePipe (list cmd1 cmd2)))
        (resCmd (sh/asnToSh cmd1))
        (resPipe (sh/asnToSh pipe))]
    (assert (.-success resCmd) "Command transpilation must succeed")
    (assert (string-contains? (.-output resCmd) "echo") "Command output must contain echo")
    (assert (.-success resPipe) "Pipeline transpilation must succeed")
    (assert (string-contains? (.-output resPipe) "grep") "Pipeline output must contain grep")
    (assert (>= (.-savingsPercent resPipe) 0.0) "Savings percentage must be non-negative")
    true))

(df testBashProcessSubstTranspile [] -> Bool
  :d "Verifies bash argument escaping and process pipeline construction"
  (let [(arg1 (esc/escapeShCompact "<(cat file.txt)"))
        (arg2 (esc/escapeShCompact "arg with spaces"))
        (c1 (sh/makeCmd "diff" (list "<(sort a.txt)" "<(sort b.txt)")))]
    (assert (string-starts-with? arg1 "'") "Special process substitution character must be wrapped in quotes")
    (assert (= arg2 "'arg with spaces'") "Spaced argument must be single-quoted")
    (assert (string-contains? c1 "diff") "Command must preserve binary name")
    (assert (string-contains? c1 "sort") "Command must preserve nested commands in args")
    true))

(df testPosixStrictCompliance [] -> Bool
  :d "Verifies POSIX strict script execution and safe escaping invariants"
  (let [(c1 (sh/makeCmd "mkdir" (list "-p" "build")))
        (c2 (sh/makeCmd "cp" (list "src/main.asl" "build/")))
        (scr (sh/makeScript (list c1 c2) true))
        (res (sh/asnToSh scr))
        (safe (esc/escapeShCompact "var_name_123"))]
    (assert (string-contains? scr ":strict true") "Script must have strict true declaration")
    (assert (.-success res) "Strict script transpilation must succeed")
    (assert (string-contains? (.-output res) "set -euo pipefail") "Strict script must prepend set -euo pipefail")
    (assert (= safe "var_name_123") "Safe identifier must remain bare without quoting")
    true))

(df runTests [] -> Bool
  :d "Executes full multi-dialect test suite"
  (and (testShellDialectParity)
       (and (testBashProcessSubstTranspile)
            (testPosixStrictCompliance))))
