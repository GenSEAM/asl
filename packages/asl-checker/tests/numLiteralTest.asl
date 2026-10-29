(module asl-checker/numLiteralTest :x [runTests] :i [(types :a ty) (check :a c)])

; (:m :ref LL-NUMLIT :do "radix literals 0x 0b 0o and _ separators are integer literals for the checker; a malformed numeric atom is ERR_BAD_NUMBER, not an unbound symbol; the literal range check reads them by value")
fn diagsOf body: String -> (List ty/Diagnostic)
  (c/checkSource (str "(module m :x [] :i [])\n\n" body) (mapEmpty) "m.asl")

fn showDiags ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str "[" d.code "] " d.message)) ds) "; ")

fn clean? body: String label: String -> Bool
  (let [(ds (diagsOf body))] (do (assert (listEmpty? ds) (str label " is accepted; got " (showDiags ds))) true))

fn rejected? body: String code: String label: String -> Bool
  (let [(ds (diagsOf body))]
    (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code code)) ds) (str label ": expected " code "; got " (showDiags ds)))
        (refute (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-1")) ds) (str label ": no unbound-symbol cascade; got " (showDiags ds)))
        true))

fn ! runTests -> Bool
  (do
    (clean? "fn f -> Int64\n  0xFF\n" "hex literal")
    (clean? "fn f -> Int64\n  0b1010\n" "binary literal")
    (clean? "fn f -> Int64\n  0o17\n" "octal literal")
    (clean? "fn f -> Int64\n  1_000\n" "separated decimal literal")
    (clean? "fn f -> Int64\n  -0x10\n" "signed hex literal")
    (clean? "fn f x: Int64 -> Int64\n  (+ x (+ 0xFF 1_000))\n" "radix literals typed as Int64 in arithmetic")
    (clean? "fn f -> Int32\n  0x7FFFFFFF\n" "hex literal inside the Int32 range is checked by value")
    (rejected? "fn f -> Int32\n  0x80000000\n" "literal-range" "hex literal past the Int32 range")
    (rejected? "fn f -> Int64\n  0xZZ\n" "ERR_BAD_NUMBER" "bad hex digit")
    (rejected? "fn f -> Int64\n  0b102\n" "ERR_BAD_NUMBER" "bad binary digit")
    (rejected? "fn f -> Int64\n  0x\n" "ERR_BAD_NUMBER" "prefix without digits")
    (rejected? "fn f -> Int64\n  1__0\n" "ERR_BAD_NUMBER" "doubled separator")
    (rejected? "fn f -> Int64\n  1_\n" "ERR_BAD_NUMBER" "trailing separator")
    (rejected? "fn f -> Int64\n  0x_FF\n" "ERR_BAD_NUMBER" "leading separator after the prefix")
    true)
