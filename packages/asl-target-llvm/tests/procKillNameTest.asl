(module asl/packages/asl-target-llvm/tests/procKillNameTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PROCKILL-SIGNAL-NAME :do "procKill takes a signal by its SIG name or by the bare name: four own sleepers (per-run unique seconds) are killed with KILL and SIGKILL, TERM and SIGTERM; a name in neither spelling, an empty one and a lower-case one are refused with io:22 and the sleeper lives; bindings run when first used, so each step takes the one before as dep, and a final SIGKILL of every sleeper runs before the first assert, so a red run leaves none")

fn ! startSleeper! secs: String -> Int64
  (match (fr/spawnSep (list "sleep" secs) "." (fr/childEnv (list)))
    ((ok r) r.pid)
    ((err _) -1))

fn ! aliveAfterReap! pid: Int64 -> Bool
  (let [(_ (procWaitPid pid true))
        (_ (sleepMs 200))
        (_ (procWaitPid pid true))]
    (resultOr (procAlive? pid) false))

fn errText r: (Result Unit String) -> String
  (match r ((ok _) "ok") ((err e) e))

fn ! finish! pids: (List Int64) -> Int64
  (fold (fn [(n Int64) (p Int64)] (let [(_ (procKill p "SIGKILL")) (_ (procWaitPid p true))] (+ n 1))) 0 pids)

fn ! runTests -> Bool
  (let [(m (mod (procSelf) 90))
        (a (startSleeper! (stringFromInt64 (+ 100 m))))
        (b (startSleeper! (stringFromInt64 (+ 200 m))))
        (c (startSleeper! (stringFromInt64 (+ 300 m))))
        (d (startSleeper! (stringFromInt64 (+ 400 m))))
        (bad1 (errText (procKill a "FOO")))
        (bad2 (errText (procKill a "")))
        (bad3 (errText (procKill a "kill")))
        (aliveAfterBad (resultOr (procAlive? a) false))
        (kBare (errText (procKill a "KILL")))
        (kFull (errText (procKill b "SIGKILL")))
        (tBare (errText (procKill c "TERM")))
        (tFull (errText (procKill d "SIGTERM")))
        (aGone (not (aliveAfterReap! a)))
        (bGone (not (aliveAfterReap! b)))
        (cGone (not (aliveAfterReap! c)))
        (dGone (not (aliveAfterReap! d)))
        (cleaned (finish! (list a b c d)))]
    (do (assert (and (> a 1) (and (> b 1) (and (> c 1) (> d 1)))) "four sleepers started")
        (assert (= cleaned 4) "every sleeper was killed and reaped before the asserts below")
        (assert (and (= bad1 "io:22") (and (= bad2 "io:22") (= bad3 "io:22"))) (str "an unknown, an empty and a lower-case name are io:22: " bad1 " " bad2 " " bad3))
        (assert aliveAfterBad "a refused name does not signal the process")
        (assert (= kFull "ok") (str "SIGKILL kills: " kFull))
        (assert (= kBare "ok") (str "the bare name KILL is accepted: " kBare))
        (assert (and (= tFull "ok") (= tBare "ok")) (str "SIGTERM and the bare TERM are accepted: " tFull " " tBare))
        (assert (and aGone (and bGone (and cGone dGone))) "all four sleepers are gone after the kills")
        true))
