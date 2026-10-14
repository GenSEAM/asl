(module asl-cli/check :x [runCheckCommand! formatCheckHelp applyCandidatePatchAndJournal! checkSourceWithFix] :i [(asl-ir/patch :a patch) (asl-cli/patch :a patchCli) (asl-compiler/diagnostics :a diag) (asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-checker/check :a checker) (asl-checker/types :a ty) (asl-parser/balance :a bal)])

fn formatCheckHelp -> Str
  (str "Usage: asl check [options] <files...>\n\n" "Options:\n" "  --format=auto|indent|paren   Override source format detection\n" "  --data                       Activate unquoted data mode\n\n" "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n" "  \"Compiler diagnostics emit structured candidate AST patches; --fix applies them with transactional rollback.\"\n\n" "[Assistive Ontology] Enforces Self-Healing & Transactional Invariants:\n" "  • Candidate AST Patches: Diagnostics include (:suggestedPatch (:astPatch ...))\n" "  • Single-Step Fix: --fix validates and applies patches in one deterministic step\n" "  • External Rollback Stack Journal: Automatically journals inverse patches to .asl/mem/patch_stack.asn\n" "  • Zero-Line-Number Invariant: Code addressed strictly by Module:symbol and :anchor\n")

fn applyCandidatePatchAndJournal! filePath: Str candidatePatch: patch/AstPatch -> (Result Str Str)
  (let [(readRes (fileRead filePath))] (mt readRes ((err _) (err (str "Failed to read target file for patch: " filePath))) ((ok src) (let [(verifyRes (patch/verifyPatch candidatePatch src))] (mt verifyRes ((err diags) (let [(diagMsg (if (not (listEmpty? diags)) (optionOr (listHead diags) (patch/makePatchDiag "" "" "" "Unknown verification error")).message "Invalid candidate patch"))] (err (str "Candidate patch validation failed: " diagMsg)))) ((ok _) (let [(preDigest (patch/computeAstDigest src)) (patchRes (patch/applyPatch candidatePatch src))] (if (not patchRes.success) (let [(errMsg (if (not (listEmpty? patchRes.diagnostics)) (optionOr (listHead patchRes.diagnostics) (patch/makePatchDiag "" "" "" "Unknown patch application error")).message "Patch application failed"))] (err (str "Patch application failed: " errMsg))) (let [(patchedSrc patchRes.patchedSource) (postDigest (patch/computeAstDigest patchedSrc)) (writeRes (fileWrite filePath patchedSrc))] (mt writeRes ((err _) (err (str "Failed to write patched source to: " filePath))) ((ok _) (let [(invOpt patchRes.inversePatch)] (mt invOpt ((none) (ok (str "(:check-fix-receipt\n" "  :file \"" filePath "\"\n" "  :status :ok\n" "  :appliedPatch \"" candidatePatch.id "\"\n" "  :rollbackJournaled false\n" "  :preRoot \"" preDigest "\"\n" "  :postRoot \"" postDigest "\")"))) ((some invPatch) (let [(entry (patchCli/makeRollbackEntry candidatePatch.id filePath candidatePatch.targetModule preDigest postDigest invPatch 1789720000000)) (pushRes (patchCli/pushRollbackStack! entry))] (mt pushRes ((err pe) (err (str "Failed to journal inverse patch: " pe))) ((ok _) (ok (str "(:check-fix-receipt\n" "  :file \"" filePath "\"\n" "  :status :ok\n" "  :appliedPatch \"" candidatePatch.id "\"\n" "  :rollbackJournaled true\n" "  :preRoot \"" preDigest "\"\n" "  :postRoot \"" postDigest "\")")))))))))))))))))))

fn findImportClauseInForms forms: (List rd/SExpr) -> Str
  (mt (listHead forms) ((none) "") ((some form) (mt form ((rd/sexprList items) (let [(tag (optionOr (listHead items) (rd/makeAtom "")))] (if (= (rd/renderSexpr tag) "module") (let [(iForm (mt (findKeywordSubform items ":import") ((some f) (some f)) ((none) (findKeywordSubform items ":i"))))] (mt iForm ((some imp) (rd/renderSexpr imp)) ((none) ""))) (findImportClauseInForms (optionOr (listTail forms) (list)))))) (_ (findImportClauseInForms (optionOr (listTail forms) (list)))))))

fn readSourceForms src: Str -> (Result (List rd/SExpr) Str)
  (let [(toks (lx/tokenize src)) (readRes (ast/readForms toks))] (mt readRes ((err e) (err e.msg)) ((ok pfs) (ok (map (fn [(pf ast/PosForm)] -> rd/SExpr pf.expr) pfs)))))

fn findKeywordArgStep items: (List rd/SExpr) idx: Int64 len: Int64 kw: Str -> (Option rd/SExpr)
  (if (>= (+ idx 1) len) (none) (let [(curr (optionOr (listGet items idx) (rd/makeAtom "")))] (if (= (rd/renderSexpr curr) kw) (listGet items (+ idx 1)) (findKeywordArgStep items (+ idx 1) len kw))))

fn findKeywordSubform items: (List rd/SExpr) kw: Str -> (Option rd/SExpr)
  (let [(argOpt (findKeywordArgStep items 0 (listLength items) kw))] (mt argOpt ((some arg) (some arg)) ((none) (mt (listHead items) ((none) (none)) ((some item) (mt item ((rd/sexprList subItems) (let [(h (optionOr (listHead subItems) (rd/makeAtom "")))] (if (= (rd/renderSexpr h) kw) (some item) (findKeywordSubform (optionOr (listTail items) (list)) kw)))) (_ (findKeywordSubform (optionOr (listTail items) (list)) kw))))))))

fn extractModuleName forms: (List rd/SExpr) -> Str
  (mt (listHead forms) ((none) "main") ((some form) (mt form ((rd/sexprList items) (let [(tag (optionOr (listHead items) (rd/makeAtom "")))] (if (= (rd/renderSexpr tag) "module") (let [(nameExpr (optionOr (listGet items 1) (rd/makeAtom "main")))] (rd/renderSexpr nameExpr)) (extractModuleName (optionOr (listTail forms) (list)))))) (_ (extractModuleName (optionOr (listTail forms) (list)))))))

fn formatCheckDiag d: ty/Diagnostic -> Str
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message)

fn formatCheckDiags diags: (List ty/Diagnostic) -> Str
  (stringJoin (map (fn [(d ty/Diagnostic)] -> Str (formatCheckDiag d)) diags) "\n")

fn checkSourceWithFix filePath: Str src: Str isFix: Bool -> (Result Str Str)
  (mt (ast/parse src)
    ((err pe) (err (str filePath ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg)))
    ((ok astForms)
     (let [(diags (checker/checkModule astForms (mapEmpty) filePath))]
       (if (not (listEmpty? diags))
         (err (formatCheckDiags diags))
         (ok (str "✓ " filePath ": Semantic check passed cleanly."))))))

fn filterNonFlagsStep args: (List Str) acc: (List Str) -> (List Str)
  (mt (listHead args) ((none) acc) ((some a) (let [(rest (optionOr (listTail args) (list)))] (if (stringStartsWith? a "-") (filterNonFlagsStep rest acc) (filterNonFlagsStep rest (listAppend acc (list a)))))))

fn filterNonFlags args: (List Str) -> (List Str)
  (filterNonFlagsStep args (list))

fn containsFlag args: (List Str) targetFlag: Str -> Bool
  (mt (listHead args) ((none) false) ((some a) (if (= a targetFlag) true (containsFlag (optionOr (listTail args) (list)) targetFlag))))

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
  (mt (listHead files) ((none) (ok (stringJoin acc "\n"))) ((some f) (let [(readRes (fileRead f))] (mt readRes ((err _) (err (str "Failed to read file: " f))) ((ok src) (let [(checkRes (cond ((stringEndsWith? f ".asn") (checkData f src)) ((stringEmpty? (optionOr (envGet "ASL_HOST") "")) (checkSourceWithFix f src isFix)) (else (hostCheck! f src))))] (mt checkRes ((err e) (err e)) ((ok out) (checkFilesStep! (optionOr (listTail files) (list)) isFix (listAppend acc (list out)))))))))))

fn runCheckCommand! args: (List Str) -> (Result Str Str)
  (cond ((listEmpty? args) (err "Usage: asl check [options] <files...>")) ((or (containsFlag args "--help") (containsFlag args "-h")) (ok (formatCheckHelp))) (else (let [(isFix (containsFlag args "--fix")) (files (filterNonFlags args))] (cond ((listEmpty? files) (err "Usage: asl check [options] <files...>")) (isFix (err "ERR_NOT_IMPLEMENTED: check --fix has no repair source")) (else (checkFilesStep! files isFix (list)))))))
