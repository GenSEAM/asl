(module aslAgent/tests/finishWallHookTest
  :x [runTests]
  :i [(aslAgent/core :a c) (asl-tools/fleet/run :a fr) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-FINISH-HANG :do "the two finish call sites in main.asl end inside the wall, through the real CLI on scripted providers: a green gated run whose revert gate sleeps 600 s with a 300 s gate timeout and 90 s of wall ends its revert check unfinished on the wall (the 900 s floor would outlast a 170 s outer bound), and a run whose grader sleeps 300 s with 30 s of wall, after a warm-up run that pays the host compile, gets its grader cut by the wall and ends needsReview inside a 90 s outer bound")

fn ! host -> (Option String)
  (let [h (optionOr (envGet "ASL_HOST") "bin/asl")
        p (resultOr (realPath h) h)]
    (if (fileExists? p)
      (some p)
      (do (assert false (str "the stage-0 host is absent at " p)) (none))))

fn ! tempDir label: String -> String
  (let [path (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-finish-hook-" label "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) (resultOr (realPath path) path)))

fn ! write path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [start (+ at (stringLength key))
            rest (c/sliceOf text start (stringLength text))]
        (match (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) "")))))

fn writeGreen -> String
  "(:turn :num 1 :reply \"(:step :op \\\"write\\\" :file \\\"subject.txt\\\" :content \\\"green\\\\n\\\") (:done)\")"

fn gateScript -> String
  "if grep -qx green subject.txt; then : > seen; echo '(:gate :asserts 1 :failed 0)'; elif test -f seen; then sleep 600; else echo '(:gate :asserts 1 :failed 1)'; exit 1; fi\n"

fn ! stage root: String name: String fixture: String withGate: Bool -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
    (and (write (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:wallReserveSec 2 :wallFinishMinSec 1))\n")
      (and (write (str root "/tests/fixtures/agentLoop/mvp/" name ".asn") fixture)
        (and (write (str root "/subject.txt") "before\n")
          (and (if withGate (write (str root "/gate.sh") (gateScript)) true)
            (gk/initGitRepoWith! root "finishHook" "finish-hook@example.invalid" (if withGate (list "subject.txt" "gate.sh") (list "subject.txt"))))))))

fn ! runMain root: String backend: String outerSec: Int64 extra: String -> fr/Done
  (match (host)
    ((none) (fr/Done :idx 0 :exit 127 :out "no host" :ms 0 :verdict "noHost"))
    ((some h)
      (let [form (str "(:agent :task \"finish hook\" :backend \"script/" backend "\" :root \"" root "\" :mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2" extra ")")
            cwd (resultOr (realPath ".") ".")
            driver (resultOr (realPath "asl/packages/asl-agent/tests/mainDriver.asl") "asl/packages/asl-agent/tests/mainDriver.asl")]
        (fr/runOneLimited (fr/job (list h "run" driver form) cwd (fr/childEnv (list (str "ASL_HOST=" h) (str "ASL_ROOT_DIR=" cwd)))) (fr/limits outerSec 16)))))

fn ! journalOf root: String out: String -> String
  (readOr (str root "/.asl/run/agentLoop/" (fieldAfter out ":session \"") ".journal"))

fn ! removeTree root: String -> Bool
  (= (fr/runOneLimited (fr/job (list "rm" "-rf" root) "/" (fr/childEnv (list))) (fr/limits 30 4)).exit 0)

fn ! runTests -> Bool
  (match (host)
    ((none) false)
    ((some _)
      (let [gradeRoot (tempDir "grade")
            revertRoot (tempDir "revert")
            gradeFixture (str "(:script :id \"hookGrade\" :mode :implement\n  :turns (" (writeGreen) ")\n  :gradeReply \"(:verdict :met true)\" :gradeModel \"grader-fixture\" :gradeDelayMs 300000\n)\n")
            revertFixture (str "(:script :id \"hookRevert\" :mode :implement\n  :turns (" (writeGreen) ")\n)\n")
            staged (and (stage gradeRoot "hookGrade" gradeFixture false) (stage revertRoot "hookRevert" revertFixture true))
            warmRoot (tempDir "warm")
            warmStaged (stage warmRoot "hookWarm" (str "(:script :id \"hookWarm\" :mode :implement\n  :turns (" (writeGreen) ")\n)\n") false)
            warm (runMain warmRoot "hookWarm" 600 "")
            graded (runMain gradeRoot "hookGrade" 90 " :wallBudget 30")
            gradeJournal (journalOf gradeRoot graded.out)
            reverted (runMain revertRoot "hookRevert" 170 " :gates (\"sh gate.sh\") :gateTimeout 300 :wallBudget 90")
            revertJournal (journalOf revertRoot reverted.out)
            cleaned (and (removeTree warmRoot) (and (removeTree gradeRoot) (removeTree revertRoot)))]
        (do
          (assert (and staged warmStaged) "the fixtures and repositories are staged")
          (assert (!= warm.exit 124) (str "the warm-up run that pays the host compile ends inside its bound: " warm.verdict))
          (assert (!= graded.exit 124) (str "the run with a 300 s grader and 30 s of wall is not killed by the 90 s outer bound: exit " (stringFromInt64 graded.exit) " " graded.verdict))
          (assert (stringContains? graded.out ":status :needsReview") (str "the run whose grader was cut ends needsReview: " graded.out))
          (assert (stringContains? (str graded.out gradeJournal) "the grader call was cut at") (str "the grader call ends on the wall cap, not on its own: " graded.out))
          (assert (!= reverted.exit 124) (str "the run whose revert gate sleeps 600 s is not killed by the 170 s outer bound: exit " (stringFromInt64 reverted.exit) " " reverted.verdict))
          (assert (stringContains? revertJournal "(:gateIntegrity :ok false") (str "the revert check that ran out of wall does not pass: " reverted.out))
          (assert (stringContains? revertJournal "revertCheck unfinished :revertKind wall") (str "the revert check names the wall as why it is unfinished: " reverted.out))
          (assert (stringContains? reverted.out ":status :failed") (str "the run ends failed with a receipt: " reverted.out))
          (assert cleaned "the temporary roots are removed")
          true))))
