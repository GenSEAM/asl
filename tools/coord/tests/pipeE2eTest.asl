(module asl-tools/coord/tests/pipeE2eTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-E2E-HERMETIC :do "the whole conductor cycle in a temp world: tick! drives one unit through the real stage children (bin/asl run conductor.asl stage ...: writeRes with the real Leon loop on a scripted reply fixture, gatesStage, realReview against the stand-in hub, mergeRes onto a dev clone); the only stand-ins are the Leon replies, the hub verdicts and the dev clone's train; three scenarios: a write that lands and merges, a write that changes nothing, a review that fails")
(schema Out
  (:f ready Bool) (:f why String) (:f tos (List String)) (:f st String) (:f sig String) (:f fails Int64) (:f devBefore String) (:f devAfter String) (:f unitSha String)
  (:f inDev Bool) (:f devImpl String) (:f wtGone Bool) (:f hubSeen String) (:f prior String) (:f trainArgs String) (:f journal String) (:f ticks Int64))

fn terminal? s: String -> Bool
  (listContains? (list "merged" "blocked" "failed") s)

fn ! stOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (cd/CUnit :id "" :st "absent" :lane "" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await ""))

; (:m :do "ticks until the unit is terminal, the journal holds the stop needle (a row that proves the scenario's point) or the deadline passes; returns the ticks run")
fn ! drive! ctx: cd/Ctx id: String needle: String deadlineMs: Int64 ticks: Int64 -> Int64
  (let [(_ (cd/tick! ctx))
        (c (stOf ctx.dir id))
        (journal (resultOr (fileReadString (cd/journalPath ctx.dir)) ""))]
    (cond
      ((terminal? c.st) ticks)
      ((and (not (stringEmpty? needle)) (stringContains? journal needle)) ticks)
      ((> (/ (nowNs) 1000000) deadlineMs) ticks)
      (else (let [(_ (sleepMs 1500))] (drive! ctx id needle deadlineMs (+ ticks 1))))))

fn ! scenario! tag: String replies: (List String) hubReply: String needle: String -> Out
  (let [(root (pf/scratch "pipeE2e" tag))
        (_ (pf/cleanup root))
        (repo (pf/e2eRepo! root))
        (prep (pf/prepare! root))
        (_ (fileWrite (str root "/hubReply.txt") hubReply))
        (leon (pf/scriptLeon! root replies))
        (dev (pf/devCloneFor! root))
        (hub (pf/startHubFor! root 900))
        (u (pf/unitIn "E1" "sh check3.sh impl.txt"))
        (_ (fileWrite (str root "/store/tasks/E1.txt") "Create impl.txt containing the single word impl."))
        (put (st/put! (str root "/store") u))
        (ctx (pf/e2eCtx root 420))
        (up (and (not (stringEmpty? repo)) (and prep (and leon (and (not (stringEmpty? dev)) (and (> hub 0) (ok? put)))))))
        (devBefore (stringTrim (pf/sh (str "git -C " dev " rev-parse HEAD"))))
        (ticks (if up (drive! ctx "E1" needle (+ (/ (nowNs) 1000000) 600000) 1) 0))
        (_ (cd/stopAll! ctx))
        (c (stOf (str root "/store") "E1"))
        (sha (stringTrim (pf/sh (str "git -C " repo " rev-parse --verify --quiet sh/E1"))))
        (out (Out :ready up :why (str "repo=" repo " prep=" (if prep "y" "n") " leon=" (if leon "y" "n") " dev=" dev " hub=" (stringFromInt64 hub) " put=" (if (ok? put) "y" "n")) :tos (pf/tosOf (str root "/store") "E1") :st c.st :sig c.sig :fails c.fails :devBefore devBefore
                  :devAfter (stringTrim (pf/sh (str "git -C " dev " rev-parse HEAD")))
                  :unitSha sha
                  :inDev (and (not (stringEmpty? sha)) (stringContains? (pf/sh (str "git -C " dev " merge-base --is-ancestor " sha " HEAD && echo yes")) "yes"))
                  :devImpl (stringTrim (resultOr (fileReadString (str dev "/impl.txt")) ""))
                  :wtGone (not (fileExists? (str root "/wts/asex-E1/.git")))
                  :hubSeen (pf/hubSeen root)
                  :prior (resultOr (fileReadString (cd/runPath (str root "/store") "E1" "prior" "txt")) "")
                  :trainArgs (stringTrim (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
                  :journal (stringJoin (pf/journalLines (str root "/store")) "\n") :ticks ticks))
        (_ (pf/stopHub! hub))
        (_ (pf/cleanup root))]
    out)

fn writeImpl -> String
  "(:step :op \"write\" :file \"impl.txt\" :content \"impl\")\n(:done)"

fn ! runTests -> Bool
  (let [(pass "(:verdict :pass :defects () :model m)")
        (fail "(:verdict :fail :defects (\"impl.txt: scripted reviewer defect\") :model m)")
        (merged (scenario! "merge" (list (writeImpl)) pass ""))
        (nothing (scenario! "nothing" (list "(:done)") pass ""))
        (reviewFail (scenario! "reviewFail" (list (writeImpl)) fail ":from reviewing :to ready"))]
    (do (assert (and merged.ready (and nothing.ready reviewFail.ready)) (str "fixture: temp repo, scripted Leon, dev clone and hub stand-in are up in all three worlds: " merged.why))
        (assert (= merged.tos (list "ready" "writing" "gating" "awaitReview" "reviewing" "merging" "merged")) (str "scenario merge: the journal path of the unit: " (stringJoin merged.tos " ") " / " merged.sig))
        (assert (and (!= merged.devAfter merged.devBefore) (and merged.inDev (= merged.devImpl "impl"))) "scenario merge: dev HEAD moved and holds the unit commit and its file")
        (assert (stringStartsWith? merged.trainArgs "train sh/E1 --onto HEAD --repo ") (str "scenario merge: the train ran onto dev with the unit branch: " merged.trainArgs))
        (assert merged.wtGone "scenario merge: the unit worktree is collected")
        (assert (stringContains? merged.hubSeen "impl.txt") "scenario merge: the reviewers were shown the unit's diff")
        (assert (and (listContains? (list "blocked" "failed") nothing.st) (and (not (listContains? nothing.tos "merging")) (and (= nothing.devAfter nothing.devBefore) (stringContains? nothing.sig ":status :failed")))) (str "scenario nothing: a Leon that writes nothing ends blocked or failed, never reaches merge, dev is untouched and the signature is the failed Leon run: " (stringJoin nothing.tos " ") " / " nothing.sig))
        (assert (and (listContains? nothing.tos "writing") (not (listContains? nothing.tos "gating"))) (str "scenario nothing: it stopped at the write: " (stringJoin nothing.tos " ")))
        (assert (and (!= reviewFail.st "merged") (and (not (listContains? reviewFail.tos "merging")) (= reviewFail.devAfter reviewFail.devBefore))) (str "scenario reviewFail: a failing review does not merge and leaves dev alone: " (stringJoin reviewFail.tos " ")))
        (assert (= (listTake reviewFail.tos 6) (list "ready" "writing" "gating" "awaitReview" "reviewing" "ready")) (str "scenario reviewFail: the unit walks to review and back to ready: " (stringJoin reviewFail.tos " ")))
        (assert (stringContains? reviewFail.prior "scripted reviewer defect") (str "scenario reviewFail: the reviewers' defect is the prior note of the next write: " reviewFail.prior))
        true))
