(module aslAgent/tests/providerWaitRowTest
  :x [runTests]
  :i [(aslAgent/main :a m)])

; (:m :ref WRITE-STAGE-YIELD :do "each provider retry pause appends one (:providerWait :turn N :sec S) row to the run journal before it sleeps and returns the sleep's own answer, so the conductor's stall probe sees a writer waiting on its provider")
fn ! runTests -> Bool
  (let [(dir (str (resultOr (realPath ".") ".") "/.asl/cache/providerWaitRowTest-" (stringFromInt64 (procSelf))))
        (_ (dirCreate (str (resultOr (realPath ".") ".") "/.asl")))
        (_ (dirCreate (str (resultOr (realPath ".") ".") "/.asl/cache")))
        (_ (dirCreate dir))
        (path (str dir "/run.journal"))
        (_ (fileWrite path "(:session :id \"t\")\n"))
        (slept (fn [(secs Int64)] -> Bool (> secs 30)))
        (wrapped (m/providerWaitSleep! path 7 slept))
        (a (wrapped 60))
        (b (wrapped 2))
        (text (resultOr (fileReadString path) ""))
        (_ (pathRemove path))
        (_ (pathRemove dir))]
    (do (assert (stringContains? text "(:providerWait :turn 7 :sec 60)\n(:providerWait :turn 7 :sec 2)\n") (str "one row per pause, in order: " text))
        (assert (and a (not b)) "the wrapper returns what the wrapped sleep returned")
        (assert (stringStartsWith? text "(:session :id \"t\")\n") "the rows are appended, the journal head is kept")
        true))
