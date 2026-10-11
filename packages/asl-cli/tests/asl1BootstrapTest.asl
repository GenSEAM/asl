(module asl-cli/tests/asl1BootstrapTest
  :x [runTests main]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

fn ! tempRoot -> String
  (str "/tmp/asl1BootstrapTest_" (stringFromInt64 (monotonicNs)))

fn ! main -> (Result Int64 String)
  (mt (envGet "ASL1_BOOT_ROOT")
    ((none) (err "missing ASL1_BOOT_ROOT"))
    ((some root)
      (mt (envGet "ASL1_FAKE_HOST")
        ((none) (err "missing ASL1_FAKE_HOST"))
        ((some fakeHost)
          (mt (envGet "ASL1_FAKE_CLANG")
            ((none) (err "missing ASL1_FAKE_CLANG"))
            ((some clang)
              (mt (sys/context!)
                ((err e) (err e))
                ((ok original)
                  (let [(ctx (sys/Context :root (optionOr (envGet "ASL1_CTX_ROOT") original.root)
                              :scriptDir original.scriptDir
                              :argv0 original.argv0
                              :hostBin fakeHost))
                        (compiler (str root "/asl/packages/asl-compiler/src/asl1.asl"))
                        (lib (str root "/asl/packages/asl-compiler/src/asl1.asl"))]
                    (mt (envGet "ASL1_EXPECT")
                      ((none) (err "missing ASL1_EXPECT"))
                      ((some expected)
                        (mt (cache/nativeAsl1! ctx lib clang)
                          ((err e) (if (or (or (and (= expected "missing") (= e "ERR_NO_NATIVE_SEED"))
                                               (and (= expected "stageFailed") (= e "native asl1 stage failed (exit 7)")))
                                           (or (or (and (= expected "retried") (stringContains? e "native asl1 stage failed (exit 7); retried from the seed: native asl1 stage failed (exit 7)"))
                                                   (and (= expected "stale") (stringStartsWith? e "ERR_SEED_STALE: ")))
                                               (and (= expected "seedSha") (stringStartsWith? e "ERR_SEED_SHA: "))))
                            (do (sys/say! e) (ok 0))
                            (err e)))
                          ((ok binary) (if (= expected "staged")
                            (do (sys/say! "BUILT") (ok 0))
                            (err (str "cold bootstrap succeeded without a pinned seed: " binary))))))))))))))))

fn ! stageCountAbsent? path: String -> Bool
  (not (fileExists? path))

fn ! cleanup path: String passed: Bool -> Bool
  (do (pathRemove path) passed)

fn ! emptyDirectory? path: String -> Bool
  (mt (sys/capture! (list "ls" "-A" path) (none))
    ((err _) false)
    ((ok captured) (and (= captured.exitCode 0) (stringEmpty? (sys/stripTrailingNewlines captured.stdout)))))

fn ! onlyEmptyCacheEntry? path: String -> Bool
  (mt (sys/capture! (list "ls" "-A" path) (none))
    ((err _) false)
    ((ok listing)
      (let [(entries (stringLines (sys/stripTrailingNewlines listing.stdout)))]
        (and (= listing.exitCode 0)
          (and (= (listLength entries) 1)
            (mt (listHead entries)
              ((none) false)
              ((some entry)
                (mt (sys/capture! (list "ls" "-A" (str path "/" entry)) (none))
                  ((err _) false)
                  ((ok files) (and (= files.exitCode 0)
                    (= (sys/stripTrailingNewlines files.stdout) "build.lock.takeover")))))))))))

fn ! hasInstalledNative? path: String -> Bool
  (mt (sys/capture! (list "ls" "-A" path) (none))
    ((err _) false)
    ((ok listing)
      (mt (listHead (stringLines (sys/stripTrailingNewlines listing.stdout)))
        ((none) false)
        ((some entry)
          (and (fileExists? (str path "/" entry "/asl1-native"))
            (and (fileExists? (str path "/" entry "/sha256"))
              (sys/executable? (str path "/" entry "/asl1-native"))))))))

fn ! testColdBootstrapRequiresSeedBeforeStages -> Bool
  (let [(root (tempRoot))
        (fixture (str root "/fixture"))
        (cacheRoot (str root "/cache"))
        (failedCacheRoot (str root "/failed-cache"))
        (relativeCacheRoot (str root "/relative-cache"))
        (seed (str root "/missing-seed/asl1-native"))
        (seedFixture (str fixture "/seed-compiler"))
        (seedScript (str "#!/bin/sh\n"
          "printf 'seed\\n' >> \"$ASL1_STAGE_LOG\"\n"
          "while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; printf 'seed llvm\\n' > \"$1\"; fi; shift; done\n"
          "exit 0\n"))
        (nativeScript (str "#!/bin/sh\n"
          "printf 'native\\n' >> \"$ASL1_STAGE_LOG\"\n"
          "while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; printf 'native llvm\\n' > \"$1\"; fi; shift; done\n"
          "exit 0\n"))
        (failingNativeScript (str "#!/bin/sh\n"
          "printf 'native-failed\\n' >> \"$ASL1_STAGE_LOG\"\n"
          "exit 7\n"))
        (fakeHost (str fixture "/host"))
        (fakeClang (str fixture "/clang"))
        (stageLog (str fixture "/stages"))
        (hostLog (str fixture "/host-calls"))
        (clangLog (str fixture "/clang-calls"))
        (source (str (resultOr (sys/context!) (sys/Context :root "." :scriptDir "." :argv0 "asl" :hostBin "asl-host")).root "/asl/packages/asl-compiler/src/asl1.asl"))
        (alternateSource (str fixture "/alternate-asl1.asl"))
        (made (and (ok? (dirCreate root)) (and (ok? (dirCreate fixture)) (ok? (dirCreate cacheRoot)))))
        (failedCacheMade (dirCreate failedCacheRoot))
        (relativeCacheMade (dirCreate relativeCacheRoot))
        (hostWritten (fileWrite fakeHost (str "#!/bin/sh\n"
          "printf '%s\\n' \"$*\" >> \"$ASL1_HOST_LOG\"\n"
          "if [ \"$1\" = run ] && [ \"$3\" = deps ]; then printf '%s\\n' \"$ASL1_FAKE_SOURCE\"; exit 0; fi\n"
          "if [ \"$1\" = run ] && [ \"$3\" = build ]; then printf 'build\\n' >> \"$ASL1_STAGE_LOG\"; while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; printf 'fake llvm\\n' > \"$1\"; fi; shift; done; exit 0; fi\n"
          "exit 9\n")))
        (clangWritten (fileWrite fakeClang (str "#!/bin/sh\n"
          "printf '%s\\n' \"$*\" >> \"$ASL1_CLANG_LOG\"\n"
          "if [ \"$1\" = --version ]; then echo fixture-clang; exit 0; fi\n"
          "out=''\n"
          "while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; out=\"$1\"; fi; shift; done\n"
          "cp \"$ASL1_NATIVE_SCRIPT\" \"$out\"\n"
          "chmod +x \"$out\"\n"
          "exit 0\n")))
        (seedWritten (fileWrite seedFixture seedScript))
        (seedMode (mt seedWritten ((err e) (err e)) ((ok _) (fileChmod seedFixture 493))))
        (nativeWritten (fileWrite (str fixture "/native-compiler") nativeScript))
        (failingNativeWritten (fileWrite (str fixture "/failing-native-compiler") failingNativeScript))
        (alternateSourceWritten (fileWrite alternateSource "(module fixture/alternateAsl1)\n"))
        (nativeMode (mt nativeWritten ((err e) (err e)) ((ok _) (fileChmod (str fixture "/native-compiler") 493))))
        (failingNativeMode (mt failingNativeWritten ((err e) (err e)) ((ok _) (fileChmod (str fixture "/failing-native-compiler") 493))))
        (seedBytes (fileReadBytes seedFixture))
        (seedDigest (mt seedBytes ((err e) (err e)) ((ok bytes) (fileWrite (str seedFixture ".sha256") (str (bytesSha256 bytes) "\n")))))
        (hostMode (mt hostWritten ((err e) (err e)) ((ok _) (fileChmod fakeHost 493))))
        (clangMode (mt clangWritten ((err e) (err e)) ((ok _) (fileChmod fakeClang 493))))
        (ctxR (sys/context!))]
    (mt ctxR
      ((err e) (do (pathRemove root) (assert false (str "context unavailable: " e))))
      ((ok ctx)
        (let [(_ (assert (fileExists? root) "temporary bootstrap root is created"))
              (_ (assert (fileExists? fixture) "fixture directory is created"))
              (_ (assert (fileExists? cacheRoot) "isolated cache directory is created"))
              (_ (assert (and (ok? failedCacheMade) (fileExists? failedCacheRoot)) "isolated failed-stage cache directory is created"))
              (_ (assert (emptyDirectory? cacheRoot) "isolated cache starts empty"))
              (_ (assert (ok? hostWritten) "fake host script is written"))
              (_ (assert (ok? clangWritten) "fake clang script is written"))
              (_ (assert (and (ok? hostMode) (fileExists? fakeHost)) "fake host fixture is executable"))
              (_ (assert (and (ok? clangMode) (fileExists? fakeClang)) "fake clang fixture is executable"))
              (_ (assert (fileExists? source) "actual ASL1 source is present for dependency hashing"))
              (_ (assert (not (fileExists? seed)) "native seed is absent before the cold request"))
              (_ (assert (and (ok? seedMode) (ok? seedDigest)) "executable native seed fixture has a matching SHA-256"))
              (_ (assert (and (ok? nativeMode) (fileExists? (str fixture "/native-compiler"))) "native-stage compiler fixture is executable"))
              (_ (assert (and (ok? failingNativeMode) (fileExists? (str fixture "/failing-native-compiler"))) "failing native-stage compiler fixture is executable"))
              (_ (assert (and (ok? alternateSourceWritten) (fileExists? alternateSource)) "alternate source fixture exists for a distinct cold cache key"))
              (_ (assert (fileExists? (str seedFixture ".sha256")) "seed digest file is available to native cache validation"))
              (host ctx.hostBin)
              (testPath (str ctx.root "/asl/packages/asl-cli/tests/asl1BootstrapTest.asl"))
              (child (sys/captureWith! (list host "run" testPath "main") (none)
                  (list (str "ASL1_BOOT_ROOT=" ctx.root)
                    (str "ASL1_FAKE_HOST=" fakeHost)
                    (str "ASL1_FAKE_CLANG=" fakeClang)
                    (str "ASL1_FAKE_SOURCE=" source)
                    (str "ASL1_NATIVE_SCRIPT=" (str fixture "/native-compiler"))
                    (str "ASL1_STAGE_LOG=" stageLog)
                    (str "ASL1_HOST_LOG=" hostLog)
                    (str "ASL1_CLANG_LOG=" clangLog)
                    (str "ASL_NATIVE_ASL1_CACHE=" cacheRoot)
                    (str "ASL_NATIVE_ASL1_SEED=" seed)
                    (str "ASL_NATIVE_ASL1_SOURCE=" source)
                    "ASL1_EXPECT=missing")))]
          (let [(childResult (mt child ((err _) (none)) ((ok captured) (some captured))))
                (_ (assert (some? childResult) "isolated nativeAsl1! process starts"))
                (_ (assert (mt childResult ((none) false) ((some captured) (= captured.exitCode 0))) "cold request returns the expected typed missing-seed result"))
                (_ (assert (mt childResult ((none) false) ((some captured) (= captured.stdout "ERR_NO_NATIVE_SEED\n"))) "child reports the exact missing-seed error"))
                (_ (assert (mt childResult ((none) false) ((some captured) (stringEmpty? captured.stderr))) "expected missing-seed path emits no diagnostic error"))
                (_ (assert (not (fileExists? seed)) "failed cold selection does not create a seed"))
                (_ (assert (stageCountAbsent? stageLog) "a missing seed never invokes a compiler stage"))
                (_ (assert (stringContains? (resultOr (fileReadString hostLog) "") " deps ") "cold request reads the source dependency closure"))
                (_ (assert (not (stringContains? (resultOr (fileReadString hostLog) "") " build ")) "cold request does not compile with the host compiler"))
                (_ (assert (fileExists? clangLog) "native toolchain version is checked before seed selection"))
                (_ (assert (= (sys/stripTrailingNewlines (resultOr (fileReadString clangLog) "")) "--version") "fake native toolchain receives only its version query"))
                (_ (assert (onlyEmptyCacheEntry? cacheRoot) "missing seed leaves only the synchronization guard, no binary or cache metadata"))
                (_ (assert (not (fileExists? (str seed ".sha256"))) "missing seed does not create a seed digest"))
                (seededChild (sys/captureWith! (list host "run" testPath "main") (none)
                  (list (str "ASL1_BOOT_ROOT=" ctx.root)
                    (str "ASL1_FAKE_HOST=" fakeHost)
                    (str "ASL1_FAKE_CLANG=" fakeClang)
                    (str "ASL1_FAKE_SOURCE=" source)
                    (str "ASL1_NATIVE_SCRIPT=" (str fixture "/native-compiler"))
                    (str "ASL1_STAGE_LOG=" stageLog)
                    (str "ASL1_HOST_LOG=" hostLog)
                    (str "ASL1_CLANG_LOG=" clangLog)
                    (str "ASL_NATIVE_ASL1_CACHE=" cacheRoot)
                    (str "ASL_NATIVE_ASL1_SEED=" seedFixture)
                    (str "ASL_NATIVE_ASL1_SOURCE=" source)
                    "ASL1_EXPECT=staged")))]
            (let [(seedResult (mt seededChild ((err _) (none)) ((ok captured) (some captured))))
                  (_ (assert (some? seedResult) "seeded nativeAsl1! process starts"))
                  (_ (assert (mt seedResult ((none) false) ((some captured) (= captured.exitCode 0))) "seeded nativeAsl1! produces an installed compiler"))
                  (_ (assert (mt seedResult ((none) false) ((some captured) (stringContains? captured.stdout "BUILT"))) "seeded bootstrap reports its installed result"))
                  (_ (assert (mt seedResult ((none) false) ((some captured) (not (stringContains? captured.stderr "ERR_MAIN_FAILED")))) "seeded bootstrap has no main failure diagnostic"))
                  (_ (assert (= (resultOr (fileReadString stageLog) "") "seed\nnative\n") "both native stages run in order, seed then stage one"))
                  (_ (assert (not (stringContains? (resultOr (fileReadString hostLog) "") " build ")) "seeded bootstrap does not interpret the compiler build"))
                  (_ (assert (stringStartsWith? (resultOr (fileReadString clangLog) "") "--version\n--version\n") "both native requests query toolchain version before linking"))
                  (_ (assert (hasInstalledNative? cacheRoot) "second-stage compiler is installed with digest and executable bit"))
                  (clearedStages (pathRemove stageLog))
                  (priorChild (sys/captureWith! (list host "run" testPath "main") (none)
                    (list (str "ASL1_BOOT_ROOT=" ctx.root)
                      (str "ASL1_FAKE_HOST=" fakeHost)
                      (str "ASL1_FAKE_CLANG=" fakeClang)
                      (str "ASL1_FAKE_SOURCE=" alternateSource)
                      (str "ASL1_NATIVE_SCRIPT=" (str fixture "/native-compiler"))
                      (str "ASL1_STAGE_LOG=" stageLog)
                      (str "ASL1_HOST_LOG=" hostLog)
                      (str "ASL1_CLANG_LOG=" clangLog)
                      (str "ASL_NATIVE_ASL1_CACHE=" cacheRoot)
                      (str "ASL_NATIVE_ASL1_SEED=" seed)
                      (str "ASL_NATIVE_ASL1_SOURCE=" alternateSource)
                      "ASL1_EXPECT=staged")))
                  (priorResult (mt priorChild ((err _) (none)) ((ok captured) (some captured))))
                  (_ (assert (ok? clearedStages) "prior-cache stage log starts empty"))
                  (_ (assert (some? priorResult) "cold request with a prior cache entry starts"))
                  (_ (assert (mt priorResult ((none) false) ((some captured) (= captured.exitCode 0))) "prior cached native binary bootstraps a distinct cold key"))
                  (_ (assert (mt priorResult ((none) false) ((some captured) (stringContains? captured.stdout "BUILT"))) "prior-cache bootstrap returns its installed compiler"))
                  (_ (assert (= (resultOr (fileReadString stageLog) "") "native\nnative\nnative\n") "a deps probe on the cached compiler precedes both build stages, without falling back to the seed"))
                  (_ (assert (not (fileExists? seed)) "a cached compiler is never promoted to the bootstrap seed"))
                  (_ (assert (not (fileExists? (str seed ".sha256"))) "no seed digest is written for a cached compiler"))
                  (_ (assert (hasInstalledNative? cacheRoot) "prior-cache bootstrap installs the second-stage binary"))
                  (clearedFailureStages (pathRemove stageLog))
                  (failedChild (sys/captureWith! (list host "run" testPath "main") (none)
                    (list (str "ASL1_BOOT_ROOT=" ctx.root)
                      (str "ASL1_FAKE_HOST=" fakeHost)
                      (str "ASL1_FAKE_CLANG=" fakeClang)
                      (str "ASL1_FAKE_SOURCE=" source)
                      (str "ASL1_NATIVE_SCRIPT=" (str fixture "/failing-native-compiler"))
                      (str "ASL1_STAGE_LOG=" stageLog)
                      (str "ASL1_HOST_LOG=" hostLog)
                      (str "ASL1_CLANG_LOG=" clangLog)
                      (str "ASL_NATIVE_ASL1_CACHE=" failedCacheRoot)
                      (str "ASL_NATIVE_ASL1_SEED=" seedFixture)
                      (str "ASL_NATIVE_ASL1_SOURCE=" source)
                      "ASL1_EXPECT=stageFailed")))
                  (failedResult (mt failedChild ((err _) (none)) ((ok captured) (some captured))))
                  (_ (assert (ok? clearedFailureStages) "failing-stage log starts empty"))
                  (_ (assert (some? failedResult) "failing native stage process starts"))
                  (_ (assert (mt failedResult ((none) false) ((some captured) (= captured.exitCode 0))) "native-stage failure is returned through the production entry point"))
                  (_ (assert (mt failedResult ((none) false) ((some captured) (stringContains? captured.stdout "native asl1 stage failed (exit 7)"))) "native-stage failure reports its exact process error"))
                  (_ (assert (= (resultOr (fileReadString stageLog) "") "seed\nnative-failed\n") "failing stage follows the successful seed stage and stops before stage two"))
                  (_ (assert (not (hasInstalledNative? failedCacheRoot)) "failed native stage installs no cache binary"))
                  (relativeChild (sys/captureWith! (list host "run" testPath "main") (some fixture)
                    (list (str "ASL1_BOOT_ROOT=" ctx.root)
                      (str "ASL1_CTX_ROOT=" ctx.root)
                      (str "ASL1_FAKE_HOST=" fakeHost)
                      (str "ASL1_FAKE_CLANG=" fakeClang)
                      "ASL1_FAKE_SOURCE=asl/packages/asl-compiler/src/asl1.asl"
                      (str "ASL1_NATIVE_SCRIPT=" (str fixture "/native-compiler"))
                      (str "ASL1_STAGE_LOG=" stageLog)
                      (str "ASL1_HOST_LOG=" hostLog)
                      (str "ASL1_CLANG_LOG=" clangLog)
                      (str "ASL_NATIVE_ASL1_CACHE=" relativeCacheRoot)
                      (str "ASL_NATIVE_ASL1_SEED=" seedFixture)
                      (str "ASL_NATIVE_ASL1_SOURCE=" source)
                      "ASL1_EXPECT=staged")))
                  (relativeResult (mt relativeChild ((err _) (none)) ((ok captured) (some captured))))
                  (_ (assert (ok? relativeCacheMade) "root-relative deps case has its own cache directory"))
                  (_ (assert (mt relativeResult ((none) false) ((some captured) (and (= captured.exitCode 0) (stringContains? captured.stdout "BUILT")))) (str "root-relative deps lines (asl1 deps since ASL1SELF) hash under the workspace root even when the caller runs elsewhere: " (mt relativeResult ((none) "no child") ((some captured) (str captured.stdout captured.stderr))))))
                  (_ (assert (hasInstalledNative? relativeCacheRoot) "root-relative deps key installs its compiler"))
                  (passed true)]
              (cleanup root passed)))))))

fn stageScript label: String code: Int64 -> String
  (str "#!/bin/sh\n"
       "printf '" label "\\n' >> \"$ASL1_STAGE_LOG\"\n"
       "while [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; printf 'llvm\\n' > \"$1\"; fi; shift; done\n"
       "exit " (stringFromInt64 code) "\n")

fn ! executable! path: String text: String -> Bool
  (and (ok? (fileWrite path text)) (ok? (fileChmod path 493)))

fn ! pinned! path: String text: String -> Bool
  (and (executable! path text)
       (mt (fileReadBytes path) ((err _) false) ((ok b) (ok? (fileWrite (str path ".sha256") (str (bytesSha256 b) "\n"))))))

fn ! seedRepo! dir: String shaOk: Bool -> Bool
  (let [(ir (str dir "/asl/seed/fixture-arch-os/asl1.ll"))
        (_ (dirCreate (sys/parentOf ir)))
        (irText "fixture ir\n")
        (written (fileWrite ir irText))
        (zipped (sys/capture! (list "gzip" "-n" "-f" ir) (none)))
        (gz (fileReadBytes (str ir ".gz")))]
    (mt gz
      ((err _) false)
      ((ok b) (let [(sha (bytesSha256 b))
                    (recorded (if shaOk sha (str (if (stringStartsWith? sha "0") "1" "0") (optionOr (stringSlice sha 1 64) ""))))]
                (and (ok? written)
                     (and (mt zipped ((ok c) (= c.exitCode 0)) ((err _) false))
                          (ok? (fileWrite (str dir "/asl/seed/seed.asn")
                                 (str "(:seeds :v 1\n  (:seed :triple \"fixture-arch-os\" :file \"asl/seed/fixture-arch-os/asl1.ll.gz\" :bytes " (stringFromInt64 (bytesLength b))
                                      " :sha256 \"" recorded "\" :llBytes " (stringFromInt64 (stringLength irText)) " :llSha256 \"" (bytesSha256 (stringToBytes irText)) "\"))\n")))))))))

fn ! seedChild! ctx: sys/Context f: String cache: String seed: (Option String) source: String script: String expect: String ctxRoot: String -> (Option sys/Captured)
  (mt (sys/captureWith! (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/tests/asl1BootstrapTest.asl") "main") (none)
        (listAppend (list (str "ASL1_BOOT_ROOT=" ctx.root) (str "ASL1_CTX_ROOT=" ctxRoot)
                          (str "ASL1_FAKE_HOST=" f "/host") (str "ASL1_FAKE_CLANG=" f "/clang") (str "ASL1_FAKE_SOURCE=" source)
                          (str "ASL1_NATIVE_SCRIPT=" f "/" script) (str "ASL1_STAGE_LOG=" f "/stages") (str "ASL1_HOST_LOG=" f "/host-calls")
                          (str "ASL1_CLANG_LOG=" f "/clang-calls") (str "ASL_NATIVE_ASL1_CACHE=" cache) (str "ASL_NATIVE_ASL1_SOURCE=" source)
                          (str "ASL1_EXPECT=" expect))
                    (mt seed ((some p) (list (str "ASL_NATIVE_ASL1_SEED=" p))) ((none) (list)))))
    ((err _) (none))
    ((ok c) (some c)))

fn ! stages! f: String -> String
  (let [(text (resultOr (fileReadString (str f "/stages")) ""))
        (_ (if (fileExists? (str f "/stages")) (pathRemove (str f "/stages")) (ok ())))]
    text)

fn ! exitedZero? c: (Option sys/Captured) -> Bool
  (mt c ((some x) (= x.exitCode 0)) ((none) false))

fn ! printed? c: (Option sys/Captured) text: String -> Bool
  (mt c ((some x) (stringContains? x.stdout text)) ((none) false))

fn ! testSeedSelection -> Bool
  (let [(root (str (tempRoot) "_seed"))
        (f (str root "/fixture"))
        (good (str root "/repo"))
        (bad (str root "/badRepo"))
        (_ (dirCreate f))
        (made (and (executable! (str f "/host") (str "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$ASL1_HOST_LOG\"\n"
                                                    "if [ \"$1\" = run ] && [ \"$3\" = deps ]; then printf '%s\\n' \"$ASL1_FAKE_SOURCE\"; exit 0; fi\nexit 9\n"))
                   (and (executable! (str f "/clang") (str "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$ASL1_CLANG_LOG\"\n"
                                                         "if [ \"$1\" = --version ]; then echo fixture-clang; exit 0; fi\n"
                                                         "if [ \"$1\" = -dumpmachine ]; then echo fixture-arch-os2.1; exit 0; fi\n"
                                                         "out=''\nwhile [ \"$#\" -gt 0 ]; do if [ \"$1\" = -o ]; then shift; out=\"$1\"; fi; shift; done\n"
                                                         "cp \"$ASL1_NATIVE_SCRIPT\" \"$out\"\nchmod +x \"$out\"\nexit 0\n"))
                        (and (executable! (str f "/native") (stageScript "native" 0))
                             (and (executable! (str f "/failing") (stageScript "native-failed" 7))
                                  (and (pinned! (str f "/seed") (stageScript "seed" 0))
                                       (and (pinned! (str f "/staleSeed") (stageScript "stale" 7))
                                            (and (seedRepo! good true) (seedRepo! bad false)))))))))
        (sources (map (fn [(n String)] -> String (str f "/source" n ".asl")) (list "A" "B" "C" "D")))
        (_ (map (fn [(p String)] -> Bool (ok? (fileWrite p (str "(module fixture/" (sys/baseName p) ")\n")))) sources))
        (src (fn [(i Int64)] -> String (optionOr (listGet sources i) "")))
        (ctxR (sys/context!))]
    (mt ctxR
      ((err e) (do (pathRemove root) (assert (stringEmpty? e) (str "context unavailable: " e)) false))
      ((ok ctx)
        (let [(_ (assert made "seed selection fixtures are written"))
              (checkedIn (seedChild! ctx f (str root "/cacheA") (none) (src 0) "native" "staged" good))
              (checkedInStages (stages! f))
              (llSha (bytesSha256 (stringToBytes "fixture ir\n")))
              (_ (assert (exitedZero? checkedIn) "without a pinned seed the checked-in seed bootstraps the compiler"))
              (_ (assert (printed? checkedIn "BUILT") "the checked-in seed bootstrap installs a compiler"))
              (_ (assert (= checkedInStages "native\nnative\n") "the linked checked-in seed runs stage one, its output stage two"))
              (_ (assert (validSeedFile? (str root "/cacheA/seed/" llSha "/asl1-native")) "the seed binary is kept under the cache keyed by llSha256 with its digest"))
              (_ (assert (stringContains? (resultOr (fileReadString (str f "/clang-calls")) "") "-dumpmachine") "the seed row is chosen by the clang triple"))
              (perturbed (seedChild! ctx f (str root "/cacheB") (none) (src 0) "native" "seedSha" bad))
              (perturbedStages (stages! f))
              (_ (assert (exitedZero? perturbed) "a perturbed manifest sha256 returns the typed error through the production entry point"))
              (_ (assert (printed? perturbed "ERR_SEED_SHA: ") "a seed whose .gz differs from the manifest sha256 is rejected"))
              (_ (assert (stringEmpty? perturbedStages) "a rejected seed never runs a stage"))
              (_ (assert (not (fileExists? (str root "/cacheB/seed"))) "a rejected seed is never unpacked or linked"))
              (warm (seedChild! ctx f (str root "/cacheC") (some (str f "/seed")) (src 1) "native" "staged" good))
              (_ (stages! f))
              (retried (seedChild! ctx f (str root "/cacheC") (some (str f "/seed")) (src 2) "failing" "retried" good))
              (retriedStages (stages! f))
              (_ (assert (exitedZero? warm) "a first build fills the cache with a compiler"))
              (_ (assert (exitedZero? retried) "a failing cached compiler reports both failures through the production entry point"))
              (_ (assert (printed? retried "retried from the seed") "a failing cached compiler is retried from the seed"))
              (_ (assert (= retriedStages "native\nnative\nnative-failed\nseed\nnative-failed\n") "a deps probe on the cached compiler precedes it running first, then the seed, each into stage two"))
              (stale (seedChild! ctx f (str root "/cacheD") (some (str f "/staleSeed")) (src 3) "native" "stale" good))
              (staleStages (stages! f))
              (_ (assert (exitedZero? stale) "a stale seed returns the typed error through the production entry point"))
              (_ (assert (printed? stale "ERR_SEED_STALE: ") "a seed that cannot build the sources is ERR_SEED_STALE"))
              (_ (assert (printed? stale "tools/seed.asl regen") "the stale-seed error names the regeneration command"))
              (_ (assert (= staleStages "stale\n") "a stale seed stops after its own stage"))
              (_ (assert (not (hasInstalledNative? (str root "/cacheD"))) "a stale seed installs nothing"))]
          (cleanup root true)))))

fn ! validSeedFile? path: String -> Bool
  (and (sys/executable? path)
       (mt (fileReadBytes path)
         ((err _) false)
         ((ok b) (= (sys/stripTrailingNewlines (resultOr (fileReadString (str path ".sha256")) "")) (bytesSha256 b)))))

fn ! runTests -> Bool
  (and (testColdBootstrapRequiresSeedBeforeStages) (testSeedSelection))
