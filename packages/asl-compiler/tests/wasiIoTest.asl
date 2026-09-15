(module asl-compiler/wasiIoTest
  :d "Unit tests for pure ASL WASI file I/O operations and vectorized ciovec buffer layout."
  :x [testEncodeCiovec
      testWasiFileRoundtrip
      testWasiNonExistentFileHandling
      testWasiPathOpenOflags
      testWasiFdWriteValidation
      testWasiDirListAndStat
      runTests]
  :i [(wasi :a wasi)])

(df testEncodeCiovec [] -> Bool
  :d "Verifies that encodeCiovec emits strictly 8 little-endian bytes."
  (let [(vec (wasi/encodeCiovec 65536 10))]
    (assert (= (list-length vec) 8) "encodeCiovec must produce strictly 8 bytes")
    (refute (!= (list-length vec) 8) "Vector byte length must not deviate from 8")
    (assert (= (option-or (list-get vec 0) -1) 0) "Pointer byte 0 must be 0")
    (assert (= (option-or (list-get vec 1) -1) 0) "Pointer byte 1 must be 0")
    (assert (= (option-or (list-get vec 2) -1) 1) "Pointer byte 2 must be 1 (65536 = 0x00010000)")
    (assert (= (option-or (list-get vec 3) -1) 0) "Pointer byte 3 must be 0")
    (assert (= (option-or (list-get vec 4) -1) 10) "Length byte 0 must be 10")
    (assert (= (option-or (list-get vec 5) -1) 0) "Length byte 1 must be 0")
    (assert (= (option-or (list-get vec 6) -1) 0) "Length byte 2 must be 0")
    (assert (= (option-or (list-get vec 7) -1) 0) "Length byte 3 must be 0")
    (let [(vecZero (wasi/encodeCiovec 0 0))]
      (assert (= (list-length vecZero) 8) "Zero vector must also be 8 bytes")
      (refute (!= (list-length vecZero) 8) "Zero vector length must be 8"))
    true))

(df testWasiFileRoundtrip [] -> Bool
  :d "Verifies roundtrip file write and read using WASI filesystem primitives."
  (let [(path "tmp/wasi_roundtrip.txt")
        (content "Hello WASI Sovereign Filesystem Roundtrip 42\n")
        (writeRes (wasi/wasiFileWrite path content))]
    (assert (= (.-_tag writeRes) "ok") (str "wasiFileWrite must succeed, got: " (option-or (mt writeRes ((err e) (some e)) ((ok _) (none))) "")))
    (refute (!= (.-_tag writeRes) "ok") "wasiFileWrite must not return error")
    (assert (wasi/wasiFileExists? path) "Written file must exist")
    (let [(readRes (wasi/wasiFileRead path))]
      (mt readRes
        ((ok text)
         (do
           (assert (= text content) "Read content must match written content")
           (refute (!= text content) "Read content must not diverge")
           true))
        ((err _) false)))))

(df testWasiNonExistentFileHandling [] -> Bool
  :d "Verifies error reporting on non-existent files."
  (let [(missingPath "tmp/non_existent_file_987654.txt")]
    (assert (not (wasi/wasiFileExists? missingPath)) "Missing path must not exist")
    (refute (wasi/wasiFileExists? missingPath) "wasiFileExists? must return false for missing path")
    (let [(readRes (wasi/wasiFileRead missingPath))]
      (mt readRes
        ((ok _) false)
        ((err code)
         (do
           (assert (= code "ENOENT") "Error code must be ENOENT")
           (refute (= code "ESUCCESS") "Error code must not be ESUCCESS")
           true))))))

(df testWasiPathOpenOflags [] -> Bool
  :d "Verifies path_open flag semantics including O_CREAT and ENOENT rejection."
  (let [(missingPath "tmp/open_missing_test_123.txt")
        (openNoCreat (wasi/wasiPathOpen 3 missingPath 0))]
    (assert (= (.-_tag openNoCreat) "err") "Opening missing path without O_CREAT must fail")
    (refute (= (.-_tag openNoCreat) "ok") "Opening missing path without O_CREAT must not succeed")
    (mt openNoCreat
      ((ok _) false)
      ((err code) (assert (= code "ENOENT") "Failure code must be ENOENT")))
    (let [(invalidDirFd (wasi/wasiPathOpen 1 "some_path.txt" 0))]
      (assert (= (.-_tag invalidDirFd) "err") "Opening with stdout fd must return error")
      (refute (= (.-_tag invalidDirFd) "ok") "Opening with stdout fd must not succeed")
      (mt invalidDirFd
        ((ok _) false)
        ((err code) (assert (= code "EBADF") "Invalid dir fd must report EBADF"))))
    true))

(df testWasiFdWriteValidation [] -> Bool
  :d "Verifies rejection of invalid and closed descriptors under D77."
  (let [(resNeg (wasi/wasiFdWrite -1 "hello"))
        (resStdin (wasi/wasiFdWrite 0 "hello"))
        (resClosed (wasi/wasiFdWrite 99 "hello"))
        (resStdout (wasi/wasiFdWrite 1 "test stdout\n"))]
    (assert (= (.-_tag resNeg) "err") "Writing to negative fd must fail")
    (refute (= (.-_tag resNeg) "ok") "Negative fd must not succeed")
    (assert (= (.-_tag resStdin) "err") "Writing to stdin fd must fail")
    (refute (= (.-_tag resStdin) "ok") "Stdin fd must not succeed for write")
    (assert (= (.-_tag resClosed) "err") "Writing to invalid fd 99 must fail")
    (refute (= (.-_tag resClosed) "ok") "Invalid fd must not succeed")
    (assert (= (.-_tag resStdout) "ok") "Writing to stdout fd must succeed")
    (refute (!= (.-_tag resStdout) "ok") "Stdout write must not fail")
    true))

(df testWasiDirListAndStat [] -> Bool
  :d "Verifies directory listing and file stat queries."
  (let [(entries (wasi/wasiDirList "asl/packages/asl-compiler/src"))]
    (assert (not (list-empty? entries)) "Source directory must contain entries")
    (refute (list-empty? entries) "Source directory entry list must not be empty")
    (let [(stOpt (wasi/wasiFileStat "asl/packages/asl-compiler/src/wasi.asl"))]
      (mt stOpt
        ((some st)
         (do
           (assert (= (option-or (map-get st "filetype") -1) 4) "wasi.asl must have filetype REGULAR_FILE (4)")
           (refute (= (option-or (map-get st "filetype") -1) 3) "wasi.asl must not be a directory")
           (assert (> (option-or (map-get st "size") -1) 0) "wasi.asl size must be greater than 0")
           true))
        ((none) false)))))

(df testWasiFdTableLifecycle [] -> Bool
  :d "Verifies dynamic allocation, I/O, and closure of descriptors in the real FD table."
  (let [(filePath "tmp/wasi_fd_lifecycle.txt")
        (openRes (wasi/wasiPathOpen 3 filePath 1))]
    (assert (= (.-_tag openRes) "ok") "wasiPathOpen with O_CREAT must succeed")
    (refute (!= (.-_tag openRes) "ok") "wasiPathOpen must not fail")
    (mt openRes
      ((ok fd)
       (do
         (assert (>= fd 4) "Allocated file descriptor must be >= 4")
         (refute (< fd 4) "Allocated descriptor must not collide with standard descriptors")
         (let [(wRes (wasi/wasiFdWrite fd "Dynamic FD Table Data\n"))]
           (assert (= (.-_tag wRes) "ok") "wasiFdWrite must succeed on open descriptor")
           (refute (!= (.-_tag wRes) "ok") "wasiFdWrite must not fail")
           (let [(closeRes (wasi/wasiFdClose fd))]
             (assert (= (.-_tag closeRes) "ok") "wasiFdClose must succeed on open descriptor")
             (refute (!= (.-_tag closeRes) "ok") "wasiFdClose must not fail")
             (let [(postCloseWrite (wasi/wasiFdWrite fd "after close"))
                   (postCloseClose (wasi/wasiFdClose fd))]
               (assert (= (.-_tag postCloseWrite) "err") "wasiFdWrite must reject closed descriptor")
               (refute (= (.-_tag postCloseWrite) "ok") "Closed descriptor must not permit writes")
               (assert (= (.-_tag postCloseClose) "err") "wasiFdClose must reject already closed descriptor")
               (refute (= (.-_tag postCloseClose) "ok") "Already closed descriptor must not close twice")
               true)))))
      ((err _) false))))

(df runTests [] -> Bool
  :d "Runs all WASI I/O unit tests."
  (do
    (assert (testEncodeCiovec) "testEncodeCiovec must pass")
    (assert (testWasiFileRoundtrip) "testWasiFileRoundtrip must pass")
    (assert (testWasiNonExistentFileHandling) "testWasiNonExistentFileHandling must pass")
    (assert (testWasiPathOpenOflags) "testWasiPathOpenOflags must pass")
    (assert (testWasiFdWriteValidation) "testWasiFdWriteValidation must pass")
    (assert (testWasiDirListAndStat) "testWasiDirListAndStat must pass")
    (assert (testWasiFdTableLifecycle) "testWasiFdTableLifecycle must pass")
    true))
