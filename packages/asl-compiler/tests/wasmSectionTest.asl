(module asl-compiler/wasmSectionTest :x [testWasmMagicHeader testEncodeSectionFraming testEncodeTypeSection testEncodeFunctionSection testEncodeMemorySection testEncodeExportSection testEncodeCodeSection runTests] :i [(wasm :a w)])

fn testWasmMagicHeader -> Bool
  (let [(hdr (w/wasmMagicHeader))] (assert (= (listLength hdr) 8) "Wasm header must be exactly 8 bytes") (refute (!= (listLength hdr) 8) "Wasm header length must not deviate from 8") (assert (= (optionOr (listGet hdr 0) -1) 0) "First byte must be 0x00") (assert (= (optionOr (listGet hdr 1) -1) 97) "Second byte must be 'a' (0x61)") (assert (= (optionOr (listGet hdr 2) -1) 115) "Third byte must be 's' (0x73)") (assert (= (optionOr (listGet hdr 3) -1) 109) "Fourth byte must be 'm' (0x6D)") (assert (= (optionOr (listGet hdr 4) -1) 1) "Fifth byte must be version 1") (assert (= (optionOr (listGet hdr 5) -1) 0) "Sixth byte must be version 0") (assert (= (optionOr (listGet hdr 6) -1) 0) "Seventh byte must be version 0") (assert (= (optionOr (listGet hdr 7) -1) 0) "Eighth byte must be version 0") true)

fn testEncodeSectionFraming -> Bool
  (let [(payload (list 1 2 3 4 5)) (sec (w/encodeSection 1 payload))] (assert (= (optionOr (listGet sec 0) -1) 1) "Section ID must be first byte") (assert (= (optionOr (listGet sec 1) -1) 5) "Payload size LEB128 must be second byte") (assert (= (listLength sec) 7) "Total section length must be 1 + 1 + 5 = 7") (refute (= (optionOr (listGet sec 0) -1) 0) "Section ID must not be 0") true)

fn testEncodeTypeSection -> Bool
  (let [(fnType (w/encodeFuncType (list 126 126) (list 126))) (typeSec (w/encodeTypeSection (list fnType)))] (assert (= (optionOr (listGet typeSec 0) -1) 1) "Type section must have ID 1") (refute (= (optionOr (listGet typeSec 0) -1) 3) "Type section ID must not be 3") (assert (> (listLength typeSec) 2) "Type section must contain payload") true)

fn testEncodeFunctionSection -> Bool
  (let [(funcSec (w/encodeFunctionSection (list 0 1)))] (assert (= (optionOr (listGet funcSec 0) -1) 3) "Function section must have ID 3") (refute (= (optionOr (listGet funcSec 0) -1) 1) "Function section ID must not be 1") (assert (= (optionOr (listGet funcSec 2) -1) 2) "Vector count must be 2") true)

fn testEncodeMemorySection -> Bool
  (let [(memSecNoMax (w/encodeMemorySection 1 -1)) (memSecWithMax (w/encodeMemorySection 1 256))] (assert (= (optionOr (listGet memSecNoMax 0) -1) 5) "Memory section must have ID 5") (assert (= (optionOr (listGet memSecWithMax 0) -1) 5) "Memory section with max must have ID 5") (refute (!= (optionOr (listGet memSecNoMax 0) -1) 5) "Memory section ID must not deviate from 5") true)

fn testEncodeExportSection -> Bool
  (let [(exp (w/encodeExportEntry "main" 0 0)) (expSec (w/encodeExportSection (list exp)))] (assert (= (optionOr (listGet expSec 0) -1) 7) "Export section must have ID 7") (refute (= (optionOr (listGet expSec 0) -1) 6) "Export section ID must not be 6") (assert (> (listLength expSec) 4) "Export section must contain encoded export descriptor") true)

fn testEncodeCodeSection -> Bool
  (let [(body (w/encodeFunctionBody (list) (list 11))) (codeSec (w/encodeCodeSection (list body)))] (assert (= (optionOr (listGet codeSec 0) -1) 10) "Code section must have ID 10") (refute (= (optionOr (listGet codeSec 0) -1) 9) "Code section ID must not be 9") (assert (> (listLength codeSec) 3) "Code section must contain payload") true)

fn runTests -> Bool
  (do (assert (testWasmMagicHeader) "testWasmMagicHeader must pass") (assert (testEncodeSectionFraming) "testEncodeSectionFraming must pass") (assert (testEncodeTypeSection) "testEncodeTypeSection must pass") (assert (testEncodeFunctionSection) "testEncodeFunctionSection must pass") (assert (testEncodeMemorySection) "testEncodeMemorySection must pass") (assert (testEncodeExportSection) "testEncodeExportSection must pass") (assert (testEncodeCodeSection) "testEncodeCodeSection must pass") true)
