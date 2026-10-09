(module asl-compiler/diagnostics :x [SelfHealingDiagnostic makeSelfHealingDiagnostic emitDiagnosticWithPatch suggestMissingImportPatch suggestMissingMatchBranchPatch suggestTypeMismatchPatch suggestMissingExportPatch formatDiagnosticWithPatch renderDiagnosticReceipt parseDiagnosticReceipt] :i [(asl-ir/patch :a patch) (asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast)])

(schema SelfHealingDiagnostic (:f code Str) (:f symbol Str) (:f anchor Str) (:f message Str) (:f suggestedPatch (Option patch/AstPatch)))

fn makeSelfHealingDiagnostic code: Str symbol: Str anchor: Str message: Str suggestedPatch: (Option patch/AstPatch) -> SelfHealingDiagnostic
  (SelfHealingDiagnostic :code code :symbol symbol :anchor anchor :message message :suggestedPatch suggestedPatch)

fn emitDiagnosticWithPatch code: Str symbol: Str anchor: Str message: Str suggestedPatch: (Option patch/AstPatch) -> SelfHealingDiagnostic
  (makeSelfHealingDiagnostic code symbol anchor message suggestedPatch)

fn safeStringSlice s: Str start: Int64 end: Int64 -> Str
  (mt (stringSlice s start end) ((some res) res) ((none) ""))

fn insertImportIntoClause clause: Str importStr: Str -> Str
  (let [(trimmed (stringTrim clause)) (len (stringLength trimmed))] (cond ((and (>= len 2) (stringEndsWith? trimmed "])")) (let [(prefix (safeStringSlice trimmed 0 (- len 2))) (trimmedPrefix (stringTrim prefix))] (if (stringEndsWith? trimmedPrefix "[") (str trimmedPrefix importStr "])") (str trimmedPrefix " " importStr "])")))) ((and (>= len 2) (stringEndsWith? trimmed "]")) (let [(prefix (safeStringSlice trimmed 0 (- len 1))) (trimmedPrefix (stringTrim prefix))] (if (stringEndsWith? trimmedPrefix "[") (str trimmedPrefix importStr "]") (str trimmedPrefix " " importStr "]")))) (else (str "[" importStr "]"))))

fn suggestMissingImportPatch targetModule: Str existingImports: Str missingImport: Str -> patch/AstPatch
  (let [(newNode (insertImportIntoClause existingImports missingImport)) (op (patch/makePatchOpReplace targetModule "imports" existingImports newNode)) (patchId (str "fix-import-" targetModule))] (patch/makeAstPatch patchId targetModule (none) (none) (list op)))

fn insertBranchIntoMatch matchExpr: Str branchStr: Str -> Str
  (let [(trimmed (stringTrim matchExpr)) (len (stringLength trimmed))] (if (and (>= len 1) (stringEndsWith? trimmed ")")) (let [(prefix (safeStringSlice trimmed 0 (- len 1)))] (str (stringTrim prefix) " " branchStr ")")) (str trimmed " " branchStr)))

fn suggestMissingMatchBranchPatch targetModule: Str fnSymbol: Str oldMatchExpr: Str missingBranch: Str -> patch/AstPatch
  (let [(newNode (insertBranchIntoMatch oldMatchExpr missingBranch)) (op (patch/makePatchOpReplace fnSymbol "body" oldMatchExpr newNode)) (patchId (str "fix-match-" fnSymbol))] (patch/makeAstPatch patchId targetModule (none) (none) (list op)))

fn suggestTypeMismatchPatch targetModule: Str fnSymbol: Str oldType: Str newType: Str -> patch/AstPatch
  (let [(op (patch/makePatchOpRetype fnSymbol "retType" oldType newType)) (patchId (str "fix-type-" fnSymbol))] (patch/makeAstPatch patchId targetModule (none) (none) (list op)))

fn insertExportIntoClause clause: Str exportStr: Str -> Str
  (let [(trimmed (stringTrim clause)) (len (stringLength trimmed))] (if (and (>= len 2) (stringEndsWith? trimmed "]")) (let [(prefix (safeStringSlice trimmed 0 (- len 1))) (trimmedPrefix (stringTrim prefix))] (if (stringEndsWith? trimmedPrefix "[") (str trimmedPrefix exportStr "]") (str trimmedPrefix " " exportStr "]"))) (str "[:x [" exportStr "]]")))

fn suggestMissingExportPatch targetModule: Str existingExports: Str symbolToExport: Str -> patch/AstPatch
  (let [(newNode (insertExportIntoClause existingExports symbolToExport)) (op (patch/makePatchOpReplace targetModule "exports" existingExports newNode)) (patchId (str "fix-export-" targetModule))] (patch/makeAstPatch patchId targetModule (none) (none) (list op)))

fn formatDiagnosticWithPatch d: SelfHealingDiagnostic -> Str
  (let [(patchStr (mt d.suggestedPatch ((some p) (str "\n  :suggestedPatch " (patch/renderPatch p))) ((none) "")))] (str "(:diagnostic\n" "  :code \"" d.code "\"\n" "  :symbol \"" d.symbol "\"\n" "  :anchor \"" d.anchor "\"\n" "  :message \"" d.message "\"" patchStr ")"))

fn renderDiagnosticReceipt d: SelfHealingDiagnostic -> Str
  (formatDiagnosticWithPatch d)

fn stripQuotes s: Str -> Str
  (let [(trimmed (stringTrim s)) (len (stringLength trimmed))] (if (and (and (>= len 2) (stringStartsWith? trimmed "\"")) (stringEndsWith? trimmed "\"")) (safeStringSlice trimmed 1 (- len 1)) trimmed))

fn extractFieldStep items: (List rd/SExpr) idx: Int64 len: Int64 key: Str -> Str
  (if (>= (+ idx 1) len) "" (let [(curr (optionOr (listGet items idx) (rd/makeAtom ""))) (currStr (rd/renderSexpr curr))] (if (= currStr key) (let [(valExpr (optionOr (listGet items (+ idx 1)) (rd/makeAtom "")))] (stripQuotes (rd/renderSexpr valExpr))) (extractFieldStep items (+ idx 1) len key))))

fn extractField items: (List rd/SExpr) key: Str -> Str
  (extractFieldStep items 0 (listLength items) key)

fn extractSubformStep items: (List rd/SExpr) idx: Int64 len: Int64 key: Str -> (Option rd/SExpr)
  (if (>= (+ idx 1) len) (none) (let [(curr (optionOr (listGet items idx) (rd/makeAtom ""))) (currStr (rd/renderSexpr curr))] (if (= currStr key) (listGet items (+ idx 1)) (extractSubformStep items (+ idx 1) len key))))

fn extractSubform items: (List rd/SExpr) key: Str -> (Option rd/SExpr)
  (extractSubformStep items 0 (listLength items) key)

fn parseSnippet s: Str -> (Result rd/SExpr Str)
  (let [(toks (lx/tokenize s)) (res (ast/readForms toks))] (mt res ((ok forms) (mt (listHead forms) ((some pf) (ok pf.expr)) ((none) (ok (rd/makeAtom s))))) ((err e) (err e.msg))))

fn parseDiagnosticReceipt content: Str -> (Result SelfHealingDiagnostic Str)
  (let [(parsedRes (parseSnippet content))] (mt parsedRes ((err e) (err (str "Diagnostic receipt syntax error: " e))) ((ok topExpr) (mt topExpr ((rd/sexprList items) (let [(tag (optionOr (listHead items) (rd/makeAtom "")))] (if (!= (rd/renderSexpr tag) ":diagnostic") (err "Receipt is not a :diagnostic form") (let [(code (extractField items ":code")) (sym (extractField items ":symbol")) (anc (extractField items ":anchor")) (msg (extractField items ":message")) (patchExpr (extractSubform items ":suggestedPatch"))] (if (or (stringEmpty? code) (stringEmpty? sym)) (err "Missing mandatory :code or :symbol in diagnostic receipt") (let [(optPatch (mt patchExpr ((some pExpr) (let [(pStr (rd/renderSexpr pExpr))] (mt (patch/parsePatch pStr) ((ok p) (some p)) ((err _) (none))))) ((none) (none))))] (ok (makeSelfHealingDiagnostic code sym anc msg optPatch)))))))) (_ (err "Diagnostic receipt must be an S-expression list"))))))
