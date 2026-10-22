(module asl-target-llvm/tests/nativeDataTest
  :x [runTests]
  :i [(tools/nativeTest :a nt) (asl-target-llvm/tests/nativeOracle :a oracle)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): testParquet/testParquetTraps/testZstd/testEqAlias compared a native run (via tools/nativeTest as a subprocess under asl-host) against a live asl-host interpretation of the exact same fixture; every one of those fixtures is fully deterministic (fixed inputs, fixed algorithm), so the host side is replaced by a one-time recorded value captured from the leftover asl-host binary before HL-DELETE removed it (parquetProbe and zstdProbe as golden/ files, confirmed byte-identical to the current native build's own stdout; the three parquetTrap error texts and eqAlias's one-line stdout inlined as literals), and the native side now calls tools/nativeTest's own prepareRun/runProc in-process instead of shelling out to asl-host")

; (:m :ref FIXA :do "testDownstream restored (FIXL's removal reported the cause rather than fixing it, out of FIXL's :owns): tools/nativeTest.asl#prepareIn read a run/test FILE argument through resolveIn (toolRoot) path, resolving the caller's own path against the toolchain root instead of the caller's cwd (NATIVE-CHDIR says the native CLI never chdirs to the toolchain root first, so a user path was always meant to be cwd-relative; only the toolchain's internal cache/manifest lookups are root-relative) -- a file living outside the toolchain root was unreadable even with ASL_ROOT correctly naming the real toolchain. Fixed in tools/nativeTest.asl (prepareIn, and --expect's file read, same bug). The removed function's second leg (ASL_NATIVE_FALLBACK=host) tested a host-interpretation fallback that sh/HLNT already deleted outright (confirmed: NATIVE-FALLBACK/ASL_NATIVE_FALLBACK live only in the unrelated asl-cli/src/native.asl eval path); that leg is gone for good, same as testAllUnsupported's prior removal, so only the rooted (ASL_ROOT-from-a-downstream-cwd) leg returns")

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/nativeData/" name ".asl")

(schema Recorded
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String)
  (:f ranNatively Bool)
  (:f buildReason String))

fn ! sh cmd: String -> Recorded
  (let [(r (processRun cmd))]
    (Recorded :exitCode r.exitCode :stdout r.stdout :stderr r.stderr :ranNatively true :buildReason ""))

; (:m :ref HL-E-LLVM :do "ranNatively/buildReason replace the old 'grep the subprocess's own stderr for NATIVE-CACHE/NATIVE-FALLBACK' check: that marker was printed by tools/nativeTest.asl's own telemetry when IT ran as the outer subprocess (the old 'asl-host run tools/nativeTest.asl run ...' shape). Calling prepareRun/runProc in-process instead means the telemetry goes to this test's own current-process stderr, never into the built fixture binary's returned stderr, so whether the fixture ran natively (never falls back, since this code path has no host to fall back to) is read directly off the Built record prepareRun returns")

fn ! nativeRun path: String args: (List String) label: String -> Recorded
  (let [(built (nt/prepareRun path label))]
    (match built.binary
      ((none) (Recorded :exitCode 127 :stdout "" :stderr built.reason :ranNatively false :buildReason built.reason))
      ((some bin) (let [(r (nt/runProc (listAppend (list bin) args) (none)))]
                    (Recorded :exitCode r.exitCode :stdout r.stdout :stderr r.stderr :ranNatively true :buildReason built.reason)))))

fn ! goldenText path: String -> String
  (resultOr (fileReadString path) (str "UNREADABLE " path))

fn errorLine text: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) (stringLines text))) "")

fn errorTail line: String -> String
  (match (stringIndexOf line "ERR_")
    ((some i) (stringReplace (optionOr (stringSlice line i (stringLength line)) line) " (after 0 asserts)" ""))
    ((none) line))

fn ! testParquet -> Bool
  (let [(native (nativeRun (fixture "parquetProbe") (list) "nativeDataParquet"))
        (recorded (goldenText "asl/packages/asl-target-llvm/tests/golden/nativeDataParquetProbe.stdout"))
        (out native.stdout)]
    (do
      (assert (= native.exitCode 0) (str "parquetProbe: native run exits 0: " native.stderr))
      (assert native.ranNatively (str "parquetProbe: the binary ran natively: " native.buildReason))
      (assert (= native.stdout recorded) "parquetProbe: native stdout equals the recorded asl-host output byte for byte")
      (assert (stringContains? out "file tests/acceptance/vtbotDataPlane/fixtures/seiSpotDeals10kCanonical.parquet\nrows 10000 groups 3\nkv {") "canonical: rows, groups and the vtbot.dataset header")
      (assert (stringContains? out "tsUs int64 rg0 n4000 poly 134189330 first 1782864090013919 last 1783010805663592") "DELTA_BINARY_PACKED tsUs row group 0")
      (assert (stringContains? out "price int64 rg0 n4000") "BYTE_STREAM_SPLIT int64 price ticks are read as int64")
      (assert (stringContains? out "first 4744 ") "byte-stream-split price ticks decode exactly")
      (assert (stringContains? out "price double rg0 n4000 fold 0.09577335263907144 sum 191.62866 first 0.04744 last 0.04791") "dictionary and plain doubles")
      (assert (stringContains? out "side int8 rg0 n4000 poly 891655596 sum 304 ones 2152") "INT32 narrowed by Int(8)")
      (assert (stringContains? out "side int8 rg2 n1000000 poly 814337255 sum 461539 ones 461539") "a 1e6-row row group reads natively")
      (assert (stringContains? out "kvAbsent err key not found") "an absent metadata key is err")
      (assert (stringContains? out "open err ERR_PARQUET_UNSUPPORTED: column") "unknown encoding is ERR_PARQUET_UNSUPPORTED at open")
      (assert (stringContains? out "has no PAR1 magic") "bad magic is err")
      (assert (stringContains? out "is too short for a parquet file") "a short file is err")
      (assert (stringContains? out "open err ERR_IO: cannot open tests/acceptance/r1Host/fixtures/parquet/missing.parquet") "a missing file is ERR_IO")
      (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "file ")) (stringLines out))) 13) "every fixture file is probed")
      true))

; (:m :ref HL-E-LLVM :do "recorded expectations captured from the leftover asl-host binary (offline, before HL-DELETE removed it) by running parquetTrap.asl with each of the three argument values; the native side's own runtime failure text (no test-harness 'FAIL path: ... (after 0 asserts)' wrapper, since this runs the compiled fixture directly rather than through a test runner) already equals the host's error text once errorTail strips that wrapper, so the parity check stays genuine rather than native-vs-same-native-path")

fn recordedTrap which: String -> Recorded
  (cond
    ((= which "type") (Recorded :exitCode 1 :stdout "trap type\n" :stderr "ERR_TYPE: parquetReadI64: column price is not of that type" :ranNatively true :buildReason ""))
    ((= which "column") (Recorded :exitCode 1 :stdout "trap column\n" :stderr "ERR_PARQUET: parquetReadF64: no column noSuchColumn" :ranNatively true :buildReason ""))
    (else (Recorded :exitCode 1 :stdout "trap group\n" :stderr "ERR_RANGE: parquetReadF64: row group outside 0..2" :ranNatively true :buildReason "")))

fn ! testParquetTraps -> Bool
  (fold (fn [(acc Bool) (which String)] -> Bool
          (let [(native (nativeRun (fixture "parquetTrap") (list which) (str "nativeDataTrap" which)))
                (recorded (recordedTrap which))]
            (do
              (assert native.ranNatively (str "trap " which ": native run does not fall back: " native.buildReason))
              (assert (= native.exitCode 1) (str "trap " which ": native exits 1"))
              (assert (= native.exitCode recorded.exitCode) (str "trap " which ": exit equals the recorded asl-host run"))
              (assert (= native.stdout recorded.stdout) (str "trap " which ": stdout equals the recorded asl-host run"))
              (assert (not (stringEmpty? (errorLine recorded.stderr))) (str "trap " which ": the recorded asl-host run names an error"))
              (assert (= (errorTail (errorLine native.stderr)) (errorTail (errorLine recorded.stderr))) (str "trap " which ": native error " (errorLine native.stderr) " equals the recorded asl-host error " (errorLine recorded.stderr)))
              acc)))
        true (list "type" "column" "group"))

fn ! testZstd -> Bool
  (let [(native (nativeRun (fixture "zstdProbe") (list) "nativeDataZstd"))
        (recorded (goldenText "asl/packages/asl-target-llvm/tests/golden/nativeDataZstdProbe.stdout"))]
    (do
      (assert (= native.exitCode 0) (str "zstdProbe: native run exits 0: " native.stderr))
      (assert native.ranNatively (str "zstdProbe: the binary ran natively: " native.buildReason))
      (assert (= native.stdout recorded) "zstdProbe: native stdout equals the recorded asl-host output byte for byte")
      (assert (stringContains? native.stdout "decoded 93") "every zstd fixture is decoded or rejected")
      (assert (stringContains? native.stdout " err ERR_ZSTD_CORRUPT") "negative frames are rejected natively")
      true))

fn ! testEqAlias -> Bool
  (let [(native (nativeRun (fixture "eqAlias") (list "a" "b") "nativeDataEqAlias"))
        (recorded (Recorded :exitCode 0 :stdout "eq true false false true true a,b\n" :stderr "" :ranNatively true :buildReason ""))]
    (do
      (assert (= native.exitCode 0) (str "eqAlias: native run exits 0: " native.stderr))
      (assert native.ranNatively (str "eqAlias: the binary ran natively: " native.buildReason))
      (assert (= native.stdout recorded.stdout) "eqAlias: native stdout equals the recorded asl-host output")
      (assert (= native.stdout "eq true false false true true a,b\n") (str "== lowers as = natively: " native.stdout))
      true))

; (:m :ref FIXA :do "testDownstream's rooted leg restored verbatim from 7c7492236 (ASL_ROOT names the toolchain from a downstream cwd, now readable because tools/nativeTest.asl#prepareIn stopped resolving the user path against toolRoot); the unrooted leg (ASL_NATIVE_FALLBACK=host) dropped for good, since that fallback feature is gone, not merely unreachable -- its own gate above (testAllUnsupported's removal note) already confirms NATIVE-FALLBACK/ASL_NATIVE_FALLBACK no longer exist in tools/nativeTest.asl")

; (:m :ref HLAUDIT-LOWS :do "d3a263c9d's own testDownstream once dropped a third, OUT-OF-ROOT leg (no ASL_ROOT at all, an absolute path to the downstream file) because asl-cli/src/command.asl's runFile! then unconditionally required ctx.hostBin for any out-of-workspace path; that requirement is gone (confirmed by hand: 'bin/asl run <absolute path outside this worktree>' with no ASL_ROOT exits 0 and prints the bin/asl-only diagnostic 'NATIVE-BYPASS ... :reason absolute-path-outside-workspace :staged .asl/cache/nativeTest/outside/<digest>.asl' to stderr), and tools/nativeTest.asl's own OUT-OF-ROOT-USERPATH comment (tools/nativeTest.asl:1523) confirms stageOutsideFile! gives the self-built ntBin the same staging minus that print (silent on success, eprintln only on failure, so the leg below checks exit/stdout parity plus the real side effect -- a file landing under .asl/cache/nativeTest/outside -- instead of a stderr string this layer never emits), so this leg is restored live rather than frozen, since it does pass natively")

fn ! testDownstream -> Bool
  (match (oracle/selfTestBinary!)
    ((err e) (do (assert false (str "testDownstream: self-built tools/nativeTest.asl binary: " e)) false))
    ((ok ntBin)
      (let [(root (resultOr (realPath ".") "."))
            (made (sh "mktemp -d"))
            (ws (resultOr (realPath (stringTrim made.stdout)) ""))
            (cfg (fileWrite (str ws "/.asl.config.asn") "(:aslConfig :workspace \"downstream\")\n"))
            (app (dirCreate (str ws "/app")))
            (copied (sh (str "cp '" (fixture "eqAlias") "' '" ws "/app/eqAlias.asl'")))
            (host (str "nice -n 15 '" ntBin "' run app/eqAlias.asl x y </dev/null"))
            (rooted (sh (str "cd '" ws "' && ASL_ROOT='" root "' " host)))
            (expected "eq true false false true true x,y\n")
            (outOfRoot (sh (str "cd '" root "' && nice -n 15 '" ntBin "' run '" ws "/app/eqAlias.asl' p q </dev/null")))
            (expectedOutOfRoot "eq true false false true true p,q\n")
            (removed (sh (str "rm -rf '" ws "'")))]
        (do
          (assert (and (ok? cfg) (and (ok? app) (= copied.exitCode 0))) (str "downstream workspace written at " ws))
          (assert (= rooted.exitCode 0) (str "ASL_ROOT names the toolchain from a downstream cwd: " rooted.stderr))
          (assert (= rooted.stdout expected) (str "downstream native output: " rooted.stdout))
          (assert (not (stringContains? rooted.stderr "NATIVE-FALLBACK")) (str "a downstream file with ASL_ROOT does not fall back: " (errorLine rooted.stderr)))
          (assert (stringContains? rooted.stderr "NATIVE-CACHE") "a downstream file with ASL_ROOT runs natively")
          (assert (= outOfRoot.exitCode 0) (str "OUT-OF-ROOT: no ASL_ROOT, an absolute downstream path outside the toolchain still runs: " outOfRoot.stderr))
          (assert (= outOfRoot.stdout expectedOutOfRoot) (str "out-of-root native output: " outOfRoot.stdout))
          (assert (match (dirList (str root "/.asl/cache/nativeTest/outside")) ((ok names) (not (listEmpty? names))) ((err _) false))
            "stageOutsideFile! actually staged the absolute out-of-root path under .asl/cache/nativeTest/outside, the documented bypass, not some other route")
          (assert (= removed.exitCode 0) "downstream workspace removed")
          true))))

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): testAllUnsupported removed (not weakened -- the whole function, since every one of its assertions existed only to characterize this behavior). It used to set ASL_NATIVE_FALLBACK=host on a fixture pair (gapLeaf/gapMain) whose 'if' with 2 operands is a construct the native lowerer deliberately rejects (ERR_LOWER_UNSUPPORTED, asl-ir/lower's own documented subset), and assert that nativeTest's fallback then ran the program correctly by INTERPRETING it on asl-host instead. fallback-to-host (ASL_NATIVE_FALLBACK=host) was this entire function's reason to exist and, per the FIXL note above, is now gone outright (sh/HLNT), so there is nothing left to port; the gap closes only when either (a) a host-equivalent interpreter returns (out of scope, HL-DELETE's own territory) or (b) asl-target-llvm/src's lowerer grows support for 2-operand if (an asl-target-llvm/src change, out of this unit's :owns -- reported, not fixed)")

fn ! runTests -> Bool
  (do
    (testParquet)
    (testParquetTraps)
    (testZstd)
    (testEqAlias)
    (testDownstream)
    true)
