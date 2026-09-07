(module asl-cli/test
  :d "Unit tests for pure AgentScript CLI dispatcher."
  :x [test-version test-help test-dispatch-version test-dispatch-gate test-dispatch-unknown test-dispatch-missing test-dispatch-eval test-dispatch-test run-tests]
  :i [(cli :a c)])

(df test-version [] -> Bool
  :d "Verifies format-version outputs canonical string."
  (string-contains? (c/format-version) "asl 0.1.0"))

(df test-help [] -> Bool
  :d "Verifies format-help contains usage commands."
  (and (string-contains? (c/format-help) "Usage: asl")
       (and (string-contains? (c/format-help) "check <file>")
            (and (string-contains? (c/format-help) "build <file>")
                 (and (string-contains? (c/format-help) "eval <expr>")
                      (string-contains? (c/format-help) "test <file>"))))))

(df ! test-dispatch-version [] -> Bool
  :d "Verifies dispatch-cmd handles version."
  (mt (c/dispatch-cmd "version" (list))
    ((ok ver) (string-contains? ver "0.1.0"))
    ((err _) false)))

(df ! test-dispatch-gate [] -> Bool
  :d "Verifies dispatch-cmd gate processes file list."
  (mt (c/dispatch-cmd "gate" (list "test.asl"))
    ((ok msg) (string-contains? msg "verified cleanly"))
    ((err _) false)))

(df ! test-dispatch-unknown [] -> Bool
  :d "Verifies dispatch-cmd rejects unknown subcommands."
  (mt (c/dispatch-cmd "non-existent-command-xyz" (list))
    ((ok _) false)
    ((err msg) (string-contains? msg "Unknown command"))))

(df ! test-dispatch-missing [] -> Bool
  :d "Verifies dispatch-cmd demands file argument."
  (mt (c/dispatch-cmd "check" (list))
    ((ok _) false)
    ((err msg) (string-contains? msg "Usage: asl check"))))

(df ! test-dispatch-eval [] -> Bool
  :d "Verifies dispatch-cmd eval evaluates expressions cleanly."
  (and (mt (c/dispatch-cmd "eval" (list "(+ 10 20)"))
         ((ok res) (= res "30"))
         ((err _) false))
       (and (mt (c/dispatch-cmd "eval" (list))
              ((ok _) false)
              ((err msg) (string-contains? msg "Usage: asl eval")))
            (mt (c/dispatch-cmd "eval" (list "(assert (= 1 2) \"mismatch\")"))
              ((ok _) false)
              ((err msg) (string-contains? msg "mismatch"))))))

(df ! test-dispatch-test [] -> Bool
  :d "Verifies dispatch-cmd test validates args and missing files."
  (and (mt (c/dispatch-cmd "test" (list))
         ((ok _) false)
         ((err msg) (string-contains? msg "Usage: asl test")))
       (mt (c/dispatch-cmd "test" (list "non-existent-test-file-xyz.asl"))
         ((ok _) false)
         ((err msg) (string-contains? msg "Failed to read test file")))))

(df ! run-tests [] -> Bool
  :d "Executes all pure ASL CLI test cases."
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p))
        true
        (list (test-version)
              (test-help)
              (test-dispatch-version)
              (test-dispatch-gate)
              (test-dispatch-unknown)
              (test-dispatch-missing)
              (test-dispatch-eval)
              (test-dispatch-test))))
