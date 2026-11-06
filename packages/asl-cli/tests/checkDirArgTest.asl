(module asl-cli/tests/checkDirArgTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a run) (asl-proc/gitFixture :a gf)])

; (:m :ref ASL-CHECK-DOT-DIR :do "asl check takes a directory like asl test does: the tracked .asl under it (dot is the root), and the verdict is the same in a scratch repo and in a linked worktree of it; before, a directory arg answered Is a directory and exit 1 in every tree")
fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/checkDirArgTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn goodSource -> String
  "(module checkDirFixture/good :x [runTests] :i [])\n\nfn runTests -> Bool\n  true\n"

fn badSource -> String
  "(module checkDirFixture/bad :x [runTests] :i [])\n\nfn runTests -> Bool\n  (true\n"

fn ! buildFixtureRepo! root: String -> Bool
  (and (ok? (gf/initContained! root))
    (and (ok? (gf/gitWrite! root (list "config" "user.name" "checkDirArgTest") (none)))
      (and (ok? (gf/gitWrite! root (list "config" "user.email" "checkDirArgTest@example.invalid") (none)))
        (and (ok? (dirCreate (str root "/sub")))
          (and (ok? (fileWrite (str root "/sub/good.asl") (goodSource)))
            (and (ok? (fileWrite (str root "/bad.asl") (badSource)))
              (and (ok? (gf/gitWrite! root (list "add" "-A") (none)))
                (ok? (gf/gitWrite! root (list "commit" "-q" "-m" "seed") (none))))))))))

fn envFor home: String -> (List String)
  (list "PATH=/usr/bin:/bin" (str "HOME=" home) "TMPDIR=/tmp" (str "ASL_ROOT=" home) (str "ASL_CLI_ROOT=" (resultOr (realPath ".") ".")))

fn ! checkIn binary: String dir: String arg: String -> run/Done
  (run/runOneLimited (run/job (list binary "check" arg) dir (envFor dir)) (run/limits 60 16))

fn ! verdictsIn binary: String dir: String label: String -> (Pair Int64 Int64)
  (let [(sub (checkIn binary dir "sub"))
        (dot (checkIn binary dir "."))]
    (do
      (assert (= sub.verdict "exit") (str label ": check sub ended on its own: " sub.out))
      (assert (= sub.exit 0) (str label ": check sub passes, the one good file under it: " sub.out))
      (assert (not (stringContains? sub.out "Is a directory")) (str label ": a directory is not read as a file: " sub.out))
      (assert (= dot.verdict "exit") (str label ": check . ended on its own: " dot.out))
      (assert (= dot.exit 1) (str label ": check . fails on the bad tracked file at the root: " dot.out))
      (assert (not (stringContains? dot.out "Is a directory")) (str label ": dot is the root, not a file: " dot.out))
      (assert (stringContains? dot.out "bad.asl") (str label ": check . reached the bad file: " dot.out))
      (pair sub.exit dot.exit)))

fn ! runTests -> Bool
  (let [(base (scratchBase!))
        (fx (str base "/fx"))
        (wt (str base "/wt"))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))
        (madeBase (dirCreate base))
        (ready (buildFixtureRepo! fx))
        (linked (gf/gitWrite! fx (list "worktree" "add" "-q" "--detach" wt) (none)))]
    (do
      (assert (some? built.binary) (str "asl/packages/asl-cli/src/native.asl builds natively: " built.reason))
      (assert (ok? madeBase) "scratch base directory is created")
      (assert ready "the fixture repo is built")
      (assert (ok? linked) "a linked worktree of the fixture exists")
      (let [(binary (optionOr built.binary ""))
            (inRepo (verdictsIn binary fx "scratch repo"))
            (inWt (verdictsIn binary wt "linked worktree"))
            (removed (pathRemove base))]
        (do
          (assert (= inRepo inWt) "the verdicts of the scratch repo and its linked worktree are the same")
          (assert (ok? removed) "scratch fixture tree removed")
          true))))
