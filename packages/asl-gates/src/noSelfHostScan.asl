(module asl-gates/noSelfHostScan
  :x [rawStarters childStarts wrappedStarts otherStarts otherTestFile? wrappedAllow wrappedRowCounts wrappedTotal wrappedDiff otherAllow otherRowCounts baselineCounts fileFindings changedFindings! findingsMessage]
  :i [(asl-parser/lexer :a lex) (asl-gates/noSelfHostBaseline :a base)])

(schema ScanState (:f open Bool) (:f count Int64))

(schema DefState (:f stage Int64) (:f names (List String)))

fn rawStarters -> (List String)
  (list "processRun" "procSpawnv" "processSpawn" "procSpawn" "procExec" "procFork")

; (:m :ref NOSELFHOST-VALUE-STARTER :do "a raw starter name passed as a value ((map processSpawn xs)) or aliased ((let [(f processRun)] ...)) starts a child as surely as a call, so it counts wherever it stands as a symbol; the other starters count only in call position, where a local helper of the same name is told apart")
fn rawStarter? name: String -> Bool
  (let [(parts (stringSplit name "/"))
        (base (optionOr (listLast parts) name))]
    (listContains? (rawStarters) base))

fn childStarter? name: String -> Bool
  (let [(parts (stringSplit name "/"))
        (base (optionOr (listLast parts) name))]
    (or (listContains? (rawStarters) base)
        (listContains? (list "ccRunCommand!" "runCommand!" "runArgv!" "runPool!" "runOne!"
                             "exec!" "execRaw!" "runSimple!" "sessionSpawn!" "sessionSpawnWithPid!" "spawn!") base)))

; (:m :ref NOSELFHOST-WRAPPED-STARTERS :do "shared wrappers whose body is a raw child start (sys/capture! sys/captureWith! from asl-cli/system, runCapture! runProc runBounded runBounded! runEngineEval! runEngineCommand! spawnWorker! spawnRunInput runSpawnDispatch! runProcIn timeoutRun! runJob! runTool! spawnSessionWith!): a call to one, or its name as a value or alias, in a Test.asl starts a child that no fleet limit bounds, so it is counted per file apart from the raw baseline and must be an allow row with a reason; a local fn of the same name is that file own helper and is not counted, as for raw starters")
fn wrapperStarters -> (List String)
  (list "capture!" "captureWith!" "runCapture!" "runProc" "runBounded" "runBounded!" "runEngineEval!" "runEngineCommand!" "spawnWorker!" "spawnRunInput" "runSpawnDispatch!" "runProcIn" "timeoutRun!" "runJob!" "runTool!" "spawnSessionWith!"
        "gitTrackedFiles!" "linkWasm32" "wasiSysExec!" "collectDirectoryFiles" "targetFacts!" "targetArgs!" "curlRequestWith" "discoverTargetSourceFiles" "judgeGate" "wasmImports")

fn wrapperStarter? name: String -> Bool
  (let [(parts (stringSplit name "/"))
        (base (optionOr (listLast parts) name))]
    (listContains? (wrapperStarters) base))

fn wrapScanToken helpers: (List String) state: ScanState token: lex/Token -> ScanState
  (let [(hit (match token.kind
                       ((lex/tokSymbol name) (and (not (listContains? helpers name)) (wrapperStarter? name)))
                       (_ false)))]
    (ScanState :open (match token.kind ((lex/tokLparen) true) (_ false))
               :count (if hit (+ state.count 1) state.count)))

fn wrappedStarts source: String -> Int64
  (let [(helpers (localHelpers source))]
    (fold (fn [(st ScanState) (tk lex/Token)] -> ScanState (wrapScanToken helpers st tk))
          (ScanState :open false :count 0) (lex/tokenize source)).count)

fn defStep state: DefState token: lex/Token -> DefState
  (match token.kind
    ((lex/tokSymbol name)
      (if (= name "fn") (DefState :stage 1 :names state.names)
        (if (and (= state.stage 1) (= name "!")) (DefState :stage 2 :names state.names)
          (if (> state.stage 0) (DefState :stage 0 :names (listAppend state.names (list name)))
            (DefState :stage 0 :names state.names)))))
    (_ (DefState :stage 0 :names state.names)))

fn localHelpers source: String -> (List String)
  (filter (fn [(n String)] -> Bool (not (listContains? (rawStarters) n)))
          (fold defStep (DefState :stage 0 :names (list)) (lex/tokenize source)).names)

fn scanToken helpers: (List String) state: ScanState token: lex/Token -> ScanState
  (let [(hit (match token.kind
                       ((lex/tokSymbol name) (and (not (listContains? helpers name))
                                                  (if state.open (childStarter? name) (rawStarter? name))))
                       (_ false)))]
    (ScanState :open (match token.kind ((lex/tokLparen) true) (_ false))
               :count (if hit (+ state.count 1) state.count)))

fn childStarts source: String -> Int64
  (let [(helpers (localHelpers source))]
    (fold (fn [(st ScanState) (tk lex/Token)] -> ScanState (scanToken helpers st tk))
          (ScanState :open false :count 0) (lex/tokenize source)).count)
fn wrappedAllow -> (List (List String))
  (list (list "asl/packages/asl-agent/tests/aslOpsTest.asl" "1" "o/runBounded is aslOps' own deadline runner; the test drives its spawn-error and ok paths on fixture argv, no bin/asl or exe")
        (list "asl/tools/tests/nativeTestLeaseTest.asl" "1" "nt/runProc runs the freshly built lease fixture binary under its own pgid lease, not the cli")
        (list "asl/packages/asl-agent/tests/gitOpsTest.asl" "1" "g/runBounded! with a 60 s deadline over fixture git commands, no bin/asl or exe")
        (list "asl/packages/asl-agent/tests/runOpsTest.asl" "1" "g/runBounded! with a 60 s deadline over fixture commands, no bin/asl or exe")
        (list "asl/packages/asl-cli/tests/asl1BootstrapTest.asl" "11" "sys/capture! runs ls -A to list a directory; filesystem read, no exe")
        (list "asl/packages/asl-cli/tests/asl1CacheBaseTest.asl" "1" "sys/capture! rm -rf of the test's own temp root")
        (list "asl/packages/asl-cli/tests/asl1CacheStampTest.asl" "2" "sys/capture! cp and rm -rf of the test's own temp files")
        (list "asl/packages/asl-engine/tests/engineTest.asl" "1" "tp/runEngineEval! is the unit under test: its body is processRun of aslBin eval with no deadline, in the product transport.asl; bounding it is a product change, plan row NOSELFHOST-WRAPPED-BINASL")
        (list "asl/packages/asl-gateway/tests/cliDispatchTest.asl" "1" "cli/runSpawnDispatch! with a 1 s deadline spawns the fixture dispatch child, pid file and temp dir owned by the test")
        (list "asl/packages/asl-intel/tests/intelParityTest.asl" "1" "h/runCapture! runs a fixture command through the intel host context")
        (list "asl/packages/asl-intel/tests/modRankTest.asl" "2" "h/runCapture! git init and git add -A on the test's temp repo")
        (list "asl/packages/asl-target-llvm/tests/nativeDataTest.asl" "1" "nt/runProc runs the freshly built probe binary, not the cli")
        (list "asl/packages/asl-target-llvm/tests/nativeGlobalsTest.asl" "1" "nt/runProc runs the freshly built probe binary, not the cli")
        (list "asl/packages/asl-target-llvm/tests/nativeShaTest.asl" "1" "nt/runProc runs the freshly built probe binary, not the cli")
        (list "bench/native/tests/paritySmokeTest.asl" "1" "nt/runProc rm -rf of the test's own work dir")
        (list "tests/conformance/bootstrap/nativeCliTest.asl" "2" "h/capture! runs bin/asl build and cli cases with a 240 s deadline")
        (list "tests/parity/cli/intelRouteTest.asl" "2" "h/capture! runs bin/asl intel coupling with a 240 s deadline")
        (list "tests/parity/forms/delegateTest.asl" "1" "d/spawnRunInput runs /bin/cat with a 5 s deadline")
                (list "asl/packages/asl-cli/tests/migrateDryRunTest.asl" "1" "mig/discoverTargetSourceFiles runs find over the test's fixture roots, read-only")
        (list "asl/packages/asl-compiler/tests/wasiCapabilityAcceptanceTest.asl" "2" "wasi/wasiSysExec! runs the wasi syscall exec route on fixture argv under test")
        (list "asl/packages/asl-compiler/tests/wasiCapabilityTest.asl" "2" "wasi/wasiSysExec! runs the wasi syscall exec route on fixture argv under test")
        (list "asl/packages/asl-compiler/tests/wasiRuntimeTest.asl" "1" "wasi/wasiSysExec! runs the wasi syscall exec route on fixture argv under test")
        (list "asl/packages/asl-gates/tests/gatesTest.asl" "3" "g/collectDirectoryFiles lists a fixture directory with find")
        (list "asl/packages/asl-syntax/tests/core/corpusTest.asl" "3" "crp/gitTrackedFiles! runs git ls-files to list the tracked corpus, read-only")
        (list "asl/packages/asl-syntax/tests/json/jsonCstTest.asl" "1" "crp/gitTrackedFiles! runs git ls-files to list the tracked corpus, read-only")
        (list "asl/packages/asl-syntax/tests/markdown/markdownTest.asl" "1" "crp/gitTrackedFiles! runs git ls-files to list the tracked corpus, read-only")
        (list "asl/packages/asl-syntax/tests/xml/xmlTest.asl" "4" "crp/gitTrackedFiles! runs git ls-files to list the tracked corpus, read-only")
        (list "asl/packages/asl-target-llvm/tests/wasmE2eTest.asl" "3" "wl/linkWasm32 and wl/wasmImports run the wasm linker and node on the test's own build output")
        (list "asl/packages/asl-target-llvm/tests/wasmNoLibcTest.asl" "4" "wl/linkWasm32 and wl/wasmImports run the wasm linker and node on the test's own build output")
        (list "asl/packages/asl-target-llvm/tests/wasmStackRootsTest.asl" "1" "wl/linkWasm32 runs the wasm linker on the test's own build output")
        (list "asl/packages/asl-target-llvm/tests/wasmSysValTest.asl" "3" "wl/linkWasm32 and wl/wasmImports run the wasm linker and node on the test's own build output")
        (list "asl/packages/asl-target-llvm/tests/wasmTailCallTest.asl" "1" "wl/linkWasm32 runs the wasm linker on the test's own build output")
        (list "harness/tests/benchTest.asl" "7" "b/judgeGate runs a fixture gate command and cb/curlRequestWith runs curl against a local fixture")
        (list "tests/conformance/bootstrap/linuxSeedTest.asl" "4" "rt/targetFacts! and gr/targetArgs! probe the target toolchain, read-only")
        (list "tools/tests/nativeModuleCacheTest.asl" "9" "nt/runProc runs freshly built probe binaries, not the cli")
        (list "tools/tests/nativePreludeKeyTest.asl" "3" "nt/runProc runs uname, clang -c and a built probe binary")
        (list "tools/tests/nativeWorkerDeadlineTest.asl" "1" "nt/spawnWorker! over a /bin/sh worker script: the worker deadline is the thing under test"))

fn wrappedRowCounts -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (row (List String))] -> (Map String Int64)
           (mapSet acc (optionOr (listGet row 0) "") (optionOr (stringToInt64 (optionOr (listGet row 1) "")) 0)))
        (mapEmpty) (wrappedAllow))

fn wrappedTotal -> Int64
  (fold (fn [(n Int64) (v Int64)] -> Int64 (+ n v)) 0 (mapValues (wrappedRowCounts)))

fn wrappedDiff hits: (List (Pair String Int64)) allow: (Map String Int64) -> (List String)
  (let [(actual (fold (fn [(acc (Map String Int64)) (h (Pair String Int64))] -> (Map String Int64) (mapSet acc (pairFirst h) (pairSecond h))) (mapEmpty) hits))
        (paths (mapKeys (fold (fn [(m (Map String Bool)) (k String)] -> (Map String Bool) (mapSet m k true)) (mapEmpty) (listAppend (mapKeys actual) (mapKeys allow)))))]
    (filter (fn [(p String)] -> Bool (!= (optionOr (mapGet actual p) 0) (optionOr (mapGet allow p) 0))) paths))

; (:m :ref D81-PROCESSRUN-BINASL :do "a suite not named *Test.asl (tests/acceptance/d81/Task*.asl, harnesses and gates under a tests directory) was never scanned, so a raw processRun of bin/asl there passed; every other tracked .asl under a tests directory is scanned too, raw and wrapped starts together, and must equal its row here in both directions: rows only leave with their calls")
fn otherTestFile? p: String -> Bool
  (and (not (stringEndsWith? p "Test.asl"))
    (and (or (stringStartsWith? p "tests/") (stringContains? p "/tests/"))
      (not (listContains? (list "tools/tests/noSelfHostTest.asl" "asl/packages/asl-gates/src/noSelfHostBaseline.asl") p))))

fn otherStarts source: String -> Int64
  (+ (childStarts source) (wrappedStarts source))

fn otherAllow -> (List (List String))
  (list (list "asl/packages/asl-agent/tests/loopRunFixture.asl" "1" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "asl/packages/asl-parser/tests/printReparseLib.asl" "1" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "asl/packages/asl-syntax/tests/asl/asnCorpusLib.asl" "1" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "asl/packages/asl-syntax/tests/asl/layoutCorpusLib.asl" "1" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "asl/packages/asl-target-llvm/tests/fixtures/rc/rcClosedFds.asl" "2" "a fixture program whose spawn is the subject under test, run by its suite")
        (list "asl/packages/asl-target-llvm/tests/fixtures/rc/rcSpawnLeak.asl" "1" "a fixture program whose spawn is the subject under test, run by its suite")
        (list "tests/acceptance/memory/evidenceTracked.asl" "14" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")

        (list "tests/conformance/hostMigration/fixtures/migration.asl" "1" "a fixture program whose spawn is the subject under test, run by its suite")
        (list "tests/harnessBench/verifyCases.asl" "2" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "tests/parity/gates/runnerCorpus.asl" "1" "pre-existing start, no bin/asl or host named: frozen until routed through asl/tools/fleet/run.asl")
        (list "tools/tests/fixtures/nativeTest/runnerProbe.asl" "1" "a fixture program whose spawn is the subject under test, run by its suite")
        (list "tools/tests/fixtures/nativeTest/sysSuite.asl" "1" "a fixture program whose spawn is the subject under test, run by its suite"))

fn otherRowCounts -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (row (List String))] -> (Map String Int64)
           (mapSet acc (optionOr (listGet row 0) "") (optionOr (stringToInt64 (optionOr (listGet row 1) "")) 0)))
        (mapEmpty) (otherAllow))

fn baselineCounts -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (row (List String))] -> (Map String Int64)
           (mapSet acc (optionOr (listGet row 0) "")
             (optionOr (stringToInt64 (optionOr (listGet row 1) "")) 0)))
        (mapEmpty) (base/bareBaseline))


; (:m :ref RED-AT-GATE :do "noSelfHostTest's per-file rules on one file's text: a *Test.asl must carry exactly its bare-start baseline row and its wrapped-start row, a tests-directory .asl not named *Test.asl exactly its otherAllow row, with the messages the whole-tree test prints; the test and the writer gate on changed files both call it")
fn fileFindings path: String source: String -> (List String)
  (let [(testFile (and (stringEndsWith? path "Test.asl") (not (listContains? (list "tools/tests/noSelfHostTest.asl" "asl/packages/asl-gates/src/noSelfHostBaseline.asl") path))))
        (bare (if testFile (childStarts source) 0))
        (baseBare (optionOr (mapGet (baselineCounts) path) 0))
        (wrapped (if testFile (wrappedStarts source) 0))
        (baseWrapped (optionOr (mapGet (wrappedRowCounts) path) 0))
        (other (if (otherTestFile? path) (otherStarts source) 0))
        (baseOther (optionOr (mapGet (otherRowCounts) path) 0))]
    (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
      (list (if (> bare baseBare) (str "new bare child starts beyond the explicit file/count/reason baseline: " path " (route the start through asl/tools/fleet/run.asl; the baselines are frozen and do not grow)") "")
            (if (and testFile (< bare baseBare)) (str "every baseline row equals its file's actual count, so a start removed from a file ratchets its row down and cannot leave room for a hidden one: " path " (lower its baseline row to the file's actual count)") "")
            (if (!= wrapped baseWrapped) (str "every Test.asl call of a shared child-start wrapper equals its allow row, in both directions; differing files: " path " (route the wrapped start through asl/tools/fleet/run.asl; the allow rows are frozen and do not grow)") "")
            (if (and (otherTestFile? path) (!= other baseOther)) (str "every child start in a tests-directory .asl not named *Test.asl equals its row in otherAllow, in both directions; differing files: " path " (route the start through asl/tools/fleet/run.asl; the allow rows are frozen and do not grow)") ""))))

; (:m :ref RED-AT-GATE :do "the findings for the .asl files a unit changed, read from root; an unreadable path (deleted) counts as empty text so a baseline row left behind is a finding; a path in no scanned class costs one string test")
fn ! changedFindings! root: String changed: (List String) -> (List String)
  (fold (fn [(acc (List String)) (p String)] -> (List String)
          (if (stringEndsWith? p ".asl")
            (listAppend acc (fileFindings p (resultOr (fileReadString (str root "/" p)) "")))
            acc))
        (list) changed)

fn findingsMessage found: (List String) -> String
  (str "noSelfHostTest on the changed files: " (stringJoin found "; "))
