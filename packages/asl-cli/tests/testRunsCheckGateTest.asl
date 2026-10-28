(module asl-cli/tests/testRunsCheckGateTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref INBOXFIX-TESTCHECK-20261028 :do "asl test of a package suite that asl check rejects (ERR_NOT_EXPORTED: a type annotation names a schema the imported module does not export) fails with the check error and runs no assertion; exporting the schema makes the same suite pass, so the verdict follows the dependency, not a stale cache")
fn ! fixtureRoot! -> String
  (str "/tmp/aslTestRunsCheckGateTest_" (stringFromInt64 (monotonicNs)))

fn ! libSource exported: Bool -> String
  (str "(module testcheckfixture/reproLib\n  :x [mk" (if exported " Box" "") "]\n  :i [])\n\n(schema Box (:f v Int))\n\nfn mk -> Int\n  3\n")

fn ! testSource -> String
  (str
    "(module testcheckfixture/reproTest\n"
    "  :x [runTests]\n"
    "  :i [(testcheckfixture/reproLib :a rl)])\n"
    "\n"
    "fn useBox b: rl/Box -> Int\n"
    "  b.v\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do (assert (= (rl/mk) 3) \"mk\") true)\n")

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! runAslTest! testPath: String -> fr/Done
  (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") "test" testPath) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testCheckRejectionFailsTest! -> Bool
  (let [(root (fixtureRoot!))
        (made (dirCreate root))
        (wCfg (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"testcheckfixture\")\n"))
        (wTest (fileWrite (str root "/reproTest.asl") (testSource)))
        (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))
        (wLibBad (fileWrite (str root "/reproLib.asl") (libSource false)))
        (bad (runAslTest! (str root "/reproTest.asl")))
        (wLibGood (fileWrite (str root "/reproLib.asl") (libSource true)))
        (good (runAslTest! (str root "/reproTest.asl")))
        (removed (pathRemove root))]
    (do
      (assert (and (ok? made) (and (ok? wCfg) (and (ok? wTest) (and (ok? wLibBad) (ok? wLibGood))))) "fixture written")
      (assert (not (= bad.exit 0)) (str "a suite asl check rejects fails asl test: " bad.out))
      (assert (stringContains? bad.out "ERR_NOT_EXPORTED") (str "the failure carries the check code: " bad.out))
      (assert (not (stringContains? bad.out "assertion(s) executed")) "no assertion ran")
      (assert (= good.exit 0) (str "exporting the schema makes the same suite pass: " good.out))
      (assert (ok? removed) "fixture directory is removed")
      true))

fn ! runTests -> Bool
  (testCheckRejectionFailsTest!)
