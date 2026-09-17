(module asl-compiler/diagnostics
  :d "Compiler Diagnostics with Structured Candidate AST Patches for Autonomous Self-Healing"
  :x [SelfHealingDiagnostic makeSelfHealingDiagnostic
      emitDiagnosticWithPatch
      suggestMissingImportPatch
      suggestMissingMatchBranchPatch
      suggestTypeMismatchPatch
      suggestMissingExportPatch
      formatDiagnosticWithPatch
      renderDiagnosticReceipt
      parseDiagnosticReceipt]
  :i [(asl-ir/patch :a patch)
      (asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)])

(dfs SelfHealingDiagnostic
  (:f code Str "Diagnostic rule code e.g. ERR_UNBOUND_SYMBOL, ERR_UNHANDLED_VARIANT, ERR_TYPE_MISMATCH")
  (:f symbol Str "Target symbol e.g. Module:symbol")
  (:f anchor Str "Anchor within symbol e.g. imports, match/0, body, retType")
  (:f message Str "Human and agent readable diagnostic explanation")
  (:f suggestedPatch (Option patch/AstPatch) "Candidate AST patch to heal the defect"))

(df makeSelfHealingDiagnostic [(code Str) (symbol Str) (anchor Str) (message Str) (suggestedPatch (Option patch/AstPatch))] -> SelfHealingDiagnostic
  :d "Constructs a SelfHealingDiagnostic record."
  (SelfHealingDiagnostic :code code :symbol symbol :anchor anchor :message message :suggestedPatch suggestedPatch))

(df emitDiagnosticWithPatch [(code Str) (symbol Str) (anchor Str) (message Str) (suggestedPatch (Option patch/AstPatch))] -> SelfHealingDiagnostic
  :d "Emits a structured SelfHealingDiagnostic carrying an optional candidate AST patch."
  (makeSelfHealingDiagnostic code symbol anchor message suggestedPatch))

(df safeStringSlice [(s Str) (start Int64) (end Int64)] -> Str
  :d "Safely slices a string and unwraps the Option result."
  (mt (string-slice s start end)
    ((some res) res)
    ((none) "")))

(df insertImportIntoClause [(clause Str) (importStr Str)] -> Str
  :d "Inserts an import entry into an existing [...] or (:i [...]) clause or creates a new one."
  (let [(trimmed (string-trim clause))
        (len (string-length trimmed))]
    (cond
      ((and (>= len 2) (string-ends-with? trimmed "])"))
       (let [(prefix (safeStringSlice trimmed 0 (- len 2)))
             (trimmedPrefix (string-trim prefix))]
         (if (string-ends-with? trimmedPrefix "[")
             (str trimmedPrefix importStr "])")
             (str trimmedPrefix " " importStr "])"))))
      ((and (>= len 2) (string-ends-with? trimmed "]"))
       (let [(prefix (safeStringSlice trimmed 0 (- len 1)))
             (trimmedPrefix (string-trim prefix))]
         (if (string-ends-with? trimmedPrefix "[")
             (str trimmedPrefix importStr "]")
             (str trimmedPrefix " " importStr "]"))))
      (:else
       (str "[" importStr "]")))))

(df suggestMissingImportPatch [(targetModule Str) (existingImports Str) (missingImport Str)] -> patch/AstPatch
  :d "Constructs a candidate AST patch to insert a missing import into target module."
  (let [(newNode (insertImportIntoClause existingImports missingImport))
        (op (patch/makePatchOpReplace targetModule "imports" existingImports newNode))
        (patchId (str "fix-import-" targetModule))]
    (patch/makeAstPatch patchId targetModule (none) (none) (list op))))

(df insertBranchIntoMatch [(matchExpr Str) (branchStr Str)] -> Str
  :d "Appends a candidate missing branch before the closing delimiter of a match expression."
  (let [(trimmed (string-trim matchExpr))
        (len (string-length trimmed))]
    (if (and (>= len 1) (string-ends-with? trimmed ")"))
        (let [(prefix (safeStringSlice trimmed 0 (- len 1)))]
          (str (string-trim prefix) " " branchStr ")"))
        (str trimmed " " branchStr))))

(df suggestMissingMatchBranchPatch [(targetModule Str) (fnSymbol Str) (oldMatchExpr Str) (missingBranch Str)] -> patch/AstPatch
  :d "Constructs a candidate AST patch to insert an unhandled match variant into a pattern match."
  (let [(newNode (insertBranchIntoMatch oldMatchExpr missingBranch))
        (op (patch/makePatchOpReplace fnSymbol "body" oldMatchExpr newNode))
        (patchId (str "fix-match-" fnSymbol))]
    (patch/makeAstPatch patchId targetModule (none) (none) (list op))))

(df suggestTypeMismatchPatch [(targetModule Str) (fnSymbol Str) (oldType Str) (newType Str)] -> patch/AstPatch
  :d "Constructs a candidate AST patch to correct a function return type annotation."
  (let [(op (patch/makePatchOpRetype fnSymbol "retType" oldType newType))
        (patchId (str "fix-type-" fnSymbol))]
    (patch/makeAstPatch patchId targetModule (none) (none) (list op))))

(df insertExportIntoClause [(clause Str) (exportStr Str)] -> Str
  :d "Inserts an exported symbol identifier into an existing (:x [...]) clause."
  (let [(trimmed (string-trim clause))
        (len (string-length trimmed))]
    (if (and (>= len 2) (string-ends-with? trimmed "]"))
        (let [(prefix (safeStringSlice trimmed 0 (- len 1)))
              (trimmedPrefix (string-trim prefix))]
          (if (string-ends-with? trimmedPrefix "[")
              (str trimmedPrefix exportStr "]")
              (str trimmedPrefix " " exportStr "]")))
        (str "[:x [" exportStr "]]"))))

(df suggestMissingExportPatch [(targetModule Str) (existingExports Str) (symbolToExport Str)] -> patch/AstPatch
  :d "Constructs a candidate AST patch to add an unexported symbol to module exports."
  (let [(newNode (insertExportIntoClause existingExports symbolToExport))
        (op (patch/makePatchOpReplace targetModule "exports" existingExports newNode))
        (patchId (str "fix-export-" targetModule))]
    (patch/makeAstPatch patchId targetModule (none) (none) (list op))))

(df formatDiagnosticWithPatch [(d SelfHealingDiagnostic)] -> Str
  :d "Formats a SelfHealingDiagnostic into canonical ASN notation adhering strictly to Zero-Line-Number Invariant."
  (let [(patchStr (mt (.-suggestedPatch d)
                    ((some p) (str "\n  :suggestedPatch " (patch/renderPatch p)))
                    ((none) "")))]
    (str "(:diagnostic\n"
         "  :code \"" (.-code d) "\"\n"
         "  :symbol \"" (.-symbol d) "\"\n"
         "  :anchor \"" (.-anchor d) "\"\n"
         "  :message \"" (.-message d) "\""
         patchStr
         ")")))

(df renderDiagnosticReceipt [(d SelfHealingDiagnostic)] -> Str
  :d "Renders diagnostic receipt to compact S-expression string."
  (formatDiagnosticWithPatch d))

(df stripQuotes [(s Str)] -> Str
  :d "Strips surrounding double quotes if present."
  (let [(trimmed (string-trim s))
        (len (string-length trimmed))]
    (if (and (and (>= len 2) (string-starts-with? trimmed "\"")) (string-ends-with? trimmed "\""))
        (safeStringSlice trimmed 1 (- len 1))
        trimmed)))

(df extractFieldStep [(items (List rd/SExpr)) (idx Int64) (len Int64) (key Str)] -> Str
  :d "Extracts a string field value from an S-expression item list by keyword."
  (if (>= (+ idx 1) len)
      ""
      (let [(curr (option-or (list-get items idx) (rd/makeAtom "")))
            (currStr (rd/renderSexpr curr))]
        (if (= currStr key)
            (let [(valExpr (option-or (list-get items (+ idx 1)) (rd/makeAtom "")))]
              (stripQuotes (rd/renderSexpr valExpr)))
            (extractFieldStep items (+ idx 1) len key)))))

(df extractField [(items (List rd/SExpr)) (key Str)] -> Str
  :d "Extracts a field string value by keyword from S-expression item list."
  (extractFieldStep items 0 (list-length items) key))

(df extractSubformStep [(items (List rd/SExpr)) (idx Int64) (len Int64) (key Str)] -> (Option rd/SExpr)
  :d "Extracts a subform S-expression from an item list by keyword."
  (if (>= (+ idx 1) len)
      (none)
      (let [(curr (option-or (list-get items idx) (rd/makeAtom "")))
            (currStr (rd/renderSexpr curr))]
        (if (= currStr key)
            (list-get items (+ idx 1))
            (extractSubformStep items (+ idx 1) len key)))))

(df extractSubform [(items (List rd/SExpr)) (key Str)] -> (Option rd/SExpr)
  :d "Extracts a subform S-expression by keyword."
  (extractSubformStep items 0 (list-length items) key))

(df parseSnippet [(s Str)] -> (Result rd/SExpr Str)
  :d "Parses an S-expression snippet string."
  (let [(toks (lx/tokenize s))
        (res (ast/readForms toks))]
    (mt res
      ((ok forms)
       (mt (list-head forms)
         ((some pf) (ok (.-expr pf)))
         ((none) (ok (rd/makeAtom s)))))
      ((err e)
       (err (.-msg e))))))

(df parseDiagnosticReceipt [(content Str)] -> (Result SelfHealingDiagnostic Str)
  :d "Parses a structured diagnostic receipt S-expression into a SelfHealingDiagnostic record."
  (let [(parsedRes (parseSnippet content))]
    (mt parsedRes
      ((err e) (err (str "Diagnostic receipt syntax error: " e)))
      ((ok topExpr)
       (mt topExpr
         ((rd/sexprList items)
          (let [(tag (option-or (list-head items) (rd/makeAtom "")))]
            (if (!= (rd/renderSexpr tag) ":diagnostic")
                (err "Receipt is not a :diagnostic form")
                (let [(code (extractField items ":code"))
                      (sym (extractField items ":symbol"))
                      (anc (extractField items ":anchor"))
                      (msg (extractField items ":message"))
                      (patchExpr (extractSubform items ":suggestedPatch"))]
                  (if (or (string-empty? code) (string-empty? sym))
                      (err "Missing mandatory :code or :symbol in diagnostic receipt")
                      (let [(optPatch (mt patchExpr
                                        ((some pExpr)
                                         (let [(pStr (rd/renderSexpr pExpr))]
                                           (mt (patch/parsePatch pStr)
                                             ((ok p) (some p))
                                             ((err _) (none)))))
                                        ((none) (none))))]
                        (ok (makeSelfHealingDiagnostic code sym anc msg optPatch))))))))
         (_ (err "Diagnostic receipt must be an S-expression list")))))))
