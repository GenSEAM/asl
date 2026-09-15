(module asl-compiler/wasiAbiTest
  :d "Unit tests for pure ASL WASI Preview 1 ABI definitions and Section 2 import framing."
  :x [testWasiDescriptors
      testWasiErrnoMapping
      testWasiOpenFlagsAndFileTypes
      testWasiImportsAndSectionFraming
      testFunctionIndexOffsetWithImports
      runTests]
  :i [(ast :a a) (wasm :a w) (wasi :a wasi)])

(df testWasiDescriptors [] -> Bool
  :d "Verifies standard WASI file descriptor constants."
  (do
    (assert (= (wasi/wasiFdStdin) 0) "Stdin descriptor must be 0")
    (assert (= (wasi/wasiFdStdout) 1) "Stdout descriptor must be 1")
    (assert (= (wasi/wasiFdStderr) 2) "Stderr descriptor must be 2")
    (assert (= (wasi/wasiFdPreopenStart) 3) "First preopened directory descriptor must be 3")
    (refute (= (wasi/wasiFdStdout) (wasi/wasiFdStderr)) "Stdout and stderr must not be equal")
    (refute (< (wasi/wasiFdPreopenStart) 3) "Preopen descriptor start must not be less than 3")
    true))

(df testWasiErrnoMapping [] -> Bool
  :d "Verifies canonical WASI errno mappings and dual-polarity refutations."
  (do
    (assert (= (wasi/wasiErrno "ESUCCESS") 0) "ESUCCESS must be 0")
    (assert (= (wasi/wasiErrnoName 0) "ESUCCESS") "Code 0 must be ESUCCESS")
    (assert (= (wasi/wasiErrno "EBADF") 8) "EBADF must be 8")
    (assert (= (wasi/wasiErrnoName 8) "EBADF") "Code 8 must be EBADF")
    (assert (= (wasi/wasiErrno "EEXIST") 20) "EEXIST must be 20")
    (assert (= (wasi/wasiErrnoName 20) "EEXIST") "Code 20 must be EEXIST")
    (assert (= (wasi/wasiErrno "EINVAL") 28) "EINVAL must be 28")
    (assert (= (wasi/wasiErrnoName 28) "EINVAL") "Code 28 must be EINVAL")
    (assert (= (wasi/wasiErrno "ENOENT") 44) "ENOENT must be 44")
    (assert (= (wasi/wasiErrnoName 44) "ENOENT") "Code 44 must be ENOENT")
    (assert (= (wasi/wasiErrno "ENOTDIR") 54) "ENOTDIR must be 54")
    (assert (= (wasi/wasiErrnoName 54) "ENOTDIR") "Code 54 must be ENOTDIR")
    (assert (= (wasi/wasiErrno "EPERM") 63) "EPERM must be 63")
    (assert (= (wasi/wasiErrnoName 63) "EPERM") "Code 63 must be EPERM")
    (assert (= (wasi/wasiErrno "ENOTCAPABLE") 76) "ENOTCAPABLE must be 76")
    (assert (= (wasi/wasiErrnoName 76) "ENOTCAPABLE") "Code 76 must be ENOTCAPABLE")
    (refute (= (wasi/wasiErrnoName 44) "ESUCCESS") "Code 44 must not be ESUCCESS")
    (refute (= (wasi/wasiErrnoName 8) "ESUCCESS") "Code 8 must not be ESUCCESS")
    (refute (= (wasi/wasiErrno "UNKNOWN_ERRNO") 0) "Unknown errno name must not return 0")
    true))

(df testWasiOpenFlagsAndFileTypes [] -> Bool
  :d "Verifies WASI open flags and file type constants."
  (do
    (assert (= (wasi/wasiOpenFlags "O_CREAT") 1) "O_CREAT must be 1")
    (assert (= (wasi/wasiOpenFlags "O_DIRECTORY") 2) "O_DIRECTORY must be 2")
    (assert (= (wasi/wasiOpenFlags "O_EXCL") 4) "O_EXCL must be 4")
    (assert (= (wasi/wasiOpenFlags "O_TRUNC") 8) "O_TRUNC must be 8")
    (refute (= (wasi/wasiOpenFlags "O_CREAT") 0) "O_CREAT flag must not be 0")
    (assert (= (wasi/wasiFileType "DIRECTORY") 3) "Directory file type must be 3")
    (assert (= (wasi/wasiFileType "REGULAR_FILE") 4) "Regular file type must be 4")
    (assert (= (wasi/wasiFileTypeName 3) "DIRECTORY") "Type 3 name must be DIRECTORY")
    (assert (= (wasi/wasiFileTypeName 4) "REGULAR_FILE") "Type 4 name must be REGULAR_FILE")
    (refute (= (wasi/wasiFileType "REGULAR_FILE") 0) "Regular file type must not be 0")
    true))

(df testWasiImportsAndSectionFraming [] -> Bool
  :d "Verifies WebAssembly Section 2 import framing for WASI Preview 1."
  (let [(importNames (wasi/wasiStandardImports))
        (entries (wasi/wasiStandardImportEntries))
        (importSec (w/encodeImportSection entries))]
    (assert (= (list-length importNames) 5) "Standard WASI preview 1 must define 5 imports")
    (refute (list-empty? importNames) "WASI imports list must not be empty")
    (assert (= (option-or (list-get importSec 0) -1) 2) "Import section must have section ID 2")
    (refute (!= (option-or (list-get importSec 0) -1) 2) "Import section ID must be strictly 2")
    (let [(singleEntry (w/encodeImportEntry "wasi_snapshot_preview1" "proc_exit" 0 3))]
      (assert (> (list-length singleEntry) 0) "Import entry must have non-zero length")
      (refute (list-empty? singleEntry) "Import entry must not be empty"))
    true))

(df testFunctionIndexOffsetWithImports [] -> Bool
  :d "Verifies that defined function indices are correctly offset by import count."
  (let [(parsed (a/parse "(df alpha [] -> I64 10) (df beta [] -> I64 20)"))]
    (mt parsed
      ((ok forms)
       (let [(idxNoOffset (w/buildFunctionTypeIndex forms))
             (idxWithImports (w/buildFunctionTypeIndexOffset forms 5))]
         (assert (= (option-or (map-get idxNoOffset "alpha") -1) 0) "First fn at offset 0 must be 0")
         (assert (= (option-or (map-get idxNoOffset "beta") -1) 1) "Second fn at offset 0 must be 1")
         (assert (= (option-or (map-get idxWithImports "alpha") -1) 5) "First fn with 5 imports must be 5")
         (assert (= (option-or (map-get idxWithImports "beta") -1) 6) "Second fn with 5 imports must be 6")
         (refute (= (option-or (map-get idxWithImports "alpha") -1) 0) "Offset fn index must not be 0")
         true))
      ((err _) false))))

(df runTests [] -> Bool
  :d "Runs all WASI ABI unit tests."
  (do
    (assert (testWasiDescriptors) "testWasiDescriptors must pass")
    (assert (testWasiErrnoMapping) "testWasiErrnoMapping must pass")
    (assert (testWasiOpenFlagsAndFileTypes) "testWasiOpenFlagsAndFileTypes must pass")
    (assert (testWasiImportsAndSectionFraming) "testWasiImportsAndSectionFraming must pass")
    (assert (testFunctionIndexOffsetWithImports) "testFunctionIndexOffsetWithImports must pass")
    true))
