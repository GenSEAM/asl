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

; (:m :ref WT-MAIN-HOME-REBUILD :do "the two other doors to a rebuild: a tree with no builder at all (bin/asl's sh decision, same three ways as guard!) and a stale head with a fresh builder (refresh! asks guard! before it takes the lock); each refusal is the rebuildRefused receipt with nothing started, and the stale setup is proved to reach refresh! by the in-tree call printing its verifying line")
fn ! sh! script: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons "/bin/sh" (cons "-c" (cons script (cons "x" args)))) "/" (run/childEnv (list))) (run/limits 120 8))

fn ! mkBare! root: String -> Bool
  (let [(real (resultOr (realPath ".") "."))
        (made (sh! "rm -rf \"$1\" && mkdir -p \"$1/bin\" \"$1/asl/host\" && cp \"$2/bin/asl\" \"$1/bin/asl\" && printf '#!/bin/sh\\ntouch \"$(dirname \"$0\")/built.marker\"\\n' > \"$1/asl/host/build.sh\" && chmod +x \"$1/bin/asl\" \"$1/asl/host/build.sh\"" (list root real)))]
    (= made.exit 0))

fn ! staleHead! home: String tree: String -> Bool
  (let [(made (sh! "mkdir -p \"$1/.asl/run/nativeCli\" \"$1/stale\" && printf '#!/bin/sh\\nexit 0\\n' > \"$1/stale/bin\" && chmod +x \"$1/stale/bin\" && printf 'bin/asl\\n' > \"$1/stale/deps\" && printf '%s\\n' \"$1/stale\" > \"$1/.asl/run/nativeCli/head$(printf %s \"$2\" | sed 's|/|_|g')\" && sleep 1 && touch \"$2/bin/asl\" && sleep 1 && touch \"$2/asl/host/out/aslNativeBuild-fresh/deps\"" (list home tree)))]
    (= made.exit 0))

fn ! tmpBase! tag: String -> String
  (str (resultOr (realPath "/tmp") "/tmp") "/rebuildGuardTest_" tag "_" (stringFromInt64 (monotonicNs)))

fn ! testNoBuilderColdPath -> Bool
  (let [(base (tmpBase! "bare"))
        (tree (str base "/tree"))
        (made (mkBare! tree))
        (outside (str base "/outside"))
        (home (str base "/home"))
        (dirs (and (ok? (dirCreate outside)) (ok? (dirCreate home))))
        (refused (callIn! tree outside home (list)))
        (refusedBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (inside (callIn! tree tree home (list)))
        (insideBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (_a (pathRemove (str tree "/asl/host/built.marker")))
        (underHome (callIn! tree outside base (list)))
        (underHomeBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (_b (pathRemove (str tree "/asl/host/built.marker")))
        (explicit (callIn! tree outside home (list (str "ASL_NATIVE_CLI_CACHE=" base "/cache"))))
        (explicitBuilt (fileExists? (str tree "/asl/host/built.marker")))
        (_c (pathRemove base))]
    (do (assert (and made dirs) "bare scratch tree staged")
        (assert (= refused.exit 2) (str "no builder, another HOME, cwd outside: exit 2: " refused.out))
        (assert (stringContains? refused.out ":code rebuildRefused") (str "the sh decision prints the receipt: " refused.out))
        (assert (not refusedBuilt) "the refused call ran no build.sh")
        (assert insideBuilt (str "no builder, cwd inside the tree: build.sh runs: " inside.out))
        (assert underHomeBuilt (str "no builder, tree under HOME: build.sh runs: " underHome.out))
        (assert explicitBuilt (str "no builder, explicit cache: build.sh runs: " explicit.out))
        true))

fn ! testRefreshAsksGuard -> Bool
  (let [(base (tmpBase! "refresh"))
        (tree (str base "/tree"))
        (made (mk! tree))
        (outside (str base "/outside"))
        (home (str base "/home"))
        (dirs (and (ok? (dirCreate outside)) (ok? (dirCreate home))))
        (stale (staleHead! home tree))
        (inside (callIn! tree tree home (list "ASL_NATIVE_BUILD_WAIT=1")))
        (_a (pathRemove (str home "/.asl/run/nativeCli/lock")))
        (refused (callIn! tree outside home (list "ASL_NATIVE_BUILD_WAIT=1")))
        (lockMade (fileExists? (str home "/.asl/run/nativeCli/lock")))
        (_b (pathRemove base))]
    (do (assert (and made (and dirs stale)) "scratch tree with a stale head staged")
        (assert (stringContains? inside.out "verifying or rebuilding") (str "the stale setup reaches refresh! from inside the tree: " inside.out))
        (assert (= refused.exit 2) (str "refresh! on a refused tree exits 2: " refused.out))
        (assert (stringContains? refused.out ":code rebuildRefused") (str "refresh! prints the receipt: " refused.out))
        (assert (not (stringContains? refused.out "verifying or rebuilding")) "refresh! did not start its verify or rebuild")
        (assert (not lockMade) "refresh! took no build lock")
        true))

fn ! testReceiptEscapes -> Bool
  (do (assert (= (nr/refusalReceipt "/t/a\"b" "/h\\c") "(:err :code rebuildRefused :tree \"/t/a\\\"b\" :home \"/h\\\\c\")") "quotes and backslashes in tree and home are escaped")
      true)

fn ! runTests -> Bool
  (do (assert (testDecision) "rebuild decision")
      (assert (testColdPath) "cold path through bin/asl in a scratch tree")
      (assert (testReceiptEscapes) "receipt escapes")
      (assert (testNoBuilderColdPath) "no-builder cold path: the sh decision")
      (assert (testRefreshAsksGuard) "refresh! asks guard! before the lock")
      true)
