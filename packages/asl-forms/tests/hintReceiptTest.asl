(module asl-forms/tests/hintReceiptTest
  :x [runTests]
  :i [(asl-forms/check :a chk)])

; (:m :do "STATICHINT gap 1, receipt hook: the rejected check receipt carries one :hint per diagnostic that has one (Option where a value is expected, unbound symbol with a known exporting module); a clean file adds none")

fn ! receiptOf! text: String -> String
  (chk/checkFileReceipt! 1 "check" "asl/packages/asl-forms/tests/hintReceiptTmp.asl" "x" text)

fn ! runTests -> Bool
  (let [(opt (receiptOf! "(module hintReceiptTmp :x [f])\n\nfn f xs: (List Int64) -> Int64\n  (listHead xs)\n"))
        (imp (receiptOf! "(module hintReceiptTmp :x [f])\n\nfn f s: String -> (List String)\n  (headerExports s)\n"))
        (near (receiptOf! "(module hintReceiptTmp :x [f])\n\nfn f xs: (List Int64) -> Int64\n  (listSun xs)\n"))
        (arity (receiptOf! "(module hintReceiptTmp :x [f])\n\nfn f xs: (List Int64) -> Int64\n  (listSum xs xs)\n"))
        (ok (receiptOf! "(module hintReceiptTmp :x [f])\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n"))]
    (do (assert (stringContains? opt ":hint \"listGet/listHead/mapGet") (str "Option hint in the receipt, got " opt))
        (assert (stringContains? imp "(asl-checker/hints :a hints)") (str "import hint in the receipt, got " imp))
        (assert (stringContains? near ":hint \"nearest known name: listSum") (str "nearest-name hint in the receipt, got " near))
        (assert (stringContains? arity "declared parameter count") (str "arity hint in the receipt, got " arity))
        (assert (not (stringContains? ok ":hint")) (str "a clean file has no hint, got " ok))
        true))
