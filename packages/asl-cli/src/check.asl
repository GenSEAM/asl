(module asl-cli/check :x [runCheckCommand! formatCheckHelp checkSourceWithFix] :i [(asl-parser/ast :a ast) (asl-checker/check :a checker) (asl-checker/types :a ty) (asl-parser/balance :a bal)])

fn formatCheckHelp -> Str
  (str "Usage: asl check [options] <files...>\n\n" "Options:\n" "  --format=auto|indent|paren   Override source format detection\n" "  --data                       Activate unquoted data mode\n" "  --fix                        Not implemented: fails with ERR_NOT_IMPLEMENTED (no repair source yet)\n\n" "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n" "  \"Diagnostics are the checker's own findings, reported as found; nothing is repaired or rewritten.\"\n")

fn formatCheckDiag d: ty/Diagnostic -> Str
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message)

fn formatCheckDiags diags: (List ty/Diagnostic) -> Str
  (stringJoin (map (fn [(d ty/Diagnostic)] -> Str (formatCheckDiag d)) diags) "\n")

fn checkSourceWithFix filePath: Str src: Str isFix: Bool -> (Result Str Str)
  (match (ast/parse src)
    ((err pe) (err (str filePath ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg)))
    ((ok astForms)
     (let [(diags (checker/checkModule astForms (mapEmpty) filePath))]
       (if (not (listEmpty? diags))
         (err (formatCheckDiags diags))
         (ok (str "✓ " filePath ": Semantic check passed cleanly."))))))

fn filterNonFlagsStep args: (List Str) acc: (List Str) -> (List Str)
  (match (listHead args) ((none) acc) ((some a) (let [(rest (optionOr (listTail args) (list)))] (if (stringStartsWith? a "-") (filterNonFlagsStep rest acc) (filterNonFlagsStep rest (listAppend acc (list a)))))))

fn filterNonFlags args: (List Str) -> (List Str)
  (filterNonFlagsStep args (list))

fn containsFlag args: (List Str) targetFlag: Str -> Bool
  (match (listHead args) ((none) false) ((some a) (if (= a targetFlag) true (containsFlag (optionOr (listTail args) (list)) targetFlag))))

fn checkData filePath: Str src: Str -> (Result Str Str)
  (let [(b (bal/checkDelimiterBalanceIn false src))]
    (if b.balanced
      (ok (str "ok " filePath ": ASN, delimiters balanced"))
      (err (str filePath ": ERR_UNBALANCED " (stringFromInt64 b.openParens) " unclosed '(', " (stringFromInt64 b.openBrackets) " unclosed '['"))))

fn shq s: Str -> Str
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! hostCheck! filePath: Str src: Str -> (Result Str Str)
  (let [(b (bal/checkDelimiterBalanceIn true src))]
    (if (not b.balanced)
      (err (str filePath ": ERR_UNBALANCED " (stringFromInt64 b.openParens) " unclosed '(', " (stringFromInt64 b.openBrackets) " unclosed '['"))
      (let [(r (processRun (str (shq (optionOr (envGet "ASL_HOST") "asl-host")) " check " (shq filePath) " 2>&1")))]
        (if (= r.exitCode 0) (ok (stringTrim r.stdout)) (err (stringTrim r.stdout))))))

fn checkFilesStep! files: (List Str) isFix: Bool acc: (List Str) -> (Result Str Str)
  (match (listHead files) ((none) (ok (stringJoin acc "\n"))) ((some f) (let [(readRes (fileReadString f))] (match readRes ((err _) (err (str "Failed to read file: " f))) ((ok src) (let [(checkRes (cond ((stringEndsWith? f ".asn") (checkData f src)) ((stringEmpty? (optionOr (envGet "ASL_HOST") "")) (checkSourceWithFix f src isFix)) (else (hostCheck! f src))))] (match checkRes ((err e) (err e)) ((ok out) (checkFilesStep! (optionOr (listTail files) (list)) isFix (listAppend acc (list out)))))))))))

fn runCheckCommand! args: (List Str) -> (Result Str Str)
  (cond ((listEmpty? args) (err "Usage: asl check [options] <files...>")) ((or (containsFlag args "--help") (containsFlag args "-h")) (ok (formatCheckHelp))) (else (let [(isFix (containsFlag args "--fix")) (files (filterNonFlags args))] (cond ((listEmpty? files) (err "Usage: asl check [options] <files...>")) (isFix (err "ERR_NOT_IMPLEMENTED: check --fix has no repair source")) (else (checkFilesStep! files isFix (list)))))))
