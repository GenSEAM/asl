(module asl-compiler/wasm-codegen-test
  :d "Unit tests for pure ASL AST lowering to WebAssembly MVP bytecode."
  :x [testLowerFunctionTypeIndex
      testLowerSimpleFunction
      testLowerConditionalFunction
      testLowerDynamicExecution
      runTests]
  :i [(ast :a a) (wasm :a w)])

(df bytesToCsv [(bytes (List Int64))] -> Str
  :d "Formats byte vector to comma-separated integer string for node execution."
  (string-join (map (fn [(b Int64)] -> Str (string-from-int64 b)) bytes) ","))

(df testLowerFunctionTypeIndex [] -> Bool
  :d "Verifies function index lookup map construction."
  (let [(parsed (a/parse "(df foo [(x I64)] -> I64 x) (df bar [(y I64)] -> I64 y)"))]
    (mt parsed
      ((ok forms)
       (let [(idxMap (w/buildFunctionTypeIndex forms))]
         (assert (= (option-or (map-get idxMap "foo") -1) 0) "foo must have index 0")
         (assert (= (option-or (map-get idxMap "bar") -1) 1) "bar must have index 1")
         (refute (= (option-or (map-get idxMap "baz") -1) 0) "non-existent baz must not have index 0")
         true))
      ((err _) false))))

(df testLowerSimpleFunction [] -> Bool
  :d "Verifies lowering of arithmetic function to Wasm bytecode."
  (let [(parsed (a/parse "(df add [(a I64) (b I64)] -> I64 (+ a b))"))]
    (mt parsed
      ((ok forms)
       (let [(bytes (w/lowerAstTopForms forms))
             (hdr (w/wasmMagicHeader))]
         (assert (> (list-length bytes) 20) "Lowered module must be non-trivial byte list")
         (refute (list-empty? bytes) "Lowered module must not be empty")
         (assert (= (option-or (list-slice bytes 0 8) (list)) hdr) "Lowered module must start with Wasm header")
         true))
      ((err _) false))))

(df testLowerConditionalFunction [] -> Bool
  :d "Verifies lowering of conditional if-else function to Wasm bytecode."
  (let [(parsed (a/parse "(df pick-max [(a I64) (b I64)] -> I64 (if (> a b) a b))"))]
    (mt parsed
      ((ok forms)
       (let [(bytes (w/lowerAstTopForms forms))]
         (assert (> (list-length bytes) 20) "Conditional function bytecode must be non-empty")
         (refute (list-empty? bytes) "Bytecode must not be empty")
         true))
      ((err _) false))))

(df testLowerDynamicExecution [] -> Bool
  :d "Dynamically validates and invokes compiled Wasm bytecode inside Node.js V8 engine."
  (let [(parsedAdd (a/parse "(df add [(a I64) (b I64)] -> I64 (+ a b))"))
        (parsedMax (a/parse "(df pick-max [(a I64) (b I64)] -> I64 (if (> a b) a b))"))]
    (mt parsedAdd
      ((ok addForms)
       (mt parsedMax
         ((ok maxForms)
          (let [(addBytes (w/lowerAstTopForms addForms))
                (maxBytes (w/lowerAstTopForms maxForms))
                (csvAdd (bytesToCsv addBytes))
                (csvMax (bytesToCsv maxBytes))
                (cmdAdd (str "/usr/local/bin/node -e 'const b = new Uint8Array([" csvAdd "]); if (!WebAssembly.validate(b)) process.exit(2); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (inst.exports.add(15n, 27n) !== 42n) process.exit(3);'"))
                (cmdMax (str "/usr/local/bin/node -e 'const b = new Uint8Array([" csvMax "]); if (!WebAssembly.validate(b)) process.exit(2); const inst = new WebAssembly.Instance(new WebAssembly.Module(b)); if (inst.exports[\"pick-max\"](99n, 12n) !== 99n) process.exit(3); if (inst.exports[\"pick-max\"](7n, 88n) !== 88n) process.exit(4);'"))
                (resAdd (sys-exec cmdAdd))
                (resMax (sys-exec cmdMax))]
            (assert (= (.-exitCode resAdd) 0) (str "Dynamic execution of add failed with code " (string-from-int64 (.-exitCode resAdd)) ", stderr: " (.-stderr resAdd) ", stdout: " (.-stdout resAdd)))
            (refute (!= (.-exitCode resAdd) 0) "add function must exit 0")
            (assert (= (.-exitCode resMax) 0) (str "Dynamic execution of pickMax failed with code " (string-from-int64 (.-exitCode resMax)) ", stderr: " (.-stderr resMax) ", stdout: " (.-stdout resMax)))
            (refute (!= (.-exitCode resMax) 0) "pickMax function must exit 0")
            true))
         ((err _) false)))
      ((err _) false))))

(df runTests [] -> Bool
  :d "Runs all Wasm code generation and lowering unit tests."
  (do
    (assert (testLowerFunctionTypeIndex) "testLowerFunctionTypeIndex must pass")
    (assert (testLowerSimpleFunction) "testLowerSimpleFunction must pass")
    (assert (testLowerConditionalFunction) "testLowerConditionalFunction must pass")
    (assert (testLowerDynamicExecution) "testLowerDynamicExecution must pass")
    true))
