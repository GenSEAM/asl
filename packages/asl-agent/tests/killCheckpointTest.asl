(module aslAgent/tests/killCheckpointTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)
      (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-TIMEOUT-NO-RECEIPT :do "an outer kill lands on a scripted Leon run mid-run after one persisted edit (SIGKILL of the whole tree, no hook can run): the journal still names a patch file that exists and holds the edit, because the loop checkpoints the patch after every turn. The fixture child is hard-bounded by bounded.asl and its tree is killed by the fleet runner")
; (:m :ref TRAIN-RED-SUITES :do "the kill is sent once the journal shows the edit turn and its checkpoint, not at a fixed second: a 120 s runner limit killed the run before the edit whenever the driver's cold compile under train load took longer (node2 trains 2026-11-16..21, 6 reds, 'the edit turn ran before the kill'); the driver starts 3 s late, the stand-in for that compile, and bounded.asl 900 s plus the same deadline here bound a run whose checkpoint never comes")
fn boundS -> Int64
  900

fn lateS -> Int64
  3

fn quotedAfter line: String -> String
  (match (stringIndexOf line ":patch \"")
    ((none) "")
    ((some at) (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ at 8) (stringLength line)) "") "\"")) "")))

fn checkpointPatch journal: String -> String
  (match (listLast (filter (fn [l] (stringStartsWith? l "(:checkpoint ")) (stringSplit journal "\n")))
    ((none) "")
    ((some l) (quotedAfter l)))

fn edited? journal: String -> Bool
  (and (stringContains? journal ":name \"edit\" :file \"task.txt\" :status ok") (not (stringEmpty? (checkpointPatch journal))))

fn ! journalOf root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        names (resultOr (dirList dir) (list))
        jname (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")]
    (if (stringEmpty? jname) "" (resultOr (fileReadString (str dir "/" jname)) "")))

fn ! awaitEdit! root: String deadlineNs: Int64 -> Bool
  (cond
    ((edited? (journalOf root)) true)
    ((> (monotonicNs) deadlineNs) false)
    (else (do (sleepMs 500) (awaitEdit! root deadlineNs))))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        root (rk/freshRecorderRoot! "killCheckpoint")
        cmd (str "exec ./bin/asl run asl/tools/fleet/bounded.asl " (stringFromInt64 (boundS)) " -- ./bin/asl run asl/packages/asl-agent/tests/killCheckpointDriver.asl " root " " (stringFromInt64 (lateS)) " >" root "/child.log 2>&1")
        started (fr/spawn 0 (fr/job (list "/bin/sh" "-c" cmd) repo (fr/childEnv (list))))
        pid (match started ((ok r) r.pid) ((err _) 0))
        seen (and (> pid 0) (awaitEdit! root (+ (monotonicNs) (* (boundS) 1000000000))))
        killed (if (> pid 0) (do (fr/killTree! pid) true) false)
        reaped (if (> pid 0) (ok? (procWaitPid pid false)) false)
        pipes (match started ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true))
        journal (journalOf root)
        patchRel (checkpointPatch journal)
        patch (if (stringEmpty? patchRel) "" (resultOr (fileReadString (str root "/" patchRel)) ""))
        log (resultOr (fileReadString (str root "/child.log")) "")
        cleaned (ok? (pathRemove root))]
    (do
      (assert (> pid 0) "the scripted run started through the fleet runner")
      (assert seen (str "the edit turn and its checkpoint reached the journal before the kill: " (stringJoin (listTake (stringLines log) 5) " | ")))
      (assert (and killed (and reaped pipes)) "the run tree was killed and reaped, its pipes closed")
      (assert (not (stringContains? journal "(:result ")) "the run was killed before any (:result ...) line")
      (assert (not (stringEmpty? patchRel)) "the journal names a checkpoint patch")
      (assert (and (stringContains? patch "-before") (stringContains? patch "+after")) "the named patch file exists and holds the edit")
      (assert cleaned "the fixture root is removed")
      true))
