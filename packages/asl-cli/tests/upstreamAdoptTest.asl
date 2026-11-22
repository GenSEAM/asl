(module asl-cli/tests/upstreamAdoptTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeBuild :a nb) (asl/packages/asl-cli/tests/nativeColdFixture :a nf) (asl-tools/fleet/run :a run)])

; (:m :ref TRAIN-SUITES-COLD-CLI :do "a scratch native CLI cache that names a read-only upstream copies a complete entry of a taken kind instead of building it, and copies nothing for an incomplete entry, an untaken kind, an entry it already has or a cache with no upstream; the upstream tree is left byte and mtime equal")
fn ! sh! cwd: String cmd: String -> run/Done
  (run/runOneLimited (run/job (list "/bin/sh" "-c" cmd) cwd (run/childEnv (list))) (run/limits 30 8))

fn ! buildIn base: String cache: String upstream: String take: (List String) -> nb/Build
  (nb/Build :root base :cache cache :tmp (str cache "/tmp.test") :lib "" :base "" :clangVersion "" :owner ""
            :deadlineNs (+ (monotonicNs) 60000000000) :maxDesc 8 :upstream upstream :take take)

fn ! listing! base: String dir: String -> String
  (sh! base (str "cd '" dir "' && find . -print | LC_ALL=C sort && ls -lnRT . 2>/dev/null || ls -ln --full-time -R .")).out

fn ! runTests -> Bool
  (let [(made (sh! "/" "mktemp -d"))
        (base (stringTrim made.out))
        (up (str base "/up"))
        (cache (str base "/cache"))
        (seeded (sh! base (str "mkdir -p up/cli-k1/.src/a up/asl1-k2 up/seed-k3 up/rt-notrace-k4 cache/tmp.test"
                               " && printf bin1 > up/cli-k1/bin && chmod 755 up/cli-k1/bin && printf 'a/x.asl\\n' > up/cli-k1/deps"
                               " && printf src > up/cli-k1/.src/a/x.asl && ln -s .src up/cli-k1/src"
                               " && printf bin2 > up/asl1-k2/bin && printf bin3 > up/seed-k3/bin && printf lib > up/rt-notrace-k4/libaslrt-notrace.a"
                               " && mkdir -p up/cli-k5 up/outside && printf bin5 > up/cli-k5/bin && printf deps > up/outside/deps && ln -s ../outside/deps up/cli-k5/deps")))
        (before (listing! base up))
        (b (buildIn base cache up (list "cli" "asl1" "rt")))
        (cliTaken (nb/adopt! b (str cache "/cli-k1") (list "bin" "deps")))
        (cliBin (resultOr (fileReadString (str cache "/cli-k1/bin")) ""))
        (cliSrc (resultOr (fileReadString (str cache "/cli-k1/src/a/x.asl")) ""))
        (cliAgain (nb/adopt! b (str cache "/cli-k1") (list "bin" "deps")))
        (asl1Taken (nb/adopt! b (str cache "/asl1-k2") (list "bin" "deps")))
        (seedTaken (nb/adopt! b (str cache "/seed-k3") (list "bin")))
        (rtTaken (nb/adopt! b (str cache "/rt-notrace-k4") (list "libaslrt-notrace.a")))
        (lostTaken (nb/adopt! b (str cache "/cli-k5") (list "bin" "deps")))
        (absentTaken (nb/adopt! b (str cache "/cli-k9") (list "bin" "deps")))
        (bare (buildIn base (str base "/bare") "" (list "cli")))
        (_ (dirCreate (str base "/bare")))
        (bareTaken (nb/adopt! bare (str base "/bare/cli-k1") (list "bin" "deps")))
        (after (listing! base up))
        (left (resultOr (dirList (str cache "/tmp.test")) (list "?")))
        (row (nb/upstreamOf (nf/upstreamText "/s/nativeCli" (list "seed" "rt" "asl1"))))
        (junk (nb/upstreamOf "(:other :dir \"/s\")"))
        (cleaned (sh! "/" (str "rm -rf '" base "'")))]
    (do (assert (and (= made.exit 0) (stringStartsWith? base "/")) (str "a scratch dir was made: " made.out))
        (assert (= seeded.exit 0) (str "the upstream store was laid out: " seeded.out))
        (assert cliTaken "a complete cli entry of a taken kind is copied from upstream")
        (assert (= cliBin "bin1") (str "the copied entry holds the upstream binary: " cliBin))
        (assert (= cliSrc "src") (str "the copied entry's src link still reaches its snapshot: " cliSrc))
        (refute cliAgain "an entry the cache already has is not copied again")
        (refute asl1Taken "an upstream entry without its deps file is not copied")
        (refute (fileExists? (str cache "/asl1-k2")) "and nothing of it is left in the cache")
        (refute seedTaken "an entry of a kind the cache does not take is not copied")
        (assert rtTaken "a runtime entry is copied by its library file")
        (refute lostTaken "a copy that lacks a needed file upstream had (here a link out of the entry) is removed, not installed")
        (refute (fileExists? (str cache "/cli-k5")) "and no entry of it is installed")
        (refute absentTaken "an entry upstream lacks is not copied")
        (refute bareTaken "a cache with no upstream copies nothing")
        (assert (= before after) "upstream is only read: its tree, sizes and mtimes are unchanged")
        (assert (listEmpty? left) (str "no partial copy is left in the build tmp: " (stringJoin left " ")))
        (assert (= (pairFirst row) "/s/nativeCli") (str "upstream.asn names the store: " (pairFirst row)))
        (assert (= (pairSecond row) (list "seed" "rt" "asl1")) "upstream.asn names the kinds it takes")
        (assert (= (pairFirst junk) "") "a file of another shape names no upstream")
        (assert (= cleaned.exit 0) "the scratch dir was removed")
        true))
