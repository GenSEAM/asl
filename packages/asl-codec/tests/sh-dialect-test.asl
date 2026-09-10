(module asl-codec/sh-dialect-test
  :d "Multi-dialect shell transpilation parity and compliance test suite"
  :x [TestShellDialectParity
      TestBashProcessSubstTranspile
      TestPosixStrictCompliance
      run-tests]
  :i [(sh-transpile :a sh)])

(df TestShellDialectParity [] -> Bool
  :d "Verifies dialect parity across command and pipeline transpilation"
  (let [(cmd1 (sh/make-cmd "echo" (list "hello")))
        (cmd2 (sh/make-cmd "grep" (list "hello")))
        (pipe (sh/make-pipe (list cmd1 cmd2)))
        (res-cmd (sh/asn-to-sh cmd1))
        (res-pipe (sh/asn-to-sh pipe))]
    (assert (.-success res-cmd) "Command transpilation must succeed")
    (assert (string-contains? (.-output res-cmd) "echo") "Command output must contain echo")
    (assert (.-success res-pipe) "Pipeline transpilation must succeed")
    (assert (string-contains? (.-output res-pipe) "grep") "Pipeline output must contain grep")
    (assert (>= (.-savings-percent res-pipe) 0.0) "Savings percentage must be non-negative")
    true))

(df TestBashProcessSubstTranspile [] -> Bool
  :d "Verifies bash argument escaping and process pipeline construction"
  (let [(arg1 (sh/escape-sh-arg "<(cat file.txt)"))
        (arg2 (sh/escape-sh-arg "arg with spaces"))
        (c1 (sh/make-cmd "diff" (list "<(sort a.txt)" "<(sort b.txt)")))]
    (assert (string-starts-with? arg1 "'") "Special process substitution character must be wrapped in quotes")
    (assert (= arg2 "'arg with spaces'") "Spaced argument must be single-quoted")
    (assert (string-contains? c1 "diff") "Command must preserve binary name")
    (assert (string-contains? c1 "sort") "Command must preserve nested commands in args")
    true))

(df TestPosixStrictCompliance [] -> Bool
  :d "Verifies POSIX strict script execution and safe escaping invariants"
  (let [(c1 (sh/make-cmd "mkdir" (list "-p" "build")))
        (c2 (sh/make-cmd "cp" (list "src/main.asl" "build/")))
        (scr (sh/make-script (list c1 c2) true))
        (res (sh/asn-to-sh scr))
        (safe (sh/escape-sh-arg "var_name_123"))]
    (assert (string-contains? scr ":strict true") "Script must have strict true declaration")
    (assert (.-success res) "Strict script transpilation must succeed")
    (assert (string-contains? (.-output res) "set -euo pipefail") "Strict script must prepend set -euo pipefail")
    (assert (= safe "var_name_123") "Safe identifier must remain bare without quoting")
    true))

(df run-tests [] -> Bool
  :d "Executes full multi-dialect test suite"
  (and (TestShellDialectParity)
       (and (TestBashProcessSubstTranspile)
            (TestPosixStrictCompliance))))
