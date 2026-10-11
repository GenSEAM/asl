(module asl-target-llvm/tests/nativeDataTest
  :x [runTests]
  :i [])

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/nativeData/" name ".asl")

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! nativeRun cache: String path: String args: String -> ProcessOutput
  (sh (str "ASL_NATIVE_TEST_CACHE='" cache "' nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " path " " args " </dev/null"))

fn ! hostRun path: String args: String -> ProcessOutput
  (sh (str "nice -n 15 asl/host/out/asl-host run " path " " args " </dev/null"))

fn errorLine text: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) (stringLines text))) "")

fn errorTail line: String -> String
  (mt (stringIndexOf line "ERR_")
    ((some i) (stringReplace (optionOr (stringSlice line i (stringLength line)) line) " (after 0 asserts)" ""))
    ((none) line))

fn ! sameAsHost what: String native: ProcessOutput host: ProcessOutput -> Bool
  (do
    (assert (= host.exitCode 0) (str what ": asl-host run exits 0: " host.stderr))
    (assert (= native.exitCode 0) (str what ": native run exits 0: " native.stderr))
    (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str what ": native run does not fall back: " (errorLine native.stderr) (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "NATIVE-FALLBACK")) (stringLines native.stderr))) "")))
    (assert (stringContains? native.stderr "NATIVE-CACHE") (str what ": the binary ran natively"))
    (assert (= native.stdout host.stdout) (str what ": native stdout equals asl-host run"))
    true)

fn ! testParquet cache: String -> Bool
  (let [(native (nativeRun cache (fixture "parquetProbe") ""))
        (host (hostRun (fixture "parquetProbe") ""))
        (out native.stdout)]
    (do
      (sameAsHost "parquetProbe" native host)
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

fn ! testParquetTraps cache: String -> Bool
  (fold (fn [(acc Bool) (which String)] -> Bool
          (let [(native (nativeRun cache (fixture "parquetTrap") which))
                (host (hostRun (fixture "parquetTrap") which))]
            (do
              (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str "trap " which ": native run does not fall back"))
              (assert (= native.exitCode 1) (str "trap " which ": native exits 1"))
              (assert (= native.exitCode host.exitCode) (str "trap " which ": exit equals asl-host run"))
              (assert (= native.stdout host.stdout) (str "trap " which ": stdout equals asl-host run"))
              (assert (not (stringEmpty? (errorLine host.stderr))) (str "trap " which ": asl-host names an error"))
              (assert (= (errorTail (errorLine native.stderr)) (errorTail (errorLine host.stderr))) (str "trap " which ": native error " (errorLine native.stderr) " equals asl-host " (errorLine host.stderr)))
              acc)))
        true (list "type" "column" "group"))

fn ! testZstd cache: String -> Bool
  (let [(native (nativeRun cache (fixture "zstdProbe") ""))
        (host (hostRun (fixture "zstdProbe") ""))]
    (do
      (sameAsHost "zstdProbe" native host)
      (assert (stringContains? native.stdout "decoded 93") "every zstd fixture is decoded or rejected")
      (assert (stringContains? native.stdout " err ERR_ZSTD_CORRUPT") "negative frames are rejected natively")
      true))

fn ! testEqAlias cache: String -> Bool
  (let [(native (nativeRun cache (fixture "eqAlias") "a b"))
        (host (hostRun (fixture "eqAlias") "a b"))]
    (do
      (sameAsHost "eqAlias" native host)
      (assert (= native.stdout "eq true false false true true a,b\n") (str "== lowers as = natively: " native.stdout))
      true))

fn ! testDownstream cache: String -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (made (sh "mktemp -d"))
        (ws (resultOr (realPath (stringTrim made.stdout)) ""))
        (cfg (fileWrite (str ws "/.asl.config.asn") "(:aslConfig :workspace \"downstream\")\n"))
        (app (dirCreate (str ws "/app")))
        (copied (sh (str "cp '" (fixture "eqAlias") "' '" ws "/app/eqAlias.asl'")))
        (host (str "nice -n 15 '" root "/asl/host/out/asl-host' run '" root "/tools/nativeTest.asl' run app/eqAlias.asl x y </dev/null"))
        (rooted (sh (str "cd '" ws "' && ASL_ROOT='" root "' ASL_NATIVE_TEST_CACHE='" cache "' " host)))
        (unrooted (sh (str "cd '" ws "' && env -u ASL_ROOT ASL_NATIVE_FALLBACK=host ASL_NATIVE_TEST_CACHE='" cache "' " host)))
        (cli (sh (str "ASL_NATIVE_TRACE=1 ASL_HOST_CACHE=0 ASL_NATIVE_TEST_CACHE='" cache "' nice -n 15 ./bin/asl run '" ws "/app/eqAlias.asl' x y </dev/null")))
        (expected "eq true false false true true x,y\n")
        (removed (sh (str "rm -rf '" ws "'")))]
    (do
      (assert (and (ok? cfg) (and (ok? app) (= copied.exitCode 0))) (str "downstream workspace written at " ws))
      (assert (= rooted.exitCode 0) (str "ASL_ROOT names the toolchain from a downstream cwd: " rooted.stderr))
      (assert (= rooted.stdout expected) (str "downstream native output: " rooted.stdout))
      (assert (not (stringContains? rooted.stderr "NATIVE-FALLBACK")) (str "a downstream file with ASL_ROOT does not fall back: " (errorLine rooted.stderr) (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "NATIVE-FALLBACK")) (stringLines rooted.stderr))) "")))
      (assert (stringContains? rooted.stderr "NATIVE-CACHE") "a downstream file with ASL_ROOT runs natively")
      (assert (stringContains? unrooted.stderr "NATIVE-FALLBACK app/eqAlias.asl: prelude load failed") "without ASL_ROOT a downstream cwd has no toolchain and says so")
      (assert (stringContains? unrooted.stderr "the running executable is never the host") (str "without ASL_ROOT and no ASL_HOST, the fallback refuses to run on the running asl-host (spawnSafety, FORKFIX L2): " unrooted.stderr))
      (assert (stringEmpty? unrooted.stdout) (str "without ASL_ROOT and no locatable host, nothing runs: " unrooted.stdout))
      (assert (= unrooted.exitCode 127) (str "without ASL_ROOT and no locatable host, the fallback exits with runFile's cannot-execute code: " unrooted.exitCode))
      (assert (= cli.exitCode 0) (str "asl run of an absolute downstream path exits 0: " cli.stderr))
      (assert (= cli.stdout expected) (str "asl run of an absolute downstream path: " cli.stdout))
      (assert (not (stringContains? cli.stderr "NATIVE-BYPASS")) "asl run routes a file under another workspace through nativeTest")
      (assert (not (stringContains? cli.stderr "NATIVE-FALLBACK")) "asl run of a downstream file does not fall back")
      (assert (stringContains? cli.stderr "NATIVE-CACHE") "asl run of a downstream file runs natively")
      (assert (= removed.exitCode 0) "downstream workspace removed")
      true))

fn ! testAllUnsupported cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_FALLBACK=host ASL_NATIVE_TEST_CACHE='" cache "' nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " (fixture "gapMain") " </dev/null")))
        (fallback (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "NATIVE-FALLBACK")) (stringLines native.stderr))) ""))]
    (do
      (assert (= native.stdout "gap leaf\ngap main\n") "the fallback runs the program")
      (assert (stringContains? fallback "compile unit failed: ") "the fallback names the failing units")
      (assert (stringContains? fallback "gapLeaf.leafNote") "the imported unit's ERR_LOWER_UNSUPPORTED is reported")
      (assert (stringContains? fallback "gapMain.main") "the entry unit's ERR_LOWER_UNSUPPORTED is reported in the same run")
      (assert (stringContains? fallback "(2 units)") "the fallback counts the failing units")
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (cache (stringTrim made.stdout))]
    (do
      (assert (= made.exitCode 0) "temporary native cache created")
      (testParquet cache)
      (testParquetTraps cache)
      (testZstd cache)
      (testEqAlias cache)
      (testDownstream cache)
      (testAllUnsupported cache)
      (assert (= (sh (str "rm -rf '" cache "'")).exitCode 0) "temporary native cache removed")
      true))
