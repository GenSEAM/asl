(module asl-cli/tests/rebuildGuardTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeRefresh :a nr)])

; (:m :ref WT-MAIN-HOME-REBUILD :do "bin/asl never starts a native rebuild in a tree that is not the caller's own: the decision (nativeRefresh guard!) is pure on (tree home cwd explicit-cache); a scratch tree with its own fake build.sh proves the cold path: HOME elsewhere and cwd outside refuses with one rebuildRefused receipt and runs no build.sh, HOME above the tree or cwd inside it or an explicit cache lets build.sh run")
fn ! mk! root: String -> Bool
  (let [(real (resultOr (realPath ".") "."))
        (made (run/runOneLimited (run/job (list "/bin/sh" "-c" "rm -rf \"$1\" && mkdir -p \"$1/bin\" \"$1/asl/host/out\" && cp \"$2/bin/asl\" \"$1/bin/asl\" && cp \"$2/asl/host/out/aslNativeBuild\" \"$1/asl/host/out/aslNativeBuild\" && cp -R \"$2/asl/host/out/aslNativeBuild-fresh\" \"$1/asl/host/out/aslNativeBuild-fresh\" && printf '#!/bin/sh\\ntouch \"$(dirname \"$0\")/built.marker\"\\n' > \"$1/asl/host/build.sh\" && chmod +x \"$1/bin/asl\" \"$1/asl/host/build.sh\" && sleep 1 && printf 'bin/asl\\n' > \"$1/asl/host/out/aslNativeBuild-fresh/deps\"" "x" root real) real (run/childEnv (list))) (run/limits 120 8)))]
    (= made.exit 0))

fn ! callIn! root: String cwd: String home: String extra: (List String) -> run/Done
  (run/runOneLimited (run/job (list (str root "/bin/asl") "run" "x") cwd (run/childEnv (cons (str "HOME=" home) extra))) (run/limits 60 16))

fn ! testDecision -> Bool
  (do (assert (nr/rebuildAllowed? "/home/u/wt/a" "/home/u" "/elsewhere" false) "a tree under HOME is the caller's own")
      (assert (nr/rebuildAllowed? "/home/u/wt/a" "/tmp/h" "/home/u/wt/a/sub" false) "cwd inside the tree is the caller's own")
      (assert (nr/rebuildAllowed? "/home/u/wt/a" "/tmp/h" "/elsewhere" true) "an explicit cache names its own pin store")
      (assert (not (nr/rebuildAllowed? "/home/u/wt/main" "/tmp/h" "/elsewhere" false)) "another HOME and a cwd outside the tree is refused")
      (assert (not (nr/rebuildAllowed? "/home/u/wt/ab" "/home/u/wt/a" "/elsewhere" false)) "a sibling that only shares a name prefix is not under the tree")
      (assert (not (nr/rebuildAllowed? "/home/u/wt/a" "" "/elsewhere" false)) "no HOME never counts as an owner")
      (assert (= (nr/refusalReceipt "/t/x" "/h") "(:err :code rebuildRefused :tree \"/t/x\" :home \"/h\")") "the receipt names tree and home")
      true)

fn ! testColdPath -> Bool
  (let [(base (str "/tmp/rebuildGuardTest_" (stringFromInt64 (monotonicNs))))
        (tree (str base "/tree"))
        (made (mk! tree))
        (outside (str base "/outside"))
        (home (str base "/home"))
        (dirs (and (ok? (dirCreate outside)) (ok? (dirCreate home))))
        (refused (callIn! tree outside home (list)))
        (refusedBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (inside (callIn! tree tree home (list)))
        (insideBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (_a (pathRemove (str tree "/asl/host/built.marker")))
        (explicit (callIn! tree outside home (list (str "ASL_NATIVE_CLI_CACHE=" base "/cache"))))
        (explicitBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (_b (pathRemove base))]
    (do (assert (and made dirs) "scratch tree staged")
        (assert (!= refused.exit 0) (str "another HOME with a cwd outside the tree exits nonzero: " refused.out))
        (assert (stringContains? refused.out ":code rebuildRefused") (str "the refusal is the rebuildRefused receipt: " refused.out))
        (assert (not refusedBuilt) "a refused call ran no build.sh")
        (assert insideBuilt (str "a call from inside the tree still rebuilds: " inside.out))
        (assert explicitBuilt (str "an explicit cache still rebuilds: " explicit.out))
        true))

fn ! runTests -> Bool
  (do (assert (testDecision) "rebuild decision")
      (assert (testColdPath) "cold path through bin/asl in a scratch tree")
      true)
