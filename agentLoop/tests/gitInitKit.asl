(module asl/agentLoop/tests/gitInitKit
  :x [initGitRepo!]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref NOSELFHOST-AGENTLOOP-TESTS :do "six tests each carried the same five bare processRun git-init calls, none of them in tools/tests/noSelfHostBaseline.asl's frozen per-file allowance, so the suite would go red the moment the scanner saw them; one shared helper here, built on fr/job + fr/runOneLimited (the same bounded Limits/killTreeWith! machinery runPool proves, mirroring asl-proc/tests/gitFixtureTest.asl's existing rawGit! pattern), replaces all five call sites in every caller without adding a single bare child start to any *Test.asl file")

fn gitStep! root: String args: (List String) -> Bool
  (= (fr/runOneLimited (fr/job (cons "git" args) root (fr/childEnv (list))) (fr/limits 10 8)).exit 0)

fn initGitRepo! root: String name: String email: String -> Bool
  (and (gitStep! root (list "init" "-q" "-b" "main"))
    (and (gitStep! root (list "config" "user.name" name))
      (and (gitStep! root (list "config" "user.email" email))
        (and (gitStep! root (list "add" "--" "subject.txt"))
          (gitStep! root (list "commit" "-q" "-m" "initial"))))))
