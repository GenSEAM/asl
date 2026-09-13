(module asl-compiler/wasi-runtime-test
  :d "End-to-end dynamic WASI runtime execution, Git VFS verification, and task registration tests."
  :x [testDynamicWasiStdoutExecution
      testDynamicWasiFileIo
      testDynamicWasiGitVfsRead
      testDynamicWasiCapabilityDenial
      testTaskRegistrationFile
      runTests]
  :i [(ast :a a) (wasm :a w) (wasi :a wasi) (vfs_git :a vfs)])

(df testDynamicWasiStdoutExecution [] -> Bool
  :d "Dynamically executes a compiled WASI module under Node.js Preview 1 host and verifies stdout and exit code 0."
  (let [(src "(df main [] -> Unit (do (fd_write 1 16 1 24) (proc_exit 0)))")
        (parseRes (a/parse src))]
    (assert (= (.-_tag parseRes) "ok") "Parsing WASI source program must succeed")
    (mt parseRes
      ((ok forms)
       (let [(byteCsv (w/emitWasiBinaryTarget forms))
             (bytePath "/tmp/wasi_dynamic_compiled.txt")
             (wByteRes (file-write bytePath byteCsv))]
         (assert (= (.-_tag wByteRes) "ok") "Writing dynamically compiled WASI bytecode must succeed")
         (refute (!= (.-_tag wByteRes) "ok") "Bytecode write must not fail")
         (assert (> (string-length byteCsv) 0) "Bytecode string must not be empty")
         (let [(jsRunner (str "const { WASI } = require('wasi')\n"
                              "const fs = require('fs')\n"
                              "const wasi = new WASI({ version: 'preview1', args: ['prog'], env: {}, preopens: { '/tmp': '/tmp' } })\n"
                              "const raw = fs.readFileSync('/tmp/wasi_dynamic_compiled.txt', 'utf8').trim()\n"
                              "const bytes = raw.split(',').map(Number)\n"
                              "const wasmBytes = new Uint8Array(bytes)\n"
                              "const mod = new WebAssembly.Module(wasmBytes)\n"
                              "const inst = new WebAssembly.Instance(mod, { wasi_snapshot_preview1: wasi.wasiImport })\n"
                              "const exitCode = wasi.start(inst)\n"
                              "console.log('WASI_EXIT_CODE:' + exitCode)\n"))
               (wRes (file-write "/tmp/run_dynamic_wasi.js" jsRunner))]
           (assert (= (.-_tag wRes) "ok") "Writing dynamic runner script to /tmp must succeed")
           (let [(execRes (sys-exec "/usr/local/bin/node /tmp/run_dynamic_wasi.js"))
                 (code (.-exitCode execRes))
                 (out (.-stdout execRes))]
             (assert (= code 0) (str "Node WASI dynamic execution exitCode: " (string-from-int64 code) ", stdout: " out))
             (refute (!= code 0) "Node WASI dynamic execution must not fail")
             (assert (string-contains? out "Hello, WASI!") "Dynamic output must contain string emitted via WASI fd_write")
             (assert (string-contains? out "WASI_EXIT_CODE:0") "Module must exit with code 0 via proc_exit")
             (refute (string-contains? out "WASI_EXIT_CODE:42") "Module must not exit with non-zero code")
             true))))
      ((err _) false))))

(df testDynamicWasiFileIo [] -> Bool
  :d "Verifies live WASI file I/O operations and error reporting against actual disk."
  (let [(testFile "/tmp/test_wasi_runtime_verified.txt")
        (testContent "WASI_RUNTIME_CONTENT_VERIFIED_50706")
        (wRes (wasi/wasiFileWrite testFile testContent))]
    (assert (= (.-_tag wRes) "ok") "wasiFileWrite must succeed")
    (refute (= (.-_tag wRes) "err") "wasiFileWrite must not fail")
    (assert (wasi/wasiFileExists? testFile) "wasiFileExists? must return true for written file")
    (refute (not (wasi/wasiFileExists? testFile)) "wasiFileExists? must not report false")
    (let [(rRes (wasi/wasiFileRead testFile))]
      (assert (= (.-_tag rRes) "ok") "wasiFileRead must succeed")
      (mt rRes
        ((ok text)
         (do
           (assert (= text testContent) "Read content must identically match written content")
           (refute (!= text testContent) "Content must not be corrupted")
           true))
        ((err _) false)))
    (let [(nonExistentRes (wasi/wasiFileRead "/tmp/definitely_missing_file_99999.txt"))]
      (assert (= (.-_tag nonExistentRes) "err") "Reading non-existent file must return err")
      (refute (= (.-_tag nonExistentRes) "ok") "Reading non-existent file must not return ok")
      (mt nonExistentRes
        ((err errMsg)
         (do
           (assert (string-contains? errMsg "ENOENT") "Error message must cite ENOENT")
           (refute (string-empty? errMsg) "Error message must not be empty")
           true))
        ((ok _) false)))
    true))

(df testDynamicWasiGitVfsRead [] -> Bool
  :d "Verifies pure ASL Git VFS reader on active repository matching ground truth."
  (let [(branchRes (vfs/gitCurrentBranch ""))
        (commitRes (vfs/gitHeadCommit ""))
        (statusMap (vfs/gitInspectRepoStatus ""))]
    (assert (= (.-_tag branchRes) "ok") "gitCurrentBranch must succeed on active repo")
    (refute (= (.-_tag branchRes) "err") "gitCurrentBranch must not fail")
    (mt branchRes
      ((ok bName)
       (do
         (assert (> (string-length bName) 0) "Branch name must not be empty")
         (refute (string-empty? bName) "Branch name must have length > 0")
         true))
      ((err _) false))
    (assert (= (.-_tag commitRes) "ok") "gitHeadCommit must succeed on active repo")
    (refute (= (.-_tag commitRes) "err") "gitHeadCommit must not fail")
    (mt commitRes
      ((ok sha)
       (do
         (assert (= (string-length sha) 40) "Commit SHA must be 40 characters")
         (refute (!= (string-length sha) 40) "Commit SHA must not be truncated or elongated")
         true))
      ((err _) false))
    (assert (= (option-or (map-get statusMap "status") "") "clean") "gitInspectRepoStatus must report clean")
    (refute (map-empty? statusMap) "Status map must not be empty")
    (let [(badRepoRes (vfs/gitReadHead "/tmp/non_existent_git_repo_99999"))]
      (assert (= (.-_tag badRepoRes) "err") "gitReadHead on non-existent repo must fail")
      (refute (= (.-_tag badRepoRes) "ok") "gitReadHead on non-existent repo must not succeed")
      true)))

(df testDynamicWasiCapabilityDenial [] -> Bool
  :d "Verifies sandboxed capability boundary intercepting sys-exec and returning typed denial."
  (let [(sandboxedCaps (wasi/sandboxedWasiCapabilities))
        (receipt (wasi/wasiSysExec "whoami" sandboxedCaps))]
    (assert (not (wasi/wasiCapabilityCheck "execCmd" sandboxedCaps)) "execCmd must not be granted in sandbox")
    (refute (wasi/wasiCapabilityCheck "execCmd" sandboxedCaps) "Sandbox must not allow execCmd")
    (assert (= (option-or (map-get receipt "status") "") "refused") "Status must be refused")
    (refute (= (option-or (map-get receipt "status") "") "ok") "Status must not be ok")
    (assert (= (option-or (map-get receipt "code") -1) 126) "Refusal code must be 126")
    (refute (!= (option-or (map-get receipt "code") -1) 126) "Code must not deviate from 126")
    (let [(stderrText (option-or (map-get receipt "stderr") ""))]
      (assert (string-contains? stderrText "ERR_CAPABILITY_DENIED") "Stderr must cite ERR_CAPABILITY_DENIED")
      (refute (string-empty? stderrText) "Stderr must not be empty")
      true)))

(df testTaskRegistrationFile [] -> Bool
  :d "Verifies that Phase507PureAslWasiRuntime.asn is registered and contains all 6 phase tasks."
  (let [(path ".asl/mem/tasks/Phase507PureAslWasiRuntime.asn")
        (readRes (file-read path))]
    (assert (= (.-_tag readRes) "ok") "Phase 507 task collection file must be readable")
    (refute (= (.-_tag readRes) "err") "Phase 507 task collection file must not fail to read")
    (mt readRes
      ((ok content)
       (do
         (assert (string-contains? content "Phase507PureAslWasiRuntime") "Task file must define Phase507PureAslWasiRuntime")
         (assert (string-contains? content "Task50701") "Task file must include Task50701")
         (assert (string-contains? content "Task50702") "Task file must include Task50702")
         (assert (string-contains? content "Task50703") "Task file must include Task50703")
         (assert (string-contains? content "Task50704") "Task file must include Task50704")
         (assert (string-contains? content "Task50705") "Task file must include Task50705")
         (assert (string-contains? content "Task50706") "Task file must include Task50706")
         (refute (string-contains? content "Task50799") "Task file must not contain non-existent task")
         (refute (string-empty? content) "Task file content must not be empty")
         true))
      ((err _) false))))

(df runTests [] -> Bool
  :d "Runs all WASI dynamic runtime, VFS, capability, and task registration tests."
  (do
    (assert (testDynamicWasiStdoutExecution) "testDynamicWasiStdoutExecution must pass")
    (assert (testDynamicWasiFileIo) "testDynamicWasiFileIo must pass")
    (assert (testDynamicWasiGitVfsRead) "testDynamicWasiGitVfsRead must pass")
    (assert (testDynamicWasiCapabilityDenial) "testDynamicWasiCapabilityDenial must pass")
    (assert (testTaskRegistrationFile) "testTaskRegistrationFile must pass")
    true))
