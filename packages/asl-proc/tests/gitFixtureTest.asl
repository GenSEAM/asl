(module asl-proc/tests/gitFixtureTest
  :x [runTests]
  :i [(asl-proc/gitFixture :a gf) (tools/fleet/run :a run)])

fn ! rawGit! root: String args: (List String) -> Bool
  (= (run/runOneLimited (run/job (cons "git" args) root (run/childEnv (list))) (run/limits 10 8)).exit 0)

fn ! headOf! root: String -> String
  (let [(done (run/runOneLimited (run/job (list "git" "rev-parse" "HEAD") root (run/childEnv (list))) (run/limits 10 8)))]
    (if (= done.exit 0) (stringTrim done.out) ""))

fn ! configOf! root: String -> String
  (resultOr (fileReadString (str root "/.git/config")) "")

fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/gitFixtureTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! buildParent! parent: String -> Bool
  (and (ok? (dirCreate parent))
    (and (rawGit! parent (list "init" "-q"))
      (and (rawGit! parent (list "config" "user.name" "gitFixtureTestParent"))
        (and (rawGit! parent (list "config" "user.email" "gitFixtureTestParent@example.invalid"))
          (and (ok? (fileWrite (str parent "/seed.txt") "seed\n"))
            (and (rawGit! parent (list "add" "seed.txt"))
              (rawGit! parent (list "commit" "-q" "-m" "seed"))))))))

fn ! testPlainFileRoot! parent: String -> Bool
  (let [(root (str parent "/blockedByFile"))
        (ready (ok? (fileWrite root "not a directory\n")))
        (headBefore (headOf! parent))
        (configBefore (configOf! parent))
        (result (gf/initContained! root))
        (headAfter (headOf! parent))
        (configAfter (configOf! parent))]
    (and ready
      (and (err? result)
        (and (= headBefore headAfter) (= configBefore configAfter)))))

fn ! testUncontainedWriteEscapes! parent: String -> Bool
  (let [(escapeRoot (str parent "/escapeProbe"))
        (ready (ok? (dirCreate escapeRoot)))
        (headBefore (headOf! parent))
        (oldPath (rawGit! escapeRoot (list "commit" "--allow-empty" "-q" "-m" "oldPathEscapeProbe")))
        (headAfterOldPath (headOf! parent))]
    (and ready (and oldPath (!= headBefore headAfterOldPath))))

fn ! testContainedWriteRefuses! parent: String -> Bool
  (let [(root (str parent "/neverInit"))
        (ready (ok? (dirCreate root)))
        (headBefore (headOf! parent))
        (configBefore (configOf! parent))
        (result (gf/gitWrite! root (list "commit" "--allow-empty" "-q" "-m" "escapeProbe") (none)))
        (headAfter (headOf! parent))
        (configAfter (configOf! parent))]
    (and ready
      (and (err? result)
        (and (= headBefore headAfter) (= configBefore configAfter)))))

fn ! runTests -> Bool
  (let [(base (scratchBase!))
        (parent (str base "/parent"))
        (parentReady (buildParent! parent))
        (caseEscape (testUncontainedWriteEscapes! parent))
        (caseA (testPlainFileRoot! parent))
        (caseB (testContainedWriteRefuses! parent))
        (cleaned (pathRemove base))]
    (do
      (assert parentReady "parent fixture repo builds and takes a seed commit")
      (assert caseEscape "an unguarded git commit in a root lacking its own .git ascends and reaches the parent repo (the incident's mechanism, reproduced here on a disposable fixture)")
      (assert caseA "initContained! refuses a root that is a plain file, and the parent's HEAD and config are unchanged")
      (assert caseB "gitWrite! refuses a root that was never its own git repo, and the parent's HEAD and config are unchanged")
      (assert (ok? cleaned) "scratch fixture tree removed")
      true))
