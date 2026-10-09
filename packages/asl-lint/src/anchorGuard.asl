(module asl-lint/anchorGuard :x [hasLineNumberAddressing? hasSymbolAnchor? hasContentAnchor? checkAnchorCompliance auditAnchorPair isReceiptCompliant? auditAnchorReceiptWithDiagnostics] :i [])

fn hasLineNumberAddressing? text: Str -> Bool
  (or (stringContains? text ":line ") (or (stringContains? text "line:") (or (stringContains? text "line_number") (or (stringContains? text ":lineNumber") (or (stringContains? text "StartLine") (stringContains? text "EndLine"))))))

fn hasSymbolAnchor? text: Str -> Bool
  (or (stringContains? text ":symbol") (or (stringContains? text ":sym") (or (stringContains? text ":name") (stringContains? text ":fn"))))

fn hasContentAnchor? text: Str -> Bool
  (or (stringContains? text ":anchor") (or (stringContains? text ":hash") (or (stringContains? text ":cas") (or (stringContains? text ":old") (stringContains? text ":baseHash")))))

fn checkAnchorCompliance text: Str -> Bool
  (let [(forbLine (hasLineNumberAddressing? text))
        (hasSym (hasSymbolAnchor? text))
        (hasAnch (hasContentAnchor? text))]
    (and (or hasSym hasAnch) (not forbLine)))

fn isReceiptCompliant? text: Str -> Bool
  (checkAnchorCompliance text)

fn auditAnchorPair r1: Str r2: Str -> Bool
  (and (isReceiptCompliant? r1) (isReceiptCompliant? r2))

fn auditAnchorReceiptWithDiagnostics text: Str -> (Pair Bool (List Str))
  (let [(forbLine (hasLineNumberAddressing? text))
        (hasSym (hasSymbolAnchor? text))
        (hasAnch (hasContentAnchor? text))
        (diags (list))
        (d1 (if forbLine (listAppend diags (list "ERR_ZERO_LINE_NUMBER: receipts must not contain line number references")) diags))
        (d2 (if (not (or hasSym hasAnch)) (listAppend d1 (list "ERR_MISSING_ANCHOR: receipt must contain a symbol or content CAS anchor")) d1))
        (compliant (and (or hasSym hasAnch) (not forbLine)))]
    (pair compliant d2))
