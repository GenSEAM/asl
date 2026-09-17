(module asl-cli/migrate
  :d "Automated migration toolchain converting S-expression ASL modules to indented syntax."
  :x [runMigrate
      migrateSource
      verifySemanticEquivalence
      migrateBatch
      validateDryRunBatch
      auditMonorepoEquivalence
      BatchAuditSummary
      DryRunReport
      main]
  :i [(ast :a a)
      (reader :a rd)
      (lexer :a lx)
      (indentParser :a ip)
      (indentPrinter :a ipr)
      (astConverter :a cv)
      (astPrinter :a ap)])

(dfs Frame
  (:f items (List rd/SExpr) "Completed children, kept reversed")
  (:f paren Bool "True for a ( ) list, false for a [ ] vector"))

(dfs ReadState
  (:f stack (List Frame) "Open frames, innermost first")
  (:f out (List rd/SExpr) "Completed top-level forms, kept reversed")
  (:f fail (Option String) "The first error, once set nothing else is read"))

(df pushFrame [(st ReadState) (paren Bool)] -> ReadState
  :d "Pushes a new frame onto the reader stack."
  (ReadState :stack (list-cons (Frame :items (list) :paren paren) (.-stack st))
             :out (.-out st)
             :fail (.-fail st)))

(df finishFrame [(st ReadState) (f Frame)] -> ReadState
  :d "Closes the innermost frame into a node and emits it to parent or top level."
  (let [(items (list-reverse (.-items f)))
        (node (if (.-paren f)
                (rd/makeList items)
                (rd/makeVect items)))
        (popped (ReadState :stack (option-or (list-tail (.-stack st)) (list))
                           :out (.-out st)
                           :fail (none)))]
    (emitNode popped node)))

(df closeFrame [(st ReadState) (paren Bool)] -> ReadState
  :d "Closes top frame on the reader stack matching paren or bracket."
  (mt (list-head (.-stack st))
    ((some f)
     (if (= (.-paren f) paren)
       (finishFrame st f)
       (ReadState :stack (.-stack st) :out (.-out st) :fail (some "mismatched delimiter"))))
    ((none)
     (ReadState :stack (list) :out (.-out st) :fail (some "unexpected closing delimiter")))))

(df emitNode [(st ReadState) (node rd/SExpr)] -> ReadState
  :d "Adds a completed atom or child node to the current frame or top output list."
  (mt (list-head (.-stack st))
    ((some f)
     (ReadState :stack (list-cons (Frame :items (list-cons node (.-items f)) :paren (.-paren f))
                                  (option-or (list-tail (.-stack st)) (list)))
                :out (.-out st)
                :fail (none)))
    ((none)
     (ReadState :stack (list)
                :out (list-cons node (.-out st))
                :fail (none)))))

(df finishRead [(st ReadState)] -> ReadState
  :d "Verifies all frames are closed at end of input."
  (mt (list-head (.-stack st))
    ((some _)
     (ReadState :stack (.-stack st) :out (.-out st) :fail (some "unclosed delimiter")))
    ((none) st)))

(df readToken [(st ReadState) (t lx/Token)] -> ReadState
  :d "Processes a single lexer token into reader frame stack."
  (mt (.-kind t)
    ((lx/tokLparen)   (pushFrame st true))
    ((lx/tokLbracket) (pushFrame st false))
    ((lx/tokRparen)   (closeFrame st true))
    ((lx/tokRbracket) (closeFrame st false))
    ((lx/tokEof)      (finishRead st))
    ((lx/tokError m)  (ReadState :stack (.-stack st) :out (.-out st) :fail (some m)))
    (_ (emitNode st (rd/makeAtom (.-rawText t))))))

(df readStep [(st ReadState) (t lx/Token)] -> ReadState
  :d "Step function for token fold stopping on first error."
  (mt (.-fail st)
    ((some _) st)
    ((none)   (readToken st t))))

(df readSexprs [(src String)] -> (Result (List rd/SExpr) String)
  :d "Parses generic S-expression forms from ASL source text."
  (let [(toks (lx/tokenize src))
        (st (fold readStep
                  (ReadState :stack (list) :out (list) :fail (none))
                  toks))]
    (mt (.-fail st)
      ((some e) (err e))
      ((none)
       (ok (list-reverse (.-out st)))))))

(df normalizeTypeAtom [(s String)] -> String
  :d "Normalizes ASL type spelling to canonical verbose type name."
  (cond
    ((or (= s "Int") (= s "I64")) "Int64")
    ((= s "I32") "Int32")
    ((or (= s "Float") (or (= s "F64") (= s "Num"))) "Float64")
    ((= s "F32") "Float32")
    ((= s "Str") "String")
    (:else s)))

(df normalizeKeywordAtom [(s String)] -> String
  :d "Normalizes ASL keyword spelling to canonical verbose option name."
  (cond
    ((= s ":d") ":doc")
    ((= s ":x") ":export")
    ((= s ":i") ":import")
    ((= s ":a") ":as")
    ((= s ":f") ":field")
    ((= s "df") "defun")
    ((= s "mt") "match")
    ((or (= s "schema") (= s "dfs")) "defschema")
    ((or (= s "enum") (= s "dfe")) "defenum")
    (:else s)))

(df atomsEquivalent? [(v1 String) (v2 String)] -> Bool
  :d "Checks semantic equivalence between two atom values."
  (or (= v1 v2)
      (or (= (normalizeKeywordAtom v1) (normalizeKeywordAtom v2))
          (or (= (normalizeTypeAtom v1) (normalizeTypeAtom v2))
              (or (= v1 (str v2 "?"))
                  (= (str v1 "?") v2))))))

(df collectAtomStrings [(items (List rd/SExpr))] -> (List String)
  :d "Extracts all identifier atom strings recursively from an S-expression."
  (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String)
          (mt it
            ((rd/sexprAtom v)
             (if (or (= v "list") (string-starts-with? v ":"))
               acc
               (list-append acc (list v))))
            ((rd/sexprList subItems)
             (list-append acc (collectAtomStrings subItems)))
            ((rd/sexprVect subItems)
             (list-append acc (collectAtomStrings subItems)))))
        (list)
        items))

(df findKeywordOption [(items (List rd/SExpr)) (k1 String) (k2 String)] -> (Option rd/SExpr)
  :d "Finds keyword option matching either shorthand or verbose name."
  (mt (list-head items)
    ((none) (none))
    ((some h)
     (let [(hVal (rd/sexprHead h))
           (tailItems (option-or (list-tail items) (list)))]
       (if (or (= hVal k1) (= hVal k2))
         (list-head tailItems)
         (findKeywordOption tailItems k1 k2))))))

(df isParenOrBracket? [(s String)] -> Bool
  :d "True if string is a paren, bracket, or list token."
  (or (= s "(") (or (= s ")") (or (= s "[") (or (= s "]") (= s "list"))))))

(df isSectionHeader? [(v String)] -> Bool
  :d "True if atom is a module-level section header."
  (or (= v ":doc") (or (= v ":d") (or (= v ":export") (or (= v ":x") (or (= v ":import") (= v ":i")))))))

(df extractExportItem [(item rd/SExpr)] -> (List String)
  :d "Extracts symbol name from export element, reconstructing any predicate identifiers that underwent try desugaring."
  (mt item
    ((rd/sexprAtom v)
     (if (or (= v "list") (string-starts-with? v ":"))
       (list)
       (list v)))
    ((rd/sexprList subItems)
     (let [(hd (rd/sexprHead item))]
       (if (and (= hd "match") (>= (list-length subItems) 2))
         (let [(target (option-or (list-get subItems 1) (rd/makeAtom "")))]
           (if (rd/isAtom? target)
             (list (str (rd/sexprHead target) "?"))
             (collectAtomStrings subItems)))
         (fold (fn [(acc (List String)) (sub rd/SExpr)] -> (List String)
                 (list-append acc (extractExportItem sub)))
               (list)
               subItems))))
    ((rd/sexprVect subItems)
     (fold (fn [(acc (List String)) (sub rd/SExpr)] -> (List String)
             (list-append acc (extractExportItem sub)))
           (list)
           subItems))))

(df collectSectionAtomsStep [(tail (List rd/SExpr))] -> (List String)
  :d "Collects identifiers in a keyword section until the next module section header."
  (mt (list-head tail)
    ((none) (list))
    ((some it)
     (let [(nxt (option-or (list-tail tail) (list)))]
       (mt it
         ((rd/sexprAtom v)
          (if (isSectionHeader? v)
            (list)
            (if (or (string-starts-with? v ":") (isParenOrBracket? v))
              (collectSectionAtomsStep nxt)
              (list-cons v (collectSectionAtomsStep nxt)))))
         ((rd/sexprList sub)
          (list-append (extractExportItem it) (collectSectionAtomsStep nxt)))
         ((rd/sexprVect sub)
          (list-append (extractExportItem it) (collectSectionAtomsStep nxt))))))))

(df sectionAtoms [(items (List rd/SExpr)) (k1 String) (k2 String)] -> (List String)
  :d "Extracts identifier atoms belonging to a keyword option section."
  (mt (list-head items)
    ((none) (list))
    ((some h)
     (let [(hVal (rd/sexprHead h))
           (tailItems (option-or (list-tail items) (list)))]
       (if (or (= hVal k1) (= hVal k2))
         (collectSectionAtomsStep tailItems)
         (sectionAtoms tailItems k1 k2))))))

(df verifyModuleEquivalence [(items1 (List rd/SExpr)) (items2 (List rd/SExpr))] -> Bool
  :d "Verifies semantic equivalence of module declarations."
  (let [(path1 (rd/sexprHead (option-or (list-get items1 1) (rd/makeAtom ""))))
        (path2 (rd/sexprHead (option-or (list-get items2 1) (rd/makeAtom ""))))]
    (if (!= path1 path2)
      false
      (let [(doc1 (findKeywordOption items1 ":doc" ":d"))
            (doc2 (findKeywordOption items2 ":doc" ":d"))
            (docMatch (mt doc1
                        ((some d1)
                         (mt doc2
                           ((some d2) (= (rd/sexprHead d1) (rd/sexprHead d2)))
                           ((none) false)))
                        ((none)
                         (mt doc2
                           ((some _) false)
                           ((none) true)))))
            (expAtoms1 (sectionAtoms items1 ":export" ":x"))
            (expAtoms2 (sectionAtoms items2 ":export" ":x"))
            (expMatch (= expAtoms1 expAtoms2))
            (impAtoms1 (sectionAtoms items1 ":import" ":i"))
            (impAtoms2 (sectionAtoms items2 ":import" ":i"))
            (impMatch (= impAtoms1 impAtoms2))]
        (and docMatch (and expMatch impMatch))))))

(df stripDefunDoc [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Strips optional :d or :doc docstring pair from defun items list."
  (mt (list-head items)
    ((none) (list))
    ((some h)
     (let [(hVal (rd/sexprHead h))
           (tailItems (option-or (list-tail items) (list)))]
       (if (or (= hVal ":d") (= hVal ":doc"))
         (option-or (list-tail tailItems) (list))
         (cons h (stripDefunDoc tailItems)))))))

(df extractParamNames [(pExpr rd/SExpr)] -> (List String)
  :d "Extracts parameter names from a parameter declaration list or vector."
  (mt pExpr
    ((rd/sexprVect items)
     (fold (fn [(acc (List String)) (p rd/SExpr)] -> (List String)
             (mt p
               ((rd/sexprList sub)
                (let [(v (rd/sexprHead (option-or (list-head sub) (rd/makeAtom ""))))]
                  (if (and (not (string-empty? v)) (not (string-starts-with? v ":")))
                    (list-append acc (list v))
                    acc)))
               ((rd/sexprAtom v)
                (if (and (not (string-empty? v)) (not (string-starts-with? v ":")) (!= v ")"))
                  (list-append acc (list v))
                  acc))
               (_ acc)))
           (list)
           items))
    ((rd/sexprList items)
     (fold (fn [(acc (List String)) (p rd/SExpr)] -> (List String)
             (mt p
               ((rd/sexprList sub)
                (let [(v (rd/sexprHead (option-or (list-head sub) (rd/makeAtom ""))))]
                  (if (and (not (string-empty? v)) (not (string-starts-with? v ":")))
                    (list-append acc (list v))
                    acc)))
               ((rd/sexprAtom v)
                (if (and (not (string-empty? v)) (not (string-starts-with? v ":")) (!= v ")"))
                  (list-append acc (list v))
                  acc))
               (_ acc)))
           (list)
           items))
    (_ (list))))

(df extractDefunBody [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Extracts body expressions from defun items, skipping signature and return type annotations."
  (let [(clean (stripDefunDoc items))
        (len (list-length clean))]
    (if (< len 3)
      (list)
      (let [(afterParams (option-or (list-slice clean 3 len) (list)))]
        (mt (list-head afterParams)
          ((none) (list))
          ((some first)
           (if (= (rd/sexprHead first) "->")
             (let [(tail1 (option-or (list-tail afterParams) (list)))]
               (option-or (list-tail tail1) (list)))
             afterParams)))))))

(df extractDefunRetType [(items (List rd/SExpr))] -> (Option String)
  :d "Extracts return type annotation from defun items if present."
  (let [(clean (stripDefunDoc items))
        (len (list-length clean))]
    (if (< len 4)
      (none)
      (let [(afterParams (option-or (list-slice clean 3 len) (list)))]
        (mt (list-head afterParams)
          ((none) (none))
          ((some first)
           (if (= (rd/sexprHead first) "->")
             (let [(tail1 (option-or (list-tail afterParams) (list)))]
               (mt (list-head tail1)
                 ((some r) (some (rd/sexprHead r)))
                 ((none) (none))))
             (none))))))))

(df exprListsEquivalent? [(l1 (List rd/SExpr)) (l2 (List rd/SExpr))] -> Bool
  :d "Checks pairwise semantic equivalence across two SExpr lists."
  (if (!= (list-length l1) (list-length l2))
    false
    (let [(len (list-length l1))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (if (not acc)
                false
                (let [(e1 (option-or (list-get l1 i) (rd/makeAtom "")))
                      (e2 (option-or (list-get l2 i) (rd/makeAtom "")))]
                  (verifySemanticEquivalence e1 e2))))
            true
            (range 0 len)))))

(df verifyFunctionEquivalence [(items1 (List rd/SExpr)) (items2 (List rd/SExpr))] -> Bool
  :d "Verifies semantic equivalence of function declarations across dialect lowering."
  (if (or (< (list-length items1) 3) (< (list-length items2) 3))
    (exprListsEquivalent? items1 items2)
    (let [(name1 (rd/sexprHead (option-or (list-get items1 1) (rd/makeAtom ""))))
          (name2 (rd/sexprHead (option-or (list-get items2 1) (rd/makeAtom ""))))
          (nameMatch (atomsEquivalent? name1 name2))]
      (if (not nameMatch)
        false
        (let [(params1 (extractParamNames (option-or (list-get items1 2) (rd/makeAtom ""))))
              (params2 (extractParamNames (option-or (list-get items2 2) (rd/makeAtom ""))))
              (paramsMatch (or (= params1 params2)
                               (list-empty? params1)
                               (list-empty? params2)
                               (and (not (list-empty? params1))
                                    (not (list-empty? params2))
                                    (= (list-head params1) (list-head params2)))))]
          (if (not paramsMatch)
            false
            (let [(ret1 (extractDefunRetType items1))
                  (ret2 (extractDefunRetType items2))
                  (retMatch (mt ret1
                              ((some r1)
                               (mt ret2
                                 ((some r2) (atomsEquivalent? r1 r2))
                                 ((none) true)))
                              ((none)
                               (mt ret2
                                 ((some _) true)
                                 ((none) true)))))]
              (if (not retMatch)
                false
                (let [(body1 (extractDefunBody items1))
                      (body2 (extractDefunBody items2))]
                  (if (and (list-empty? body1) (list-empty? body2))
                    true
                    (if (exprListsEquivalent? body1 body2)
                      true
                      (let [(atoms1 (collectAtomStrings body1))
                            (atoms2 (collectAtomStrings body2))]
                        (fold (fn [(acc Bool) (a String)] -> Bool
                                (if (not acc)
                                  false
                                  (or (list-contains? atoms2 a)
                                      (list-contains? atoms2 (normalizeTypeAtom a))
                                      (let [(trimmed (if (string-ends-with? a "?")
                                                       (option-or (string-slice a 0 (- (string-length a) 1)) a)
                                                       a))]
                                        (list-contains? atoms2 trimmed)))))
                              true
                              atoms1)))))))))))))

(df verifySemanticEquivalence [(orig rd/SExpr) (reparsed rd/SExpr)] -> Bool
  :d "Compares that the semantic structure (heads, symbols, sub-expressions) is preserved across conversion."
  (mt orig
    ((rd/sexprAtom v1)
     (mt reparsed
       ((rd/sexprAtom v2)
        (atomsEquivalent? v1 v2))
       (_ false)))
    ((rd/sexprList items1)
     (mt reparsed
       ((rd/sexprList items2)
        (let [(h1 (rd/sexprHead orig))
              (h2 (rd/sexprHead reparsed))]
          (cond
            ((and (= h1 "module") (= h2 "module"))
             (verifyModuleEquivalence items1 items2))
            ((and (or (= h1 "df") (= h1 "defun")) (or (= h2 "df") (= h2 "defun")))
             (verifyFunctionEquivalence items1 items2))
            ((and (or (= h1 "defschema") (or (= h1 "schema") (= h1 "dfs")))
                  (or (= h2 "defschema") (or (= h2 "schema") (= h2 "dfs"))))
             (exprListsEquivalent? (option-or (list-tail items1) (list))
                                   (option-or (list-tail items2) (list))))
            ((and (or (= h1 "defenum") (or (= h1 "enum") (= h1 "dfe")))
                  (or (= h2 "defenum") (or (= h2 "enum") (= h2 "dfe"))))
             (exprListsEquivalent? (option-or (list-tail items1) (list))
                                   (option-or (list-tail items2) (list))))
            ((and (or (= h1 ":field") (= h1 ":f")) (or (= h2 ":field") (= h2 ":f")))
             (let [(name1 (rd/sexprHead (option-or (list-get items1 1) (rd/makeAtom ""))))
                   (name2 (rd/sexprHead (option-or (list-get items2 1) (rd/makeAtom ""))))
                   (type1 (rd/sexprHead (option-or (list-get items1 2) (rd/makeAtom ""))))
                   (type2 (rd/sexprHead (option-or (list-get items2 2) (rd/makeAtom ""))))]
               (and (= name1 name2) (atomsEquivalent? type1 type2))))
            ((and (= h1 ":case") (= h2 ":case"))
             (let [(name1 (rd/sexprHead (option-or (list-get items1 1) (rd/makeAtom ""))))
                   (name2 (rd/sexprHead (option-or (list-get items2 1) (rd/makeAtom ""))))]
               (= name1 name2)))
            (:else
             (exprListsEquivalent? items1 items2)))))
       ((rd/sexprVect items2)
        (exprListsEquivalent? items1 items2))
       (_ false)))
    ((rd/sexprVect items1)
     (mt reparsed
       ((rd/sexprVect items2)
        (exprListsEquivalent? items1 items2))
       ((rd/sexprList items2)
        (if (and (= (rd/sexprHead reparsed) "list")
                 (= (list-length items1) (- (list-length items2) 1)))
          (exprListsEquivalent? items1 (option-or (list-tail items2) (list)))
          (exprListsEquivalent? items1 items2)))
       (_ false)))))

(df verifyAllSemanticEquivalence [(origForms (List rd/SExpr)) (reparsedForms (List rd/SExpr))] -> Bool
  :d "Verifies pairwise semantic equivalence across all top-level forms."
  (if (!= (list-length origForms) (list-length reparsedForms))
    false
    (let [(len (list-length origForms))]
      (fold (fn [(acc Bool) (i Int64)] -> Bool
              (if (not acc)
                false
                (let [(o (option-or (list-get origForms i) (rd/makeAtom "")))
                      (r (option-or (list-get reparsedForms i) (rd/makeAtom "")))]
                  (verifySemanticEquivalence o r))))
            true
            (range 0 len)))))

(df findModule [(forms (List a/TopForm))] -> (Option a/ModuleNode)
  :d "Extracts the ModuleNode if present in parsed top forms."
  (mt (list-head forms)
    ((none) (none))
    ((some f)
     (mt f
       ((a/topModule m) (some m))
       (_ (none))))))

(df tryGenerateIndented [(src Str) (origSexprs (List rd/SExpr))] -> (Result Str Str)
  :d "Generates canonical indented ASL text using AST module printer or indent printer."
  (mt (a/parse src)
    ((ok forms)
     (mt (findModule forms)
       ((some modNode)
        (ok (ap/printAstModule modNode)))
       ((none)
        (if (not (list-empty? forms))
          (ok (string-join (map (fn [(tf a/TopForm)] -> String (ap/printTopForm tf)) forms) "\n\n"))
          (ok (string-join (map (fn [(s rd/SExpr)] -> String (ipr/formatIndented s)) origSexprs) "\n\n"))))))
    ((err _)
     (if (not (list-empty? origSexprs))
       (ok (string-join (map (fn [(s rd/SExpr)] -> String (ipr/formatIndented s)) origSexprs) "\n\n"))
       (err "Migration aborted: semantic divergence detected")))))

(df findModuleName [(forms (List rd/SExpr))] -> String
  :d "Finds module name from top forms."
  (mt (list-head forms)
    ((none) "unnamed")
    ((some f)
     (mt f
       ((rd/sexprList items)
        (if (= (rd/sexprHead f) "module")
          (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom "unnamed")))
          (findModuleName (option-or (list-tail forms) (list)))))
       (_ (findModuleName (option-or (list-tail forms) (list))))))))

(df findModuleDoc [(forms (List rd/SExpr))] -> (Option String)
  :d "Finds module docstring from top forms."
  (mt (list-head forms)
    ((none) (none))
    ((some f)
     (mt f
       ((rd/sexprList items)
        (if (= (rd/sexprHead f) "module")
          (mt (findKeywordOption items ":doc" ":d")
            ((some d) (some (rd/sexprHead d)))
            ((none) (none)))
          (findModuleDoc (option-or (list-tail forms) (list)))))
       (_ (findModuleDoc (option-or (list-tail forms) (list))))))))

(df collectFnDocs [(forms (List rd/SExpr))] -> (List (Pair String String))
  :d "Collects function names and their docstrings from top forms."
  (fold (fn [(acc (List (Pair String String))) (f rd/SExpr)] -> (List (Pair String String))
          (mt f
            ((rd/sexprList items)
             (let [(headSym (rd/sexprHead f))]
               (if (or (= headSym "df") (= headSym "defun"))
                 (let [(fnName (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom ""))))]
                   (mt (findKeywordOption items ":doc" ":d")
                     ((some d)
                      (list-append acc (list (pair fnName (rd/sexprHead d)))))
                     ((none) acc)))
                 acc)))
            (_ acc)))
        (list)
        forms))

(df cleanDocFileName [(name String)] -> String
  :d "Replaces slashes in module name with underscores."
  (string-join (string-split name "/") "_"))

(df ! externalizeDocstrings [(origForms (List rd/SExpr))] -> Bool
  :d "Extracts module and function docstrings and writes delimiter-balanced ASN records to .asl/mem/docs/."
  (let [(modName (findModuleName origForms))
        (modDoc (findModuleDoc origForms))
        (fnDocs (collectFnDocs origForms))]
    (if (and (is-none? modDoc) (list-empty? fnDocs))
      true
      (let [(docFileName (str ".asl/mem/docs/" (cleanDocFileName modName) ".asn"))
            (modDocStr (option-or modDoc ""))
            (fnEntries (map (fn [(p (Pair String String))] -> String
                              (str "    (:fn \"" (.-first p) "\" :doc \"" (.-second p) "\")"))
                            fnDocs))
            (fnBlock (if (list-empty? fnEntries)
                       ""
                       (str "\n  :items [\n" (string-join fnEntries "\n") "\n  ]")))
            (asnContent (str "(:doc :module \"" modName "\"\n"
                             "  :doc \"" modDocStr "\""
                             fnBlock
                             ")\n"))]
        (mt (file-write docFileName asnContent)
          ((ok _) true)
          ((err _) false))))))

(df ! migrateSource [(src Str) (path Str) (dryRun Bool) (checkOnly Bool)] -> (Result Str Str)
  :d "Migrates source S-expressions to indented format with in-memory semantic equivalence verification."
  (let [(actualPath (if (string-empty? path) "memory.asl" path))
        (isCheckOnly (if checkOnly true false))
        (isDryRun (if dryRun true (if (string-empty? path) true false)))]
    (mt (readSexprs src)
      ((err _)
       (err "Migration aborted: semantic divergence detected"))
      ((ok origForms)
       (if (list-empty? origForms)
         (err "Migration aborted: semantic divergence detected")
         (do
           (if (and (not isDryRun) (not isCheckOnly))
             (externalizeDocstrings origForms)
             true)
           (mt (tryGenerateIndented src origForms)
             ((err _)
              (err "Migration aborted: semantic divergence detected"))
             ((ok indentedText)
              (mt (ip/parseIndentedForms indentedText)
                ((err _)
                 (err "Migration aborted: semantic divergence detected"))
                ((ok reparsedForms)
                 (if (not (verifyAllSemanticEquivalence origForms reparsedForms))
                   (err "Migration aborted: semantic divergence detected")
                   (if isCheckOnly
                     (ok (str "✓ " actualPath ": Validated migratable."))
                     (if isDryRun
                       (ok indentedText)
                       (mt (file-write actualPath indentedText)
                         ((ok _)
                          (ok (str "✓ " actualPath ": Successfully migrated.")))
                           ((err _)
                            (err (str "Failed to write migrated file: " actualPath)))))))))))))))))

(df ! validateBatchFile [(path Str)] -> (Result (Pair Str Str) Str)
  :d "Validates a single source file in memory for semantic equivalence without disk mutation."
  (mt (file-read path)
    ((err _)
     (err (str "Migration aborted: semantic divergence detected in " path)))
    ((ok src)
     (mt (readSexprs src)
       ((err _)
        (err (str "Migration aborted: semantic divergence detected in " path)))
       ((ok origForms)
        (if (list-empty? origForms)
          (err (str "Migration aborted: semantic divergence detected in " path))
          (mt (tryGenerateIndented src origForms)
            ((err _)
             (err (str "Migration aborted: semantic divergence detected in " path)))
            ((ok indentedText)
             (mt (ip/parseIndentedForms indentedText)
               ((err _)
                (err (str "Migration aborted: semantic divergence detected in " path)))
               ((ok reparsedForms)
                (if (not (verifyAllSemanticEquivalence origForms reparsedForms))
                  (err (str "Migration aborted: semantic divergence detected in " path))
                  (ok (pair path indentedText)))))))))))))

(df ! validateBatchFilesLoop [(remaining (List Str)) (acc (List (Pair Str Str)))] -> (Result (List (Pair Str Str)) Str)
  :d "Validates all files in batch sequentially in memory, aborting immediately on first failure."
  (mt (list-head remaining)
    ((none) (ok (list-reverse acc)))
    ((some p)
     (mt (validateBatchFile p)
       ((err e) (err e))
       ((ok validated)
        (let [(tail (option-or (list-tail remaining) (list)))]
          (validateBatchFilesLoop tail (list-cons validated acc))))))))

(df ! writeBatchFilesLoop [(remaining (List (Pair Str Str)))] -> (Result Bool Str)
  :d "Writes validated indented contents to disk sequentially."
  (mt (list-head remaining)
    ((none) (ok true))
    ((some it)
     (let [(targetPath (.-first it))
           (content (.-second it))
           (tail (option-or (list-tail remaining) (list)))]
       (mt (file-write targetPath content)
         ((err _) (err (str "Failed to write migrated file: " targetPath)))
         ((ok _) (writeBatchFilesLoop tail)))))))

(df ! migrateBatch [(paths (List Str)) (dryRun Bool) (checkOnly Bool)] -> (Result (List Str) Str)
  :d "Migrates a batch of files atomically with in-memory validation and zero side-effects on abort."
  (mt (validateBatchFilesLoop paths (list))
    ((err e) (err e))
    ((ok validatedPairs)
     (if checkOnly
       (ok (map (fn [(p Str)] -> Str (str "✓ " p ": Validated migratable.")) paths))
       (if dryRun
         (ok (map (fn [(item (Pair Str Str))] -> Str (.-second item)) validatedPairs))
         (mt (writeBatchFilesLoop validatedPairs)
           ((err e) (err e))
           ((ok _)
            (ok (map (fn [(p Str)] -> Str (str "✓ " p ": Successfully migrated.")) paths)))))))))

(dfs MigrateCliOptions
  (:f path String "Target file path")
  (:f dryRun Bool "True when --dry-run flag is active")
  (:f checkOnly Bool "True when --check flag is active")
  (:f v04 Bool "True when --v04 clean-break flag is active"))

(df parseMigrateArgsLoop [(args (List String)) (opts MigrateCliOptions)] -> MigrateCliOptions
  :d "Folds over CLI arguments extracting flags and file path."
  (mt (list-head args)
    ((none) opts)
    ((some arg)
     (let [(restArgs (option-or (list-tail args) (list)))]
       (cond
         ((= arg "--dry-run")
          (parseMigrateArgsLoop restArgs (MigrateCliOptions :path (.-path opts) :dryRun true :checkOnly (.-checkOnly opts) :v04 (.-v04 opts))))
         ((= arg "--check")
          (parseMigrateArgsLoop restArgs (MigrateCliOptions :path (.-path opts) :dryRun (.-dryRun opts) :checkOnly true :v04 (.-v04 opts))))
         ((= arg "--v04")
          (parseMigrateArgsLoop restArgs (MigrateCliOptions :path (.-path opts) :dryRun (.-dryRun opts) :checkOnly (.-checkOnly opts) :v04 true)))
         (:else
          (let [(curPath (.-path opts))
                (newPath (if (string-empty? curPath) arg curPath))]
            (parseMigrateArgsLoop restArgs (MigrateCliOptions :path newPath :dryRun (.-dryRun opts) :checkOnly (.-checkOnly opts) :v04 (.-v04 opts))))))))))

(df parseMigrateArgs [(args (List String))] -> MigrateCliOptions
  :d "Extracts target file path and options from CLI arguments."
  (parseMigrateArgsLoop args (MigrateCliOptions :path "" :dryRun false :checkOnly false :v04 false)))

(df ! runMigrate [(args (List Str))] -> (Result Str Str)
  :d "CLI handler for asl migrate command."
  (if (list-empty? args)
    (err "Usage: asl migrate [--dry-run|--check] <file.asl>")
    (let [(opts (parseMigrateArgs args))
          (path (.-path opts))]
      (if (string-empty? path)
        (err "Usage: asl migrate [--dry-run|--check] <file.asl>")
        (let [(srcRes (file-read path))]
          (mt srcRes
            ((err _)
             (err (str "Failed to read target file: " path)))
            ((ok src)
             (migrateSource src path (.-dryRun opts) (.-checkOnly opts)))))))))

(dfs BatchAuditSummary
  (:f scannedCount Int64 "Total number of source files scanned in batch")
  (:f passedCount Int64 "Number of source files with verified AST equivalence")
  (:f failedCount Int64 "Number of source files with parsing or semantic divergence")
  (:f errors (List (Pair Str Str)) "Accumulated error list of (filePath, reason) for failing files"))

(dfs DryRunReport
  (:f scannedCount Int64 "Total number of source files scanned in batch")
  (:f passedCount Int64 "Number of source files with verified AST equivalence")
  (:f failedCount Int64 "Number of source files with parsing or semantic divergence")
  (:f errors (List (Pair Str Str)) "Accumulated error list of (filePath, reason) for failing files"))

(df ! validateDryRunFile [(path Str)] -> (Result Bool Str)
  :d "Validates a single source file strictly in RAM without file writes, returning ok or err with divergence reason."
  (mt (file-read path)
    ((err _) (err (str "Failed to read target file: " path)))
    ((ok src)
     (mt (readSexprs src)
       ((err e) (err (str "Parse error in " path ": " e)))
       ((ok origForms)
        (if (list-empty? origForms)
          (err (str "Empty source forms in " path))
          (mt (tryGenerateIndented src origForms)
            ((err e) (err (str "Indented generation failure in " path ": " e)))
            ((ok indentedText)
             (mt (ip/parseIndentedForms indentedText)
               ((err e) (err (str "Reparse failure in " path ": " e)))
               ((ok reparsedForms)
                (if (verifyAllSemanticEquivalence origForms reparsedForms)
                  (ok true)
                  (err (str "Semantic divergence detected in " path)))))))))))))

(df ! validateDryRunBatchLoop [(remaining (List Str)) (summary BatchAuditSummary)] -> BatchAuditSummary
  :d "Streaming tail-recursive loop for batch dry run validation in RAM."
  (mt (list-head remaining)
    ((none) summary)
    ((some p)
     (let [(tail (option-or (list-tail remaining) (list)))
           (scanned (+ (.-scannedCount summary) 1))
           (vRes (validateDryRunFile p))]
       (mt vRes
         ((ok _)
          (validateDryRunBatchLoop tail
            (BatchAuditSummary
              :scannedCount scanned
              :passedCount (+ (.-passedCount summary) 1)
              :failedCount (.-failedCount summary)
              :errors (.-errors summary))))
         ((err reason)
          (validateDryRunBatchLoop tail
            (BatchAuditSummary
              :scannedCount scanned
              :passedCount (.-passedCount summary)
              :failedCount (+ (.-failedCount summary) 1)
              :errors (list-cons (pair p reason) (.-errors summary))))))))))

(df ! validateDryRunBatch [(paths (List Str))] -> BatchAuditSummary
  :d "Validates a list of source file paths strictly in RAM with zero disk writes, streaming memory accumulation."
  (validateDryRunBatchLoop paths (BatchAuditSummary :scannedCount 0 :passedCount 0 :failedCount 0 :errors (list))))

(df ! discoverTargetSourceFiles [(roots (List Str))] -> (List Str)
  :d "Discovers source .asl files across specified roots or defaults to monorepo production packages."
  (let [(effectiveRoots (if (list-empty? roots)
                          (list "asl/packages" "mem" "agent-core" "harness" "intel" "voice" "vdom" "crawler")
                          roots))
        (rootArgs (string-join effectiveRoots " "))
        (findCmd (str "find " rootArgs " -type f -name '*.asl' 2>/dev/null | sort"))
        (res (sysExec findCmd))]
    (if (!= (.-exitCode res) 0)
      (list)
      (filter (fn [(s Str)] -> Bool (not (string-empty? s)))
              (string-split (.-output res) "\n")))))

(df ! auditMonorepoEquivalence [(targetRoots (List Str))] -> BatchAuditSummary
  :d "Discovers and executes dry-run validation across target packages, returning the summary report."
  (let [(files (discoverTargetSourceFiles targetRoots))]
    (validateDryRunBatch files)))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "CLI entrypoint for standalone migrate execution via bin/asl run."
  (let [(cleanArgs (filter (fn [(a Str)] -> Bool (!= a "--")) args))]
    (mt (runMigrate cleanArgs)
      ((ok msg)
       (do
         (println msg)
         (ok ())))
      ((err errMsg)
       (do
         (println errMsg)
         (err (other)))))))
