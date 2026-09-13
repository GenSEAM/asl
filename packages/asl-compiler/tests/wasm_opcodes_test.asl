(module asl-compiler/wasm-opcodes-test
  :d "Unit tests for WebAssembly v1 MVP opcode matrix and instruction assembly."
  :x [testOpcodesLookup
      testEmitInstrConst
      testEmitInstrLocalAndCall
      testEmitInstrBinaryOp
      testEmitInstrIf
      runTests]
  :i [(wasm :a w)])

(df testOpcodesLookup [] -> Bool
  :d "Verifies opcode mnemonic lookup values."
  (let [(cUnreach (w/wasmOpcode "unreachable"))
        (cCall (w/wasmOpcode "call"))
        (cGet (w/wasmOpcode "local.get"))
        (cI32Const (w/wasmOpcode "i32.const"))
        (cI64Const (w/wasmOpcode "i64.const"))
        (cI32Add (w/wasmOpcode "i32.add"))
        (cI64Add (w/wasmOpcode "i64.add"))
        (cUnknown (w/wasmOpcode "unknown_opcode"))]
    (assert (= cUnreach 0) "unreachable opcode must be 0x00")
    (assert (= cCall 16) "call opcode must be 0x10")
    (assert (= cGet 32) "local.get opcode must be 0x20")
    (assert (= cI32Const 65) "i32.const opcode must be 0x41")
    (assert (= cI64Const 66) "i64.const opcode must be 0x42")
    (assert (= cI32Add 106) "i32.add opcode must be 0x6A")
    (assert (= cI64Add 124) "i64.add opcode must be 0x7C")
    (assert (= cUnknown -1) "unknown opcode must return -1")
    (refute (!= cI64Add 124) "i64.add must strictly equal 124")
    true))

(df testEmitInstrConst [] -> Bool
  :d "Verifies constant instruction emission with LEB128 encoding."
  (let [(i32Val (w/emitInstrConstI32 42))
        (i32Neg (w/emitInstrConstI32 -1))
        (i64Val42 (w/emitInstrConstI64 42))
        (i64Val100 (w/emitInstrConstI64 100))
        (i64Neg128 (w/emitInstrConstI64 -128))]
    (assert (= i32Val (list 65 42)) "i32.const 42 must be [0x41, 42]")
    (assert (= i32Neg (list 65 127)) "i32.const -1 must be [0x41, 127]")
    (assert (= i64Val42 (list 66 42)) "i64.const 42 must be [0x42, 42]")
    (assert (= i64Val100 (list 66 228 0)) "i64.const 100 must be [0x42, 228, 0]")
    (assert (= i64Neg128 (list 66 128 127)) "i64.const -128 must be [0x42, 128, 127]")
    (refute (= i32Neg (list 65 255)) "i32.const -1 must not use unsigned 255")
    true))

(df testEmitInstrLocalAndCall [] -> Bool
  :d "Verifies local variable access and call instruction emission."
  (let [(get0 (w/emitInstrLocalGet 0))
        (get5 (w/emitInstrLocalGet 5))
        (set1 (w/emitInstrLocalSet 1))
        (call0 (w/emitInstrCall 0))
        (call3 (w/emitInstrCall 3))]
    (assert (= get0 (list 32 0)) "local.get 0 must be [0x20, 0]")
    (assert (= get5 (list 32 5)) "local.get 5 must be [0x20, 5]")
    (assert (= set1 (list 33 1)) "local.set 1 must be [0x21, 1]")
    (assert (= call0 (list 16 0)) "call 0 must be [0x10, 0]")
    (assert (= call3 (list 16 3)) "call 3 must be [0x10, 3]")
    (refute (= get0 (list 33 0)) "local.get must not emit local.set opcode")
    true))

(df testEmitInstrBinaryOp [] -> Bool
  :d "Verifies binary arithmetic and comparison opcode mapping."
  (let [(add32 (w/emitInstrBinaryOp "+" "i32"))
        (add64 (w/emitInstrBinaryOp "+" "i64"))
        (sub64 (w/emitInstrBinaryOp "-" "i64"))
        (mul64 (w/emitInstrBinaryOp "*" "i64"))
        (eq64 (w/emitInstrBinaryOp "=" "i64"))
        (lt64 (w/emitInstrBinaryOp "<" "i64"))]
    (assert (= add32 (list 106)) "+ i32 must emit 0x6A")
    (assert (= add64 (list 124)) "+ i64 must emit 0x7C")
    (assert (= sub64 (list 125)) "- i64 must emit 0x7D")
    (assert (= mul64 (list 126)) "* i64 must emit 0x7E")
    (assert (= eq64 (list 81)) "= i64 must emit 0x51")
    (assert (= lt64 (list 83)) "< i64 must emit 0x53")
    (refute (= add32 (list 124)) "+ i32 must not emit 64-bit opcode")
    true))

(df testEmitInstrIf [] -> Bool
  :d "Verifies structured if-else-end block emission."
  (let [(thenInst (w/emitInstrConstI64 42))
        (elseInst (w/emitInstrConstI64 50))
        (ifElse (w/emitInstrIf 126 thenInst elseInst))
        (ifNoElse (w/emitInstrIf 126 thenInst (list)))]
    (assert (= ifElse (list 4 126 66 42 5 66 50 11)) "if-else-end structure must match spec")
    (assert (= ifNoElse (list 4 126 66 42 11)) "if-end structure without else must match spec")
    (refute (list-contains? ifNoElse 5) "if without else must not contain else opcode 0x05")
    true))

(df runTests [] -> Bool
  :d "Runs all Wasm opcode and instruction assembly unit tests."
  (do
    (assert (testOpcodesLookup) "testOpcodesLookup must pass")
    (assert (testEmitInstrConst) "testEmitInstrConst must pass")
    (assert (testEmitInstrLocalAndCall) "testEmitInstrLocalAndCall must pass")
    (assert (testEmitInstrBinaryOp) "testEmitInstrBinaryOp must pass")
    (assert (testEmitInstrIf) "testEmitInstrIf must pass")
    true))
