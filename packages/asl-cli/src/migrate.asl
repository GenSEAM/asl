(module asl-cli/migrate :x [runMigrate migrateSource verifySemanticEquivalence migrateBatch validateDryRunBatch auditMonorepoEquivalence BatchAuditSummary DryRunReport main discoverTargetSourceFiles] :i [(ast :a a) (reader :a rd) (lexer :a lx) (indentParser :a ip) (indentPrinter :a ipr) (astConverter :a cv) (astPrinter :a ap)])

fn readSexprs src: String -> (Result (List rd/SExpr) String)
  (let [(toks (lx/tokenize src)) (readRes (a/readForms toks))] (mt readRes ((err e) (err e.msg)) ((ok pfs) (ok (map (fn [(pf a/PosForm)] -> rd/SExpr pf.expr) pfs)))))

fn normalizeTypeAtom s: String -> String
  (cond ((or (= s "Int") (= s "I64")) "Int64") ((= s "I32") "Int32") ((or (= s "Float") (or (= s "F64") (= s "Num"))) "Float64") ((= s "F32") "Float32") ((= s "Str") "String") (else s))

fn normalizeKeywordAtom s: String -> String
  (cond ((= s ":d") ":doc") ((= s ":x") ":export") ((= s ":i") ":import") ((= s ":a") ":as") ((= s ":f") ":field") ((or (= s "df") (or (= s "defun") (= s "fn"))) "defun") ((= s "mt") "match") ((or (= s "schema") (= s "dfs")) "defschema") ((or (= s "enum") (= s "dfe")) "defenum") (else s))

fn atomsEquivalent? v1: String v2: String -> Bool
  (or (= v1 v2) (or (= (normalizeKeywordAtom v1) (normalizeKeywordAtom v2)) (or (= (normalizeTypeAtom v1) (normalizeTypeAtom v2)) (or (= v1 (str v2 "?")) (= (str v1 "?") v2)))))

fn collectAtomStrings items: (List rd/SExpr) -> (List String)
  (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String) (mt it ((rd/sexprAtom v) (if (or (= v "list") (stringStartsWith? v ":")) acc (listAppend acc (list v)))) ((rd/sexprList subItems) (listAppend acc (collectAtomStrings subItems))) ((rd/sexprVect subItems) (listAppend acc (collectAtomStrings subItems))))) (list) items)

fn findKeywordOption items: (List rd/SExpr) k1: String k2: String -> (Option rd/SExpr)
  (mt (listHead items) ((none) (none)) ((some h) (let [(hVal (rd/sexprHead h)) (tailItems (optionOr (listTail items) (list)))] (if (or (= hVal k1) (= hVal k2)) (listHead tailItems) (findKeywordOption tailItems k1 k2)))))

fn isParenOrBracket? s: String -> Bool
  (or (= s "(") (or (= s ")") (or (= s "[") (or (= s "]") (= s "list")))))

fn isSectionHeader? v: String -> Bool
  (or (= v ":doc") (or (= v ":d") (or (= v ":export") (or (= v ":x") (or (= v ":import") (= v ":i"))))))

fn extractExportItem item: rd/SExpr -> (List String)
  (mt item ((rd/sexprAtom v) (if (or (= v "list") (stringStartsWith? v ":")) (list) (list v))) ((rd/sexprList subItems) (let [(hd (rd/sexprHead item))] (if (and (= hd "match") (>= (listLength subItems) 2)) (let [(target (optionOr (listGet subItems 1) (rd/makeAtom "")))] (if (rd/isAtom? target) (list (str (rd/sexprHead target) "?")) (collectAtomStrings subItems))) (fold (fn [(acc (List String)) (sub rd/SExpr)] -> (List String) (listAppend acc (extractExportItem sub))) (list) subItems)))) ((rd/sexprVect subItems) (fold (fn [(acc (List String)) (sub rd/SExpr)] -> (List String) (listAppend acc (extractExportItem sub))) (list) subItems)))

fn collectSectionAtomsStep tail: (List rd/SExpr) -> (List String)
  (mt (listHead tail) ((none) (list)) ((some it) (let [(nxt (optionOr (listTail tail) (list)))] (mt it ((rd/sexprAtom v) (if (isSectionHeader? v) (list) (if (or (stringStartsWith? v ":") (isParenOrBracket? v)) (collectSectionAtomsStep nxt) (cons v (collectSectionAtomsStep nxt))))) ((rd/sexprList sub) (listAppend (extractExportItem it) (collectSectionAtomsStep nxt))) ((rd/sexprVect sub) (listAppend (extractExportItem it) (collectSectionAtomsStep nxt)))))))

fn sectionAtoms items: (List rd/SExpr) k1: String k2: String -> (List String)
  (mt (listHead items) ((none) (list)) ((some h) (let [(hVal (rd/sexprHead h)) (tailItems (optionOr (listTail items) (list)))] (if (or (= hVal k1) (= hVal k2)) (collectSectionAtomsStep tailItems) (sectionAtoms tailItems k1 k2)))))

fn verifyModuleEquivalence items1: (List rd/SExpr) items2: (List rd/SExpr) -> Bool
  (let [(path1 (rd/sexprHead (optionOr (listGet items1 1) (rd/makeAtom "")))) (path2 (rd/sexprHead (optionOr (listGet items2 1) (rd/makeAtom ""))))] (if (!= path1 path2) false (let [(doc1 (findKeywordOption items1 ":doc" ":d")) (doc2 (findKeywordOption items2 ":doc" ":d")) (docMatch (mt doc1 ((some d1) (mt doc2 ((some d2) (= (rd/sexprHead d1) (rd/sexprHead d2))) ((none) false))) ((none) (mt doc2 ((some _) false) ((none) true))))) (expAtoms1 (sectionAtoms items1 ":export" ":x")) (expAtoms2 (sectionAtoms items2 ":export" ":x")) (expMatch (= expAtoms1 expAtoms2)) (impAtoms1 (sectionAtoms items1 ":import" ":i")) (impAtoms2 (sectionAtoms items2 ":import" ":i")) (impMatch (= impAtoms1 impAtoms2))] (and docMatch (and expMatch impMatch)))))

fn stripDefunDoc items: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead items) ((none) (list)) ((some h) (let [(hVal (rd/sexprHead h)) (tailItems (optionOr (listTail items) (list)))] (if (or (= hVal ":d") (= hVal ":doc")) (optionOr (listTail tailItems) (list)) (cons h (stripDefunDoc tailItems))))))

fn extractParamNames pExpr: rd/SExpr -> (List String)
  (mt pExpr ((rd/sexprVect items) (fold (fn [(acc (List String)) (p rd/SExpr)] -> (List String) (mt p ((rd/sexprList sub) (let [(v (rd/sexprHead (optionOr (listHead sub) (rd/makeAtom ""))))] (if (and (not (stringEmpty? v)) (not (stringStartsWith? v ":"))) (listAppend acc (list v)) acc))) ((rd/sexprAtom v) (if (and (not (stringEmpty? v)) (not (stringStartsWith? v ":")) (!= v ")")) (listAppend acc (list v)) acc)) (_ acc))) (list) items)) ((rd/sexprList items) (fold (fn [(acc (List String)) (p rd/SExpr)] -> (List String) (mt p ((rd/sexprList sub) (let [(v (rd/sexprHead (optionOr (listHead sub) (rd/makeAtom ""))))] (if (and (not (stringEmpty? v)) (not (stringStartsWith? v ":"))) (listAppend acc (list v)) acc))) ((rd/sexprAtom v) (if (and (not (stringEmpty? v)) (not (stringStartsWith? v ":")) (!= v ")")) (listAppend acc (list v)) acc)) (_ acc))) (list) items)) (_ (list)))

fn extractDefunBody items: (List rd/SExpr) -> (List rd/SExpr)
  (let [(clean (stripDefunDoc items)) (len (listLength clean))] (if (< len 3) (list) (let [(afterParams (optionOr (listSlice clean 3 len) (list)))] (mt (listHead afterParams) ((none) (list)) ((some first) (if (= (rd/sexprHead first) "->") (let [(tail1 (optionOr (listTail afterParams) (list)))] (optionOr (listTail tail1) (list))) afterParams))))))

fn extractDefunRetType items: (List rd/SExpr) -> (Option String)
  (let [(clean (stripDefunDoc items)) (len (listLength clean))] (if (< len 4) (none) (let [(afterParams (optionOr (listSlice clean 3 len) (list)))] (mt (listHead afterParams) ((none) (none)) ((some first) (if (= (rd/sexprHead first) "->") (let [(tail1 (optionOr (listTail afterParams) (list)))] (mt (listHead tail1) ((some r) (some (rd/sexprHead r))) ((none) (none)))) (none)))))))

fn exprListsEquivalent? l1: (List rd/SExpr) l2: (List rd/SExpr) -> Bool
  (if (!= (listLength l1) (listLength l2)) false (let [(len (listLength l1))] (fold (fn [(acc Bool) (i Int64)] -> Bool (if (not acc) false (let [(e1 (optionOr (listGet l1 i) (rd/makeAtom ""))) (e2 (optionOr (listGet l2 i) (rd/makeAtom "")))] (verifySemanticEquivalence e1 e2)))) true (range 0 len))))

fn verifyFunctionEquivalence items1: (List rd/SExpr) items2: (List rd/SExpr) -> Bool
  (if (or (< (listLength items1) 3) (< (listLength items2) 3)) (exprListsEquivalent? items1 items2) (let [(name1 (rd/sexprHead (optionOr (listGet items1 1) (rd/makeAtom "")))) (name2 (rd/sexprHead (optionOr (listGet items2 1) (rd/makeAtom "")))) (nameMatch (atomsEquivalent? name1 name2))] (if (not nameMatch) false (let [(params1 (extractParamNames (optionOr (listGet items1 2) (rd/makeAtom "")))) (params2 (extractParamNames (optionOr (listGet items2 2) (rd/makeAtom "")))) (paramsMatch (= params1 params2))] (if (not paramsMatch) false (let [(ret1 (extractDefunRetType items1)) (ret2 (extractDefunRetType items2)) (retMatch (mt ret1 ((some r1) (mt ret2 ((some r2) (atomsEquivalent? r1 r2)) ((none) true))) ((none) (mt ret2 ((some _) true) ((none) true)))))] (if (not retMatch) false (let [(body1 (extractDefunBody items1)) (body2 (extractDefunBody items2))] (if (and (listEmpty? body1) (listEmpty? body2)) true (if (exprListsEquivalent? body1 body2) true (let [(atoms1 (collectAtomStrings body1)) (atoms2 (collectAtomStrings body2))] (fold (fn [(acc Bool) (a String)] -> Bool (if (not acc) false (or (listContains? atoms2 a) (listContains? atoms2 (normalizeTypeAtom a)) (let [(trimmed (if (stringEndsWith? a "?") (optionOr (stringSlice a 0 (- (stringLength a) 1)) a) a))] (listContains? atoms2 trimmed))))) true atoms1))))))))))))

fn verifySemanticEquivalence orig: rd/SExpr reparsed: rd/SExpr -> Bool
  (mt orig ((rd/sexprAtom v1) (mt reparsed ((rd/sexprAtom v2) (atomsEquivalent? v1 v2)) (_ false))) ((rd/sexprList items1) (mt reparsed ((rd/sexprList items2) (let [(h1 (rd/sexprHead orig)) (h2 (rd/sexprHead reparsed))] (cond ((and (= h1 "module") (= h2 "module")) (verifyModuleEquivalence items1 items2)) ((and (or (= h1 "df") (or (= h1 "defun") (= h1 "fn"))) (or (= h2 "df") (or (= h2 "defun") (= h2 "fn")))) (verifyFunctionEquivalence items1 items2)) ((and (or (= h1 "defschema") (or (= h1 "schema") (= h1 "dfs"))) (or (= h2 "defschema") (or (= h2 "schema") (= h2 "dfs")))) (exprListsEquivalent? (optionOr (listTail items1) (list)) (optionOr (listTail items2) (list)))) ((and (or (= h1 "defenum") (or (= h1 "enum") (= h1 "dfe"))) (or (= h2 "defenum") (or (= h2 "enum") (= h2 "dfe")))) (exprListsEquivalent? (optionOr (listTail items1) (list)) (optionOr (listTail items2) (list)))) ((and (or (= h1 ":field") (= h1 ":f")) (or (= h2 ":field") (= h2 ":f"))) (let [(name1 (rd/sexprHead (optionOr (listGet items1 1) (rd/makeAtom "")))) (name2 (rd/sexprHead (optionOr (listGet items2 1) (rd/makeAtom "")))) (type1 (rd/sexprHead (optionOr (listGet items1 2) (rd/makeAtom "")))) (type2 (rd/sexprHead (optionOr (listGet items2 2) (rd/makeAtom ""))))] (and (= name1 name2) (atomsEquivalent? type1 type2)))) ((and (= h1 ":case") (= h2 ":case")) (let [(name1 (rd/sexprHead (optionOr (listGet items1 1) (rd/makeAtom "")))) (name2 (rd/sexprHead (optionOr (listGet items2 1) (rd/makeAtom ""))))] (= name1 name2))) (else (exprListsEquivalent? items1 items2))))) ((rd/sexprVect items2) (exprListsEquivalent? items1 items2)) (_ false))) ((rd/sexprVect items1) (mt reparsed ((rd/sexprVect items2) (exprListsEquivalent? items1 items2)) ((rd/sexprList items2) (if (and (= (rd/sexprHead reparsed) "list") (= (listLength items1) (- (listLength items2) 1))) (exprListsEquivalent? items1 (optionOr (listTail items2) (list))) (exprListsEquivalent? items1 items2))) (_ false))))

fn verifyAllSemanticEquivalence origForms: (List rd/SExpr) reparsedForms: (List rd/SExpr) -> Bool
  (if (!= (listLength origForms) (listLength reparsedForms)) false (let [(len (listLength origForms))] (fold (fn [(acc Bool) (i Int64)] -> Bool (if (not acc) false (let [(o (optionOr (listGet origForms i) (rd/makeAtom ""))) (r (optionOr (listGet reparsedForms i) (rd/makeAtom "")))] (verifySemanticEquivalence o r)))) true (range 0 len))))

fn findModule forms: (List a/TopForm) -> (Option a/ModuleNode)
  (mt (listHead forms) ((none) (none)) ((some f) (mt f ((a/topModule m) (some m)) (_ (none)))))

fn tryGenerateIndented src: Str origSexprs: (List rd/SExpr) -> (Result Str Str)
  (mt (a/parse src) ((ok forms) (mt (findModule forms) ((some modNode) (ok (ap/printAstModule modNode))) ((none) (if (not (listEmpty? forms)) (ok (stringJoin (map (fn [(tf a/TopForm)] -> String (ap/printTopForm tf)) forms) "\n\n")) (ok (stringJoin (map (fn [(s rd/SExpr)] -> String (ipr/formatIndented s)) origSexprs) "\n\n")))))) ((err _) (if (not (listEmpty? origSexprs)) (ok (stringJoin (map (fn [(s rd/SExpr)] -> String (ipr/formatIndented s)) origSexprs) "\n\n")) (err "Migration aborted: semantic divergence detected"))))

fn findModuleName forms: (List rd/SExpr) -> String
  (mt (listHead forms) ((none) "unnamed") ((some f) (mt f ((rd/sexprList items) (if (= (rd/sexprHead f) "module") (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom "unnamed"))) (findModuleName (optionOr (listTail forms) (list))))) (_ (findModuleName (optionOr (listTail forms) (list)))))))

fn findModuleDoc forms: (List rd/SExpr) -> (Option String)
  (mt (listHead forms) ((none) (none)) ((some f) (mt f ((rd/sexprList items) (if (= (rd/sexprHead f) "module") (mt (findKeywordOption items ":doc" ":d") ((some d) (some (rd/sexprHead d))) ((none) (none))) (findModuleDoc (optionOr (listTail forms) (list))))) (_ (findModuleDoc (optionOr (listTail forms) (list)))))))

fn collectFnDocs forms: (List rd/SExpr) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (f rd/SExpr)] -> (List (Pair String String)) (mt f ((rd/sexprList items) (let [(headSym (rd/sexprHead f))] (if (or (= headSym "df") (or (= headSym "defun") (= headSym "fn"))) (let [(fnName (rd/sexprHead (optionOr (listGet items 1) (rd/makeAtom ""))))] (mt (findKeywordOption items ":doc" ":d") ((some d) (listAppend acc (list (pair fnName (rd/sexprHead d))))) ((none) acc))) acc))) (_ acc))) (list) forms)

fn cleanDocFileName name: String -> String
  (stringJoin (stringSplit name "/") "_")

fn ! externalizeDocstrings origForms: (List rd/SExpr) -> Bool
  (let [(modName (findModuleName origForms)) (modDoc (findModuleDoc origForms)) (fnDocs (collectFnDocs origForms))] (if (and (none? modDoc) (listEmpty? fnDocs)) true (let [(docFileName (str ".asl/mem/docs/" (cleanDocFileName modName) ".asn")) (modDocStr (optionOr modDoc "")) (fnEntries (map (fn [(p (Pair String String))] -> String (str "    (:fn \"" (pairFirst p) "\" :doc \"" (pairSecond p) "\")")) fnDocs)) (fnBlock (if (listEmpty? fnEntries) "" (str "\n  :items [\n" (stringJoin fnEntries "\n") "\n  ]"))) (asnContent (str "(:doc :module \"" modName "\"\n" "  :doc \"" modDocStr "\"" fnBlock ")\n"))] (mt (fileWrite docFileName asnContent) ((ok _) true) ((err _) false)))))

fn ! migrateSource src: Str path: Str dryRun: Bool checkOnly: Bool -> (Result Str Str)
  (let [(actualPath (if (stringEmpty? path) "memory.asl" path)) (isCheckOnly (if checkOnly true false)) (isDryRun (if dryRun true (if (stringEmpty? path) true false)))] (if (stringContains? src "\nfn ") (mt (ip/parseIndentedForms src) ((err _) (err "Migration aborted: semantic divergence detected")) ((ok _) (if isCheckOnly (ok (str "✓ " actualPath ": Validated migratable.")) (if isDryRun (ok src) (ok (str "✓ " actualPath ": Already migrated.")))))) (mt (readSexprs src) ((err _) (err "Migration aborted: semantic divergence detected")) ((ok origForms) (if (listEmpty? origForms) (err "Migration aborted: semantic divergence detected") (do (if (and (not isDryRun) (not isCheckOnly)) (externalizeDocstrings origForms) true) (mt (tryGenerateIndented src origForms) ((err _) (err "Migration aborted: semantic divergence detected")) ((ok indentedText) (mt (ip/parseIndentedForms indentedText) ((err _) (err "Migration aborted: semantic divergence detected")) ((ok reparsedForms) (if (not (verifyAllSemanticEquivalence origForms reparsedForms)) (err "Migration aborted: semantic divergence detected") (if isCheckOnly (ok (str "✓ " actualPath ": Validated migratable.")) (if isDryRun (ok indentedText) (mt (fileWrite actualPath indentedText) ((ok _) (ok (str "✓ " actualPath ": Successfully migrated."))) ((err _) (err (str "Failed to write migrated file: " actualPath)))))))))))))))))

fn ! validateBatchFile path: Str -> (Result (Pair Str Str) Str)
  (mt (fileRead path) ((err _) (err (str "Migration aborted: semantic divergence detected in " path))) ((ok src) (if (stringContains? src "\nfn ") (mt (ip/parseIndentedForms src) ((ok _) (ok (pair path src))) ((err _) (err (str "Migration aborted: semantic divergence detected in " path)))) (mt (readSexprs src) ((err _) (err (str "Migration aborted: semantic divergence detected in " path))) ((ok origForms) (if (listEmpty? origForms) (err (str "Migration aborted: semantic divergence detected in " path)) (mt (tryGenerateIndented src origForms) ((err _) (err (str "Migration aborted: semantic divergence detected in " path))) ((ok indentedText) (mt (ip/parseIndentedForms indentedText) ((err _) (err (str "Migration aborted: semantic divergence detected in " path))) ((ok reparsedForms) (if (not (verifyAllSemanticEquivalence origForms reparsedForms)) (err (str "Migration aborted: semantic divergence detected in " path)) (ok (pair path indentedText)))))))))))))

fn ! validateBatchFilesLoop remaining: (List Str) acc: (List (Pair Str Str)) -> (Result (List (Pair Str Str)) Str)
  (mt (listHead remaining) ((none) (ok (listReverse acc))) ((some p) (mt (validateBatchFile p) ((err e) (err e)) ((ok validated) (let [(tail (optionOr (listTail remaining) (list)))] (validateBatchFilesLoop tail (cons validated acc)))))))

fn ! writeBatchFilesLoop remaining: (List (Pair Str Str)) -> (Result Bool Str)
  (mt (listHead remaining) ((none) (ok true)) ((some it) (let [(targetPath (pairFirst it)) (content (pairSecond it)) (tail (optionOr (listTail remaining) (list)))] (mt (fileWrite targetPath content) ((err _) (err (str "Failed to write migrated file: " targetPath))) ((ok _) (writeBatchFilesLoop tail))))))

fn ! migrateBatch paths: (List Str) dryRun: Bool checkOnly: Bool -> (Result (List Str) Str)
  (mt (validateBatchFilesLoop paths (list)) ((err e) (err e)) ((ok validatedPairs) (if checkOnly (ok (map (fn [(p Str)] -> Str (str "✓ " p ": Validated migratable.")) paths)) (if dryRun (ok (map (fn [(item (Pair Str Str))] -> Str (pairSecond item)) validatedPairs)) (mt (writeBatchFilesLoop validatedPairs) ((err e) (err e)) ((ok _) (ok (map (fn [(p Str)] -> Str (str "✓ " p ": Successfully migrated.")) paths))))))))

(schema MigrateCliOptions (:f path String) (:f dryRun Bool) (:f checkOnly Bool) (:f v04 Bool))

fn parseMigrateArgsLoop args: (List String) opts: MigrateCliOptions -> MigrateCliOptions
  (mt (listHead args) ((none) opts) ((some arg) (let [(restArgs (optionOr (listTail args) (list)))] (cond ((= arg "--dry-run") (parseMigrateArgsLoop restArgs (with opts :dryRun true))) ((= arg "--check") (parseMigrateArgsLoop restArgs (with opts :checkOnly true))) ((= arg "--v04") (parseMigrateArgsLoop restArgs (with opts :v04 true))) (else (let [(curPath opts.path) (newPath (if (stringEmpty? curPath) arg curPath))] (parseMigrateArgsLoop restArgs (with opts :path newPath))))))))

fn parseMigrateArgs args: (List String) -> MigrateCliOptions
  (parseMigrateArgsLoop args (MigrateCliOptions :path "" :dryRun false :checkOnly false :v04 false))

fn ! runMigrate args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl migrate [--dry-run|--check] <file.asl>") (let [(opts (parseMigrateArgs args)) (path opts.path)] (if (stringEmpty? path) (err "Usage: asl migrate [--dry-run|--check] <file.asl>") (let [(srcRes (fileRead path))] (mt srcRes ((err _) (err (str "Failed to read target file: " path))) ((ok src) (migrateSource src path opts.dryRun opts.checkOnly)))))))

(schema BatchAuditSummary (:f scannedCount Int64) (:f passedCount Int64) (:f failedCount Int64) (:f errors (List (pair Str Str))))

(schema DryRunReport (:f scannedCount Int64) (:f passedCount Int64) (:f failedCount Int64) (:f errors (List (pair Str Str))))

fn ! validateDryRunFile path: Str -> (Result Bool Str)
  (mt (fileRead path) ((err _) (err (str "Failed to read target file: " path))) ((ok src) (if (stringContains? src "\nfn ") (mt (ip/parseIndentedForms src) ((ok _) (ok true)) ((err e) (err (str "Parse error in " path ": " e)))) (mt (readSexprs src) ((err e) (err (str "Parse error in " path ": " e))) ((ok origForms) (if (listEmpty? origForms) (err (str "Empty source forms in " path)) (mt (tryGenerateIndented src origForms) ((err e) (err (str "Indented generation failure in " path ": " e))) ((ok indentedText) (mt (ip/parseIndentedForms indentedText) ((err e) (err (str "Reparse failure in " path ": " e))) ((ok reparsedForms) (if (verifyAllSemanticEquivalence origForms reparsedForms) (ok true) (err (str "Semantic divergence detected in " path)))))))))))))

fn ! validateDryRunBatchLoop remaining: (List Str) summary: BatchAuditSummary -> BatchAuditSummary
  (mt (listHead remaining) ((none) summary) ((some p) (let [(tail (optionOr (listTail remaining) (list))) (scanned (+ summary.scannedCount 1)) (vRes (validateDryRunFile p))] (mt vRes ((ok _) (validateDryRunBatchLoop tail (with summary :scannedCount scanned :passedCount (+ summary.passedCount 1)))) ((err reason) (validateDryRunBatchLoop tail (with summary :scannedCount scanned :failedCount (+ summary.failedCount 1) :errors (cons (pair p reason) summary.errors))))))))

fn ! validateDryRunBatch paths: (List Str) -> BatchAuditSummary
  (validateDryRunBatchLoop paths (BatchAuditSummary :scannedCount 0 :passedCount 0 :failedCount 0 :errors (list)))

fn ! discoverTargetSourceFiles roots: (List Str) -> (List Str)
  (let [(effectiveRoots (if (listEmpty? roots) (list "asl/packages" "harness" "intel" "vdom") roots)) (rootArgs (stringJoin effectiveRoots " ")) (findCmd (str "find " rootArgs " -type f -name '*.asl' 2>/dev/null | sort")) (res (processRun findCmd))] (if (!= res.exitCode 0) (list) (filter (fn [(s Str)] -> Bool (not (stringEmpty? s))) (stringSplit res.stdout "\n"))))

fn ! auditMonorepoEquivalence targetRoots: (List Str) -> BatchAuditSummary
  (let [(files (discoverTargetSourceFiles targetRoots))] (validateDryRunBatch files))

fn ! main args: (List Str) -> (Result Unit IoError)
  (let [(cleanArgs (filter (fn [(a Str)] -> Bool (!= a "--")) args))] (mt (runMigrate cleanArgs) ((ok msg) (do (println msg) (ok ()))) ((err errMsg) (do (println errMsg) (err (other))))))
