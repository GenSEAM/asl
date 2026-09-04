(module asl-cli/test
  :d "Unit tests for pure AgentScript CLI dispatcher."
  :x [test-version test-help test-dispatch-version test-dispatch-unknown test-dispatch-missing run-tests]
  :i [(cli :a c)])

(df test-version [] -> Bool
  :d "Verifies format-version outputs canonical string."
  (string-contains? (c/format-version) "asl 1.0.0"))

(df test-help [] -> Bool
  :d "Verifies format-help contains usage commands."
  (and (string-contains? (c/format-help) "Usage: asl")
       (and (string-contains? (c/format-help) "check <file>")
            (string-contains? (c/format-help) "build <file>"))))

(df ! test-dispatch-version [] -> Bool
  :d "Verifies dispatch-cmd handles version."
  (mt (c/dispatch-cmd "version" (list))
    ((ok ver) (string-contains? ver "1.0.0"))
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

(df ! run-tests [] -> Bool
  :d "Executes all pure ASL CLI test cases."
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p))
        true
        (list (test-version)
              (test-help)
              (test-dispatch-version)
              (test-dispatch-unknown)
              (test-dispatch-missing))))
