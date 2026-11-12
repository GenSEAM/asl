(module asl/tools/vcs/tests/vcsApplyCheckedTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref APPLYPATCH-SOFT-ERR :do "outcomeOf turns a git child that did not run to its end (spawnFailed, timeout, runaway) into err and a finished one into ok with its exit; applyPatchChecked! over a temp repo: a refused patch is ok with a non-zero exit, quiet drops the whitespace warning, an option-like patch is refused")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsApplyCheckedTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! git dir: String args: (List String) -> String
  (stringTrim (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).out)

fn done exit: Int64 verdict: String -> fr/Done
  (fr/Done :idx 0 :exit exit :out "o" :ms 0 :verdict verdict)

fn isErr? r: (Result gb/Out String) -> Bool
  (match r ((ok _) false) ((err _) true))

fn exitOf r: (Result gb/Out String) -> Int64
  (match r ((ok o) o.exit) ((err _) -1))

fn outOf r: (Result gb/Out String) -> String
  (match r ((ok o) o.out) ((err e) e))

fn ! readAt dir: String p: String -> String
  (resultOr (fileReadString (str dir "/" p)) "<absent>")

fn ! runTests -> Bool
  (let [(fin (gb/outcomeOf (done 1 "exit")))
        (token (gb/outcomeOf (done 124 "tokenWait")))
        (spawn (gb/outcomeOf (done 127 "spawnFailed")))
        (late (gb/outcomeOf (done 124 "timeout")))
        (runaway (gb/outcomeOf (done 125 "runaway")))
        (dir (scratch))
        (mk (sh "." (list "mkdir" "-p" dir)))
        (_ (git dir (list "init" "-q" "-b" "main")))
        (w (ok? (fileWrite (str dir "/a.txt") "one\ntwo\n")))
        (_ (git dir (list "add" "-A")))
        (_ (git dir (list "commit" "-q" "-m" "c0")))
        (ws (str dir "/ws.diff"))
        (bad (str dir "/bad.diff"))
        (w1 (ok? (fileWrite ws "diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n-one\n+uno  \n two\n")))
        (w2 (ok? (fileWrite bad "diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-zzz\n+yyy  \n")))
        (loud (gb/applyPatchChecked! dir ws false false))
        (a1 (readAt dir "a.txt"))
        (back (gb/restoreTree! dir "HEAD" (list "a.txt")))
        (quiet (gb/applyPatchChecked! dir ws false true))
        (a2 (readAt dir "a.txt"))
        (refused (gb/applyPatchChecked! dir bad false true))
        (refusedLoud (gb/applyPatchChecked! dir bad false false))
        (option (gb/applyPatchChecked! dir "-p" false true))
        (_ (pathRemove dir))]
    (do (assert (= (exitOf fin) 1) (str "a finished git with exit 1 is ok with exit 1: " (outOf fin)))
        (assert (and (isErr? spawn) (stringContains? (outOf spawn) "spawnFailed")) (str "a git that did not start is err: " (outOf spawn)))
        (assert (and (isErr? late) (stringContains? (outOf late) "timeout")) (str "a git that timed out is err: " (outOf late)))
        (assert (isErr? runaway) (str "a git that ran away is err: " (outOf runaway)))
        (assert (isErr? token) (str "a git that never got a token is err: " (outOf token)))
        (assert (and (= mk.exit 0) (and w (and w1 w2))) "fixture repo and two patches")
        (assert (and (= (exitOf loud) 0) (= a1 "uno  \ntwo\n")) (str "the patch applies: " (outOf loud) a1))
        (assert (stringContains? (outOf loud) "trailing whitespace") (str "without quiet git warns about the whitespace: " (outOf loud)))
        (assert (and (= back.exit 0) (and (= (exitOf quiet) 0) (= a2 "uno  \ntwo\n"))) (str "quiet applies it too: " (outOf quiet)))
        (assert (not (stringContains? (outOf quiet) "whitespace")) (str "quiet passes --whitespace=nowarn: " (outOf quiet)))
        (assert (and (not (isErr? refused)) (!= (exitOf refused) 0)) (str "a patch git refuses is ok with a non-zero exit: " (outOf refused)))
        (assert (and (stringContains? (outOf refused) "patch does not apply") (not (stringContains? (outOf refused) "whitespace"))) (str "and quiet keeps only the error: " (outOf refused)))
        (assert (stringContains? (outOf refusedLoud) "trailing whitespace") (str "the decoy without quiet carries the warning: " (outOf refusedLoud)))
        (assert (= (outOf option) "patch not accepted") (str "an option-like patch is refused before git: " (outOf option)))
        true))
