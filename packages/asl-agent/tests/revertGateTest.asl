(module aslAgent/tests/revertGateTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)
      (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-REVERT-NO-RESTORE :do "a writer ran git show main:F > F to prove red on main and the budget ended before the restore, losing a 193-line change; (:step :op gate :revert F) reverts, runs the gate and restores F in one step, and a raw git show redirected into the tree is refused")

fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn boolField rec: (List (Pair String ex/Val)) k: String -> Bool
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vBool b) b) (_ false)))
    ((none) false))

fn revertOp file: String rev: (Option String) -> (List (Pair String c/KvVal))
  (listAppend
    (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "gate")) (pair "revert" (c/kvStr file)))
    (match rev ((some v) (list (pair "rev" (c/kvStr v)))) ((none) (list))))

fn freshRoot -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        root (str base "/revertGateTest-" (stringFromInt64 (nowNs)))]
    (if (ok? (dirCreate root)) root root))

fn ! text! path: String -> String
  (resultOr (fileReadString path) "<absent>")

fn ! envWith root: String gates: (List String) -> ex/ExecEnv
  (envTimed root gates 60)

fn ! envTimed root: String gates: (List String) timeout: Int64 -> ex/ExecEnv
  (ex/makeExecEnv root root "auto" (list "subject.txt" "same.txt" "new.txt") false "HEAD" gates
    (list (pair "gate" "local")) "" (list) 20000 timeout (none) "revertGateTest" (none))

; (:m :ref LEON-REVERT-NO-RESTORE :do "rebuilds the tree a run killed mid-revert would leave: subject.txt at its HEAD text and the revert entry the gate copied to snap/ while it ran")
fn ! crashState! root: String -> Bool
  (let [snap (str root "/snap")
        dir (str root "/.asl/run/revert")
        made (ok? (dirCreate dir))
        names (filter (fn [n] (!= n "subject.txt")) (resultOr (dirList snap) (list)))
        copied (fold (fn [acc n] (and acc (match (fileReadBytes (str snap "/" n)) ((ok b) (ok? (fileWrite (str dir "/" n) b))) ((err _) false)))) true names)
        reverted (match (fileReadBytes (str snap "/subject.txt")) ((ok b) (ok? (fileWrite (str root "/subject.txt") b))) ((err _) false))]
    (and made (and copied (and reverted (not (listEmpty? names))))))

fn ! runOne! env: ex/ExecEnv op: (List (Pair String c/KvVal)) -> (List (Pair String ex/Val))
  (let [out (ex/execOp! op env (r/newProcs) (fn [] "id1") (fn [s] false) (fn [a b n] true) (fn [f d] (t/aslRun 0 "" "")))]
    out.rec)

fn ! runTests -> Bool
  (let [root (freshRoot)
        subject (str root "/subject.txt")
        seeded (and (ok? (fileWrite subject "green\n")) (ok? (fileWrite (str root "/same.txt") "same\n")))
        repo (gk/initGitRepoWith! root "revertGate" "revert-gate@example.invalid" (list "subject.txt" "same.txt"))
        changed (and (ok? (fileWrite subject "red\n")) (ok? (fileWrite (str root "/new.txt") "new\n")))
        dependent (envWith root (list "test \"$(cat subject.txt)\" = red && test -f new.txt"))
        independent (envWith root (list "true"))
        recRed (runOne! dependent (revertOp "subject.txt" (none)))
        afterRed (text! subject)
        recPass (runOne! independent (revertOp "subject.txt" (some "main")))
        afterPass (text! subject)
        recNew (runOne! dependent (revertOp "new.txt" (none)))
        afterNew (text! (str root "/new.txt"))
        recSame (runOne! dependent (revertOp "same.txt" (none)))
        recOwns (runOne! dependent (revertOp "other.txt" (none)))
        recRev (runOne! dependent (revertOp "subject.txt" (some "noSuchRev")))
        recSlow (runOne! (envTimed root (list "grep -q red subject.txt || sleep 20") 2) (revertOp "subject.txt" (none)))
        afterSlow (text! subject)
        recSnap (runOne! (envWith root (list "mkdir -p snap && cp subject.txt snap/subject.txt && cp .asl/run/revert/* snap/ && grep -q red subject.txt")) (revertOp "subject.txt" (none)))
        crashed (crashState! root)
        crashText (text! subject)
        held (fileLock (str root "/.asl/run/revert/revertGateTest-subject.txt.lock") true)
        sweptLive (ex/sweepRevertBackups! root)
        liveText (text! subject)
        freed (match held ((ok fd) (ok? (fdClose fd))) ((err _) false))
        swept (ex/sweepRevertBackups! root)
        sweptText (text! subject)
        receipt (ex/formatOpReceipt recRed 2000)
        backups (resultOr (dirList (str root "/.asl/run/revert")) (list))]
    (do
      (assert seeded "the fixture files are written")
      (assert repo "the fixture repo commits subject.txt and same.txt")
      (assert changed "the working change is written")
      (assert (= (strField recRed "status") "ok") "a revert gate step on a changed owned file answers ok")
      (assert (boolField recRed "red") "the gate that reads subject.txt is red with subject.txt as at HEAD")
      (assert (= afterRed "red\n") "subject.txt holds the working change again after the red revert run")
      (assert (boolField recRed "revertRestored") "the receipt says the file was restored")
      (assert (none? (ex/recGet recRed "gateRuns")) "revert runs are not reported as gateRuns, so they never back a gate claim")
      (assert (stringContains? receipt ":red true") "the formatted receipt carries :red true")
      (assert (stringContains? receipt ":restored true") "the formatted receipt carries :restored true")
      (assert (= (strField recPass "status") "ok") "a gate that does not read the file still answers ok")
      (assert (not (boolField recPass "red")) "a gate that passes on the reverted file is not red")
      (assert (stringContains? (strField recPass "message") "does not prove the change") "the not-red answer says the gate does not prove the change")
      (assert (= afterPass "red\n") "subject.txt holds the working change after the not-red run at :rev main")
      (assert (boolField recNew "red") "a file absent at HEAD is removed for the run and the gate that needs it is red")
      (assert (= afterNew "new\n") "the new file is back after the run")
      (assert (= (strField recSame "error") "ERR_REVERT_UNCHANGED") "a file equal to its HEAD text has nothing to revert")
      (assert (= (strField recOwns "error") "ERR_OWNS") "a file outside :owns is not reverted")
      (assert (= (strField recRev "error") "ERR_REVERT_REV") "a rev that names no commit is refused before any write")
      (assert (= (text! subject) "red\n") "the refused steps left subject.txt unchanged")
      (assert (listEmpty? backups) "every backup is removed once its file is restored")
      (assert (= (match (r/checkRunGitGuard "git show main:subject.txt > subject.txt") ((some g) (pairFirst g)) ((none) "")) "git show >") "git show REV:F > F in the tree is refused")
      (assert (some? (r/checkRunGitGuard "git -C . show HEAD:a.asl >a.asl")) "a glued redirect behind a global option is refused too")
      (assert (stringContains? (match (r/checkRunGitGuard "git show HEAD:a > a") ((some g) (pairSecond g)) ((none) "")) ":revert") "the refusal points at the revert gate step")
      (assert (none? (r/checkRunGitGuard "git show main:subject.txt > /tmp/old.txt")) "a git show into /tmp stays allowed")
      (assert (none? (r/checkRunGitGuard "git show main:subject.txt")) "a plain git show stays allowed")
      (assert (= (strField recSlow "verdict") "unknown") (str "a gate that times out on the reverted file is unknown, not red: " (strField recSlow "verdict")))
      (assert (not (boolField recSlow "red")) "a timed-out revert run is not red")
      (assert (= afterSlow "red\n") "subject.txt is restored after the timed-out run")
      (assert (= (strField recSnap "verdict") "red") "the snapshotting gate is red on revert")
      (assert crashed "the mid-revert snapshot holds the revert entry and the reverted file")
      (assert (= crashText "green\n") "the rebuilt crash state has subject.txt at its HEAD text")
      (assert (ok? held) "the test holds the entry lock like a live run")
      (assert (listEmpty? sweptLive) "an entry whose lock is held belongs to a live run and is not swept")
      (assert (= liveText "green\n") "the live entry's file is left alone")
      (assert freed "the lock is released")
      (assert (= swept (list "subject.txt")) "with no live owner the start sweep restores subject.txt and names it")
      (assert (= sweptText "red\n") "subject.txt holds the working change again after the sweep")
      (assert (listEmpty? (resultOr (dirList (str root "/.asl/run/revert")) (list))) "the swept entry is removed")
      (assert (ok? (pathRemove root)) "the temp dir is removed")
      true))
