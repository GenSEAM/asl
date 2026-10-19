(module asl-target-llvm/tests/nativeShaTest
  :x [runTests]
  :i [(tools/nativeTest :a nt)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): hostRun used to re-derive the FIPS 180-4 vectors by interpreting the probe through asl-host, but the probe is fully deterministic (fixed 1 MiB affine fill, fixed algorithm) and its expected stdout was already pinned to the literal vectors() below, so the host round-trip is dropped and native.stdout is compared straight to vectors(). nativeRun used to shell out to asl-host to run tools/nativeTest.asl as a subprocess; it now calls tools/nativeTest's own prepareRun/runProc in-process (the same pipeline tools/nativeTest.asl would have driven), which has zero host dependency even on a cold cache")

fn probe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativeSha/shaProbe.asl"

fn ! nativeRun -> nt/ProcOut
  (let [(built (nt/prepareRun (probe) "nativeShaTest"))]
    (mt built.binary
      ((none) (nt/ProcOut :exitCode 127 :stdout "" :stderr built.reason))
      ((some bin) (nt/runProc (list bin) (none)))))

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
  (let [(native (nativeRun))
        (ms (shaMs native.stderr))]
    (do
      (assert (= native.exitCode 0) (str "native sha probe exits 0: " native.stderr))
      (refute (stringContains? native.stderr "NATIVE-FALLBACK") (str "native sha probe does not fall back to a host: " native.stderr))
      (assert (= native.stdout (vectors)) (str "native digests of empty, abc and the 1 MB affine fill are the FIPS 180-4 values: " native.stdout))
      (assert (>= ms 0) (str "native probe reports shaMs: " native.stderr))
      (assert (< ms 50) (str "native bytesSha256 of 1 MB takes under 50 ms (best of 3), took " ms " ms"))
      true))
