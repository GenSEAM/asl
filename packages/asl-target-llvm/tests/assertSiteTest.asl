(module asl-target-llvm/tests/assertSiteTest
  :x [runTests]
  :i [(tools/fleet/run :a run)])

fn workDir -> String
  "asl/packages/asl-target-llvm/tests/assertSiteWork"

fn lambdaFixture -> String
  (str "(module asl-target-llvm/tests/assertSiteWork/lambdaSiteTest :x [runTests] :i [])\n\n"
       "fn check xs: (List Int64) -> Bool\n"
       "  (do (map (fn [(x Int64)] -> Bool (do (assert (> x 0) \"positive\") true)) xs) true)\n\n"
       "fn runTests -> Bool\n"
       "  (let [(n (listLength (list 1 2)))]\n"
       "    (assert (= n 2) \"two; (assert in a string\")\n"
       "    (refute (= n 3))\n"
       "    (check (list 1 2 0))\n"
       "    true)\n")

fn bareFixture -> String
  (str "(module asl-target-llvm/tests/assertSiteWork/bareSiteTest :x [runTests] :i [])\n\n"
       "fn runTests -> Bool\n"
       "  (let [(n (listLength (list 1)))]\n"
       "    (assert (= n 1)) (refute (= n 1))\n"
       "    true)\n")

fn ! run! name: String source: String -> String
  (let [(path (str (workDir) "/" name ".asl"))
        (written (fileWrite path source))]
    (if (ok? written)
      (let [(root (resultOr (realPath ".") "."))
            (done (run/runOneLimited (run/job (list (str root "/bin/asl") "test" path) root (run/childEnv (list))) (run/limits 300 64)))]
        done.out)
      (str "cannot write " path)))

fn ! runTests -> Bool
  (let [(made (dirCreate (workDir)))
        (lifted (run! "lambdaSiteTest" (lambdaFixture)))
        (bare (run! "bareSiteTest" (bareFixture)))
        (removed (pathRemove (workDir)))]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert (stringContains? lifted (str (workDir) "/lambdaSiteTest.asl:4:40: ERR_ASSERT: assertion failed: positive\n"))
              (str "an assert inside a lifted lambda names its own line and column, after the two sites a string and a refute hold: " lifted))
      (assert (stringContains? lifted (str "FAIL " (workDir) "/lambdaSiteTest.asl: ERR_ASSERT: assertion failed: positive (after 4 asserts)"))
              (str "the FAIL line keeps its form: " lifted))
      (assert (stringContains? bare (str (workDir) "/bareSiteTest.asl:5:22: ERR_REFUTE: refutation failed: predicate held true\n"))
              (str "a bare refute second on its line names its column: " bare))
      (refute (stringContains? bare "bareSiteTest.asl:5:5:") (str "the passing assert before it prints no site: " bare))
      (assert (ok? removed) "the fixture directory is removed")
      true))
