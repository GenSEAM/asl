(module asl-parquet/tests/readerNativeTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty) (asl-target-llvm :a llvm) (tools/fleet/run :a run)])

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/readerNativeTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd " (shellQuote root) " && (" cmd ")) > " (shellQuote outPath) " 2> " (shellQuote errPath))) root
                                         (run/childEnv (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" prelude) (str "PATH=" path))))
                                 (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Captured
  (shWithin cmd 600)

fn fixturePath -> String
  "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-zstdPageV2.parquet"

fn driverSource -> String
  (stringJoin (list
    "(module readerNativeDriver :x [main] :i [(asl-parquet/reader :a r)])"
    ""
    "fn ! sumI64At arr: I64Array i: Int64 acc: Float64 -> Float64"
    "  (if (= i (i64ArrayLen arr)) acc (sumI64At arr (+ i 1) (+ acc (int64ToFloat64 (i64ArrayGet arr i)))))"
    ""
    "fn ! sumI8At arr: I8Array i: Int64 acc: Float64 -> Float64"
    "  (if (= i (i8ArrayLen arr)) acc (sumI8At arr (+ i 1) (+ acc (int64ToFloat64 (i8ArrayGet arr i)))))"
    ""
    "fn ! sumF64At arr: F64Array i: Int64 acc: Float64 -> Float64"
    "  (if (= i (f64ArrayLen arr)) acc (sumF64At arr (+ i 1) (+ acc (f64ArrayGet arr i))))"
    ""
    "fn ! columnI64Sum h: H name: String groups: Int64 rg: Int64 acc: Float64 -> Float64"
    "  (if (>= rg groups) acc (columnI64Sum h name groups (+ rg 1) (+ acc (sumI64At (r/parquetReadI64 h name rg) 0 0.0))))"
    ""
    "fn ! columnI8Sum h: H name: String groups: Int64 rg: Int64 acc: Float64 -> Float64"
    "  (if (>= rg groups) acc (columnI8Sum h name groups (+ rg 1) (+ acc (sumI8At (r/parquetReadI8 h name rg) 0 0.0))))"
    ""
    "fn ! columnF64Sum h: H name: String groups: Int64 rg: Int64 acc: Float64 -> Float64"
    "  (if (>= rg groups) acc (columnF64Sum h name groups (+ rg 1) (+ acc (sumF64At (r/parquetReadF64 h name rg) 0 0.0))))"
    ""
    "fn ! printColumn! h: H name: String groups: Int64 -> Bool"
    "  (let [(kind (r/parquetColumnType h name))]"
    "    (cond"
    "      ((= kind \"int64\") (do (println (str name \": \" (columnI64Sum h name groups 0 0.0))) true))"
    "      ((= kind \"int8\") (do (println (str name \": \" (columnI8Sum h name groups 0 0.0))) true))"
    "      ((= kind \"double\") (do (println (str name \": \" (columnF64Sum h name groups 0 0.0))) true))"
    "      (else (do (println (str name \": unsupported type \" kind)) true))))"
    ""
    "fn ! printColumns! h: H cols: (List C) groups: Int64 -> Bool"
    "  (mt (listHead cols)"
    "    ((some c) (and (printColumn! h c.name groups) (printColumns! h (optionOr (listTail cols) (list)) groups)))"
    "    (none true))"
    ""
    "fn ! main -> (Result Int64 String)"
    (str "  (mt (r/parquetOpen \"" (fixturePath) "\")")
    "    ((err e) (err (str \"parquetOpen failed: \" e)))"
    "    ((ok h)"
    "     (do (println (str \"rows: \" h.rows))"
    "         (printColumns! h h.cols (r/parquetNumRowGroups h))"
    "         (ok 0))))"
    "") "\n")

fn formatDiags ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String
                       (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! clangBin -> String
  (let [(c (optionOr (envGet "CLANG") ""))] (if (stringEmpty? c) "clang" c))

fn ! compileNative path: String llPath: String exePath: String -> Captured
  (mt (lk/linkEntry! path)
    ((err ds) (Captured :exitCode 1 :stdout "" :stderr (str "link failed: " (formatDiags ds))))
    ((ok m)
      (mt (llvm/emitLlvmProgramNative! m "readerNativeDriver.main")
        ((err ds) (Captured :exitCode 1 :stdout "" :stderr (str "LLVM emission failed: " (formatDiags ds))))
        ((ok code)
          (do
            (fileWrite llPath code)
            (sh (str "nice -n 15 " (clangBin) " -O2 -Wno-override-module -x ir " (shellQuote llPath)
                    " -x none asl/host/out/libaslrt.a -lm -o " (shellQuote exePath))))))))

fn ! testReaderNative -> Bool
  (let [(dir (str "asl/packages/asl-parquet/tests/.tmp-reader-native-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (path (str dir "/readerNativeDriver.asl"))
        (llPath (str dir "/readerNativeDriver.ll"))
        (exePath (str dir "/readerNativeDriver"))
        (written (fileWrite path (driverSource)))
        (buildStart (monotonicNs))
        (native (if (and (ok? made) (ok? written)) (compileNative path llPath exePath)
                    (Captured :exitCode 1 :stdout "" :stderr "fixture setup failed")))
        (buildEnd (monotonicNs))
        (hostStart (monotonicNs))
        (interp (sh (str (shellQuote (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host")) " run " (shellQuote path))))
        (hostEnd (monotonicNs))
        (nativeStart (monotonicNs))
        (ran (if (= native.exitCode 0) (sh (shellQuote exePath))
                 (Captured :exitCode 1 :stdout "" :stderr native.stderr)))
        (nativeEnd (monotonicNs))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedSrc (if (fileExists? path) (pathRemove path) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "temporary driver directory is created")
      (assert (ok? written) "driver source is written")
      (assert (= native.exitCode 0) (str "linkEntry! lowers the parquet reader driver and links natively: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run exits 0 on the driver: " interp.stderr))
      (assert (= ran.exitCode interp.exitCode) "native driver exit matches asl-host run")
      (assert (= ran.stdout interp.stdout) "native driver's per-column sums match asl-host run, column by column")
      (assert (= ran.exitCode 0) (str "native driver reads every column without error: " ran.stderr))
      (println (str "readerNativeTest: build " (/ (- buildEnd buildStart) 1000000) "ms, asl-host run " (/ (- hostEnd hostStart) 1000000)
                     "ms, native run " (/ (- nativeEnd nativeStart) 1000000) "ms"))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "driver source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testReaderNative) "a driver over asl-parquet/reader.asl linked via lk/linkEntry! and compiled to native code prints the same per-column sums as asl-host run")
    true)
