(module asl-target-llvm/tests/nativeShaTest
  :x [runTests]
  :i [])

fn probe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativeSha/shaProbe.asl"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! nativeRun cache: String -> ProcessOutput
  (sh (str "ASL_NATIVE_TEST_CACHE='" cache "' nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " (probe) " </dev/null"))

fn ! hostRun -> ProcessOutput
  (sh (str "nice -n 15 asl/host/out/asl-host run " (probe) " </dev/null"))

fn shaMs stderr: String -> Int64
  (mt (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "shaMs ")) (stringLines stderr)))
    ((none) -1)
    ((some line) (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 6 (stringLength line)) ""))) -1)))

fn vectors -> String
  (stringJoin (list "empty e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                    "abc ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                    "data b7f7ba5ce5463b3c84a283f779d7a652cbf99122de5923ba51627607ff1497d5"
                    "") "\n")

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (cache (stringTrim made.stdout))
        (native (nativeRun cache))
        (host (hostRun))
        (ms (shaMs native.stderr))]
    (do
      (assert (= made.exitCode 0) "temporary native cache created")
      (assert (= native.exitCode 0) (str "native sha probe exits 0: " native.stderr))
      (refute (stringContains? native.stderr "NATIVE-FALLBACK") (str "native sha probe does not fall back to asl-host: " native.stderr))
      (assert (= host.exitCode 0) (str "asl-host sha probe exits 0: " host.stderr))
      (assert (= host.stdout (vectors)) (str "asl-host digests of empty, abc and the 1 MB affine fill are the FIPS 180-4 values: " host.stdout))
      (assert (= native.stdout host.stdout) (str "native digests equal asl-host's: " native.stdout))
      (assert (>= ms 0) (str "native probe reports shaMs: " native.stderr))
      (assert (< ms 50) (str "native bytesSha256 of 1 MB takes under 50 ms (best of 3), took " ms " ms"))
      (assert (= (sh (str "rm -rf '" cache "'")).exitCode 0) "temporary native cache removed")
      true))
