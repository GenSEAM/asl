(module asl/tools/coord/tests/janitorTest
  :x [runTests]
  :i [(asl-tools/coord/janitor :a j) (asl-tools/fleet/run :a fr)])

; (:m :ref RES-JANITOR :do "pure plan over fixture listings (live pid, young, old, lookalike names, merged clean, merged dirty, blocked, level gate, bound) and one end-to-end run in a private base: dry-run deletes nothing, apply removes only planned paths and a sibling file survives")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/janitorTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> Bool
  (= (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).exit 0)

fn cfg0 -> j/Cfg
  (j/Cfg :tmp "/t" :runDir "/r" :modePath "/m" :storeDir "/s" :repo "/repo" :wtBase "/wts"
         :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20 :budgetS 30)

fn sc name: String age: Int64 -> j/Scratch
  (j/Scratch :name name :path (str "/t/" name) :bytes 1000 :mtimeS (- 1000000 age))

fn wt unit: String dirty: Int64 merged: Bool st: String -> j/WtFact
  (j/WtFact :unit unit :path (str "/wts/asex-" unit) :bytes 5000 :dirty dirty :merged merged :detached false :foreign 0 :st st)

fn lst level: String scratch: (List j/Scratch) alive: (List Int64) wts: (List j/WtFact) -> j/Listing
  (j/Listing :nowS 1000000 :level level :scratch scratch :alive alive :held (list) :wts wts)

fn paths rows: (List j/Row) -> (List String)
  (map (fn [(r j/Row)] -> String r.path) rows)

fn ! testPure -> Bool
  (let [(c (cfg0))
        (old 7200)
        (young 600)]
    (do
      (assert (= (j/scratchPid "aslRun-123-abc") 123) "aslRun pid parsed")
      (assert (= (j/scratchPid "cmdTest-77") 77) "cmdTest pid parsed")
      (assert (= (j/scratchPid "loopRunTest_88") 88) "loopRunTest pid parsed")
      (assert (= (j/scratchPid "formsPin-5000-x-y") 5000) "dash suffix may contain dashes")
      (assert (= (j/scratchPid "cmdTestX") -1) "lookalike without pid is not a match")
      (assert (= (j/scratchPid "cmdTest-12x") -1) "pid with letters is not a match")
      (assert (= (j/scratchPid "aslRun-123") -1) "aslRun needs a suffix")
      (assert (= (j/scratchPid "xcmdTest-123") -1) "prefix must start the name")
      (assert (= (j/scratchPid "cmdTest-1") -1) "pid 1 is never a match")
      (assert (= (listLength (j/plan c (lst "low" (list (sc "cmdTest-4242" old)) (list 4242) (list)))) 0) "a live pid is kept")
      (assert (= (listLength (j/plan c (lst "low" (list (sc "cmdTest-4242" young)) (list) (list)))) 0) "a dead pid that is too young is kept")
      (assert (= (paths (j/plan c (lst "low" (list (sc "cmdTest-4242" old)) (list) (list)))) (list "/t/cmdTest-4242")) "a dead pid that is old is reclaimed")
      (assert (= (listLength (j/plan c (lst "low" (list (sc "cmdTestX" old) (sc "cmdTest-4242x" old) (sc "other" old)) (list) (list)))) 0) "names that only look similar are kept")
      (assert (= (listLength (j/plan c (lst "ok" (list (sc "cmdTest-4242" old)) (list) (list)))) 0) "level ok keeps scratch younger than a day")
      (assert (= (listLength (j/plan c (lst "ok" (list (sc "cmdTest-4242" 90000)) (list) (list)))) 1) "scratch older than a day is eligible at level ok")
      (assert (= (listLength (j/plan c (lst "ok" (list (sc "cmdTest-4242" 90000)) (list 4242) (list)))) 0) "a live pid is kept even past a day")
      (assert (= (paths (j/plan c (lst "stop" (list) (list) (list (wt "u1" 0 true "merged"))))) (list "/wts/asex-u1")) "a merged clean worktree is reclaimed")
      (assert (= (listLength (j/plan c (lst "stop" (list) (list) (list (wt "u1" 2 true "merged"))))) 0) "a merged dirty worktree is kept")
      (assert (= (listLength (j/plan c (lst "stop" (list) (list) (list (wt "u1" 0 false "merged"))))) 0) "a worktree ahead of main is kept")
      (assert (= (listLength (j/plan c (lst "stop" (list) (list) (list (wt "u2" 0 true "blocked") (wt "u3" 0 true "escalated") (wt "u4" 0 true "writing"))))) 0) "blocked, escalated and running units keep their worktree")
      (assert (= (listLength (j/plan c (lst "ok" (list) (list) (list (wt "u1" 0 true "merged"))))) 0) "level ok reclaims no worktree")
      (assert (= (listLength (j/plan c (lst "low" (list) (list) (list (wt "main" 0 true "merged"))))) 0) "a protected unit is kept")
      (assert (= (listLength (j/plan (with c :maxPaths 2) (lst "low" (list (sc "cmdTest-4242" old) (sc "cmdTest-4243" old) (sc "cmdTest-4244" old)) (list) (list)))) 2) "the plan is bounded by maxPaths")
      (assert (= (j/scratchPid "aslOpsTest_55") -1) "aslOpsTest_ is not a pid name")
      (assert (= (j/scratchPid "aslNCacheLockTest_55") -1) "aslNCacheLockTest_ is not a pid name")
      (assert (= (j/foreignIgnored (list "!! asl/host/out/" "!! .asl/cache/x.bin" "!! .asl/build/" "?? new.txt")) 0) "ignored build allowlist is not foreign")
      (assert (= (j/foreignIgnored (list "!! asl/host/out/" "!! .asl/mem/work/x.asn")) 1) "an ignored mem ledger file is foreign")
      (assert (= (j/foreignIgnored (list "!! .asl/mem/sessions/" "!! a.local.asn" "!! .asl/")) 3) "sessions, local asn and a collapsed .asl dir are foreign")
      (assert (= (j/foreignIgnored (list "!! asl/host/outside/")) 1) "a prefix lookalike of the allowlist is foreign")
      (assert (= (j/modeOf "(:janitor :mode apply)\n") "apply") "a form with a trailing newline reads apply")
      (assert (= (j/modeOf "; (:janitor :mode apply)\n") "dry") "a comment alone reads dry")
      (assert (= (j/modeOf "; note :mode apply\n(:janitor :mode dry)\n") "dry") "a comment never overrides the form")
      (assert (= (j/modeOf "") "dry") "no text reads dry")
      (assert (not (= (j/modeOf "(:janitor :mode applyx)") "apply")) "a lookalike token is not apply")
      (assert (j/aliveFrom (err "probe failed")) "a failed liveness probe counts as alive")
      (assert (not (j/aliveFrom (ok false))) "a dead pid reads dead")
      (assert (j/aliveFrom (ok true)) "a live pid reads alive")
      (assert (= (listLength (j/plan c (lst "stop" (list) (list) (list (with (wt "u1" 0 true "merged") :foreign 1))))) 0) "a merged clean worktree with a foreign ignored file is kept")
      (assert (= (listLength (j/plan c (lst "stop" (list) (list) (list (with (wt "u1" 0 true "merged") :detached true))))) 0) "a detached worktree is kept")
      (assert (j/heldName? "aslRebuildKeepsPriorRtTest-123") "rebuild test leftover name")
      (assert (j/heldName? "conductorTest-9-x") "conductorTest leftover name")
      (assert (j/heldName? "trialDriver-abc") "trialDriver leftover name")
      (assert (not (j/heldName? "trialDriver-")) "a bare prefix is not a leftover")
      (assert (not (j/heldName? "aslStubHost-1")) "aslStubHost is not in the table")
      (assert (not (j/heldName? "xconductorTest-1")) "the prefix must start the name")
      (assert (= (paths (j/plan c (lst "low" (list (sc "aslRebuildKeepsPriorRtTest-77" old) (sc "trialDriver-5" old) (sc "conductorTest-3-a" old)) (list) (list)))) (list "/t/aslRebuildKeepsPriorRtTest-77" "/t/trialDriver-5" "/t/conductorTest-3-a")) "old leftovers of the three patterns are listed")
      (assert (= (listLength (j/plan c (lst "low" (list (sc "trialDriver-5" young)) (list) (list)))) 0) "a fresh leftover is within grace and kept")
      (assert (= (listLength (j/plan c (lst "low" (list (sc "aslStubHost-1" old)) (list) (list)))) 0) "aslStubHost is never listed")
      (assert (= (listLength (j/plan c (lst "ok" (list (sc "trialDriver-5" old)) (list) (list)))) 0) "level ok keeps a leftover younger than a day")
      (assert (= (listLength (j/plan c (with (lst "low" (list (sc "trialDriver-5" old)) (list) (list)) :held (list "/t/trialDriver-5")))) 0) "a held leftover is kept")
      (assert (j/heldFrom 124 "") "lsof timeout counts as held")
      (assert (j/heldFrom 127 "") "lsof missing counts as held")
      (assert (j/heldFrom 2 "") "lsof error counts as held")
      (assert (j/heldFrom 1 "4242\n") "lsof output on exit 1 counts as held")
      (assert (not (j/heldFrom 1 "")) "lsof exit 1 with no output is free")
      (assert (j/freshFrom 0 "/t/x\n") "an entry newer than the window is fresh")
      (assert (not (j/freshFrom 0 "")) "no entry newer than the window is stale")
      (assert (j/freshFrom 124 "") "a find timeout keeps the dir")
      (assert (j/freshFrom 2 "") "a find error keeps the dir")
      (let [(many (listAppend (map (fn [(i Int64)] -> String (str "aslRun-" (stringFromInt64 (+ 100 i)) "-x")) (range 0 150)) (list "trialDriver-1")))
            (capped (j/capNames many 100))]
        (do (assert (listContains? capped "trialDriver-1") "a per-pattern cap keeps the other patterns in the scan")
            (assert (= (listLength capped) 101) "aslRun-* is capped at 100")
            true))
      (assert (stringContains? (j/renderRow (j/Row :class "a" :path "/t/x" :bytes 7 :why "w" :unit "")) "(:reclaim :path \"/t/x\" :bytes 7") "row rendering")
      true))

fn ! exists? p: String -> Bool
  (fileExists? p)

fn ! mkOld! dir: String -> Bool
  (and (= (sh "." (list "mkdir" "-p" dir)).exit 0)
    (and (put (str dir "/f.txt") "x")
      (= (sh "." (list "touch" "-t" "202001010000" dir (str dir "/f.txt"))).exit 0)))

fn ! mkIdle! dir: String -> Bool
  (and (mkOld! dir)
    (and (put (str dir "/new.txt") "fresh")
      (= (sh "." (list "touch" "-t" "202001010000" dir)).exit 0)))

fn ! testE2e base: String -> Bool
  (let [(tmp (str base "/tmp"))
        (repo (str base "/repo"))
        (wts (str base "/wts"))
        (store (str base "/store"))
        (c (j/Cfg :tmp tmp :runDir (str base "/run") :modePath (str base "/mode.asn") :storeDir store :repo repo :wtBase wts
                  :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20 :budgetS 30))
        (dead (str tmp "/cmdTest-3999999"))
        (live (str tmp "/cmdTest-" (stringFromInt64 (procSelf))))
        (look (str tmp "/cmdTestX"))
        (young (str tmp "/cmdTest-3999998"))
        (sib (str tmp "/sibling.txt"))
        (wtDone (str wts "/asex-done"))
        (wtIgn (str wts "/asex-ign"))
        (wtCache (str wts "/asex-cache"))
        (link (str tmp "/cmdTest-3999997"))
        (target (str base "/target"))
        (wtBlocked (str wts "/asex-blocked"))]
    (do
      (assert (not (resultOr (procAlive? 3999999) false)) "the fixture pid is not alive")
      (assert (= (sh "." (list "mkdir" "-p" tmp store (str store "/cond"))).exit 0) "private base")
      (assert (mkOld! dead) "dead old scratch")
      (assert (mkOld! live) "live old scratch")
      (assert (mkOld! look) "lookalike old scratch")
      (assert (= (sh "." (list "mkdir" "-p" young)).exit 0) "young dead scratch")
      (assert (put sib "keep") "sibling file")
      (assert (= (sh "." (list "mkdir" "-p" repo)).exit 0) "repo dir")
      (assert (git repo (list "init" "-q" "-b" "main")) "repo init")
      (assert (put (str repo "/a.txt") "1\n") "repo file")
      (assert (put (str repo "/.gitignore") ".asl/mem/work/\n.asl/cache/\n") "gitignore")
      (assert (git repo (list "add" "-A")) "repo add")
      (assert (git repo (list "commit" "-q" "-m" "base")) "repo commit")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/done" wtDone "main")) "merged worktree")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/blocked" wtBlocked "main")) "blocked worktree")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/ign" wtIgn "main")) "worktree with ignored ledger")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/cache" wtCache "main")) "worktree with ignored cache")
      (assert (= (sh "." (list "mkdir" "-p" (str wtIgn "/.asl/mem/work") (str wtCache "/.asl/cache"))).exit 0) "ignored dirs")
      (assert (put (str wtIgn "/.asl/mem/work/x.asn") "plan") "ignored ledger file")
      (assert (put (str wtCache "/.asl/cache/c.bin") "obj") "ignored cache file")
      (assert (put (str store "/cond/ign.asn") "(:cu :id \"ign\" :st merged :wt \"\")") "cond row ign merged")
      (assert (put (str store "/cond/cache.asn") "(:cu :id \"cache\" :st merged :wt \"\")") "cond row cache merged")
      (assert (mkOld! target) "symlink target dir")
      (assert (= (sh "." (list "ln" "-s" target link)).exit 0) "dead-pid symlink into another dir")
      (assert (put (str store "/cond/done.asn") "(:cu :id \"done\" :st merged :wt \"\")") "cond row merged")
      (assert (put (str store "/cond/blocked.asn") "(:cu :id \"blocked\" :st blocked :wt \"\")") "cond row blocked")
      (assert (put (str store "/slots.asn") "(:slots :base 4 :level low)") "level low")
      (let [(t1 (j/tick! c))]
        (do
          (assert (stringContains? t1 ":mode dry") "default mode is dry")
          (assert (stringContains? t1 "cmdTest-3999999") "dry plan names the dead scratch")
          (assert (stringContains? t1 "asex-done") "dry plan names the merged worktree")
          (assert (and (exists? dead) (and (exists? wtDone) (exists? sib))) "dry-run deletes nothing")
          (assert (exists? (str base "/run/janitor.asn")) "dry-run writes the plan file")
          (assert (put (str base "/mode.asn") "; (:janitor :mode apply)\n") "comment-only mode file")
          (assert (not (j/modeApply? c)) "a comment holding :mode apply does not enable deletion")
          (assert (put (str base "/mode.asn") "(:janitor :mode apply)\n") "mode file in the private base")
          (assert (j/modeApply? c) "the mode form with a trailing newline enables apply")
          (let [(stale (j/apply! c (list (j/Row :class "b" :path wtIgn :bytes 1 :why "stale" :unit "ign")
                                         (j/Row :class "b" :path wtBlocked :bytes 1 :why "stale" :unit "blocked")
                                         (j/Row :class "a" :path live :bytes 1 :why "stale" :unit "")
                                         (j/Row :class "a" :path young :bytes 1 :why "stale" :unit ""))))]
            (do
              (assert (= stale 0) "a stale plan is fully processed within the budget")
              (assert (and (exists? wtIgn) (exists? (str wtIgn "/.asl/mem/work/x.asn"))) "apply re-checks ignored files before removal")
              (assert (exists? wtBlocked) "apply re-checks the conductor state before removal")
              (assert (and (exists? live) (exists? young)) "apply re-checks pid liveness and age before removal")
              true))
          (let [(t0 (j/tick! (with c :budgetS 0)))]
            (do
              (assert (stringContains? t0 ":mode apply") "apply mode read under a zero budget")
              (assert (and (exists? dead) (exists? wtDone)) "a zero budget defers every removal")
              (assert (stringContains? (resultOr (fileReadString (str base "/run/janitor.asn")) "") "(:deferred :n") "deferred rows are recorded")
              true))
          (let [(t2 (j/tick! c))]
            (do
              (assert (stringContains? t2 ":mode apply") "apply mode read")
              (assert (not (exists? dead)) "apply removes the dead old scratch")
              (assert (not (exists? wtDone)) "apply removes the merged clean worktree")
              (assert (exists? live) "a live pid dir survives")
              (assert (exists? look) "a lookalike dir survives")
              (assert (exists? young) "a young dir survives")
              (assert (exists? wtBlocked) "a blocked unit worktree survives")
              (assert (exists? sib) "a sibling file survives")
              (assert (exists? wtIgn) "a worktree holding an ignored ledger file survives")
              (assert (exists? (str wtIgn "/.asl/mem/work/x.asn")) "the ignored ledger file survives")
              (assert (not (exists? wtCache)) "a worktree with only allowlisted ignored files is removed")
              (assert (exists? link) "a symlink into another dir survives")
              (assert (exists? (str target "/f.txt")) "the symlink target survives")
              (assert (stringContains? (resultOr (fileReadString (str base "/run/janitor.asn")) "") (str "(:removed :path \"" dead "\"")) "a removed row is appended per removal")
              (assert (exists? repo) "the repo survives")
              true))))))

fn ! testHeld base: String -> Bool
  (let [(tmp (str base "/tmp"))
        (c (j/Cfg :tmp tmp :runDir (str base "/run") :modePath (str base "/mode.asn") :storeDir (str base "/store") :repo (str base "/none") :wtBase (str base "/wts")
                  :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20 :budgetS 30))
        (oldD (str tmp "/aslRebuildKeepsPriorRtTest-111"))
        (freshD (str tmp "/trialDriver-222"))
        (heldD (str tmp "/conductorTest-333"))
        (stubD (str tmp "/aslStubHost-444"))
        (idleD (str tmp "/trialDriver-666"))
        (deep (str tmp "/sub/deep"))
        (linkG (str tmp "/trialDriver-777"))
        (linkT (str tmp "/trialDriver-778"))]
    (do
      (assert (= (sh "." (list "mkdir" "-p" tmp (str base "/store"))).exit 0) "held fixture base")
      (assert (and (mkOld! oldD) (and (mkOld! heldD) (mkOld! stubD))) "old leftovers")
      (assert (= (sh "." (list "mkdir" "-p" freshD)).exit 0) "fresh leftover")
      (assert (mkIdle! idleD) "idle leftover: old top directory, fresh file inside")
      (assert (mkOld! deep) "old grandchild of TMPDIR")
      (assert (= (sh "." (list "ln" "-s" deep linkG)).exit 0) "symlink to a TMPDIR grandchild")
      (assert (= (sh "." (list "ln" "-s" tmp linkT)).exit 0) "symlink to TMPDIR itself")
      (match (fr/guardStart! (list "sleep" "60") heldD (fr/childEnv (list)) (fr/limits 90 4))
        ((err _) (assert false "a live holder started"))
        ((ok g)
          (let [(t1 (j/tick! c))
                (_ (put (str base "/mode.asn") "(:janitor :mode apply)\n"))
                (_ (sleepMs 300))
                (stale (j/apply! c (list (j/Row :class "a" :path heldD :bytes 1 :why "stale" :unit ""))))
                (loose (j/apply! c (list (j/Row :class "a" :path linkG :bytes 1 :why "stale" :unit "") (j/Row :class "a" :path linkT :bytes 1 :why "stale" :unit ""))))
                (t2 (j/tick! c))
                (_ (fr/killTree! g.run.pid))]
            (do
              (assert (stringContains? t1 "aslRebuildKeepsPriorRtTest-111") "dry plan lists the old leftover")
              (assert (not (stringContains? t1 "conductorTest-333")) "the held leftover is not listed")
              (assert (not (stringContains? t1 "trialDriver-222")) "the fresh leftover is not listed")
              (assert (not (stringContains? t1 "aslStubHost-444")) "aslStubHost is not listed")
              (assert (and (= stale 0) (fileExists? heldD)) "a stale plan row for a held dir is refused at removal")
              (assert (and (= loose 0) (and (fileExists? linkG) (and (fileExists? linkT) (fileExists? (str deep "/f.txt"))))) "symlinks to a TMPDIR grandchild and to TMPDIR itself are refused")
              (assert (not (stringContains? t1 "trialDriver-666")) "an idle leftover with fresh content inside is not listed")
              (assert (fileExists? idleD) "the idle leftover survives apply")
              (assert (not (fileExists? oldD)) "apply removed the old leftover")
              (assert (and (fileExists? heldD) (and (fileExists? freshD) (fileExists? stubD))) "held, fresh and stub leftovers survive")
              true))))
      true))

fn ! runTests -> Bool
  (let [(base (scratch))]
    (do (assert (testPure) "pure plan")
        (assert (testE2e base) "end to end")
        (assert (testHeld (str base "-held")) "leftover patterns with a live holder")
        (assert (= (sh "." (list "rm" "-rf" base (str base "-held"))).exit 0) "private bases removed")
        true))
