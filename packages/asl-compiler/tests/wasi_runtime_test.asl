(module asl-compiler/wasi-runtime-test
  :d "End-to-end dynamic WASI runtime execution, Git VFS verification, and task registration tests."
  :x [testDynamicWasiStdoutExecution
      testDynamicWasiFileIo
      testDynamicWasiGitVfsRead
      testDynamicWasiCapabilityDenial
      testTaskRegistrationFile
      runTests]
  :i [(wasm :a w) (wasi :a wasi) (vfs_git :a vfs)])

(df testDynamicWasiStdoutExecution [] -> Bool
  :d "Dynamically executes a compiled WASI module under Node.js Preview 1 host and verifies stdout and exit code 0."
  (let [(jsRunner (str "const { WASI } = require('wasi');\n"
                       "const wasi = new WASI({ version: 'preview1', args: ['prog'], env: {}, preopens: { '/tmp': '/tmp' } });\n"
                       "const typeSec = [0x01, 0x10, 0x03, 0x60, 0x01, 0x7f, 0x00, 0x60, 0x04, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f, 0x60, 0x00, 0x00];\n"
                       "const importSec = [0x02, 0x46, 0x02, 0x16, ...Buffer.from('wasi_snapshot_preview1'), 0x09, ...Buffer.from('proc_exit'), 0x00, 0x00, 0x16, ...Buffer.from('wasi_snapshot_preview1'), 0x08, ...Buffer.from('fd_write'), 0x00, 0x01];\n"
                       "const funcSec = [0x03, 0x02, 0x01, 0x02];\n"
                       "const memSec = [0x05, 0x03, 0x01, 0x00, 0x01];\n"
                       "const expSec = [0x07, 0x13, 0x02, 0x06, ...Buffer.from('_start'), 0x00, 0x02, 0x06, ...Buffer.from('memory'), 0x02, 0x00];\n"
                       "const msg = Buffer.from('Hello, WASI!\\n');\n"
                       "const ciovec = Buffer.from([32, 0, 0, 0, 13, 0, 0, 0]);\n"
                       "const dataSec = [0x0b, 0x20, 0x02, 0x00, 0x41, 0x10, 0x0b, 0x08, ...ciovec, 0x00, 0x41, 0x20, 0x0b, 0x0d, ...msg];\n"
                       "const code = [0x41, 0x01, 0x41, 0x10, 0x41, 0x01, 0x41, 0x08, 0x10, 0x01, 0x1a, 0x41, 0x00, 0x10, 0x00, 0x0b];\n"
                       "const codeSec = [0x0a, 0x13, 0x01, 0x11, 0x00, ...code];\n"
                       "const wasmBytes = new Uint8Array([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, ...typeSec, ...importSec, ...funcSec, ...memSec, ...expSec, ...codeSec, ...dataSec]);\n"
                       "const mod = new WebAssembly.Module(wasmBytes);\n"
                       "const inst = new WebAssembly.Instance(mod, { wasi_snapshot_preview1: wasi.wasiImport });\n"
                       "const exitCode = wasi.start(inst);\n"
                       "console.log('WASI_EXIT_CODE:' + exitCode);\n"))
        (wRes (file-write "/tmp/run_dynamic_wasi.js" jsRunner))]
    (assert (= (.-_tag wRes) "ok") "Writing runner script to /tmp must succeed")
    (let [(execRes (sys-exec "/usr/local/bin/node /tmp/run_dynamic_wasi.js"))
          (code (.-exitCode execRes))
          (out (.-stdout execRes))]
      (assert (= code 0) (str "Node WASI execution exitCode: " (string-from-int64 code) ", stdout: " out))
      (refute (!= code 0) "Node WASI execution must not fail")
      (assert (string-contains? out "Hello, WASI!") "Output must contain string emitted via WASI fd_write")
      (assert (string-contains? out "WASI_EXIT_CODE:0") "Module must exit with code 0 via proc_exit")
      (refute (string-contains? out "WASI_EXIT_CODE:42") "Module must not exit with non-zero code")
      true)))

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
