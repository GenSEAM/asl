(module asl-cli/binAslNativeTest :x [runTests] :i [(tools/fleet/run :a run)])

fn probe -> String
  "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl"

fn fixture name: String -> String
  (str "asl/packages/asl-cli/tests/fixtures/servedBy/" name ".asl")

fn ! envWith extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (cons "ASL_NATIVE_CLI_WAIT=1" extra))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "SERVED_STOP_PID=") (stringStartsWith? row "ASL_NATIVE_TRACE="))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 1500 64))

fn ! binAslSplit! root: String args: (List String) env: (List String) errFile: String -> run/Done
  (run/runOneLimited (run/job (listAppend (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$BIN_ASL_ERR\"" (str root "/bin/asl")) args) root (cons (str "BIN_ASL_ERR=" errFile) env)) (run/limits 1500 64))

fn freshSuite tag: String -> String
  (str "(module quietFixture/quietTest :x [runTests] :i [])\n\nfn runTests -> Bool\n  (do (assert (= (stringLength \"" tag "\") " (stringFromInt64 (stringLength tag)) ") \"the tag has its length\")\n      true)\n")

fn ! testServed root: String host: String -> Bool
  (let [(native (binAsl! root (list "test" (probe)) (envWith (list))))
        (forced (binAsl! root (list "test" (probe)) (envWith (list (str "ASL_HOST=" host)))))
        (checked (binAsl! root (list "check" "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") (envWith (list))))]
    (do (assert (= native.verdict "exit") "bin/asl test ended on its own, inside the limit")
        (assert (= native.exit 0) (str "bin/asl test served the probe natively: " native.out))
        (assert (stringContains? native.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the native run reports the probe's four assertions and one refutation")
        (refute (stringContains? native.out "runs on asl-host") "bin/asl printed no host fallback note for test")
        (assert (!= forced.exit 0) "with ASL_HOST set, bin/asl test runs on asl-host and the probe fails")
        (assert (stringContains? forced.out "no asl-host stands between bin/asl and this suite") "the forced host run fails on the host refutation")
        (assert (= checked.exit 0) (str "bin/asl check runs natively: " checked.out))
        (refute (stringContains? checked.out "is not native yet") "check runs natively without a host-fallback note")
        (refute (stringContains? checked.out "runs on asl-host") "check prints no host fallback note")
        (assert (stringContains? checked.out "ok asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") "the native check result is reported")
        true))

fn ! testUnsupportedFallsBack root: String -> Bool
  (let [(gap (binAsl! root (list "test" (fixture "unsupportedProbe")) (envWith (list))))
        (failing (binAsl! root (list "test" (fixture "failingProbe")) (envWith (list))))]
    (do (assert (= gap.exit 0) (str "a suite the native lowering rejects keeps the asl-host verdict: " gap.out))
        (assert (stringContains? gap.out (str "asl: " (fixture "unsupportedProbe") " runs on asl-host: ERR_NATIVE_UNSUPPORTED: ")) "the rerun note names the suite and the gap")
        (assert (stringContains? gap.out "ERR_LOWER_UNSUPPORTED] 'recur'") "the note carries the lowering diagnostic")
        (assert (stringContains? gap.out "unsupportedProbe.asl: 1 assertion(s) executed (1 passed)") "asl-host ran the suite's assertion")
        (assert (= failing.exit 1) (str "a suite that fails natively fails: " failing.out))
        (assert (stringContains? failing.out "ERR_ASSERT: assertion failed: two has two letters") "the native failure is reported")
        (refute (stringContains? failing.out "runs on asl-host") "a native test failure is never rerun on asl-host")
        true))

fn ! testSilentVerbs root: String -> Bool
  (let [(version (binAsl! root (list "version") (envWith (list))))
        (crawler (binAsl! root (list "crawler") (envWith (list))))
        (crawl (binAsl! root (list "crawl") (envWith (list))))
        (engine (binAsl! root (list "engine" "status") (envWith (list))))
        (mesh (binAsl! root (list "mesh" "status") (envWith (list))))
        (build (binAsl! root (list "build" "--help") (envWith (list))))
        (audit (binAsl! root (list "audit") (envWith (list))))
        (pack (binAsl! root (list "pack" "--help") (envWith (list))))
        (note (binAsl! root (list "note" "list") (envWith (list))))
        (doc (binAsl! root (list "doc") (envWith (list))))
        (lens (binAsl! root (list "lens" "info" "falsification") (envWith (list))))
        (consilium (binAsl! root (list "consilium") (envWith (list))))
        (browser (binAsl! root (list "browser") (envWith (list))))
        (web (binAsl! root (list "web") (envWith (list))))
        (search (binAsl! root (list "search") (envWith (list))))
        (research (binAsl! root (list "research") (envWith (list))))]
    (do (assert (= version.exit 0) (str "bin/asl version still answers: " version.out))
        (refute (stringContains? version.out "is not native yet") "version runs natively without a host-fallback note")
        (assert (stringContains? version.out "asl 0.1.0 (bin/asl)") "version keeps its own banner line")
        (assert (= crawler.exit 0) (str "bin/asl crawler still answers: " crawler.out))
        (refute (stringContains? crawler.out "is not native yet") "crawler runs natively without a host-fallback note")
        (assert (stringContains? crawler.out "asl-crawler: Sovereign Web Crawler") "crawler keeps its usage banner")
        (assert (= crawl.exit 0) (str "bin/asl crawl (alias) still answers: " crawl.out))
        (refute (stringContains? crawl.out "is not native yet") "crawl alias runs natively without a host-fallback note")
        (assert (= engine.exit 0) (str "bin/asl engine status still answers: " engine.out))
        (refute (stringContains? engine.out "is not native yet") "engine runs natively without a host-fallback note")
        (assert (stringContains? engine.out "ASL ENGINE STATUS") "engine keeps its status banner")
        (assert (= mesh.exit 0) (str "bin/asl mesh status still answers: " mesh.out))
        (refute (stringContains? mesh.out "is not native yet") "mesh runs natively without a host-fallback note")
        (assert (stringContains? mesh.out "ASL AUDIT MESH STATUS") "mesh keeps its status banner")
        (assert (= build.exit 0) (str "bin/asl build --help still answers: " build.out))
        (refute (stringContains? build.out "is not native yet") "build runs natively without a host-fallback note")
        (assert (stringContains? build.out "usage: asl build FILE") "build keeps its usage line")
        (assert (= audit.exit 0) (str "bin/asl audit still answers: " audit.out))
        (refute (stringContains? audit.out "is not native yet") "audit runs natively without a host-fallback note")
        (assert (stringContains? audit.out "(:audit :sub consistency") "audit keeps its consistency receipt")
        (assert (= pack.exit 0) (str "bin/asl pack --help still answers: " pack.out))
        (refute (stringContains? pack.out "is not native yet") "pack runs natively without a host-fallback note")
        (assert (stringContains? pack.out "usage: asl pack") "pack keeps its usage line")
        (assert (= note.exit 0) (str "bin/asl note list still answers: " note.out))
        (refute (stringContains? note.out "is not native yet") "note runs natively without a host-fallback note")
        (assert (stringContains? note.out "(:note :action \"list\" :receipt (:notes :count") "note list keeps its receipt shape")
        (assert (= doc.exit 1) (str "bin/asl doc with no argument still answers: " doc.out))
        (refute (stringContains? doc.out "is not native yet") "doc runs natively without a host-fallback note")
        (assert (stringContains? doc.out "doc requires SYMBOL (path#name) or FILE") "doc keeps its missing-argument message")
        (assert (= lens.exit 0) (str "bin/asl lens info still answers: " lens.out))
        (refute (stringContains? lens.out "is not native yet") "lens runs natively without a host-fallback note")
        (assert (stringContains? lens.out "Lens:             falsification") "lens keeps its info banner")
        (assert (= consilium.exit 0) (str "bin/asl consilium still answers: " consilium.out))
        (refute (stringContains? consilium.out "is not native yet") "consilium runs natively without a host-fallback note")
        (assert (stringContains? consilium.out "asl-consilium: Sovereign Multi-LLM Frontier Council Deliberation Engine") "consilium keeps its usage banner")
        (refute (stringContains? browser.out "is not native yet") "browser runs natively without a host-fallback note")
        (assert (!= browser.exit 0) (str "bin/asl browser with no gateway listening still fails the same way: " browser.out))
        (assert (= web.exit 1) (str "bin/asl web with no query still answers: " web.out))
        (refute (stringContains? web.out "is not native yet") "web runs natively without a host-fallback note")
        (assert (stringContains? web.out "Missing query argument") "web keeps its missing-argument message")
        (assert (= search.exit 1) (str "bin/asl search with no query still answers: " search.out))
        (refute (stringContains? search.out "is not native yet") "search runs natively without a host-fallback note")
        (assert (stringContains? search.out "Missing query argument") "search keeps its missing-argument message")
        (assert (= research.exit 1) (str "bin/asl research with no topic still answers: " research.out))
        (refute (stringContains? research.out "is not native yet") "research runs natively without a host-fallback note")
        (assert (stringContains? research.out "Missing topic argument") "research keeps its missing-argument message")
        true))

fn ! testQuiet root: String host: String -> Bool
  (let [(dir (str root "/.asl/cache/binAslQuiet/" (stringFromInt64 (procSelf))))
        (tag (str "quiet" (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (rel (str ".asl/cache/binAslQuiet/" (stringFromInt64 (procSelf)) "/quietTest.asl"))
        (made (mt (dirCreate dir) ((err e) (err e)) ((ok _) (fileWrite (str dir "/quietTest.asl") (freshSuite tag)))))
        (nativeErr (str dir "/native.err"))
        (hostErr (str dir "/host.err"))
        (native (binAslSplit! root (list "test" rel) (envWith (list)) nativeErr))
        (forced (binAslSplit! root (list "test" rel) (envWith (list (str "ASL_HOST=" host))) hostErr))
        (nativeText (resultOr (fileRead nativeErr) "unreadable"))
        (hostText (resultOr (fileRead hostErr) "unreadable"))
        (cleaned (run/runOneLimited (run/job (list "/bin/rm" "-rf" dir) root (run/childEnv (list))) (run/limits 30 4)))]
    (do (assert (ok? made) "the fresh suite was written")
        (assert (= native.exit 0) (str "the fresh suite passes natively: " native.out nativeText))
        (assert (= forced.exit 0) (str "the fresh suite passes on asl-host: " forced.out hostText))
        (refute (stringContains? nativeText "NATIVE-") (str "native stderr carries no NATIVE-* telemetry: " nativeText))
        (assert (= nativeText hostText) (str "native stderr equals the host path's stderr: native " nativeText " host " hostText))
        (assert (= cleaned.exit 0) "the fresh suite was removed")
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (host (str root "/asl/host/out/asl-host"))]
    (and (testServed root host) (and (testUnsupportedFallsBack root) (and (testSilentVerbs root) (testQuiet root host)))))
