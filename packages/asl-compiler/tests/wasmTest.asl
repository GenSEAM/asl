(module asl-compiler/wasmTest
  :d "Dynamic end-to-end WebAssembly engine validation, execution and refutation test suite."
  :x [testWasmBinaryValidation
      testWasmFunctionExecution
      testWasmDualPolarityRefutations
      runTests]
  :i [(ast :a a) (wasm :a w)])

(df bytesToCsv [(bytes (List Int64))] -> Str
  :d "Formats byte vector to comma-separated integer string for node execution."
  (string-join (map (fn [(b Int64)] -> Str (string-from-int64 b)) bytes) ","))

(df testWasmBinaryValidation [] -> Bool
  :d "Verifies that emitted Wasm modules strictly validate under standard WebAssembly engines."
  (let [(src "(df test-val [(x I64)] -> I64 (* x 3))")
        (parsed (a/parse src))]
    (mt parsed
      ((ok forms)
       (let [(bytes (w/emitWasmBinaryBytes forms))
             (csv (bytesToCsv bytes))
             (cmd (str "node -e 'const b = new Uint8Array([" csv "]); if (!WebAssembly.validate(b)) process.exit(1); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (!inst.exports.memory) process.exit(2); const p1 = inst.exports.aslAlloc(100); if (p1 <= 0) process.exit(3); if (typeof inst.exports.aslRpcDispatch !== \"function\") process.exit(4);'"))
             (res (sysExec cmd))]
         (assert (= (.-exitCode res) 0) (str "Validation and runtime bridge failed, stderr: " (.-stderr res)))
         (refute (!= (.-exitCode res) 0) "Emitted module must pass WebAssembly.validate and export bridge")
         true))
      ((err _) false))))

(df testWasmFunctionExecution [] -> Bool
  :d "Dynamically executes compiled arithmetic, comparison, and conditional functions in Node.js V8."
  (let [(src "(df add-nums [(a I64) (b I64)] -> I64 (+ a b)) (df mult-nums [(x I64) (y I64)] -> I64 (* x y)) (df sub-nums [(x I64) (y I64)] -> I64 (- x y)) (df clamp-val [(v I64) (low I64) (high I64)] -> I64 (if (< v low) low (if (> v high) high v)))")
        (parsed (a/parse src))]
    (mt parsed
      ((ok forms)
       (let [(bytes (w/emitWasmBinaryBytes forms))
             (csv (bytesToCsv bytes))
             (cmd (str "node -e 'const b = new Uint8Array([" csv "]); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (inst.exports[\"add-nums\"](100n, 250n) !== 350n) process.exit(1); if (inst.exports[\"mult-nums\"](7n, 8n) !== 56n) process.exit(2); if (inst.exports[\"sub-nums\"](50n, 18n) !== 32n) process.exit(3); if (inst.exports[\"clamp-val\"](5n, 10n, 20n) !== 10n) process.exit(4); if (inst.exports[\"clamp-val\"](25n, 10n, 20n) !== 20n) process.exit(5); if (inst.exports[\"clamp-val\"](15n, 10n, 20n) !== 15n) process.exit(6);'"))
             (res (sysExec cmd))]
         (assert (= (.-exitCode res) 0) (str "Dynamic function execution failed, stderr: " (.-stderr res)))
         (refute (!= (.-exitCode res) 0) "All compiled functions must produce exact numerical results")
         true))
      ((err _) false))))

(df testWasmDualPolarityRefutations [] -> Bool
  :d "Verifies that corrupted headers, invalid opcodes, and bad section lengths are rejected by WebAssembly engine."
  (let [(cmdTruncHdr "node -e 'const b = new Uint8Array([0, 97, 115]); if (WebAssembly.validate(b)) process.exit(1);'")
        (cmdBadMagic "node -e 'const b = new Uint8Array([1, 2, 3, 4, 1, 0, 0, 0]); if (WebAssembly.validate(b)) process.exit(1);'")
        (cmdBadSection "node -e 'const b = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 99, 1]); if (WebAssembly.validate(b)) process.exit(1);'")
        (cmdBadOpcode "node -e 'const b = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 10, 4, 1, 2, 0, 255]); if (WebAssembly.validate(b)) process.exit(1);'")
        (resTrunc (sysExec cmdTruncHdr))
        (resMagic (sysExec cmdBadMagic))
        (resSec (sysExec cmdBadSection))
        (resOp (sysExec cmdBadOpcode))]
    (assert (= (.-exitCode resTrunc) 0) "Truncated header must be rejected by WebAssembly.validate")
    (refute (!= (.-exitCode resTrunc) 0) "Truncated header must not pass validation")
    (assert (= (.-exitCode resMagic) 0) "Corrupted magic must be rejected by WebAssembly.validate")
    (refute (!= (.-exitCode resMagic) 0) "Corrupted magic must not pass validation")
    (assert (= (.-exitCode resSec) 0) "Corrupted section length must be rejected by WebAssembly.validate")
    (refute (!= (.-exitCode resSec) 0) "Corrupted section must not pass validation")
    (assert (= (.-exitCode resOp) 0) "Invalid opcode 0xFF must be rejected by WebAssembly.validate")
    (refute (!= (.-exitCode resOp) 0) "Invalid opcode must not pass validation")
    true))

(df runTests [] -> Bool
  :d "Runs all end-to-end Wasm validation and dynamic execution tests."
  (do
    (assert (testWasmBinaryValidation) "testWasmBinaryValidation must pass")
    (assert (testWasmFunctionExecution) "testWasmFunctionExecution must pass")
    (assert (testWasmDualPolarityRefutations) "testWasmDualPolarityRefutations must pass")
    true))
