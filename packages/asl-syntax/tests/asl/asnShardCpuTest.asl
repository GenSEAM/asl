(module asl-syntax/tests/asl/asnShardCpuTest
  :x [runTests]
  :i [(tools/fleet/run :a fr)])

; (:m :ref NO-SH-PY :do "ported off asnShardCpuTest.sh: a wall-clock timeoutMs via tools/fleet/run.asl's killTree! stands in for the shell original's ulimit -t 240 CPU cap around asnShard1Test.asl/asnShard2Test.asl")

fn totalExecuted text: String -> (Option Int64)
  (let [(marker " assertion(s) executed (")
        (parts (stringSplit text marker))]
    (if (< (listLength parts) 2) (none)
      (let [(before (optionOr (listGet parts (- (listLength parts) 2)) ""))
            (words (stringSplit (stringTrim before) " "))]
        (stringToInt64 (optionOr (listLast words) "")))))

fn checkShard! suite: String -> Bool
  (let [(done (fr/runOneLimited (fr/job (list (fr/nativeCli!) "test" suite) "." (fr/childEnv (list)))
                                (fr/limits 240000 8)))
        (total (totalExecuted done.out))
        (passed (fr/executedOf done.out))]
    (do
      (assert (= done.exit 0) (str suite " exits 0 within the CPU cap (exit " (stringFromInt64 done.exit) ")"))
      (assert (match total ((some n) (> n 0)) ((none) false)) (str suite " reports a positive assertion count"))
      (assert (= total passed) (str suite " reports all assertions passed, got " done.out))
      true))

fn ! runTests -> Bool
  (do
    (assert (checkShard! "asl/packages/asl-syntax/tests/asl/asnShard1Test.asl") "asnShard1Test.asl passes under the CPU cap")
    (assert (checkShard! "asl/packages/asl-syntax/tests/asl/asnShard2Test.asl") "asnShard2Test.asl passes under the CPU cap")
    true)
