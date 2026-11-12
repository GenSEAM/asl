(module asl-tools/fleet/tests/runTmpTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref TMP-LEAK-RUNNER :do "a pooled or guarded child gets its own scratch dir in ASL_RUN_TMP under the caller's base and the runner removes it after every verdict while TMPDIR stays the caller's: the child prints both, writes a file in the scratch dir and exits or sleeps past a 2 s timeout; afterwards the dir is gone, the base and a sibling file are untouched, fr/spawn creates no aslRun dir, and stopGuard! removes the dir of a guarded child it stops; every child is bounded by a 2 s limit or killed with its tree")
fn scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/runTmpTest-" (stringFromInt64 (procSelf)))

fn script life: String -> String
  (str "echo RT=$ASL_RUN_TMP; echo TT=$TMPDIR; touch \"$ASL_RUN_TMP/payload\"; exec sleep " life)

fn keyOf text: String key: String -> String
  (stringReplace (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x key)) (stringLines text))) key) key "")

fn ! envFor base: String -> (List String)
  (fr/childEnv (list (str "TMPDIR=" base)))

fn ! pooled life: String base: String -> fr/Done
  (fr/runOneLimited (fr/job (list "sh" "-c" (script life)) "." (envFor base)) (fr/limits 2 8))

fn ! guarded life: String base: String -> fr/ProcOut
  (fr/runGuarded (list "sh" "-c" (script life)) "." (envFor base) (fr/limits 2 8))

fn ! aslRunIn base: String -> (List String)
  (filter (fn [(n String)] -> Bool (stringContains? n "aslRun-")) (resultOr (dirList base) (list)))

fn ! spawnedNoDir base: String -> Bool
  (match (fr/spawn 0 (fr/job (list "sh" "-c" "exec sleep 30") "." (envFor base)))
    ((err _) false)
    ((ok r) (let [(here (aslRunIn base)) (_ (fr/killTree! r.pid)) (_ (procWaitPid r.pid false))] (listEmpty? here))))

fn ! stopRemoves base: String -> Bool
  (match (fr/guardStart! (list "sh" "-c" (script "30")) "." (envFor base) (fr/limits 20 8))
    ((err _) false)
    ((ok g) (let [(made (aslRunIn base))
                  (_ (sleepMs 300))
                  (_ (fr/stopGuard! g))
                  (_ (procWaitPid g.run.pid false))]
              (and (= (listLength made) 1) (listEmpty? (aslRunIn base))))))

fn ! runTests -> Bool
  (let [(base (scratch))
        (_ (pathRemove base))
        (_ (dirCreate base))
        (_ (fileWrite (str base "/sibling") "keep"))
        (k (pooled "60" base))
        (kd (keyOf k.out "RT="))
        (e (pooled "0" base))
        (ed (keyOf e.out "RT="))
        (g (guarded "60" base))
        (gd (keyOf g.stdout "RT="))
        (leftover (aslRunIn base))
        (noDir (spawnedNoDir base))
        (stopOk (stopRemoves base))
        (siblingKept (= (resultOr (fileReadString (str base "/sibling")) "") "keep"))
        (_ (pathRemove base))]
    (do (assert (= k.verdict "timeout") (str "the sleeping child is killed by its timeout: " k.verdict))
        (assert (stringStartsWith? kd (str base "/aslRun-")) (str "the child's scratch dir is fresh under the caller's base: " kd))
        (assert (stringStartsWith? ed (str base "/aslRun-")) (str "an exiting child gets one too: " ed))
        (assert (stringStartsWith? gd (str base "/aslRun-")) (str "a guarded child gets one: " gd))
        (assert (and (not (= kd ed)) (not (= kd gd))) "each child has its own dir")
        (assert (= (keyOf k.out "TT=") base) (str "the pooled child's TMPDIR is the caller's: " (keyOf k.out "TT=")))
        (assert (= (keyOf g.stdout "TT=") base) (str "the guarded child's TMPDIR is the caller's: " (keyOf g.stdout "TT=")))
        (assert g.timedOut "the guarded sleeper is killed by its timeout")
        (assert (not (fileExists? kd)) (str "the killed child's scratch dir is gone: " kd))
        (assert (not (fileExists? ed)) (str "the exited child's scratch dir is gone: " ed))
        (assert (not (fileExists? gd)) (str "the guarded killed child's scratch dir is gone: " gd))
        (assert (listEmpty? leftover) (str "no aslRun dir remains in the base: " (stringJoin leftover " ")))
        (assert noDir "fr/spawn creates no aslRun dir")
        (assert stopOk "stopGuard! removes the dir of the guard it stops")
        (assert siblingKept "a file the runner did not create is untouched")
        true))
