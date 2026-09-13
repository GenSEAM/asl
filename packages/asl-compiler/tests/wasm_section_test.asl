(module asl-compiler/wasm-section-test
  :d "Unit tests for WebAssembly v1 binary header and section framing assembly."
  :x [testWasmMagicHeader
      testEncodeSectionFraming
      testEncodeTypeSection
      testEncodeFunctionSection
      testEncodeMemorySection
      testEncodeExportSection
      testEncodeCodeSection
      runTests]
  :i [(wasm :a w)])

(df testWasmMagicHeader [] -> Bool
  :d "Verifies the 8-byte standard WebAssembly magic header."
  (let [(hdr (w/wasmMagicHeader))]
    (assert (= (list-length hdr) 8) "Wasm header must be exactly 8 bytes")
    (refute (!= (list-length hdr) 8) "Wasm header length must not deviate from 8")
    (assert (= (option-or (list-get hdr 0) -1) 0) "First byte must be 0x00")
    (assert (= (option-or (list-get hdr 1) -1) 97) "Second byte must be 'a' (0x61)")
    (assert (= (option-or (list-get hdr 2) -1) 115) "Third byte must be 's' (0x73)")
    (assert (= (option-or (list-get hdr 3) -1) 109) "Fourth byte must be 'm' (0x6D)")
    (assert (= (option-or (list-get hdr 4) -1) 1) "Fifth byte must be version 1")
    (assert (= (option-or (list-get hdr 5) -1) 0) "Sixth byte must be version 0")
    (assert (= (option-or (list-get hdr 6) -1) 0) "Seventh byte must be version 0")
    (assert (= (option-or (list-get hdr 7) -1) 0) "Eighth byte must be version 0")
    true))

(df testEncodeSectionFraming [] -> Bool
  :d "Verifies section ID and LEB128 payload size framing."
  (let [(payload (list 1 2 3 4 5))
        (sec (w/encodeSection 1 payload))]
    (assert (= (option-or (list-get sec 0) -1) 1) "Section ID must be first byte")
    (assert (= (option-or (list-get sec 1) -1) 5) "Payload size LEB128 must be second byte")
    (assert (= (list-length sec) 7) "Total section length must be 1 + 1 + 5 = 7")
    (refute (= (option-or (list-get sec 0) -1) 0) "Section ID must not be 0")
    true))

(df testEncodeTypeSection [] -> Bool
  :d "Verifies Type section encoding."
  (let [(fnType (w/encodeFuncType (list 126 126) (list 126)))
        (typeSec (w/encodeTypeSection (list fnType)))]
    (assert (= (option-or (list-get typeSec 0) -1) 1) "Type section must have ID 1")
    (refute (= (option-or (list-get typeSec 0) -1) 3) "Type section ID must not be 3")
    (assert (> (list-length typeSec) 2) "Type section must contain payload")
    true))

(df testEncodeFunctionSection [] -> Bool
  :d "Verifies Function section encoding."
  (let [(funcSec (w/encodeFunctionSection (list 0 1)))]
    (assert (= (option-or (list-get funcSec 0) -1) 3) "Function section must have ID 3")
    (refute (= (option-or (list-get funcSec 0) -1) 1) "Function section ID must not be 1")
    (assert (= (option-or (list-get funcSec 2) -1) 2) "Vector count must be 2")
    true))

(df testEncodeMemorySection [] -> Bool
  :d "Verifies Memory section encoding with limits."
  (let [(memSecNoMax (w/encodeMemorySection 1 -1))
        (memSecWithMax (w/encodeMemorySection 1 256))]
    (assert (= (option-or (list-get memSecNoMax 0) -1) 5) "Memory section must have ID 5")
    (assert (= (option-or (list-get memSecWithMax 0) -1) 5) "Memory section with max must have ID 5")
    (refute (!= (option-or (list-get memSecNoMax 0) -1) 5) "Memory section ID must not deviate from 5")
    true))

(df testEncodeExportSection [] -> Bool
  :d "Verifies Export section encoding."
  (let [(exp (w/encodeExportEntry "main" 0 0))
        (expSec (w/encodeExportSection (list exp)))]
    (assert (= (option-or (list-get expSec 0) -1) 7) "Export section must have ID 7")
    (refute (= (option-or (list-get expSec 0) -1) 6) "Export section ID must not be 6")
    (assert (> (list-length expSec) 4) "Export section must contain encoded export descriptor")
    true))

(df testEncodeCodeSection [] -> Bool
  :d "Verifies Code section encoding."
  (let [(body (w/encodeFunctionBody (list) (list 11)))
        (codeSec (w/encodeCodeSection (list body)))]
    (assert (= (option-or (list-get codeSec 0) -1) 10) "Code section must have ID 10")
    (refute (= (option-or (list-get codeSec 0) -1) 9) "Code section ID must not be 9")
    (assert (> (list-length codeSec) 3) "Code section must contain payload")
    true))

(df runTests [] -> Bool
  :d "Runs all Wasm section framing unit tests."
  (do
    (assert (testWasmMagicHeader) "testWasmMagicHeader must pass")
    (assert (testEncodeSectionFraming) "testEncodeSectionFraming must pass")
    (assert (testEncodeTypeSection) "testEncodeTypeSection must pass")
    (assert (testEncodeFunctionSection) "testEncodeFunctionSection must pass")
    (assert (testEncodeMemorySection) "testEncodeMemorySection must pass")
    (assert (testEncodeExportSection) "testEncodeExportSection must pass")
    (assert (testEncodeCodeSection) "testEncodeCodeSection must pass")
    true))
