(module aslAgent/tests/moduleTrackedTest
  :x [runTests]
  :i [(aslAgent/exec :a ex) (asl-tools/fleet/run :a fr)])

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "the module header check refuses no file the workspace already tracks: every tracked .asl written back as it is passes (grader 2026-11-18 found 739 false refusals on 91785f92b); the list comes from git ls-files through the fleet runner")
fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        done (fr/runOneLimited (fr/job (list "git" "ls-files" "*.asl") root (list "PATH=/usr/bin:/bin")) (fr/limits 60 4))
        paths (filter (fn [p] (not (stringEmpty? p))) (stringSplit done.out "\n"))
        bad (filter (fn [p] (not (stringEmpty? (ex/moduleMismatch! root "write" p (resultOr (fileReadString (str root "/" p)) ""))))) paths)]
    (do
      (assert (and (= done.exit 0) (> (listLength paths) 2000)) (str "git ls-files listed the tracked .asl files, exit " (stringFromInt64 done.exit) " count " (stringFromInt64 (listLength paths))))
      (assert (listEmpty? bad) (str (stringFromInt64 (listLength bad)) " tracked files would be refused: " (stringJoin (listTake bad 8) " ")))
      true))
