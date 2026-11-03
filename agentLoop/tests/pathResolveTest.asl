(module asl/agentLoop/tests/pathResolveTest
  :x [runTests]
  :i [(asl/agentLoop/pathResolve :a pr) (asl/agentLoop/core :a c) (asl/agentLoop/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-PATH-RESOLVE :do "node2 2026-11-02 repeatFailure runs sent module-name paths (asl-gates/metaAudit.asl, tree asl-gates, write asl-tools/coord/x.asl) three times in a row and stopped; this suite holds the resolver on that shape of tree and drives a recorded run whose read, tree and write name module paths")

fn files -> (List String)
  (list "pk/packages/kit-gates/src/metaAudit.asl" "pk/packages/kit-gates/src/auditGates.asl" "pk/packages/kit-gates/manifest.asn"
        "pk/packages/kit-cli/src/cacheGc.asl" "pk/tools/coord/conductor.asl" "pk/tools/coord/tests/conductorTest.asl"
        "pk/packages/kit-cli/src/util.asl" "pk/packages/kit-gates/src/util.asl")

fn ! recorded! -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! "pathResolve")
        made (and (ok? (dirCreate (str root "/pk/packages/kit-gates/src"))) (ok? (dirCreate (str root "/pk/tools/coord/tests"))))
        w1 (fileWrite (str root "/pk/packages/kit-gates/src/metaAudit.asl") "META-AUDIT-BODY\n")
        w2 (fileWrite (str root "/pk/tools/coord/tests/conductorTest.asl") "x\n")
        repo (gk/initGitRepo! root "pathResolve" "path-resolve@example.invalid")
        replies (list "(:step :op \"read\" :file \"kit-gates/metaAudit.asl\")"
                      "(:step :op \"tree\" :path \"kit-gates\")"
                      "(:step :op \"write\" :file \"kit-tools/coord/tests/newNote.txt\" :content \"NEWBODY\\n\")"
                      "(:done)")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/pathResolve.asn") (rk/scriptFixtureTextFromReplies! "pathResolve" replies))
        form (str "(:agent :task \"read the meta audit\" :backend \"script/pathResolve\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :budget 8 :contextTokens 120000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        written (resultOr (fileReadString (str root "/pk/tools/coord/tests/newNote.txt")) "")
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal (str text "\n(:written \"" written "\")") :sentLines (list)))

fn ! runTests -> Bool
  (let [fs (files)
        run (recorded!)]
    (do
      (assert (= (pr/resolveIn fs "kit-gates/metaAudit.asl") (some "pk/packages/kit-gates/src/metaAudit.asl")) "a module-name file path resolves to the one file ending in its rest")
      (assert (= (pr/resolveIn fs "kit-gates/util.asl") (some "pk/packages/kit-gates/src/util.asl")) "two candidates narrow to the one that carries the dropped segment")
      (assert (= (pr/resolveIn fs "other/util.asl") (none)) "two candidates that carry no dropped segment resolve to nothing")
      (assert (= (pr/resolveIn (pr/dirsOf fs) "kit-gates") (some "pk/packages/kit-gates")) "a single-segment directory resolves by its last segment")
      (assert (= (pr/resolveIn (pr/dirsOf fs) "kit-tools/coord/tests") (some "pk/tools/coord/tests")) "a directory path resolves by its rest")
      (assert (= (pr/resolveIn fs "nowhere/missing.asl") (none)) "a name with no candidate resolves to nothing")
      (assert (stringContains? run.journal "META-AUDIT-BODY") "the recorded read of kit-gates/metaAudit.asl returned the file")
      (assert (stringContains? run.journal "resolvedFrom") "the receipt names the path the step was sent with")
      (assert (not (stringContains? run.journal "Directory not found")) "the tree of kit-gates found the package directory")
      (assert (stringContains? run.journal "(:written \"NEWBODY") "the write to a module-name directory landed in the resolved directory")
      (assert (none? (pr/resolveIn (list "asl" "asl/tools" "asl/tools/coord" "asl/other" "asl/other/fixtures") "asl/tools/coord/fixtures")) "a new dir under a real top-level prefix is not redirected to another package's same-named dir")
      true))
