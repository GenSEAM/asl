(module aslAgent/tests/pathResolveTest
  :x [runTests]
  :i [(aslAgent/pathResolve :a pr) (aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

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

; (:m :ref LEON-MODULE-PATH-ASLTOOLS :do "two fleet/run.asl files under different package dirs, so suffix matching alone is ambiguous; the module headers name them kit-tools/fleet/run and kit-other/fleet/run")
fn ! moduleRoot! -> String
  (let [root (rk/freshRecorderRoot! "pathResolveModule")
        made (and (ok? (dirCreate (str root "/pk/tools/fleet"))) (ok? (dirCreate (str root "/pk/other/fleet"))))
        w1 (fileWrite (str root "/pk/tools/fleet/run.asl") "(module kit-tools/fleet/run\n  :x [job])\n\nfn job -> Int64\n  1\n")
        w2 (fileWrite (str root "/pk/other/fleet/run.asl") "(module kit-other/fleet/run\n  :x [job])\n\nfn job -> Int64\n  2\n")
        repo (gk/initGitRepo! root "pathResolveModule" "path-resolve.invalid")]
    root)

fn ! readTarget! root: String want: String -> String
  (let [r (pr/resolveOp! (list (pair "file" (c/kvStr want))) "read" root)]
    (match (c/dictGet (pairFirst r) "file") ((some (c/kvStr t)) t) (_ "")))

fn ! opTarget! root: String opName: String want: String -> String
  (let [(r (pr/resolveOp! (list (pair "file" (c/kvStr want))) opName root))]
    (match (c/dictGet (pairFirst r) "file") ((some (c/kvStr t)) t) (_ "")))

; (:m :ref MODPATH-LOWS :do "the workspace shape in a scratch root: asl/tools/fleet/run.asl declares asl-tools/fleet/run and a package kit-tools holds another fleet/run.asl, so the assert no longer reads the live tree")
fn ! aslRoot! -> String
  (let [root (rk/freshRecorderRoot! "pathResolveAsl")
        made (and (ok? (dirCreate (str root "/asl/tools/fleet"))) (ok? (dirCreate (str root "/asl/packages/kit-tools/src/fleet"))))
        w1 (fileWrite (str root "/asl/tools/fleet/run.asl") "(module asl-tools/fleet/run\n  :x [job])\n\nfn job -> Int64\n  1\n")
        w2 (fileWrite (str root "/asl/packages/kit-tools/src/fleet/run.asl") "(module kit-tools/fleet/run\n  :x [job])\n\nfn job -> Int64\n  2\n")
        repo (gk/initGitRepo! root "pathResolveAsl" "path-resolve.invalid")]
    root)

fn ! memoBuilds! root: String -> Int64
  (listLength (filter (fn [l] (stringStartsWith? l "(:mod ")) (stringLines (resultOr (fileReadString (str root "/.asl/run/pathResolve/modules.asn")) ""))))

fn ! runTests -> Bool
  (let [fs (files)
        run (recorded!)
        mroot (moduleRoot!)
        bare (readTarget! mroot "kit-tools/fleet/run")
        withExt (readTarget! mroot "kit-tools/fleet/run.asl")
        other (readTarget! mroot "kit-other/fleet/run")
        outl (opTarget! mroot "outline" "pk/tools/fleet/run")
        qry (opTarget! mroot "query" "pk/other/fleet/run")
        obs (opTarget! mroot "observe" "pk/tools/fleet/run")
        again (readTarget! mroot "kit-tools/fleet/run")
        builds (memoBuilds! mroot)
        moved (fileWrite (str mroot "/pk/tools/fleet/run.asl") "(module kit-moved/fleet/run\n  :x [job])\n\nfn job -> Int64\n  1\n")
        stale (readTarget! mroot "kit-tools/fleet/run")
        rebuilt (memoBuilds! mroot)
        mcleaned (ok? (pathRemove mroot))
        aroot (aslRoot!)
        real (readTarget! aroot "asl-tools/fleet/run")
        acleaned (ok? (pathRemove aroot))]
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
      (assert (= bare "pk/tools/fleet/run.asl") (str "a module name without .asl resolves through the checker to its file: " bare))
      (assert (= withExt "pk/tools/fleet/run.asl") (str "a module name with .asl resolves to the file its header declares, though another fleet/run.asl exists: " withExt))
      (assert (= other "pk/other/fleet/run.asl") (str "the other package keeps its own module: " other))
      (assert (and (= outl "pk/tools/fleet/run.asl") (and (= qry "pk/other/fleet/run.asl") (= obs "pk/tools/fleet/run.asl"))) (str "outline, query and observe of a missing x/y run on x/y.asl when it exists: " outl " " qry " " obs))
      (assert mcleaned "the module fixture root is removed")
      (assert (= real "asl/tools/fleet/run.asl") (str "in a scratch root of the workspace shape asl-tools/fleet/run resolves to asl/tools/fleet/run.asl: " real))
      (assert acleaned "the scratch workspace root is removed")
      (assert (= again "pk/tools/fleet/run.asl") (str "a repeated module lookup still resolves: " again))
      (assert (= builds 2) (str "two module names looked up five times build the index twice: the .asl and repeat lookups reuse the memo row and x/y to x/y.asl builds none: " (stringFromInt64 builds)))
      (assert (and (!= stale "pk/tools/fleet/run.asl") (= rebuilt 3)) (str "a memo row whose file no longer declares the module is not used: the lookup builds again: " stale " builds " (stringFromInt64 rebuilt)))
      (assert (none? (pr/resolveIn (list "asl" "asl/tools" "asl/tools/coord" "asl/other" "asl/other/fixtures") "asl/tools/coord/fixtures")) "a new dir under a real top-level prefix is not redirected to another package's same-named dir")
      true))
