(module asl/packages/asl-target-llvm/tests/procKillNameTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PROCKILL-SIGNAL-NAME :do "procKill takes a signal by its SIG name or by the bare name: four own sleepers (per-run unique seconds) are killed with KILL and SIGKILL, TERM and SIGTERM; a name in neither spelling, an empty one and a lower-case one are refused with io:22 and the sleeper lives; bindings run when first used, so each step takes the one before as dep, and a final SIGKILL of every sleeper runs before the first assert, so a red run leaves none")

fn ! spawn! secs: String -> Int64
  (match (fr/spawnSep (list "sleep" secs) "." (fr/childEnv (list)))
    ((ok r) r.pid)
    ((err _) -1))

fn ! aliveAfterReap! pid: Int64 dep: Int64 -> Bool
  (let [(_ (procWaitPid pid true))
        (_ (sleepMs (+ 200 (* 0 dep))))
        (_ (procWaitPid pid true))]
    (resultOr (procAlive? pid) false))

fn errText r: (Result Unit String) -> String
  (match r ((ok _) "ok") ((err e) e))

fn ! finish! pids: (List Int64) dep: Int64 -> Int64
  (fold (fn [(n Int64) (p Int64)] (let [(_ (procKill p "SIGKILL")) (_ (procWaitPid p true))] (+ n 1))) (* 0 dep) pids)

fn ! runTests -> Bool
  (let [(m (mod (procSelf) 90))
        (a (spawn! (stringFromInt64 (+ 100 m))))
        (b (spawn! (stringFromInt64 (+ 200 m))))
        (c (spawn! (stringFromInt64 (+ 300 m))))
        (d (spawn! (stringFromInt64 (+ 400 m))))
        (bad1 (errText (procKill (+ a (* 0 b)) "FOO")))
        (bad2 (errText (procKill (+ a (* 0 (stringLength bad1))) "")))
        (bad3 (errText (procKill (+ a (* 0 (stringLength bad2))) "kill")))
        (aliveAfterBad (resultOr (procAlive? (+ a (* 0 (stringLength bad3)))) false))
        (kBare (errText (procKill (+ a (* 0 (stringLength bad3))) (if aliveAfterBad "KILL" "KILL"))))
        (kFull (errText (procKill (+ b (* 0 (stringLength kBare))) "SIGKILL")))
        (tBare (errText (procKill (+ c (* 0 (stringLength kFull))) "TERM")))
        (tFull (errText (procKill (+ d (* 0 (stringLength tBare))) "SIGTERM")))
        (aGone (not (aliveAfterReap! a (stringLength tFull))))
        (bGone (not (aliveAfterReap! b (stringLength tFull))))
        (cGone (not (aliveAfterReap! c (stringLength tFull))))
        (dGone (not (aliveAfterReap! d (stringLength tFull))))
        (cleaned (finish! (list a b c d) (+ (if aGone 1 0) (+ (if bGone 1 0) (+ (if cGone 1 0) (if dGone 1 0))))))]
    (do (assert (and (> a 1) (and (> b 1) (and (> c 1) (> d 1)))) "four sleepers started")
        (assert (= cleaned 4) "every sleeper was killed and reaped before the asserts below")
        (assert (and (= bad1 "io:22") (and (= bad2 "io:22") (= bad3 "io:22"))) (str "an unknown, an empty and a lower-case name are io:22: " bad1 " " bad2 " " bad3))
        (assert aliveAfterBad "a refused name does not signal the process")
        (assert (= kFull "ok") (str "SIGKILL kills: " kFull))
        (assert (= kBare "ok") (str "the bare name KILL is accepted: " kBare))
        (assert (and (= tFull "ok") (= tBare "ok")) (str "SIGTERM and the bare TERM are accepted: " tFull " " tBare))
        (assert (and aGone (and bGone (and cGone dGone))) "all four sleepers are gone after the kills")
        true))
