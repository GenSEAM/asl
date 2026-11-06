(module asl-tools/coord/tests/trialDriverTest
  :x [runTests]
  :i [(asl-tools/coord/trial :a tr) (asl-tools/coord/conductor :a cd) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref LEON-TRIAL :do "TRIAL-DRIVER gate: trial.asl check, run and collect as children on a temp source repo (pipeFix e2eRepo!, the spec base is the pipeFix seedUnit! branch sh/BASE, main plus marker.txt that every cell gate needs), its dev clone (pipeFix devCloneFor!: branch dev, origin remote removed after the remote case, a stand-in host build added after the build cases), a temp store and a stand-in production repo; the write stage runs the real conductor stage child whose Leon is a scripted bin/asl in the temp repo (good: writes impl.txt; readloop: three read turns, a readStreak signal, and it moves the production head mid-run), gates run the real gate, review goes through the real provider to the hub stand-in, merge trains onto trialDev-<cell> with the recording train of the dev clone. The one stand-in for an interface not on main: the TRIAL-PIN receipt file <id>-leon.asn is pre-written for one cell; collect runs the real trialAnalyze report on the records")

fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

; (:m :do "scripted Leon: the conductor starts <repo>/bin/asl with the (:agent ...) form in the unit worktree; any other call goes to the real CLI of this worktree; in readloop mode it also moves the production stand-in ref trialProbe one commit back, a stage moving a production head mid-run; a good run first copies seeded.txt, when its worktree has one, to <repo>/.git/seen-<id>")
fn leonScript here: String repo: String prod: String -> String
  (str "#!/bin/sh\ncase \"$1\" in\n  \"(:agent\"*) ;;\n  *) exec " here "/bin/asl \"$@\" ;;\nesac\n"
       "id=$(basename \"$PWD\"); id=${id#asex-}\nmode=$(cat " repo "/.git/leonMode-$id 2>/dev/null)\nmkdir -p .asl/run/agentLoop\nj=.asl/run/agentLoop/s$id.journal\n"
       "if [ \"$mode\" = readloop ]; then\n"
       "  for t in 1 2 3; do echo \"(:turn $t :reply \\\"(:step :op read :file check.sh)\\\")\" >> $j; done\n"
       "  echo \"(:turn 3 :signal :readStreak :cause :notFound :reason \\\"3 turns in a row persisted nothing\\\")\" >> $j\n"
       "  git -C " prod " branch -f trialProbe HEAD~1\n"
       "  echo \"(:result :status :escalated :stop readStreak :turns 3)\" >> $j\n"
       "  echo \"(:agent :status :failed :receipt (:agentReceipt :status :escalated :stop readStreak :servedAlias \\\"flashLow\\\" :turns 3))\"\n"
       "  exit 1\nfi\n"
       "[ -f seeded.txt ] && cp seeded.txt " repo "/.git/seen-$id\n"
       "printf impl > impl.txt\necho \"(:turn 1 :reply \\\"(:step :op edit :file impl.txt)\\\")\" >> $j\necho \"(:result :status :ok :stop done :turns 1)\" >> $j\n"
       "echo \"(:agent :status :ok :receipt (:agentReceipt :status :ok :stop done :servedAlias \\\"flashLow\\\" :turns 1))\"\nexit 0\n")

fn seedPatch -> String
  "diff --git a/impl.txt b/impl.txt\nnew file mode 100644\n--- /dev/null\n+++ b/impl.txt\n@@ -0,0 +1 @@\n+impl\n"

fn bugPatch -> String
  "diff --git a/seeded.txt b/seeded.txt\nnew file mode 100644\n--- /dev/null\n+++ b/seeded.txt\n@@ -0,0 +1 @@\n+bug\n"

fn specText root: String here: String prodSha: String devRepo: String -> String
  (str "(:trialSpec :store \"" root "/store\" :repo \"" root "/repo\" :toolRoot \"" here "\" :devRepo \"" devRepo "\" :devPrefix \"trialDev-\" :devBase \"dev\""
       " :worktrees \"" root "/wts\" :home \"" root "/home\" :lanes \"" root "/home/lanes.asn\" :base \"sh/BASE\" :leaseSec 600 :writers 1 :gates 1 :reviews 1 :stageSec 600"
       " :minFreeMb 0 :minDiskMb 1)\n"
       "(:head :repo \"" root "/p/repo\" :sha \"" prodSha "\" :ref \"trialProbe\")\n"
       "(:model :tag \"A\" :alias \"flashLow\")\n"
       "(:task :id \"T1\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt marker.txt\" :do \"write impl into impl.txt\" :known merge)\n"
       "(:task :id \"T2\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt marker.txt\" :do \"write impl into impl.txt\" :known stall)\n"
       "(:task T3 :owns (\"impl.txt\") :gate \"sh check3.sh impl.txt marker.txt\" :do \"seeded\" :skipWrite true :seed \"" root "/seedT3.patch\" :known merge)\n"
       "(:task :id \"T4\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt marker.txt\" :do \"fix the seeded bug\" :seed \"" root "/seedT4.patch\" :known merge)\n")

; (:m :do "stand-in host build of the dev clone: aslNativeBuild answers its usage line on stderr with exit 2 as the real one does; broken prints nothing")
fn builderScript broken: Bool -> String
  (if broken "#!/bin/sh\nexit 0\n" "#!/bin/sh\necho 'usage: nativeBuild ROOT [CACHE]' >&2\nexit 2\n")

; (:m :do "pipeFix e2eRepo! source repo (c0, then c1 with the hub-client marker hubPreflight looks for) , a base branch sh/BASE = main plus marker.txt made by pipeFix seedUnit!, the scripted Leon, the pipeFix dev clone on branch dev with its origin remote and recording train but no host build yet, a second e2eRepo! as the production stand-in whose ref trialProbe is the pinned head, and the seed patch; repos are made only by the pipeFix helpers, the fixture itself only creates or moves a branch ref and removes a remote")
fn ! fixture! root: String here: String -> Bool
  (let [(repo (pf/e2eRepo! root))
        (prep (pf/prepare! root))
        (dev (pf/devCloneFor! root))
        (prod (pf/e2eRepo! (str root "/p")))
        (base (pf/seedUnit! root (pf/unitIn "BASE" "sh check.sh marker.txt") "parked" "marker.txt"))
        (m (pf/sh (str "git -C " prod " branch trialProbe && mkdir -p " repo "/bin " dev "/asl/host/out && echo asl/host/out/ >> " dev "/.git/info/exclude && echo madeOk")))
        (l (fileWrite (str repo "/bin/asl") (leonScript here repo prod)))
        (lm (fileWrite (str repo "/.git/leonMode-T2-A") "readloop\n"))
        (x (pf/sh (str "chmod 755 " repo "/bin/asl && echo madeOk")))
        (s (fileWrite (str root "/seedT3.patch") (seedPatch)))
        (s4 (fileWrite (str root "/seedT4.patch") (bugPatch)))
        (stale (pf/sh (str "git -C " repo " worktree add -q -b sh/T3-seed " root "/wts/asex-T3-seed sh/BASE && echo madeOk")))
        (r (fileWrite (cd/runPath (str root "/store") "T1-A" "leon" "asn") "(:agentReceipt :status :ok :stop done :servedAlias \"flashLow\" :turns 7)\n"))]
    (and (not (stringEmpty? repo)) (and prep (and (not (stringEmpty? dev)) (and (not (stringEmpty? prod)) (and (not (stringEmpty? base)) (and (stringContains? m "madeOk") (and (ok? l) (and (ok? lm) (and (stringContains? x "madeOk") (and (ok? s) (and (ok? s4) (and (stringContains? stale "madeOk") (ok? r))))))))))))))

fn ! builder! dev: String broken: Bool -> Bool
  (let [(w (fileWrite (str dev "/asl/host/out/aslNativeBuild") (builderScript broken)))]
    (and (ok? w) (stringContains? (pf/sh (str "chmod 755 " dev "/asl/host/out/aslNativeBuild && echo madeOk")) "madeOk")))

fn ! trial! here: String cmd: String spec: String env: (List String) sec: Int64 -> fr/Done
  (fr/runOneLimited (fr/job (list (str here "/bin/asl") "run" (str here "/asl/tools/coord/trial.asl") cmd "--spec" spec) here (fr/childEnv env)) (fr/limits sec 200))

fn rowOf runs: String id: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? l (str "(:trialRun :id \"" id "\""))) (stringLines runs)) "")

; (:m :do "pure parts: spec rows incl. a bare-id task row, cell ids, the pinned stage argv and the scratch dev branch")
fn ! testPure -> Bool
  (let [(s (tr/parseSpec (specText "/r" "/h" "abc" "/r/dev")))
        (cells (tr/cellsOf s))
        (ids (map (fn [(c tr/Cell)] -> String c.id) cells))
        (w (optionOr (listHead cells) (tr/Cell :id "" :task (tr/TTask :id "" :owns (list) :gate "" :text "" :skipWrite false :seed "" :known "") :model (tr/Model :tag "" :alias ""))))
        (argv (tr/stageArgv s "write" w))
        (seedCell (optionOr (listGet cells 2) w))
        (seedArgv (tr/stageArgv s "gates" seedCell))]
    (do (assert (= ids (list "T1-A" "T2-A" "T3-seed" "T4-A")) (str "cells: one per (task, model), one per seeded task: " (stringJoin ids " ")))
        (assert (and (= s.devBase "dev") (and (= s.base "sh/BASE") (and (= s.leaseSec 600) (= (listLength s.heads) 1)))) "spec scalars and head rows parse")
        (assert (and (listContains? argv "--writer-model") (listContains? argv "flashLow")) (str "a write cell's stage argv pins the model: " (stringJoin argv " ")))
        (assert (and (listContains? argv "--dev") (listContains? argv "trialDev-T1-A")) "the stage argv names the cell's scratch dev branch")
        (assert (not (listContains? seedArgv "--writer-model")) "a seeded cell has no writer pin")
        (assert (= (tr/devBranchOf s "T1-A") "trialDev-T1-A") "dev branch is the prefix plus the cell id")
        true))

; (:m :do "the corpus on main is one multi-line (:trialCorpus :tasks (...)) form; a spec naming it gets its six tasks, the seeded ones with their seeds, and check accepts the base-seed writer task T4; :skip (T4) leaves it out")
fn ! testCorpus -> Bool
  (let [(here (pf/here))
        (root (pf/scratch "trialDriver" "corpus"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (spec (str root "/spec.asn"))
        (w (fileWrite spec (str "(:trialSpec :toolRoot \"" here "\")\n(:model :tag \"A\" :alias \"flashLow\")\n(:corpus :path \"asl/tools/coord/trial/corpus.asn\")\n")))
        (s (resultOr (tr/specLines! spec) (tr/emptySpec)))
        (ids (map (fn [(t tr/TTask)] -> String t.id) s.tasks))
        (t1 (optionOr (listHead s.tasks) (tr/TTask :id "" :owns (list) :gate "" :text "" :skipWrite false :seed "" :known "")))
        (skips (map (fn [(t tr/TTask)] -> String t.id) (filter (fn [(t tr/TTask)] -> Bool t.skipWrite) s.tasks)))
        (seeded (map (fn [(t tr/TTask)] -> String t.id) (filter (fn [(t tr/TTask)] -> Bool (not (stringEmpty? t.seed))) s.tasks)))
        (ps (tr/specProblems! s))
        (specSkip (str root "/specSkip.asn"))
        (w2 (fileWrite specSkip (str "(:trialSpec :toolRoot \"" here "\")\n(:model :tag \"A\" :alias \"flashLow\")\n(:corpus :path \"asl/tools/coord/trial/corpus.asn\" :skip (\"T4\"))\n")))
        (s2 (resultOr (tr/specLines! specSkip) (tr/emptySpec)))
        (ids2 (map (fn [(t tr/TTask)] -> String t.id) s2.tasks))
        (ps2 (tr/specProblems! s2))
        (_ (pf/cleanup root))]
    (do (assert (and (ok? w) (= ids (list "T1" "T2" "T3" "T4" "T5" "T6"))) (str "the multi-line corpus yields six tasks: " (stringJoin ids " ")))
        (assert (and (stringStartsWith? t1.text "Write asl-utils/humanBytes") (and (= t1.known "merge") (= t1.owns (list "asl/packages/asl-utils/src/humanBytes.asl" "asl/packages/asl-utils/tests/humanBytesTest.asl")))) (str "T1 text, known and owns survive the join: " t1.text))
        (assert (and (= skips (list "T5" "T6")) (= seeded (list "T4" "T5" "T6"))) (str "seeded tasks keep skipWrite and seed: " (stringJoin skips " ") " / " (stringJoin seeded " ")))
        (assert (and (not (stringContains? (stringJoin ps " ") "baseSeedUnsupported")) (and (not (listContains? ps "seedMissing:T4")) (not (listContains? ps "seedMissing:T5")))) (str "check accepts the base-seed writer task T4 and finds the seed files: " (stringJoin ps " ")))
        (assert (and (ok? w2) (and (= ids2 (list "T1" "T2" "T3" "T5" "T6")) (not (stringContains? (stringJoin ps2 " ") "baseSeedUnsupported")))) (str "a corpus row :skip leaves those tasks out: " (stringJoin ids2 " ")))
        true))

fn ! testCycle -> Bool
  (let [(here (pf/here))
        (root (pf/scratch "trialDriver" "t1"))
        (_ (pf/cleanup root))
        (fx (fixture! root here))
        (hub (pf/startHubFor! root 1500))
        (env (pf/envFor root))
        (dev (str root "/dev"))
        (prod (str root "/p/repo"))
        (prodSha (gitIn prod "rev-parse trialProbe"))
        (spec (str root "/spec.asn"))
        (badSpec (str root "/specBad.asn"))
        (w1 (fileWrite spec (specText root here prodSha dev)))
        (w2 (fileWrite badSpec (specText root here prodSha prod)))
        (cRemote (trial! here "check" spec env 300))
        (_ (pf/sh (str "git -C " dev " remote remove origin")))
        (b1 (builder! dev true))
        (cBroken (trial! here "check" spec env 300))
        (b2 (builder! dev false))
        (repoMain0 (gitIn (str root "/repo") "rev-parse main"))
        (devBase0 (gitIn dev "rev-parse dev"))
        (cGood (trial! here "check" spec env 300))
        (cBad (trial! here "check" badSpec env 300))
        (rRun (trial! here "run" spec env 1500))
        (runs (readOr (str root "/store/trial/runs.asn")))
        (t1 (rowOf runs "T1-A"))
        (t2 (rowOf runs "T2-A"))
        (t3 (rowOf runs "T3-seed"))
        (t4 (rowOf runs "T4-A"))
        (seen4 (readOr (str root "/repo/.git/seen-T4-A")))
        (seedBr4 (gitIn (str root "/repo") "show trialSeed-T4-A:seeded.txt"))
        (devBug4 (gitIn dev "show trialDev-T4-A:seeded.txt"))
        (devImpl4 (gitIn dev "show trialDev-T4-A:impl.txt"))
        (devFile (gitIn dev "show trialDev-T1-A:impl.txt"))
        (devFile3 (gitIn dev "show trialDev-T3-seed:impl.txt"))
        (devHub (gitIn dev "show trialDev-T1-A:marker.txt"))
        (devCur (gitIn dev "branch --show-current"))
        (devBase1 (gitIn dev "rev-parse dev"))
        (repoMain1 (gitIn (str root "/repo") "rev-parse main"))
        (prodSha1 (gitIn prod "rev-parse trialProbe"))
        (trainArgs (readOr (str dev "/.git/trainArgs")))
        (ev2 (readOr (str root "/store/trial/T2-A/sT2-A.journal")))
        (_ (pf/sh (str "git -C " prod " branch -f trialProbe " prodSha)))
        (infraRow (stringReplace t1 ":failedAt \"\" :merged true " ":failedAt \"incomplete\" :merged false "))
        (wInfra (fileAppend (str root "/store/trial/runs.asn") (str infraRow "\n")))
        (rAgain (trial! here "run" spec env 600))
        (runs2 (readOr (str root "/store/trial/runs.asn")))
        (t1rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trialRun :id \"T1-A\"")) (stringLines runs2)))
        (t2rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trialRun :id \"T2-A\"")) (stringLines runs2)))
        (t1last (optionOr (listHead (listReverse t1rows)) ""))
        (rCollect (trial! here "collect" spec env 600))
        (report (readOr (str root "/store/trial/report.asn")))
        (summary (readOr (str root "/store/trial/collect.asn")))
        (_ (pf/sh (str "git -C " prod " branch -f trialProbe HEAD~1")))
        (cMoved (trial! here "check" spec env 300))
        (rMoved (trial! here "run" spec env 300))
        (_ (pf/stopHub! hub))
        (_ (pf/cleanup root))]
    (do (assert (and fx (and (> hub 0) (and (ok? w1) (and (ok? w2) (and b1 (and b2 (not (stringEmpty? prodSha)))))))) "fixture: repo, scripted Leon, dev clone, production stand-in, hub stand-in, specs, stand-in builds")
        (assert (and (= cRemote.exit 1) (and (stringContains? cRemote.out "devRepoRemote") (stringContains? cRemote.out "devRepoBuild:noHostOut"))) (str "check refuses a dev clone with a remote and without a host build: " cRemote.out))
        (assert (and (= cBroken.exit 1) (and (stringContains? cBroken.out "devRepoBuild:notRunnable") (not (stringContains? cBroken.out "devRepoRemote")))) (str "check refuses a dev host build that does not run: " cBroken.out))
        (assert (and (= cGood.exit 0) (stringContains? cGood.out "(:check :problems ())")) (str "check passes on the trial setup: " (stringFromInt64 cGood.exit) " " cGood.out))
        (assert (and (= cBad.exit 1) (and (stringContains? cBad.out "devRepoOnMain:main") (stringContains? cBad.out "isProduction:"))) (str "check refuses a devRepo on main inside a production repo: " cBad.out))
        (assert (and (= rRun.exit 1) (and (stringContains? rRun.out ":cells 4 :merged 3 ") (stringContains? rRun.out (str ":headProblems (\"headMoved:" prod "@trialProbe\")")))) (str "run: four cells, three merged, and exit 1 naming the head a stage moved mid-run: " (stringFromInt64 rRun.exit) " " rRun.out " " (optionOr (stringSlice runs 0 2400) runs)))
        (assert (and (stringContains? t1 ":merged true ") (and (stringContains? t1 "(:write :ok true") (and (stringContains? t1 "(:gates :exit 0 :executed 1 :redBefore (:exit 1 :executed 1)") (and (stringContains? t1 "(:review :verdict \"pass\"") (stringContains? t1 "(:merge :ok true"))))) (str "T1-A passed all four stages: " t1))
        (assert (and (stringContains? t1 ":devBranch \"trialDev-T1-A\"") (and (= devFile "impl") (= devHub "impl"))) (str "T1-A landed on its scratch branch trialDev-T1-A, written from the spec base sh/BASE, not main: " devFile))
        (assert (and (stringContains? t1 ":src leon") (and (stringContains? t1 ":turns 7") (and (stringContains? t1 ":served \"flashLow\"") (stringContains? t1 ":pinBroken false")))) (str "T1-A Leon facts come from the <id>-leon.asn receipt: " t1))
        (assert (and (stringContains? t2 ":failedAt \"write\"") (and (stringContains? t2 ":merged false ") (not (stringContains? t2 "(:gates ")))) (str "T2-A stopped at write and went no further: " t2))
        (assert (and (stringContains? t2 ":stop \"readStreak\"") (and (stringContains? t2 ":signals ((:readStreak :cause notFound))") (and (not (stringContains? t2 " :err ")) (and (stringContains? t2 ":ops ((:read 3))") (stringContains? t2 ":src journal"))))) (str "T2-A record carries the stop, signal and ops from the copied journal: " t2))
        (assert (stringContains? ev2 ":signal :readStreak") "T2-A journal was copied to <store>/trial/T2-A/")
        (assert (and (stringContains? t3 ":merged true ") (and (stringContains? t3 ":seeded false :skipWrite true ") (and (not (stringContains? t3 "(:write ")) (and (not (stringContains? t3 " :leon ")) (= devFile3 "impl"))))) (str "seeded T3 skipped write, passed gates and review and merged: " t3))
        (assert (and (= (stringTrim seen4) "bug") (and (= seedBr4 "bug") (and (= devBug4 "bug") (and (= devImpl4 "impl") (stringContains? t4 ":base \"trialSeed-T4-A\""))))) (str "writer cell T4-A started from trialSeed-T4-A, base plus its seed, saw the seeded bug and merged on top of it: seen=" seen4 " br=" seedBr4 " dev=" devBug4 " impl=" devImpl4 " " t4))
        (assert (stringContains? t3 ":merged true ") "seeded T3 ran although an interrupted run left its worktree behind")
        (assert (and (= devCur "dev") (and (= devBase1 devBase0) (and (= repoMain1 repoMain0) (and (not (stringEmpty? prodSha1)) (!= prodSha1 prodSha))))) (str "devRepo back on dev, dev and source main unmoved, the production stand-in moved by the stage: " devCur))
        (assert (and (stringContains? trainArgs "train sh/T1-A --onto HEAD") (not (stringContains? trainArgs "sh/T2-A"))) (str "the train ran for merged cells only: " trainArgs))
        (assert (and (ok? wInfra) (and (= rAgain.exit 0) (and (stringContains? rAgain.out ":cells 1 :merged 1 ") (and (= (listLength t1rows) 3) (and (stringContains? t1last ":merged true ") (= (listLength t2rows) 1)))))) (str "the next run retries only the cell whose last record is an infra failure (T1-A incomplete), not the task-failed T2-A: " rAgain.out))
        (assert (and (= rCollect.exit 0) (and (and (stringContains? report "(:class wReadLoop :n 1 :insert hint") (stringContains? report "(:class merged :n 2 ")) (stringContains? summary ":runs 4 :merged 3 :failedAt ((:seed 0) (:write 1)"))) (str "collect runs the real trialAnalyze report and summarises: " summary " " report))
        (assert (and (= cMoved.exit 1) (stringContains? cMoved.out "headMoved:")) (str "check fails once a production head moved: " cMoved.out))
        (assert (and (= rMoved.exit 1) (stringContains? rMoved.out "(:refuse ")) (str "run refuses once a production head moved: " rMoved.out))
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "spec, cells and stage argv")
      (assert (testCorpus) "the corpus on main through specLines!")
      (assert (testCycle) "check, run and collect through the real stages")
      true)
