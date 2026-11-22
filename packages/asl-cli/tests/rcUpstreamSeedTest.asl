(module asl-cli/tests/rcUpstreamSeedTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeBuild :a nb) (asl-tools/fleet/run :a run)])

; (:m :ref SUITE-BIMODAL-COLD :do "a linked worktree's empty .asl/cache/rcRuntime names the main checkout's rcRuntime as read-only upstream (kind rt) so variantRuntime! adopts the asan, notrace and counted runtimes instead of building them; the main checkout, a worktree whose main has no such cache, a cache of another name and a cache with an upstream.asn already are left alone")
fn ! sh! cwd: String cmd: String -> run/Done
  (run/runOneLimited (run/job (list "/bin/sh" "-c" cmd) cwd (run/childEnv (list))) (run/limits 30 8))

fn ! buildIn root: String cache: String -> nb/Build
  (nb/Build :root root :cache cache :tmp (str cache "/tmp.test") :lib "" :base "" :clangVersion "" :owner ""
            :deadlineNs (+ (monotonicNs) 60000000000) :maxDesc 8)

fn ! runTests -> Bool
  (let [(made (sh! "/" "mktemp -d"))
        (base (stringTrim made.out))
        (laid (sh! base (str "mkdir -p main/.git main/.asl/cache/rcRuntime w1 w2 w3 w4 w5 other/.git"
                             " && printf 'gitdir: ../main/.git/worktrees/w5\\n' > w5/.git"
                             " && printf 'gitdir: " base "/main/.git/worktrees/w1\\n' > w1/.git"
                             " && printf 'gitdir: " base "/main/.git/worktrees/w2\\n' > w2/.git"
                             " && printf 'gitdir: " base "/nomain/.git/worktrees/w3\\n' > w3/.git"
                             " && printf 'gitdir: " base "/main/.git/worktrees/w4\\n' > w4/.git"
                             " && mkdir -p w4/.asl/cache/rcRuntime && printf '(:upstream :dir \"/x\" :take (cli))\\n' > w4/.asl/cache/rcRuntime/upstream.asn")))
        (w1 (str base "/w1/.asl/cache/rcRuntime"))
        (seeded (nb/seedRcUpstream! (buildIn (str base "/w1") w1)))
        (row (nb/upstreamOf (resultOr (fileReadString (str w1 "/upstream.asn")) "")))
        (again (nb/seedRcUpstream! (buildIn (str base "/w1") w1)))
        (other (nb/seedRcUpstream! (buildIn (str base "/w2") (str base "/w2/.asl/cache/nativeTest"))))
        (noMain (nb/seedRcUpstream! (buildIn (str base "/w3") (str base "/w3/.asl/cache/rcRuntime"))))
        (mainItself (nb/seedRcUpstream! (buildIn (str base "/main") (str base "/main/.asl/cache/rcRuntime"))))
        (relative (nb/seedRcUpstream! (buildIn (str base "/w5") (str base "/w5/.asl/cache/rcRuntime"))))
        (noRelFile (fileExists? (str base "/w5/.asl/cache/rcRuntime/upstream.asn")))
        (kept (nb/seedRcUpstream! (buildIn (str base "/w4") (str base "/w4/.asl/cache/rcRuntime"))))
        (keptText (resultOr (fileReadString (str base "/w4/.asl/cache/rcRuntime/upstream.asn")) ""))
        (cleaned (sh! "/" (str "rm -rf '" base "'")))]
    (do (assert (and (= made.exit 0) (stringStartsWith? base "/")) (str "a scratch dir was made: " made.out))
        (assert (= laid.exit 0) (str "the trees were laid out: " laid.out))
        (assert (= (nb/mainRootOfGit "gitdir: /m/.git/worktrees/x\n") "/m") "the main checkout is read from a worktree's .git file")
        (assert (= (nb/mainRootOfGit "gitdir: /a/b/.git/worktrees/w/.git/worktrees/x\n") "") "an ambiguous path names no main")
        (assert (= (nb/mainRootOfGit "gitdir: ../main/.git/worktrees/x\n") "") "a relative gitdir (worktree.useRelativePaths) names no main")
        (assert (= (nb/mainRootOfGit "") "") "an empty .git file names no main")
        (assert (= (nb/mainRootOfGit "gitdir: /m/.git\n") "") "a gitdir that is not a worktree entry names no main")
        (assert (= (nb/mainRootOfGit "not a pointer") "") "text that is no gitdir line names no main")
        (assert seeded "a linked worktree's rcRuntime cache is seeded with the main checkout's as upstream")
        (assert (= (pairFirst row) (str base "/main/.asl/cache/rcRuntime")) (str "the upstream dir is the main checkout's rcRuntime: " (pairFirst row)))
        (assert (= (pairSecond row) (list "rt")) "and only the rt kind is taken")
        (refute again "a cache that already has an upstream.asn is not seeded again")
        (refute other "a cache that is not an rcRuntime is not seeded")
        (refute noMain "a worktree whose main has no rcRuntime cache is not seeded")
        (refute mainItself "the main checkout is not seeded from itself")
        (refute relative "a relative gitdir seeds nothing")
        (refute noRelFile "and writes no upstream.asn")
        (refute kept "an upstream.asn written by someone else is kept")
        (assert (stringContains? keptText ":take (cli)") (str "and left unchanged: " keptText))
        (assert (= cleaned.exit 0) "the scratch dir was removed")
        true))
