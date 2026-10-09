(module asl-compiler/wasmCodegenTest :x [testLowerFunctionTypeIndex testLowerSimpleFunction testLowerConditionalFunction testLowerDynamicExecution! runTests] :i [(asl-parser/ast :a a) (wasm :a w)])

fn bytesToCsv bytes: (List Int64) -> Str
  (stringJoin (map (fn [(b Int64)] -> Str (stringFromInt64 b)) bytes) ",")

fn testLowerFunctionTypeIndex -> Bool
  (let [(parsed (a/parse "(fn foo [(x I64)] -> I64 x) (fn bar [(y I64)] -> I64 y)"))] (mt parsed ((ok forms) (let [(idxMap (w/buildFunctionTypeIndex forms))] (assert (= (optionOr (mapGet idxMap "foo") -1) 0) "foo must have index 0") (assert (= (optionOr (mapGet idxMap "bar") -1) 1) "bar must have index 1") (refute (= (optionOr (mapGet idxMap "baz") -1) 0) "non-existent baz must not have index 0") true)) ((err _) false)))

fn testLowerSimpleFunction -> Bool
  (let [(parsed (a/parse "(fn add [(a I64) (b I64)] -> I64 (+ a b))"))] (mt parsed ((ok forms) (let [(bytes (w/lowerAstTopForms forms)) (hdr (w/wasmMagicHeader))] (assert (> (listLength bytes) 20) "Lowered module must be non-trivial byte list") (refute (listEmpty? bytes) "Lowered module must not be empty") (assert (= (optionOr (listSlice bytes 0 8) (list)) hdr) "Lowered module must start with Wasm header") true)) ((err _) false)))

fn testLowerConditionalFunction -> Bool
  (let [(parsed (a/parse "(fn pick-max [(a I64) (b I64)] -> I64 (if (> a b) a b))"))] (mt parsed ((ok forms) (let [(bytes (w/lowerAstTopForms forms))] (assert (> (listLength bytes) 20) "Conditional function bytecode must be non-empty") (refute (listEmpty? bytes) "Bytecode must not be empty") true)) ((err _) false)))

fn testLowerDynamicExecution! -> Bool
  (let [(parsedAdd (a/parse "(fn add [(a I64) (b I64)] -> I64 (+ a b))")) (parsedMax (a/parse "(fn pick-max [(a I64) (b I64)] -> I64 (if (> a b) a b))"))] (mt parsedAdd ((ok addForms) (mt parsedMax ((ok maxForms) (let [(addBytes (w/lowerAstTopForms addForms)) (maxBytes (w/lowerAstTopForms maxForms)) (csvAdd (bytesToCsv addBytes)) (csvMax (bytesToCsv maxBytes)) (cmdAdd (str "node -e 'const b = new Uint8Array([" csvAdd "]); if (!WebAssembly.validate(b)) process.exit(2); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (inst.exports.add(15n, 27n) !== 42n) process.exit(3);'")) (cmdMax (str "node -e 'const b = new Uint8Array([" csvMax "]); if (!WebAssembly.validate(b)) process.exit(2); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (inst.exports[\"pick-max\"](99n, 12n) !== 99n) process.exit(3); if (inst.exports[\"pick-max\"](7n, 88n) !== 88n) process.exit(4);'")) (resAdd (processRun cmdAdd)) (resMax (processRun cmdMax))] (assert (= resAdd.exitCode 0) (str "Dynamic execution of add failed with code " (stringFromInt64 resAdd.exitCode) ", stderr: " resAdd.stderr ", stdout: " resAdd.stdout)) (refute (!= resAdd.exitCode 0) "add function must exit 0") (assert (= resMax.exitCode 0) (str "Dynamic execution of pickMax failed with code " (stringFromInt64 resMax.exitCode) ", stderr: " resMax.stderr ", stdout: " resMax.stdout)) (refute (!= resMax.exitCode 0) "pickMax function must exit 0") true)) ((err _) false))) ((err _) false)))

fn ! runTests -> Bool
  (do (assert (testLowerFunctionTypeIndex) "testLowerFunctionTypeIndex must pass") (assert (testLowerSimpleFunction) "testLowerSimpleFunction must pass") (assert (testLowerConditionalFunction) "testLowerConditionalFunction must pass") (assert (testLowerDynamicExecution!) "testLowerDynamicExecution must pass") true)
