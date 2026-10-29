(module asl-ir/tests/litPatternTest :x [runTests] :i [(asl-ir/types :a ty) (asl-ir/lower :a low) (asl-ir/printer :a prn)])

; (:m :ref LL-NUMLIT :do "a radix or underscore integer literal used as a match pattern is a literal arm compared by value, like a decimal one; a malformed numeric atom is still rejected")
fn lowered src: String -> String
  (match (low/lowerSource src)
    ((ok m) (prn/printSsa m))
    ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; "))))

fn srcOf pat: String -> String
  (stringJoin (list "(module demo/pat :x [probe] :i [])" "" "fn probe n: Int64 -> Int64" (str "  (match n (" pat " 1) (_ 2))") "") "\n")

fn arm? pat: String want: Int64 -> Bool
  (let [(t (lowered (srcOf pat))) (okText (and (not (stringContains? t "failed")) (stringContains? t (str "(const int " (stringFromInt64 want) ")"))))]
    (do (assert okText (str pat " as a match pattern compares against the constant " (stringFromInt64 want) "; got " t)) okText))

fn ! runTests -> Bool
  (do
    (arm? "0xFF" (- 256 1))
    (arm? "0b1010" (+ 8 2))
    (arm? "0o17" (+ 8 7))
    (arm? "1_000" (* 10 100))
    (arm? "-0x10" (- 0 16))
    (arm? "42" 42)
    (assert (stringContains? (lowered (srcOf "0xZZ")) "failed") "a malformed hex pattern is still rejected")
    true)
