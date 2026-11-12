(module aslAgent/tests/killCheckpointTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)
      (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-TIMEOUT-NO-RECEIPT :do "an outer bound kills a scripted Leon run mid-turn after one persisted edit (bounded.asl 240 s, room for a cold compile; the kill is SIGKILL, no hook can run): the journal still names a patch file that exists and holds the edit, because the loop checkpoints the patch after every turn. The fixture child is hard-bounded by bounded.asl and its tree is killed by the runner")
fn ! child! root: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "./bin/asl" "run" "asl/tools/fleet/bounded.asl") argv) root (fr/childEnv (list))) (fr/limits 120 64))

fn quotedAfter line: String -> String
  (match (stringIndexOf line ":patch \"")
    ((none) "")
    ((some at) (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ at 8) (stringLength line)) "") "\"")) "")))

fn checkpointPatch journal: String -> String
  (match (listLast (filter (fn [l] (stringStartsWith? l "(:checkpoint ")) (stringSplit journal "\n")))
    ((none) "")
    ((some l) (quotedAfter l)))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        root (rk/freshRecorderRoot! "killCheckpoint")
        done (child! repo (list "240" "--" "./bin/asl" "run" "asl/packages/asl-agent/tests/killCheckpointDriver.asl" root))
        journalDir (str root "/.asl/run/agentLoop")
        names (resultOr (dirList journalDir) (list))
        jname (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        journal (if (stringEmpty? jname) "" (resultOr (fileReadString (str journalDir "/" jname)) ""))
        patchRel (checkpointPatch journal)
        patch (if (stringEmpty? patchRel) "" (resultOr (fileReadString (str root "/" patchRel)) ""))
        cleaned (ok? (pathRemove root))]
    (do
      (assert (= done.exit 124) "the outer bound killed the scripted run (exit 124)")
      (assert (stringContains? journal ":name \"edit\" :file \"task.txt\" :status ok") "the edit turn ran before the kill")
      (assert (not (stringContains? journal "(:result ")) "the run was killed before any (:result ...) line")
      (assert (not (stringEmpty? patchRel)) "the journal names a checkpoint patch")
      (assert (and (stringContains? patch "-before") (stringContains? patch "+after")) "the named patch file exists and holds the edit")
      (assert cleaned "the fixture root is removed")
      true))
