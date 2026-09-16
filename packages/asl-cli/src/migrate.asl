(module asl-cli/migrate
  :d "Automated migration toolchain converting S-expression ASL modules to indented syntax."
  :x [runMigrate migrateSource verifySemanticEquivalence]
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
    ((= s "df") "defun")
    ((= s "mt") "match")
    (:else s)))

(df atomsEquivalent? [(v1 String) (v2 String)] -> Bool
  :d "Checks semantic equivalence between two atom values."
  (or (= v1 v2)
      (or (= (normalizeKeywordAtom v1) (normalizeKeywordAtom v2))
          (= (normalizeTypeAtom v1) (normalizeTypeAtom v2)))))

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
          (list-append (collectAtomStrings sub) (collectSectionAtomsStep nxt)))
         ((rd/sexprVect sub)
          (list-append (collectAtomStrings sub) (collectSectionAtomsStep nxt))))))))

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
             (let [(clean1 (stripDefunDoc items1))
                   (clean2 (stripDefunDoc items2))]
               (exprListsEquivalent? clean1 clean2)))
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

(df ! migrateSource [(src Str) (path Str) (dryRun Bool) (checkOnly Bool)] -> (Result Str Str)
  :d "Migrates source S-expressions to indented format with in-memory semantic equivalence verification."
  (mt (readSexprs src)
    ((err _)
     (err "Migration aborted: semantic divergence detected"))
    ((ok origForms)
     (if (list-empty? origForms)
       (err "Migration aborted: semantic divergence detected")
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
               (if checkOnly
                 (ok (str "✓ " path ": Validated migratable."))
                 (if dryRun
                   (ok indentedText)
                   (mt (file-write path indentedText)
                     ((ok _)
                      (ok (str "✓ " path ": Successfully migrated.")))
                     ((err _)
                      (err (str "Failed to write migrated file: " path)))))))))))))))

(dfs MigrateCliOptions
  (:f path String "Target file path")
  (:f dryRun Bool "True when --dry-run flag is active")
  (:f checkOnly Bool "True when --check flag is active"))

(df parseMigrateArgsLoop [(args (List String)) (opts MigrateCliOptions)] -> MigrateCliOptions
  :d "Folds over CLI arguments extracting flags and file path."
  (mt (list-head args)
    ((none) opts)
    ((some arg)
     (let [(restArgs (option-or (list-tail args) (list)))]
       (cond
         ((= arg "--dry-run")
          (parseMigrateArgsLoop restArgs (MigrateCliOptions :path (.-path opts) :dryRun true :checkOnly (.-checkOnly opts))))
         ((= arg "--check")
          (parseMigrateArgsLoop restArgs (MigrateCliOptions :path (.-path opts) :dryRun (.-dryRun opts) :checkOnly true)))
         (:else
          (let [(curPath (.-path opts))
                (newPath (if (string-empty? curPath) arg curPath))]
            (parseMigrateArgsLoop restArgs (MigrateCliOptions :path newPath :dryRun (.-dryRun opts) :checkOnly (.-checkOnly opts))))))))))

(df parseMigrateArgs [(args (List String))] -> MigrateCliOptions
  :d "Extracts target file path and options from CLI arguments."
  (parseMigrateArgsLoop args (MigrateCliOptions :path "" :dryRun false :checkOnly false)))

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
