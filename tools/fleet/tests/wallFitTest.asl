(module asl-tools/fleet/tests/wallFitTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PERF-GATE-TIMEOUT-FIT :do "runShell! against a private wall ledger (the ASL_GATE_TIMES row of the gate's env) and the stand-in host: a gate whose recorded wall is above its timeout is refused unlaunched with exit 126, verdict wallOverBound and a receipt naming the recorded wall, the bound and the fitted timeout; the recorded walls of several files add up; a gate that fits, an unrecorded suite and a corrupt ledger launch as before")

fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/wallFitTest-" (stringFromInt64 (procSelf)))

fn ! sh argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits 60 16))

fn ! runTests -> Bool
  (let [(dir (scratch))
        (_ (sh (list "mkdir" "-p" dir)))
        (ledger (str dir "/gateTimes.asn"))
        (wrote (ok? (fileWrite ledger "(:suiteTime :suite \"green2.asl\" :ms 400 :samples (400))\n(:suiteTime :suite \"green3.asl\" :ms 5000 :samples (9000 5000 4000))\n")))
        (host (fr/stubHost!))
        (env (fr/childEnv (list (str "ASL_GATE_TIMES=" ledger))))
        (slow (fr/runShell! (str host " test green3.asl") dir env (fr/limits 2 16)))
        (fits (fr/runShell! (str host " test green2.asl") dir env (fr/limits 2 16)))
        (sum (fr/runShell! (str host " test green2.asl ./green3.asl") dir env (fr/limits 5 16)))
        (roomy (fr/runShell! (str host " test green2.asl green3.asl") dir env (fr/limits 6 16)))
        (unknown (fr/runShell! (str host " test green4.asl") dir env (fr/limits 2 16)))
        (_ (fileWrite ledger "(:suiteTime :suite \"green3.asl\" :ms 5000\nnot a row\n"))
        (corrupt (fr/runShell! (str host " test green3.asl") dir env (fr/limits 2 16)))
        (removed (fr/stubRemove!))
        (cleaned (= (sh (list "rm" "-rf" dir)).exit 0))]
    (do (assert (and wrote (not (stringEmpty? host))) "ledger and stand-in host written")
        (assert (and (= slow.exit 126) (= slow.verdict "wallOverBound")) (str "a gate recorded at 5000 ms is refused under a 2 s timeout: exit " slow.exit " " slow.verdict " " slow.out))
        (assert (not (stringContains? slow.out "assertion(s)")) (str "the refused gate was never launched: " slow.out))
        (assert (stringContains? slow.out "(:fleetRun :verdict :wallOverBound :gate ") "the receipt is a named :fleetRun row")
        (assert (stringContains? slow.out " :recordedMs 5000 :timeoutMs 2000 :fitTimeoutS 8 :suites (\"green3.asl\") :ledger ") (str "it names the recorded wall, the bound and the fitted timeout 1.5 x 5000 ms: " slow.out))
        (assert (and (= fits.exit 0) (stringContains? fits.out "2 assertion(s) executed (2 passed)")) (str "a gate recorded under its timeout runs: " fits.out))
        (assert (and (= sum.exit 126) (stringContains? sum.out " :recordedMs 5400 :timeoutMs 5000 :fitTimeoutS 9 :suites (\"green2.asl\" \"green3.asl\")")) (str "the recorded walls of the gate's files add up: " sum.out))
        (assert (and (= roomy.exit 0) (stringContains? roomy.out "3 assertion(s) executed (3 passed)")) (str "the same two files run under a timeout above their sum: " roomy.out))
        (assert (and (= unknown.exit 0) (stringContains? unknown.out "4 assertion(s) executed")) (str "an unrecorded suite is launched: " unknown.out))
        (assert (and (= corrupt.exit 0) (stringContains? corrupt.out "3 assertion(s) executed")) (str "a ledger that does not read refuses nothing: " corrupt.out))
        (assert (and removed cleaned) "stand-in host and scratch removed")
        true))
