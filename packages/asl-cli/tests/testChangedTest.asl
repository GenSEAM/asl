(module asl-cli/tests/testChangedTest :x [runTests])

fn ! shell! cwd: String script: String -> Int64
  (mt (procSpawnv (list "/bin/sh" "-c" script) (some cwd) (none))
    ((err _) 127)
    ((ok sp)
      (let [(closed (fdClose sp.stdin))]
        (mt (procWaitPid sp.pid false)
          ((ok status) (if (ok? closed) (optionOr status 1) 127))
          ((err _) 127)))))

fn ! cli! tree: String repo: String output: String args: String -> Int64
  (shell! repo
    (str "ASL_CLI_ROOT=\"" tree "\" ASL_CLI_HOST_BIN=\"" tree "/asl/host/out/asl-host\" ASL_ROOT=\"" repo "\" nice -n 15 perl -e 'alarm 30; exec @ARGV' \""
         tree "/asl/host/out/asl-host\" run \"" tree "/asl/packages/asl-cli/src/command.asl\" test " args " > \"" output "\" 2>&1"))

fn ! runTests -> Bool
  (let [(tree (resultOr (realPath ".") "."))
        (repo (str "/tmp/testChanged-" (stringFromInt64 (monotonicNs))))
        (out (str "/tmp/testChanged-log-" (stringFromInt64 (monotonicNs))))
        (alphaText (resultOr (fileReadString "asl/packages/asl-cli/tests/fixtures/testChanged/alpha.asl") ""))
        (betaText (resultOr (fileReadString "asl/packages/asl-cli/tests/fixtures/testChanged/beta.asl") ""))
        (alphaTest (resultOr (fileReadString "asl/packages/asl-cli/tests/fixtures/testChanged/alphaTest.asl") ""))
        (betaTest (resultOr (fileReadString "asl/packages/asl-cli/tests/fixtures/testChanged/betaTest.asl") ""))
        (made (dirCreate repo))
        (srcDir (dirCreate (str repo "/testChanged")))
        (testsDir (dirCreate (str repo "/tests")))
        (config (fileWrite (str repo "/.asl.config.asn") "(:aslConfig :workspace \"testChanged\" :version \"0.1.0\")\n"))
        (a (fileWrite (str repo "/testChanged/alpha.asl") alphaText))
        (b (fileWrite (str repo "/testChanged/beta.asl") betaText))
        (at (fileWrite (str repo "/tests/alphaTest.asl") alphaTest))
        (bt (fileWrite (str repo "/tests/betaTest.asl") betaTest))
        (initialized (shell! repo "git init -q && git config user.email test@example.invalid && git config user.name Test && git add . && git commit -qm fixture"))
        (alphaChanged (fileWrite (str repo "/testChanged/alpha.asl") (stringReplace alphaText "  1" "  2")))
        (firstExit (cli! tree repo out "--changed HEAD"))
        (firstOutput (resultOr (fileReadString out) ""))
        (alphaBroken (fileWrite (str repo "/testChanged/alpha.asl") (stringReplace alphaText "  1" "  0")))]
    (do
      (assert (and (= firstExit 0) (stringContains? firstOutput "(:pass :file \"tests/alphaTest.asl\"")
                   (and (not (stringContains? firstOutput "betaTest.asl"))
                        (stringContains? firstOutput ":files 1 :selected 1 :passed 1 :failed 0")))
              (str "tree CLI must select and run only the importing suite; exit=" (stringFromInt64 firstExit) " output=" firstOutput))
      (assert (and (= initialized 0) (and (ok? alphaChanged) (and (ok? alphaBroken) (and (ok? config) (and (ok? made) (and (ok? srcDir) (and (ok? testsDir) (and (ok? a) (and (ok? b) (and (ok? at) (ok? bt)))))))))))
              "fixture git repository is committed and its modules and suites are written")
      (assert (and (= (cli! tree repo out "--changed HEAD") 1)
                   (stringContains? (resultOr (fileReadString out) "") ":selected 1 :passed 0 :failed 1"))
              "a failing selected suite produces a failed summary and nonzero exit")
      (let [(committedFailure (shell! repo "git add . && git commit -qm failing-module"))
            (irrelevant (fileWrite (str repo "/README.txt") "not a module change"))
            (emptyExit (cli! tree repo out "--changed HEAD"))
            (emptyOutput (resultOr (fileReadString out) ""))
            (dryChange (fileWrite (str repo "/testChanged/alpha.asl") (stringReplace alphaText "  1" "  2")))
            (badExit (cli! tree repo out "--changed TESTIMPACT_NO_SUCH_BASE"))
            (badOutput (resultOr (fileReadString out) ""))
            (dryExit (cli! tree repo out "--changed HEAD --dry-run"))
            (dryOutput (resultOr (fileReadString out) ""))
            (removed (pathRemove repo))
            (logRemoved (pathRemove out))]
        (do
          (assert (and (= committedFailure 0) (and (ok? irrelevant) (and (= emptyExit 0) (stringContains? emptyOutput ":selected 0 :passed 0 :failed 0"))))
                  (str "empty selection is successful and never sweeps; output=" emptyOutput))
          (assert (and (= badExit 2) (stringContains? badOutput "ERR_SELECTION") (stringContains? badOutput "bad revision"))
                  (str "unknown BASE is a typed error, not a full sweep; output=" badOutput))
          (assert (and (= dryExit 0) (stringContains? dryOutput "(:selected :file \"tests/alphaTest.asl\")")
                       (and (not (stringContains? dryOutput "(:pass")) (stringContains? dryOutput ":selected 1")))
                  (str "dry-run lists selected suites without running them; output=" dryOutput))
          (assert (and (ok? removed) (ok? logRemoved)) "throwaway git repository and command log are removed")))
      true))
