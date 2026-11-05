(module asl-tools/coord/tests/trialDriverTest
  :x [runTests]
  :i [(asl-tools/coord/trial :a tr) (asl-tools/coord/conductor :a cd) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref LEON-TRIAL :do "TRIAL-DRIVER gate: trial.asl check, run and collect as children on a temp source repo, a temp dev clone on branch trialBase, a temp store and a stand-in production repo; the write stage runs the real conductor stage child whose Leon is a scripted bin/asl in the temp repo (good: writes impl.txt; readloop: three read turns and a readStreak signal), gates run the real gate, review goes through the real provider to the hub stand-in, merge trains onto trialDev-<cell> with a recording train in the dev clone. The one stand-in for an interface not on main: the TRIAL-PIN receipt file <id>-leon.asn is pre-written for one cell; collect runs the real trialAnalyze report on the records")

fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

; (:m :do "scripted Leon: the conductor starts <repo>/bin/asl with the (:agent ...) form in the unit worktree; any other call goes to the real CLI of this worktree")
fn leonScript here: String repo: String -> String
  (str "#!/bin/sh\ncase \"$1\" in\n  \"(:agent\"*) ;;\n  *) exec " here "/bin/asl \"$@\" ;;\nesac\n"
       "id=$(basename \"$PWD\"); id=${id#asex-}\nmode=$(cat " repo "/.git/leonMode-$id 2>/dev/null)\nmkdir -p .asl/run/agentLoop\nj=.asl/run/agentLoop/s$id.journal\n"
       "if [ \"$mode\" = readloop ]; then\n"
       "  for t in 1 2 3; do echo \"(:turn $t :reply \\\"(:step :op read :file check.sh)\\\")\" >> $j; done\n"
       "  echo \"(:turn 3 :signal :readStreak :cause :notFound :reason \\\"3 turns in a row persisted nothing\\\")\" >> $j\n"
       "  echo \"(:result :status :escalated :stop readStreak :turns 3)\" >> $j\n"
       "  echo \"(:agent :status :failed :receipt (:agentReceipt :status :escalated :stop readStreak :servedAlias \\\"flashLow\\\" :turns 3))\"\n"
       "  exit 1\nfi\n"
       "printf impl > impl.txt\necho \"(:turn 1 :reply \\\"(:step :op edit :file impl.txt)\\\")\" >> $j\necho \"(:result :status :ok :stop done :turns 1)\" >> $j\n"
       "echo \"(:agent :status :ok :receipt (:agentReceipt :status :ok :stop done :servedAlias \\\"flashLow\\\" :turns 1))\"\nexit 0\n")

; (:m :do "recording train in the dev clone (as mergeRealTest: the in-process mergeCheck calls its audit subcommands, which pass): merges the branch it is given onto the checked-out branch and logs its args")
fn trainScript -> String
  "#!/bin/sh\nif [ \"$1\" = audit ]; then echo \"(:audit :sub $2 :status :passed)\"; exit 0; fi\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\necho \"$@\" >> \"$D/.git/trainArgs\"\ngit -C \"$D\" merge --no-ff -q -m \"train $2\" \"$2\" || exit 1\nexit 0\n"

fn seedPatch -> String
  "diff --git a/impl.txt b/impl.txt\nnew file mode 100644\n--- /dev/null\n+++ b/impl.txt\n@@ -0,0 +1 @@\n+impl\n"

fn specText root: String here: String prodSha: String devRepo: String -> String
  (str "(:trialSpec :store \"" root "/store\" :repo \"" root "/repo\" :toolRoot \"" here "\" :devRepo \"" devRepo "\" :devPrefix \"trialDev-\" :devBase \"trialBase\""
       " :worktrees \"" root "/wts\" :home \"" root "/home\" :lanes \"" root "/home/lanes.asn\" :base \"main\" :leaseSec 600 :writers 1 :gates 1 :reviews 1 :stageSec 600"
       " :minFreeMb 0 :minDiskMb 1)\n"
       "(:head :repo \"" root "/prod\" :sha \"" prodSha "\")\n"
       "(:model :tag \"A\" :alias \"flashLow\")\n"
       "(:task :id \"T1\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt\" :do \"write impl into impl.txt\" :known merge)\n"
       "(:task :id \"T2\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt\" :do \"write impl into impl.txt\" :known stall)\n"
       "(:task T3 :owns (\"impl.txt\") :gate \"sh check3.sh impl.txt\" :do \"seeded\" :skipWrite true :seed \"" root "/seedT3.patch\" :known merge)\n")

; (:m :do "temp repo with the hub-client marker hubPreflight looks for, the scripted Leon, a dev clone on trialBase with no remote and the recording train, a stand-in production repo and the seed patch")
fn ! fixture! root: String here: String -> Bool
  (let [(repo (pf/repoIn root))
        (prep (pf/prepare! root))
        (m (pf/sh (str "cd " repo " && mkdir -p asl/packages/asl-agent/src && echo hubAsnPath > asl/packages/asl-agent/src/providers.asl && git add -A && git commit -qm marker"
                       " && mkdir -p bin && echo bin/asl >> .git/info/exclude && echo readloop > .git/leonMode-T2-A && echo madeOk")))
        (l (fileWrite (str repo "/bin/asl") (leonScript here repo)))
        (d (pf/sh (str "chmod 755 " repo "/bin/asl && git clone -q " repo " " root "/dev && cd " root "/dev && git config user.email t@example.invalid && git config user.name t"
                       " && git remote remove origin && git checkout -q -b trialBase && mkdir -p bin && echo bin/asl >> .git/info/exclude && echo madeOk")))
        (t (fileWrite (str root "/dev/bin/asl") (trainScript)))
        (p (pf/sh (str "chmod 755 " root "/dev/bin/asl && mkdir -p " root "/prod && cd " root "/prod && git init -q -b main && git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m p0 && echo madeOk")))
        (s (fileWrite (str root "/seedT3.patch") (seedPatch)))
        (r (fileWrite (cd/runPath (str root "/store") "T1-A" "leon" "asn") "(:agentReceipt :status :ok :stop done :servedAlias \"flashLow\" :turns 7)\n"))]
    (and (not (stringEmpty? repo)) (and prep (and (stringContains? m "madeOk") (and (ok? l) (and (stringContains? d "madeOk") (and (ok? t) (and (stringContains? p "madeOk") (and (ok? s) (ok? r))))))))))

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
    (do (assert (= ids (list "T1-A" "T2-A" "T3-seed")) (str "cells: one per (task, model), one per seeded task: " (stringJoin ids " ")))
        (assert (and (= s.devBase "trialBase") (and (= s.leaseSec 600) (= (listLength s.heads) 1))) "spec scalars and head rows parse")
        (assert (and (listContains? argv "--writer-model") (listContains? argv "flashLow")) (str "a write cell's stage argv pins the model: " (stringJoin argv " ")))
        (assert (and (listContains? argv "--dev") (listContains? argv "trialDev-T1-A")) "the stage argv names the cell's scratch dev branch")
        (assert (not (listContains? seedArgv "--writer-model")) "a seeded cell has no writer pin")
        (assert (= (tr/devBranchOf s "T1-A") "trialDev-T1-A") "dev branch is the prefix plus the cell id")
        true))

fn ! testCycle -> Bool
  (let [(here (pf/here))
        (root (pf/scratch "trialDriver" "t1"))
        (_ (pf/cleanup root))
        (fx (fixture! root here))
        (hub (pf/startHubFor! root 1500))
        (env (pf/envFor root))
        (prodSha (gitIn (str root "/prod") "rev-parse HEAD"))
        (spec (str root "/spec.asn"))
        (badSpec (str root "/specBad.asn"))
        (w1 (fileWrite spec (specText root here prodSha (str root "/dev"))))
        (w2 (fileWrite badSpec (specText root here prodSha (str root "/prod"))))
        (repoMain0 (gitIn (str root "/repo") "rev-parse main"))
        (devBase0 (gitIn (str root "/dev") "rev-parse trialBase"))
        (cGood (trial! here "check" spec env 300))
        (cBad (trial! here "check" badSpec env 300))
        (rRun (trial! here "run" spec env 1500))
        (runs (readOr (str root "/store/trial/runs.asn")))
        (t1 (rowOf runs "T1-A"))
        (t2 (rowOf runs "T2-A"))
        (t3 (rowOf runs "T3-seed"))
        (devFile (gitIn (str root "/dev") "show trialDev-T1-A:impl.txt"))
        (devFile3 (gitIn (str root "/dev") "show trialDev-T3-seed:impl.txt"))
        (devCur (gitIn (str root "/dev") "branch --show-current"))
        (devBase1 (gitIn (str root "/dev") "rev-parse trialBase"))
        (repoMain1 (gitIn (str root "/repo") "rev-parse main"))
        (prodSha1 (gitIn (str root "/prod") "rev-parse HEAD"))
        (trainArgs (readOr (str root "/dev/.git/trainArgs")))
        (ev2 (readOr (str root "/store/trial/T2-A/sT2-A.journal")))
        (rAgain (trial! here "run" spec env 600))
        (runs2 (readOr (str root "/store/trial/runs.asn")))
        (rCollect (trial! here "collect" spec env 600))
        (report (readOr (str root "/store/trial/report.asn")))
        (summary (readOr (str root "/store/trial/collect.asn")))
        (_ (pf/sh (str "cd " root "/prod && git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m moved")))
        (cMoved (trial! here "check" spec env 300))
        (rMoved (trial! here "run" spec env 300))
        (_ (pf/stopHub! hub))
        (_ (pf/cleanup root))]
    (do (assert (and fx (and (> hub 0) (and (ok? w1) (and (ok? w2) (not (stringEmpty? prodSha)))))) "fixture: repo, scripted Leon, dev clone, production stand-in, hub stand-in, specs")
        (assert (and (= cGood.exit 0) (stringContains? cGood.out "(:check :problems ())")) (str "check passes on the trial setup: " (stringFromInt64 cGood.exit) " " cGood.out))
        (assert (and (= cBad.exit 1) (and (stringContains? cBad.out "devRepoOnMain:main") (stringContains? cBad.out "isProduction:"))) (str "check refuses a devRepo on main inside a production repo: " cBad.out))
        (assert (and (= rRun.exit 0) (stringContains? rRun.out ":cells 3 :merged 2 ")) (str "run: three cells, two merged: " (stringFromInt64 rRun.exit) " " rRun.out " " (optionOr (stringSlice runs 0 2400) runs)))
        (assert (and (stringContains? t1 ":merged true ") (and (stringContains? t1 "(:write :ok true") (and (stringContains? t1 "(:gates :exit 0 :executed 1 :redBefore (:exit 1 :executed 1)") (and (stringContains? t1 "(:review :verdict \"pass\"") (stringContains? t1 "(:merge :ok true"))))) (str "T1-A passed all four stages: " t1))
        (assert (and (stringContains? t1 ":devBranch \"trialDev-T1-A\"") (= devFile "impl")) (str "T1-A landed on its scratch branch trialDev-T1-A: " devFile))
        (assert (and (stringContains? t1 ":src leon") (and (stringContains? t1 ":turns 7") (and (stringContains? t1 ":served \"flashLow\"") (stringContains? t1 ":pinBroken false")))) (str "T1-A Leon facts come from the <id>-leon.asn receipt: " t1))
        (assert (and (stringContains? t2 ":failedAt \"write\"") (and (stringContains? t2 ":merged false ") (not (stringContains? t2 "(:gates ")))) (str "T2-A stopped at write and went no further: " t2))
        (assert (and (stringContains? t2 ":stop \"readStreak\"") (and (stringContains? t2 ":signals ((:readStreak :cause notFound))") (and (not (stringContains? t2 " :err ")) (and (stringContains? t2 ":ops ((:read 3))") (stringContains? t2 ":src journal"))))) (str "T2-A record carries the stop, signal and ops from the copied journal: " t2))
        (assert (stringContains? ev2 ":signal :readStreak") "T2-A journal was copied to <store>/trial/T2-A/")
        (assert (and (stringContains? t3 ":merged true ") (and (stringContains? t3 ":seeded false :skipWrite true ") (and (not (stringContains? t3 "(:write ")) (and (not (stringContains? t3 " :leon ")) (= devFile3 "impl"))))) (str "seeded T3 skipped write, passed gates and review and merged: " t3))
        (assert (and (= devCur "trialBase") (and (= devBase1 devBase0) (and (= repoMain1 repoMain0) (= prodSha1 prodSha)))) (str "devRepo back on trialBase, trialBase, source main and production head unmoved: " devCur))
        (assert (and (stringContains? trainArgs "train sh/T1-A --onto HEAD") (not (stringContains? trainArgs "sh/T2-A"))) (str "the train ran for merged cells only: " trainArgs))
        (assert (and (= rAgain.exit 0) (and (stringContains? rAgain.out ":cells 0 ") (= runs2 runs))) (str "a second run skips recorded cells: " rAgain.out))
        (assert (and (= rCollect.exit 0) (and (and (stringContains? report "(:class wReadLoop :n 1 :insert hint") (stringContains? report "(:class merged :n 1 ")) (stringContains? summary ":runs 3 :merged 2 :failedAt ((:seed 0) (:write 1)"))) (str "collect runs the real trialAnalyze report and summarises: " summary " " report))
        (assert (and (= cMoved.exit 1) (stringContains? cMoved.out "headMoved:")) (str "check fails once a production head moved: " cMoved.out))
        (assert (and (= rMoved.exit 1) (stringContains? rMoved.out "(:refuse ")) (str "run refuses once a production head moved: " rMoved.out))
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "spec, cells and stage argv")
      (assert (testCycle) "check, run and collect through the real stages")
      true)
