(module asl-ir/tests/numLiteralLowerTest :x [runTests] :i [(asl-ir/types :a ty) (asl-ir/lower :a low) (asl-ir/printer :a prn)])

; (:m :ref LL-NUMLIT :do "lowering turns 0x 0b 0o and _ literals into the constant of their value, not an unknown symbol or zero; a malformed numeric atom stays a lowering error")
fn lowered src: String -> String
  (match (low/lowerSource src)
    ((ok m) (prn/printSsa m))
    ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; "))))

fn srcOf lit: String -> String
  (stringJoin (list "(module demo/lit :x [probe] :i [])" "" "fn probe -> Int64" (str "  " lit) "") "\n")

fn constText lit: String -> String
  (lowered (srcOf lit))

fn hasConst? lit: String want: Int64 -> Bool
  (let [(t (constText lit)) (ok (stringContains? t (str "(const int " (stringFromInt64 want) ")")))]
    (do (assert ok (str lit " lowers to the constant " (stringFromInt64 want) "; got " t)) ok))

fn ! runTests -> Bool
  (do
    (hasConst? "0xFF" (- 256 1))
    (hasConst? "0b1010" (+ 8 2))
    (hasConst? "0o17" (+ 8 7))
    (hasConst? "1_000" (* 10 100))
    (hasConst? "0xFFFF_FFFF" (- (<< 1 32) 1))
    (hasConst? "-0x10" (- 0 16))
    (hasConst? "0x7FFFFFFFFFFFFFFF" (- (<< 1 62) (- 0 (- (<< 1 62) 1))))
    (refute (stringContains? (constText "0xFF") "failed") "0xFF lowers without a diagnostic")
    (assert (stringContains? (constText "0xZZ") "failed") "a malformed hex atom is still a lowering error")
    true)
