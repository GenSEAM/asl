(module aslAgent/tests/finishWallBudgetTest
  :x [runTests]
  :i [(aslAgent/core :a c) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-TIMEOUT-NO-RECEIPT-CAUSE :do "a run whose grader call would outlast the wall left for the finish writes its (:partialReceipt ...) first, skips the grader with (:specCheck (:verdict skipped :reasons (wallBudget))) and ends needsReview inside the outer bound; the same run with wall to spare still calls the grader; the fixture grader sleeps 300 s, the outer bound is 90 s after a warm-up run that pays the host compile")
fn ! child argv: (List String) cwd: String -> Bool
  (= (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 20 8)).exit 0)

fn ! host -> (Option String)
  (let [h (optionOr (envGet "ASL_HOST") "bin/asl")
        p (resultOr (realPath h) h)]
    (if (fileExists? p)
      (some p)
      (do (assert false (str "the stage-0 host is absent at " p)) (none))))

fn ! tempDir label: String -> String
  (let [path (str "/tmp/asl-finish-wall-" label "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn ! write path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! initRepo root: String -> Bool
  (and (write (str root "/subject.txt") "before\n")
    (and (child (list "git" "-C" root "init" "-q" "-b" "main") root)
      (and (child (list "git" "-C" root "config" "user.name" "finishWall") root)
        (and (child (list "git" "-C" root "config" "user.email" "finish-wall@example.invalid") root)
          (and (child (list "git" "-C" root "add" "--" "subject.txt") root)
            (child (list "git" "-C" root "commit" "-q" "-m" "initial") root))))))

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [start (+ at (stringLength key))
            rest (c/sliceOf text start (stringLength text))]
        (match (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) "")))))

fn writeGreen -> String
  "(:turn :num 1 :reply \"(:step :op \\\"write\\\" :file \\\"subject.txt\\\" :content \\\"green\\\\n\\\") (:done)\")"

fn fixtureText id: String delayMs: Int64 -> String
  (str "(:script :id \"" id "\" :mode :implement\n  :turns (" (writeGreen) ")\n  :gradeReply \"(:verdict :met true)\" :gradeModel \"grader-fixture\" :gradeDelayMs \"" (stringFromInt64 delayMs) "\"\n)\n")

fn ! stage root: String name: String delayMs: Int64 minSec: Int64 -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
       (write (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:wallReserveSec 2 :wallFinishMinSec " (stringFromInt64 minSec) "))\n"))
       (write (str root "/tests/fixtures/agentLoop/mvp/" name ".asn") (fixtureText name delayMs)))

fn ! runMain root: String backend: String outerSec: Int64 -> fr/Done
  (match (host)
    ((none) (fr/Done :idx 0 :exit 127 :out "no host" :ms 0 :verdict "noHost"))
    ((some h)
      (let [form (str "(:agent :task \"finish wall\" :backend \"script/" backend "\" :root \"" root "\" :mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2 :wallBudget 30)")
            cwd (resultOr (realPath ".") ".")
            driver (resultOr (realPath "asl/packages/asl-agent/tests/mainDriver.asl") "asl/packages/asl-agent/tests/mainDriver.asl")]
        (fr/runOneLimited (fr/job (list h "run" driver form) cwd (fr/childEnv (list (str "ASL_HOST=" h) (str "ASL_ROOT_DIR=" cwd)))) (fr/limits outerSec 16)))))

fn ! journalOf root: String out: String -> String
  (readOr (str root "/.asl/run/agentLoop/" (fieldAfter out ":session \"") ".journal"))

fn indexOr text: String key: String -> Int64
  (optionOr (stringIndexOf text key) -1)

fn ! runTests -> Bool
  (match (host)
    ((none) false)
    ((some _)
      (let [slowRoot (tempDir "slow")
            roomRoot (tempDir "room")
            staged (and (stage slowRoot "slowFinish" 300000 60) (stage roomRoot "roomFinish" 3000 1))
            repos (and staged (and (initRepo slowRoot) (initRepo roomRoot)))
            room (runMain roomRoot "roomFinish" 400)
            startNs (nowNs)
            slow (runMain slowRoot "slowFinish" 90)
            slowSec (/ (- (nowNs) startNs) 1000000000)
            slowJournal (journalOf slowRoot slow.out)
            roomJournal (journalOf roomRoot room.out)
            partialAt (indexOr slowJournal "(:partialReceipt :turns")
            resultAt (indexOr slowJournal "(:result :status")
            cleaned (and (ok? (pathRemove slowRoot)) (ok? (pathRemove roomRoot)))]
        (do
          (assert repos "the fixtures and repositories are staged")
          (assert (and (= slow.exit 1) (stringContains? slow.out ":status :needsReview")) (str "the run with 28 s of wall for a 300 s grader ends needsReview with exit 1, not killed by the outer bound: exit " (stringFromInt64 slow.exit)))
          (assert (< slowSec 60) (str "after a warm-up run it exits well before the 90 s outer bound and the 300 s grader: " (stringFromInt64 slowSec) " s"))
          (assert (stringContains? slow.out ":verdict skipped") "the receipt marks the spec check skipped")
          (assert (stringContains? slow.out ":specCheck (:verdict skipped :reason wallBudget)") "the receipt names the wall budget as the skip reason")
          (assert (stringContains? slowJournal ":signal :finishSkipped") "the journal signals the skipped finish step")
          (assert (and (>= partialAt 0) (>= resultAt 0) (< partialAt resultAt)) "the partial receipt is journaled before the final result")
          (assert (stringContains? slowJournal ":stop \"") "the partial receipt carries the stop cause")
          (assert (and (= room.exit 0) (stringContains? room.out ":status :ok") (stringContains? room.out ":verdict pass")) "with wall to spare the grader is still called and passes")
          (assert (not (stringContains? roomJournal ":signal :finishSkipped")) "no finish step is skipped when time remains")
          (assert cleaned "the temporary roots are removed")
          true))))
