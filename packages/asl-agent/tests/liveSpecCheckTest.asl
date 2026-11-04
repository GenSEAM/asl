(module aslAgent/tests/liveSpecCheckTest
  :x [runTests]
  :i [(aslAgent/core :a c) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-CAPS :do "every child start goes through asl/tools/fleet/run.asl with a timeout and a descendant limit, as the spawnSafety rule requires")
fn ! child argv: (List String) cwd: String -> Bool
  (= (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 20 8)).exit 0)

fn ! host -> (Option String)
  (let [h (optionOr (envGet "ASL_HOST") "bin/asl")
        p (resultOr (realPath h) h)]
    (if (fileExists? p)
      (some p)
      (do (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST")) (none))))

fn ! tempDir label: String -> String
  (let [path (str "/tmp/asl-live-spec-" label "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate path) path))

fn ! write path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! initCommitRepo root: String initial: String -> Bool
  (and (write (str root "/subject.txt") initial)
    (and (child (list "git" "-C" root "init" "-q" "-b" "main") root)
      (and (child (list "git" "-C" root "config" "user.name" "liveSpec") root)
        (and (child (list "git" "-C" root "config" "user.email" "live-spec@example.invalid") root)
          (and (child (list "git" "-C" root "add" "--" "subject.txt") root)
            (child (list "git" "-C" root "commit" "-q" "-m" "initial") root))))))

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [start (+ at (stringLength key))
            rest (c/sliceOf text start (stringLength text))]
        (match (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) "")))))

fn ! runMain root: String task: String backend: String extra: String -> fr/Done
  (match (host)
    ((none) (fr/Done :idx 0 :exit 127 :out "no host" :ms 0 :verdict "noHost"))
    ((some h)
      (let [form (str "(:agent :task \"" task "\" :backend \"script/" backend "\" :root \"" root "\" " extra ")")
            cwd (resultOr (realPath ".") ".")
            driver (resultOr (realPath "asl/packages/asl-agent/tests/mainDriver.asl") "asl/packages/asl-agent/tests/mainDriver.asl")]
        (fr/runOneLimited (fr/job (list h "run" driver form) cwd (fr/childEnv (list (str "ASL_HOST=" h) (str "ASL_ROOT_DIR=" cwd)))) (fr/limits 600 16)))))

; (:m :ref LEON-CAPS :do "end to end through main with the scripted fixture transport: :gradeReply and :gradeModel are the fake grader channel, so these asserts prove the real wiring from the live receipt and journal to the end status and exit code, and the claim backing of the final reply against a gate that really ran; the fake proves nothing about a model's judgement")
fn fixtureText id: String turns: String extra: String -> String
  (str "(:script :id \"" id "\" :mode :implement\n  :turns (" turns ")\n  " extra "\n)\n")

fn ! stage root: String name: String text: String -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
       (write (str root "/.asl.config.asn") (if (stringStartsWith? name "claim") "(:aslConfig :agentLoop (:specCheck false))\n" "(:aslConfig)\n"))
       (write (str root "/tests/fixtures/agentLoop/mvp/" name ".asn") text))

fn writeGreen -> String
  "(:turn :num 1 :reply \"(:step :op \\\"write\\\" :file \\\"subject.txt\\\" :content \\\"green\\\\n\\\") (:done)\")"

fn claimTurn claim: String -> String
  (str "(:turn :num 1 :reply \"" claim " (:step :op \\\"write\\\" :file \\\"subject.txt\\\" :content \\\"green\\\\n\\\") (:done)\")")

fn ! journalOf root: String out: String -> String
  (readOr (str root "/.asl/run/agentLoop/" (fieldAfter out ":session \"") ".journal"))

fn ! gateScript root: String -> Bool
  (and (write (str root "/test.sh") "#!/bin/sh\ngrep -qx green subject.txt && echo '3 assertion(s) executed (3 passed)'\n")
    (and (child (list "chmod" "+x" (str root "/test.sh")) root)
      (and (child (list "git" "-C" root "add" "--" "test.sh") root)
        (child (list "git" "-C" root "commit" "-q" "-m" "gate") root))))

fn ! runTests -> Bool
  (match (host)
    ((none) false)
    ((some _)
      (let [passRoot (tempDir "x")
            failRoot (tempDir "x")
            sameRoot (tempDir "x")
            plainRoot (tempDir "x")
            claimOkRoot (tempDir "x")
            claimBadRoot (tempDir "x")
            pass-staged (stage passRoot "specPass" (fixtureText "specPass" (writeGreen) ":gradeReply \"(:verdict :met true)\" :gradeModel \"grader-fixture\""))
            fail-staged (stage failRoot "specFail" (fixtureText "specFail" (writeGreen) ":gradeReply \"(:verdict :met false :missing (\\\"no test covers it\\\"))\" :gradeModel \"grader-fixture\""))
            same-staged (stage sameRoot "specSame" (fixtureText "specSame" (writeGreen) ":gradeReply \"(:verdict :met true)\" :gradeModel \"writer-x\""))
            plain-staged (stage plainRoot "specPlain" (fixtureText "specPlain" (writeGreen) ""))
            okStaged (stage claimOkRoot "claimOk" (fixtureText "claimOk" (claimTurn "The gate passed with 3 assertions executed.") ""))
            badStaged (stage claimBadRoot "claimBad" (fixtureText "claimBad" (claimTurn "The gate passed with 9 assertions executed.") ""))
            ready (and pass-staged (and fail-staged (and same-staged (and plain-staged (and okStaged badStaged)))))
            repos (and ready (and (initCommitRepo passRoot "before\n") (and (initCommitRepo failRoot "before\n")
                    (and (initCommitRepo sameRoot "before\n") (and (initCommitRepo plainRoot "before\n")
                      (and (initCommitRepo claimOkRoot "before\n") (and (initCommitRepo claimBadRoot "before\n")
                        (and (gateScript claimOkRoot) (gateScript claimBadRoot)))))))))
            passRun (runMain passRoot "spec pass" "specPass" ":mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2")
            failRun (runMain failRoot "spec fail" "specFail" ":mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2")
            sameRun (runMain sameRoot "spec same model" "specSame" ":mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2")
            plainRun (runMain plainRoot "no grader channel" "specPlain" ":mode \"implement\" :model \"writer-x\" :owns (\"subject.txt\") :budget 2")
            okRun (runMain claimOkRoot "backed claim" "claimOk" ":mode \"implement\" :owns (\"subject.txt\") :gates (\"./test.sh\") :budget 2")
            badRun (runMain claimBadRoot "unbacked claim" "claimBad" ":mode \"implement\" :owns (\"subject.txt\") :gates (\"./test.sh\") :budget 2")
            passJournal (journalOf passRoot passRun.out)
            badJournal (journalOf claimBadRoot badRun.out)
            failSubject (readOr (str failRoot "/subject.txt"))
            cleaned (fold (fn [acc r] (and acc (ok? (pathRemove r)))) true (list passRoot failRoot sameRoot plainRoot claimOkRoot claimBadRoot))]
        (do
          (assert repos "the fixtures and repositories are staged")
          (assert (and (= passRun.exit 0) (stringContains? passRun.out ":status :ok")
                       (stringContains? passRun.out ":specCheck (:verdict pass :model \"grader-fixture\" :reasons ())")
                       (stringContains? passJournal "(:graderServed :model \"grader-fixture\")"))
                  "a scripted grader of another model that finds the task met leaves the live receipt ok and exit 0, with the verdict in the receipt and the grader's model in the journal")
          (assert (and (= failRun.exit 1) (stringContains? failRun.out ":status :needsReview")
                       (stringContains? failRun.out ":specCheck (:verdict fail :model \"grader-fixture\" :reasons (\"no test covers it\"))")
                       (= failSubject "green\n"))
                  "a not-met verdict makes the live receipt needsReview with exit 1, reports the reasons and keeps the written change")
          (assert (and (= sameRun.exit 1) (stringContains? sameRun.out ":status :needsReview")
                       (stringContains? sameRun.out "is the writer's model"))
                  "a grader that serves the writer's own model is a fail even when it says met")
          (assert (and (= plainRun.exit 1) (stringContains? plainRun.out ":status :needsReview")
                       (stringContains? plainRun.out ":specCheck (:verdict skipped :reason noGrader)"))
                  "a transport without a grader channel ends needsReview with verdict skipped, exit 1")
          (assert (and (= okRun.exit 0) (stringContains? okRun.out ":status :ok") (stringContains? okRun.out ":unbacked 0"))
                  "a final claim of 3 assertions executed is backed by the gate that executed 3")
          (assert (and (= badRun.exit 1) (stringContains? badRun.out ":unbacked 1")
                       (stringContains? badRun.out ":unbackedClaims (\"The gate passed with 9 assertions executed")
                       (stringContains? badJournal ":unbacked 1"))
                  "a final claim of 9 assertions executed that no gate run executed is counted unbacked in the receipt and the journal, with exit 1")
          (assert cleaned "live spec-check temporary roots are removed")
          true))))
