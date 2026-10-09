(module asl/packages/asl-compiler/tests/wasmBinaryTargetTest :x [testMemorySectionEmission testRpcExportsEmission testCompilerWasmBinTarget testDynamicWasmRuntimeBridge! runTests] :i [(asl-parser/ast :a a) (../src/compiler :a comp) (../src/wasm :a w)])

fn compileWasmBinSource src: Str -> comp/CompileResult
  (mt (a/parse src) ((ok forms) (comp/CompileResult :ok true :code (w/emitWasmBinaryTarget forms) :diagnostics (list))) ((err pe) (comp/CompileResult :ok false :code "" :diagnostics (list pe.msg))))

fn testMemorySectionEmission -> Bool
  (let [(memSec (w/emitWasmMemorySection))] (assert (= (optionOr (listGet memSec 0) -1) 5) "Memory section ID must be 5") (refute (= (optionOr (listGet memSec 0) -1) 4) "Memory section ID must not be 4") (assert (> (listLength memSec) 3) "Memory section payload must declare limits") true)

fn testRpcExportsEmission -> Bool
  (let [(rpcList (w/emitWasmRpcExports 1 2 3)) (flatBytes (w/flattenByteLists rpcList))] (assert (= (listLength rpcList) 4) "Must export exactly 4 descriptors (memory, alloc, free, dispatch)") (refute (< (listLength rpcList) 4) "RPC exports count must not be less than 4") (assert (> (listLength flatBytes) 30) "Flattened RPC export bytes must be substantial") true)

fn testCompilerWasmBinTarget -> Bool
  (let [(src "(df calc [(x I64)] -> I64 (* x 2))") (resBin (compileWasmBinSource src)) (resWasm (compileWasmBinSource src))] (assert resBin.ok "wasm-bin compilation must succeed") (refute (not resBin.ok) "wasm-bin compilation must not fail") (assert resWasm.ok "wasm compilation must succeed") (assert (not (stringEmpty? resBin.code)) "wasm-bin code output must not be empty") (refute (stringContains? resBin.code "pub fn") "wasm-bin must not be Rust code") (assert (stringContains? resBin.code "0,97,115,109") "wasm-bin code must contain Wasm magic header bytes") true)

fn testDynamicWasmRuntimeBridge! -> Bool
  (let [(src "(df double-val [(n I64)] -> I64 (+ n n))") (res (compileWasmBinSource src))] (assert res.ok "Compilation must succeed") (let [(csv res.code) (cmd (str "node -e 'const b = new Uint8Array([" csv "]); if (!WebAssembly.validate(b)) process.exit(2); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (!inst.exports.memory || inst.exports.memory.buffer.byteLength < 65536) process.exit(3); const p1 = inst.exports.aslAlloc(1024); const p2 = inst.exports.aslAlloc(2048); if (p1 <= 0 || p2 < p1 + 1024) process.exit(4); if (typeof inst.exports.aslRpcDispatch !== \"function\") process.exit(5); if (inst.exports[\"double-val\"](21n) !== 42n) process.exit(6);'")) (execRes (processRun cmd)) (code execRes.exitCode)] (assert (= code 0) (str "Dynamic runtime bridge validation failed with exit code " (stringFromInt64 code) ", stderr: " execRes.stderr)) (refute (!= code 0) "Runtime bridge validation must exit 0") true))

fn ! runTests -> Bool
  (do (assert (testMemorySectionEmission) "testMemorySectionEmission must pass") (assert (testRpcExportsEmission) "testRpcExportsEmission must pass") (assert (testCompilerWasmBinTarget) "testCompilerWasmBinTarget must pass") (assert (testDynamicWasmRuntimeBridge!) "testDynamicWasmRuntimeBridge must pass") true)
