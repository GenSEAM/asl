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
         :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20)

fn sc name: String age: Int64 -> j/Scratch
  (j/Scratch :name name :path (str "/t/" name) :bytes 1000 :mtimeS (- 1000000 age))

fn wt unit: String dirty: Int64 merged: Bool st: String -> j/WtFact
  (j/WtFact :unit unit :path (str "/wts/asex-" unit) :bytes 5000 :dirty dirty :merged merged :st st)

fn lst level: String scratch: (List j/Scratch) alive: (List Int64) wts: (List j/WtFact) -> j/Listing
  (j/Listing :nowS 1000000 :level level :scratch scratch :alive alive :wts wts)

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
      (assert (stringContains? (j/renderRow (j/Row :class "a" :path "/t/x" :bytes 7 :why "w" :unit "")) "(:reclaim :path \"/t/x\" :bytes 7") "row rendering")
      true))

fn ! exists? p: String -> Bool
  (fileExists? p)

fn ! mkOld! dir: String -> Bool
  (and (= (sh "." (list "mkdir" "-p" dir)).exit 0)
    (and (put (str dir "/f.txt") "x")
      (= (sh "." (list "touch" "-t" "202001010000" dir)).exit 0)))

fn ! testE2e base: String -> Bool
  (let [(tmp (str base "/tmp"))
        (repo (str base "/repo"))
        (wts (str base "/wts"))
        (store (str base "/store"))
        (c (j/Cfg :tmp tmp :runDir (str base "/run") :modePath (str base "/mode.asn") :storeDir store :repo repo :wtBase wts
                  :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20))
        (dead (str tmp "/cmdTest-3999999"))
        (live (str tmp "/cmdTest-" (stringFromInt64 (procSelf))))
        (look (str tmp "/cmdTestX"))
        (young (str tmp "/cmdTest-3999998"))
        (sib (str tmp "/sibling.txt"))
        (wtDone (str wts "/asex-done"))
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
      (assert (git repo (list "add" "-A")) "repo add")
      (assert (git repo (list "commit" "-q" "-m" "base")) "repo commit")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/done" wtDone "main")) "merged worktree")
      (assert (git repo (list "worktree" "add" "-q" "-b" "sh/blocked" wtBlocked "main")) "blocked worktree")
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
          (assert (put (str base "/mode.asn") "(:janitor :mode apply)") "mode file in the private base")
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
              (assert (exists? repo) "the repo survives")
              true))))))

fn ! runTests -> Bool
  (let [(base (scratch))]
    (do (assert (testPure) "pure plan")
        (assert (testE2e base) "end to end")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
