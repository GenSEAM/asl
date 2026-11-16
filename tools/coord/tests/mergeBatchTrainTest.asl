(module asl-tools/coord/tests/mergeBatchTrainTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref TRAIN-BATCH-BRANCHES :do "the batch merge stage over the real tools/fleet/train.asl: a fixture repo under the gitignored scratch/ (so the native CLI runs its suites) with HEAD on dev and four unit branches each adding one suite; its bin/asl hands the merge stage's train argv to the real train with a fixture scratch, caches and identity. A batch of two green branches merges both into dev; a batch with one breaking branch merges neither, retries the clean one and charges the breaking one with a train red naming its suite. git is reached only through git init, one fast-import stream, read-tree and read-only commands")

fn ! root -> String
  (resultOr (realPath ".") ".")

fn ! fixtureRel -> String
  (str "scratch/mergeBatchTrainTest-" (procSelf))

fn ! fixture -> String
  (str (root) "/" (fixtureRel))

fn ! repo -> String
  (str (fixture) "/repo")

fn ! store -> String
  (str (fixture) "/store")

fn ! gitEnv -> (List String)
  (fr/childEnv (list "GIT_AUTHOR_NAME=mergeBatchTrainTest" "GIT_AUTHOR_EMAIL=mergeBatchTrainTest@localhost" "GIT_COMMITTER_NAME=mergeBatchTrainTest" "GIT_COMMITTER_EMAIL=mergeBatchTrainTest@localhost"))

fn ! gitIn args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons "git" args) (repo) (gitEnv)) (fr/limits 120 0))

fn ! cleanup! -> Bool
  (= (fr/runOneLimited (fr/job (list "rm" "-rf" (fixture)) (root) (fr/childEnv (list))) (fr/limits 120 0)).exit 0)

fn ! held c: Bool -> Bool
  (if c true (do (cleanup!) false))

fn ! suite name: String good: Bool -> String
  (str "(module " (fixtureRel) "/wt/" name " :x [runTests] :i [])\n\nfn ! runTests -> Bool\n  (do (assert (= (stringLength (str \"" name "\" \"x\")) (+ " (if good "1" "2") " (stringLength \"" name "\"))) \"" name " length\") true)\n")

fn fileOp f: (Pair String String) -> String
  (str "M 100644 inline " (pairFirst f) "\ndata " (stringLength (pairSecond f)) "\n" (pairSecond f) "\n")

fn commitOp ref: String mark: String from: String files: (List (Pair String String)) -> String
  (str "commit refs/heads/" ref "\n" (if (stringEmpty? mark) "" (str "mark " mark "\n"))
       "committer mergeBatchTrainTest <mergeBatchTrainTest@localhost> 1700000000 +0000\ndata " (stringLength ref) "\n" ref "\n"
       (if (stringEmpty? from) "" (str "from " from "\n"))
       (stringJoin (map fileOp files) "") "\n")

fn ! stream -> String
  (str (commitOp "main" ":1" "" (list (pair "notes.txt" "notes\n") (pair ".gitignore" "asl/host/out/\nbin/\n")))
       "reset refs/heads/dev\nfrom :1\n\n"
       (commitOp "sh/E1" "" ":1" (list (pair "e1Test.asl" (suite "e1Test" true))))
       (commitOp "sh/E2" "" ":1" (list (pair "e2Test.asl" (suite "e2Test" true))))
       (commitOp "sh/E3" "" ":1" (list (pair "e3Test.asl" (suite "e3Test" true))))
       (commitOp "sh/E4" "" ":1" (list (pair "e4Test.asl" (suite "e4Test" false))))
       "done\n")

; (:m :do "the repo's bin/asl: drops the leading train word and runs the real train from the workspace root with the fixture's scratch, caches and git identity")
fn ! wrapper -> String
  (let [(f (fixture)) (r (root))]
    (str "#!/bin/sh\nshift\ncd '" r "' || exit 2\nexec env GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@localhost GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@localhost"
         " ASL_TRAIN_CACHE='" f "/graph' ASL_FLEET_CACHE='" f "/verdicts' ASL_GATE_TIMES='" f "/times.asn' '" r "/bin/asl' run tools/fleet/train.asl --scratch '" f "/wt' --cli '" r "/bin/asl' \"$@\"\n"))

fn ! build! -> Bool
  (let [(streamPath (str (fixture) "/stream"))]
    (and (= (fr/runOneLimited (fr/job (list "mkdir" "-p" (str (repo) "/bin") (str (store) "/runs") (str (fixture) "/home")) (root) (fr/childEnv (list))) (fr/limits 60 0)).exit 0)
      (and (= (gitIn (list "init" "-q" "-b" "dev")).exit 0)
        (and (ok? (fileWrite streamPath (stream)))
          (and (= (fr/runShell! (str "git fast-import --quiet --done < '" streamPath "'") (repo) (gitEnv) (fr/limits 120 0)).exit 0)
            (and (= (gitIn (list "read-tree" "-u" "--reset" "HEAD")).exit 0)
              (and (ok? (fileWrite (str (repo) "/bin/asl") (wrapper)))
                   (= (fr/runOneLimited (fr/job (list "chmod" "755" (str (repo) "/bin/asl")) (root) (fr/childEnv (list))) (fr/limits 60 0)).exit 0))))))))

fn stubPass rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 0 "(:mergeCheck :verdict pass)")

fn ! member! id: String -> (Pair st/Task cd/CUnit)
  (let [(u (with (pf/unitIn id "true") :owns (list (str id ".txt"))))
        (c (pf/cuIn id "merging" "" (str "sh/" id)))
        (_ (st/put! (store) u))
        (_ (cd/writeCUnit! (store) c))]
    (pair u c))

fn ! inDev? branch: String -> Bool
  (= (gitIn (list "merge-base" "--is-ancestor" branch "dev")).exit 0)

fn ! batch! lead: String pass: String -> cd/Res
  (let [(l (member! lead))
        (_ (member! pass))
        (_ (fileWrite (cd/batchPath (store) lead) (str "(:batch :leader \"" lead "\" :units (\"" pass "\"))\n")))
        (rc (cd/realCfg (list "--repo" (repo) "--dev-repo" (repo) "--dev" "dev" "--worktrees" (str (fixture) "/wts") "--home" (str (fixture) "/home")) (store)))]
    (cd/mergeBatchWith rc (store) (pairFirst l) (pairSecond l) stubPass))

fn ! runTests -> Bool
  (let [(_ (cleanup!))
        (built (build!))
        (green (batch! "E1" "E2"))
        (greenPass (resultOr (fileReadString (cd/passPath (store) "E1")) ""))
        (bothIn (and (inDev? "sh/E1") (inDev? "sh/E2")))
        (red (batch! "E3" "E4"))
        (redPass (resultOr (fileReadString (cd/passPath (store) "E3")) ""))
        (noneIn (and (not (inDev? "sh/E3")) (not (inDev? "sh/E4"))))
        (gone (cleanup!))]
    (do (assert built "fixture repo on dev with four unit branches built by fast-import, its bin/asl handing over to the real train")
        (assert (= green.ok 1) (str "the green batch merges its leader: " green.sig))
        (assert (stringContains? greenPass "(:pass :unit \"E2\"") (str "the passenger has its row: " greenPass))
        (assert (stringContains? greenPass ":ok 1 ") (str "and it is merged: " greenPass))
        (assert bothIn "both green branches are in dev")
        (assert (= red.verdict "rebatch") (str "the clean member of the red batch is retried: " red.verdict " " red.sig))
        (assert (stringContains? redPass "(:pass :unit \"E4\"") (str "the breaking member has its row: " redPass))
        (assert (stringContains? redPass ":sig \"train red: e4Test.asl") (str "charged with a train red naming its suite: " redPass))
        (assert noneIn "neither branch of the red batch is in dev")
        (assert gone "fixture removed")
        true))
