(module asl-cli/tests/cacheFallbackTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/nativeCli :a nc)
      (asl/packages/asl-cli/src/cacheFallback :a cf)
      (asl-tools/fleet/run :a run)])

(schema Ran (:f exit Int64) (:f out String))

fn fixtureSource -> String
  (stringJoin (list
    "(module cacheFixtureTest :x [runTests] :i [])"
    ""
    "fn ! runTests -> Bool"
    "  (let [(n (stringLength \"abcd\"))]"
    "    (do (assert (= n 4) \"length computed\")"
    "        (assert (> n 1) \"length above one\")"
    "        true))"
    "") "\n")

fn ! runCli! cli: String root: String cwd: String tmp: String file: String extra: (List String) -> Ran
  (let [(d (run/runOneLimited
             (run/job (list cli "test" file) cwd
               (run/childEnv (listAppend extra (list (str "ASL_CLI_ROOT=" root) (str "ASL_CLI_SCRIPT_DIR=" root "/bin") (str "ASL_CLI_ARGV0=" root "/bin/asl") (str "TMPDIR=" tmp) (str "ASL_NATIVE_CLI_DIR=" (sys/parentOf cli))))))
             (run/limits 900 32)))]
    (Ran :exit d.exit :out d.out))

fn ! countIn dir: String -> Int64
  (listLength (resultOr (dirList dir) (list)))

fn ! anyUnder? dir: String suffix: String -> Bool
  (listAny? (fn [(n String)] -> Bool (sys/isDir? (str dir "/" n suffix))) (resultOr (dirList dir) (list)))

fn ! shell! cmd: String -> Bool
  (= (run/runOneLimited (run/job (list "/bin/sh" "-c" cmd) "/" (run/childEnv (list))) (run/limits 120 8)).exit 0)

fn ! runTests -> Bool
  (let [(real (resultOr (realPath ".") "."))
        (t (str "/tmp/cacheFallbackTest." (stringFromInt64 (procSelf))))
        (fake (str t "/root"))
        (proj (str t "/proj"))
        (plain (str t "/plain"))
        (tmp (str t "/tmp"))
        (cli (stringTrim (resultOr (fileReadString (nc/headPath (nc/cacheDir!) real)) "")))
        (_ (dirCreate (str proj "/.git")))
        (_ (dirCreate plain))
        (_ (dirCreate tmp))
        (_ (fileWrite (str proj "/fixTest.asl") (fixtureSource)))
        (_ (fileWrite (str plain "/fixTest.asl") (fixtureSource)))
        (made (cf/overlayFor! real fake))
        (_ (shell! (str "chmod a-w '" fake "/.asl/cache'")))
        (rootWritable (cf/writable? (str fake "/.asl/cache")))
        (guarded (runCli! (str cli "/bin") fake plain tmp (str plain "/fixTest.asl") (list "ASL_CLI_OVERLAY=/nonexistent")))
        (afterGuard (countIn tmp))
        (home (str t "/home"))
        (tmp2 (str t "/tmp2"))
        (_ (dirCreate (str home "/.asl/run/nativeCli")))
        (_ (dirCreate tmp2))
        (_ (shell! (str "chmod -R a-w '" home "'")))
        (roHome (runCli! (str cli "/bin") real plain tmp2 (str plain "/fixTest.asl") (list (str "HOME=" home))))
        (homeNoise (anyUnder? tmp2 "/clang"))
        (homeEntries (countIn (str home "/.asl/run/nativeCli")))
        (inProject (runCli! (str cli "/bin") fake proj tmp (str proj "/fixTest.asl") (list)))
        (projectEntries (countIn proj))
        (afterProject (countIn (str fake "/.asl/cache")))
        (outside (runCli! (str cli "/bin") fake plain tmp (str plain "/fixTest.asl") (list)))
        (afterOutside (countIn (str fake "/.asl/cache")))
        (tmpEntries (countIn tmp))
        (tmpWritable (cf/writable? tmp))
        (cleaned (shell! (str "chmod -R u+w '" t "' && rm -rf '" t "'")))]
    (do (assert cleaned "the scratch tree is removed with its permissions restored")
        (assert made "a stand-in toolchain root of symlinks with a real cache directory is built")
        (assert (not rootWritable) "writable? is false for the read-only cache directory")
        (assert tmpWritable "writable? is true for a writable directory")
        (assert (= inProject.exit 0) (str "under a read-only toolchain cache a test inside a git project passes: " inProject.out))
        (assert (stringContains? inProject.out "2 assertion(s) executed (2 passed)") (str "its two assertions execute: " inProject.out))
        (assert (= afterProject 0) "nothing is written under the toolchain root cache")
        (assert (= roHome.exit 0) (str "a read-only HOME does not stop a test: " roHome.out))
        (assert (not (stringContains? roHome.out "cannot record")) "and prints no clang-facts error")
        (assert homeNoise "the clang facts are kept under $TMPDIR/asl-cache-home-<id>/clang")
        (assert (= homeEntries 0) "nothing is written under the read-only HOME")
        (assert (= projectEntries 2) "the project tree is untouched: only .git and the fixture are in it")
        (assert (!= guarded.exit 0) (str "with ASL_CLI_OVERLAY set and the cache still unwritable the CLI does not exec again: " guarded.out))
        (assert (stringContains? guarded.out "permissionDenied") (str "it ends with the original error: " guarded.out))
        (assert (= afterGuard 0) "the guarded run builds no overlay")
        (assert (= outside.exit 0) (str "outside any git project the test passes too: " outside.out))
        (assert (stringContains? outside.out "2 assertion(s) executed (2 passed)") (str "its two assertions execute: " outside.out))
        (assert (= afterOutside 0) "still nothing under the toolchain root cache")
        (assert (> tmpEntries 0) "the cache lands under $TMPDIR/asl-cache-<uid>")
        true))
