(module asl-codegen/c99Expr
  :d "Pure ISO C99 expression lowering, control flow, and statement synthesis."
  :x [lowerCExpr
      lowerCAtom
      lowerCLet
      lowerCIf
      lowerCCond
      lowerCMatch
      lowerCCall
      lowerCFieldAccess
      lowerCRecordInit
      lowerCDo
      isC99Keyword?
      mangleCIdent
      mangleCTypeName
      c99TypeStr
      isIntegerLiteral?
      isFloatLiteral?]
  :i [(reader :a rd)])

(df sliceStrOr [(s String) (start Int64) (end Int64) (fallback String)] -> String
  :d "Safely slices string within bounds or returns fallback."
  (option-or (string-slice s start end) fallback))

(df stripModulePrefix [(s String)] -> String
  :d "Strips module alias prefix separated by slash if present."
  (if (string-contains? s "/")
      (mt (string-index-of s "/")
        ((some idx) (sliceStrOr s (+ idx 1) (string-length s) s))
        ((none) s))
      s))

(df isC99Keyword? [(s String)] -> Bool
  :d "Checks if string collides with any of the 32 ISO C99 reserved keywords or standard entrypoints."
  (let [(kwList (list "auto" "break" "case" "char" "const" "continue" "default" "do"
                      "double" "else" "enum" "extern" "float" "for" "goto" "if"
                      "inline" "int" "long" "register" "restrict" "return" "short"
                      "signed" "sizeof" "static" "struct" "switch" "typedef" "union"
                      "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary"
                      "main" "exit" "abort" "index"))]
    (list-contains? kwList s)))

(df isDigitChar? [(c String)] -> Bool
  :d "Returns true if single-character string is an ASCII decimal digit."
  (and (>= c "0") (<= c "9")))

(df isDigitsOnly? [(s String) (idx Int64) (len Int64)] -> Bool
  :d "Recursively checks if all characters from idx to len are digits."
  (if (>= idx len)
      true
      (let [(ch (sliceStrOr s idx (+ idx 1) ""))]
        (if (isDigitChar? ch)
            (isDigitsOnly? s (+ idx 1) len)
            false))))

(df isIntegerLiteral? [(s String)] -> Bool
  :d "Determines if string represents an integer literal."
  (let [(sLen (string-length s))]
    (if (<= sLen 0)
        false
        (if (string-ends-with? s "LL")
            (let [(stemLen (- sLen 2))]
              (if (<= stemLen 0)
                  false
                  (isIntegerLiteral? (sliceStrOr s 0 stemLen ""))))
            (if (string-starts-with? s "-")
                (if (<= sLen 1)
                    false
                    (isDigitsOnly? s 1 sLen))
                (isDigitsOnly? s 0 sLen))))))

(df isFloatLiteral? [(s String)] -> Bool
  :d "Determines if string represents a floating-point literal."
  (let [(sLen (string-length s))]
    (if (or (<= sLen 2) (not (string-contains? s ".")))
        false
        (let [(dotIdx (string-index-of s "."))]
          (mt dotIdx
            ((some idx)
             (let [(prefix (sliceStrOr s 0 idx ""))
                   (suffix (sliceStrOr s (+ idx 1) sLen ""))
                   (pValid (or (isIntegerLiteral? prefix) (and (string-starts-with? prefix "-") (isIntegerLiteral? (sliceStrOr prefix 1 (string-length prefix) "")))))
                   (sValid (isDigitsOnly? suffix 0 (string-length suffix)))]
               (and pValid sValid)))
            ((none) false))))))

(df capitalizeSeg [(seg String)] -> String
  :d "Capitalizes a single word segment for PascalCase transformation."
  (let [(segLen (string-length seg))]
    (if (<= segLen 0)
        ""
        (let [(head (string-upper (sliceStrOr seg 0 1 "")))
              (tail (string-lower (sliceStrOr seg 1 segLen "")))]
          (str head tail)))))

(df pascalIdent [(s String)] -> String
  :d "Converts kebab-case or snake_case identifier to PascalCase."
  (if (and (not (string-contains? s "-"))
           (not (string-contains? s "_")))
      (if (and (> (string-length s) 0)
               (= (string-upper (sliceStrOr s 0 1 "")) (sliceStrOr s 0 1 "")))
          s
          (capitalizeSeg s))
      (let [(norm (string-replace s "_" "-"))
            (segs (string-split norm "-"))
            (caps (map capitalizeSeg segs))]
        (string-join caps ""))))

(df mangleCTypeName [(s String)] -> String
  :d "Mangles an ASL type identifier into an ISO C99 type name."
  (let [(clean (if (string-starts-with? s ":")
                   (sliceStrOr s 1 (string-length s) "")
                   s))]
    (cond
      ((or (= clean "Int64") (= clean "I64")) "int64_t")
      ((or (= clean "Int32") (= clean "I32")) "int32_t")
      ((or (= clean "Float64") (= clean "F64")) "double")
      ((or (= clean "Float32") (= clean "F32")) "float")
      ((= clean "Bool") "bool")
      ((or (= clean "Unit") (= clean "void")) "void")
      ((or (= clean "String") (= clean "Str")) "asl_string_t")
      (:else
       (let [(p (pascalIdent clean))]
         (if (string-starts-with? p "Asl")
             p
             (str "Asl" p)))))))

(df c99TypeStr [(s String)] -> String
  :d "Canonical mapping from ASL type string to ISO C99 type declaration."
  (mangleCTypeName s))

(df mangleCIdent [(s String)] -> String
  :d "Mangles an ASL kebab-case identifier into a safe C99 snake_case identifier."
  (let [(sLen (string-length s))]
    (if (<= sLen 0)
        ""
        (let [(base1 (if (and (> sLen 1) (string-ends-with? s "?"))
                         (let [(stem (sliceStrOr s 0 (- sLen 1) ""))]
                           (if (string-starts-with? stem "is-")
                               (str "is_" (sliceStrOr stem 3 (string-length stem) ""))
                               (str "is_" stem)))
                         s))
              (len1 (string-length base1))
              (base2 (if (and (> len1 1) (string-ends-with? base1 "!"))
                         (str (sliceStrOr base1 0 (- len1 1) "") "_mut")
                         base1))
              (snaked (string-replace (string-replace base2 "-" "_") "/" "_"))]
          (if (isC99Keyword? snaked)
              (str "asl_" snaked)
              snaked)))))

(df getAtomStr [(e rd/SExpr)] -> String
  :d "Extracts atom string value from an SExpr or returns empty."
  (mt e
    ((rd/sexprAtom v) v)
    ((rd/sexprList _) "")
    ((rd/sexprVect _) "")))

(df nthAtom [(items (List rd/SExpr)) (idx Int64)] -> String
  :d "Extracts atom string from items at index or empty string."
  (getAtomStr (option-or (list-get items idx) (rd/sexprAtom ""))))

(df sliceFrom1 [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Slices items starting from index 1."
  (if (> (list-length items) 1)
      (option-or (list-slice items 1 (list-length items)) (list))
      (list)))

(df sliceTail [(items (List rd/SExpr)) (start Int64)] -> (List rd/SExpr)
  :d "Slices list from start index or returns empty list."
  (if (> (list-length items) start)
      (option-or (list-slice items start (list-length items)) (list))
      (list)))

(df lowerCAtom [(s String)] -> String
  :d "Emits an ISO C99 terminal literal or sanitized identifier."
  (cond
    ((= s "true") "true")
    ((= s "false") "false")
    ((or (= s "nil") (= s "()")) "(void)0")
    ((string-starts-with? s "\"")
     (let [(sLen (string-length s))
           (contentLen (if (>= sLen 2) (- sLen 2) 0))]
       (str "(asl_string_t){ .data = " s ", .len = " (int-to-string contentLen) " }")))
    ((isIntegerLiteral? s)
     (if (string-ends-with? s "LL")
         s
         (str s "LL")))
    ((isFloatLiteral? s) s)
    (:else (mangleCIdent s))))

(df isBinaryOp? [(op String)] -> Bool
  :d "Checks if string corresponds to a standard binary or unary arithmetic/logical operator."
  (let [(ops (list "+" "-" "*" "/" "%" "&" "|" "^" "<<" ">>" "=" "!=" "<" "<=" ">" ">=" "and" "or"))]
    (list-contains? ops op)))

(df opToC [(op String)] -> String
  :d "Maps an ASL operator symbol to its ISO C99 equivalent token."
  (cond
    ((= op "=") "==")
    ((= op "!=") "!=")
    ((= op "<") "<")
    ((= op "<=") "<=")
    ((= op ">") ">")
    ((= op ">=") ">=")
    ((= op "and") "&&")
    ((= op "or") "||")
    (:else op)))

(df lowerCFieldAccess [(target String) (field String)] -> String
  :d "Lowers a record field access into standard C99 dot notation."
  (let [(clean (if (string-starts-with? field ".-")
                   (sliceStrOr field 2 (string-length field) "")
                   (if (string-starts-with? field ".")
                       (sliceStrOr field 1 (string-length field) "")
                       field)))]
    (str target "." (mangleCIdent clean))))

(df lowerCRecordField [(items (List rd/SExpr)) (idx Int64)] -> String
  :d "Lowers a single record init key-value field."
  (let [(kPos (+ 1 (* idx 2)))
        (vPos (+ 2 (* idx 2)))
        (kAtom (nthAtom items kPos))
        (kClean (if (string-starts-with? kAtom ":")
                    (sliceStrOr kAtom 1 (string-length kAtom) kAtom)
                    kAtom))
        (vNode (option-or (list-get items vPos) (rd/sexprAtom "()")))
        (vVal (lowerCExpr vNode))]
    (str "." (mangleCIdent kClean) " = " vVal)))

(df lowerCRecordFieldsStep [(items (List rd/SExpr)) (idx Int64) (numPairs Int64) (acc (List String))] -> (List String)
  :d "Accumulates lowered record field initializers."
  (if (>= idx numPairs)
      acc
      (lowerCRecordFieldsStep items (+ idx 1) numPairs (list-append acc (list (lowerCRecordField items idx))))))

(df lowerCRecordInit [(items (List rd/SExpr))] -> String
  :d "Lowers record construction into a C99 designated compound literal."
  (let [(rawName (nthAtom items 0))
        (recName (stripModulePrefix rawName))
        (recType (mangleCTypeName recName))
        (itemsLen (list-length items))]
    (if (<= itemsLen 1)
        (str "(" recType "){ 0 }")
        (let [(numPairs (/ (- itemsLen 1) 2))
              (fieldStrs (lowerCRecordFieldsStep items 0 numPairs (list)))]
          (str "(" recType "){ " (string-join fieldStrs ", ") " }")))))

(df lowerCIf [(items (List rd/SExpr))] -> String
  :d "Lowers an if form into if-statement with returns if branches have control flow, else ternary."
  (let [(condExpr (lowerCExpr (option-or (list-get items 1) (rd/sexprAtom "false"))))
        (rawThen (lowerCExpr (option-or (list-get items 2) (rd/sexprAtom "(void)0"))))
        (rawElse (if (> (list-length items) 3)
                     (lowerCExpr (option-or (list-get items 3) (rd/sexprAtom "(void)0")))
                     "(void)0"))
        (thenHasFlow (or (string-contains? rawThen "return ") (string-contains? rawThen "switch")))
        (elseHasFlow (or (string-contains? rawElse "return ") (string-contains? rawElse "switch")))]
    (if (or thenHasFlow elseHasFlow)
        (let [(tWrap (if (string-starts-with? rawThen "{") (str "(" rawThen ")") rawThen))
              (eWrap (if (string-starts-with? rawElse "{") (str "(" rawElse ")") rawElse))
              (tStmt (if thenHasFlow rawThen (str "return " tWrap ";")))
              (eStmt (if elseHasFlow rawElse (str "return " eWrap ";")))]
          (str "if (" condExpr ") { " tStmt " } else { " eStmt " }"))
        (str "((" condExpr ") ? (" rawThen ") : (" rawElse "))"))))

(df lowerCCondClause [(clause rd/SExpr)] -> (Pair String String)
  :d "Extracts condition and expression from a single cond clause."
  (let [(cList (rd/sexprToList clause))]
    (if (<= (list-length cList) 0)
        (pair "false" "(void)0")
        (let [(head (nthAtom cList 0))
              (isElse (or (= head ":else") (= head "else")))]
          (if isElse
              (let [(bVal (lowerCExpr (option-or (list-get cList 1) (rd/sexprAtom "(void)0"))))]
                (pair ":else" bVal))
              (let [(cVal (lowerCExpr (option-or (list-get cList 0) (rd/sexprAtom "false"))))
                    (bVal (lowerCExpr (option-or (list-get cList 1) (rd/sexprAtom "(void)0"))))]
                (pair cVal bVal)))))))

(df hasCondFlow? [(clauses (List rd/SExpr)) (idx Int64)] -> Bool
  (if (>= idx (list-length clauses))
      false
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause cNode))
            (rawBody (.-second p))]
        (if (or (string-starts-with? rawBody "return") (or (string-starts-with? rawBody "switch") (string-starts-with? rawBody "{")))
            true
            (hasCondFlow? clauses (+ idx 1))))))

(df lowerCCondStmtLoop [(clauses (List rd/SExpr)) (idx Int64)] -> String
  (if (>= idx (list-length clauses))
      ""
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause cNode))
            (cCond (.-first p))
            (rawBody (.-second p))
            (hasFlow (or (string-starts-with? rawBody "return") (or (string-starts-with? rawBody "switch") (string-starts-with? rawBody "{"))))
            (wrapBody (if (string-starts-with? rawBody "{") (str "(" rawBody ")") rawBody))
            (stmt (if hasFlow rawBody (str "return " wrapBody ";")))]
        (if (= cCond ":else")
            (str "else { " stmt " } ")
            (if (= idx 0)
                (str "if (" cCond ") { " stmt " } " (lowerCCondStmtLoop clauses (+ idx 1)))
                (str "else if (" cCond ") { " stmt " } " (lowerCCondStmtLoop clauses (+ idx 1))))))))

(df lowerCCondExprLoop [(clauses (List rd/SExpr)) (idx Int64)] -> String
  (if (>= idx (list-length clauses))
      "(void)0"
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause cNode))
            (cCond (.-first p))
            (rawBody (.-second p))]
        (if (= cCond ":else")
            rawBody
            (let [(restExpr (lowerCCondExprLoop clauses (+ idx 1)))]
              (str "((" cCond ") ? (" rawBody ") : (" restExpr "))"))))))

(df lowerCCond [(items (List rd/SExpr))] -> String
  :d "Lowers a cond form into nested C99 ternary expressions or if-else statements."
  (let [(clauses (sliceFrom1 items))]
    (if (hasCondFlow? clauses 0)
        (lowerCCondStmtLoop clauses 0)
        (lowerCCondExprLoop clauses 0))))

(df inferCType [(valExpr String)] -> String
  :d "Infers a C99 variable type from lowered value expression."
  (cond
    ((and (string-ends-with? valExpr "LL")
          (not (string-contains? valExpr "(")))
     "int64_t")
    ((or (= valExpr "true") (= valExpr "false"))
     "bool")
    (:else "__auto_type")))

(df lowerCLetBinding [(b rd/SExpr)] -> String
  :d "Lowers a single let binding into a C declaration."
  (let [(pair (rd/sexprToList b))
        (pairLen (list-length pair))]
    (cond
      ((>= pairLen 3)
       (let [(vName (mangleCIdent (nthAtom pair 0)))
             (vType (c99TypeStr (nthAtom pair 1)))
             (vVal (lowerCExpr (option-or (list-get pair 2) (rd/sexprAtom "()"))))]
         (if (= vType "void")
             (str vVal ";")
             (if (string-starts-with? vVal "switch")
                 (str vType " " vName "; " (string-replace vVal "return " (str vName " = ")))
                 (str vType " " vName " = " vVal ";")))))
      ((= pairLen 2)
       (let [(rawName (nthAtom pair 0))
             (vName (mangleCIdent rawName))
             (vVal (lowerCExpr (option-or (list-get pair 1) (rd/sexprAtom "()"))))
             (vType (inferCType vVal))]
         (if (or (string-starts-with? rawName "unused")
                 (or (string-starts-with? vVal "println(")
                     (or (string-starts-with? vVal "eprintln(")
                         (or (string-starts-with? vVal "print(")
                             (string-starts-with? vVal "eprint(")))))
             (str vVal ";")
             (if (string-starts-with? vVal "switch")
                 (str vType " " vName "; " (string-replace vVal "return " (str vName " = ")))
                 (str vType " " vName " = " vVal ";")))))
      (:else ""))))

(df isNonEmptyStr? [(s String)] -> Bool
  :d "Checks if string is non-empty."
  (> (string-length s) 0))

(df isBlockStmt? [(s String)] -> Bool
  :d "Checks if statement is a block or switch statement."
  (and (string-ends-with? s "}")
       (or (string-starts-with? s "{")
           (string-starts-with? s "switch"))))

(df lowerCLetBodyStmt [(e rd/SExpr)] -> String
  :d "Lowers a statement in a let body."
  (let [(s (lowerCExpr e))]
    (if (or (string-ends-with? s ";") (isBlockStmt? s))
        s
        (str s ";"))))

(df lowerCLet [(items (List rd/SExpr))] -> String
  :d "Lowers a let binding form into a scoped C99 compound statement block."
  (let [(bindingsNode (option-or (list-get items 1) (rd/sexprVect (list))))
        (bodyNodes (sliceTail items 2))
        (bindList (rd/sexprToList bindingsNode))
        (decls (map lowerCLetBinding bindList))
        (validDecls (filter isNonEmptyStr? decls))
        (bodyLen (list-length bodyNodes))]
    (if (<= bodyLen 0)
        (str "{ " (string-join validDecls " ") " }")
        (let [(bodyStmts (map lowerCLetBodyStmt bodyNodes))]
          (str "{ " (string-join validDecls " ") " " (string-join bodyStmts " ") " }")))))

(df anyTrue? [(bools (List Bool))] -> Bool
  :d "Returns true if any boolean in list is true."
  (if (<= (list-length bools) 0)
      false
      (if (option-or (list-get bools 0) false)
          true
          (anyTrue? (sliceFrom1 bools)))))

(df isStringVarName? [(name String)] -> Bool
  :d "Checks if payload variable is a string name."
  (let [(names (list "src" "path" "sSrc" "entrySrc" "content" "text" "fullText" "outputStr" "raw" "msg" "s" "line" "str" "doc" "val" "modPath" "alias" "candAsl" "candSrc" "errStr" "failureMsg" "p" "fpath" "exprStr" "target" "emsg" "failure" "errMessage" "key" "name" "reason" "chunk" "s1" "s2" "varName" "bname" "nextBname" "cname" "c" "ch"))]
    (list-contains? names name)))

(df isSliceVarName? [(name String)] -> Bool
  :d "Checks if payload variable is a slice name."
  (let [(names (list "forms" "entryForms" "fList" "xs" "t" "files" "tokens" "args" "items" "lines" "parts" "cases" "fields" "defuns" "schemas" "enums" "r" "tail" "depFormsList" "entryForms" "fList"))]
    (list-contains? names name)))

(df isMapVarName? [(name String)] -> Bool
  :d "Checks if payload variable is a map name."
  (let [(names (list "deps" "filesMap" "schemasMap" "enumsMap" "caseOwnerMap" "importsMap" "funsMap" "exportsMap"))]
    (list-contains? names name)))

(df isSExprVarName? [(name String)] -> Bool
  :d "Checks if payload variable is an SExpr name."
  (let [(names (list "aExpr" "firstExpr" "e" "expr" "sexpr" "node" "h" "it" "v" "item" "firstItem" "pairExpr" "nameExpr" "valExpr" "paramsExpr" "msgExpr" "rnode" "innerE"))]
    (list-contains? names name)))

(df isIntVarName? [(name String)] -> Bool
  :d "Checks if payload variable is an integer name."
  (let [(names (list "count" "n" "len" "idx" "pos" "col" "i"))]
    (list-contains? names name)))

(df isParseErrVarName? [(name String)] -> Bool
  :d "Checks if payload variable is a ParseError name."
  (or (= name "pe") (= name "perr")))

(df isDefunVarName? [(name String)] -> Bool
  :d "Checks if payload variable is a DefunNode name."
  (or (= name "dfNode") (or (= name "dfOpt") (= name "d"))))

(df isFrameVarName? [(name String)] -> Bool
  :d "Checks if payload variable is an AslFrame name."
  (= name "f"))

(df isPosFormVarName? [(name String)] -> Bool
  :d "Checks if payload variable is an AslPosForm name."
  (or (= name "m") (or (= name "extra") (or (= name "pf") (= name "pForm")))))

(df isRunStateVarName? [(name String)] -> Bool
  :d "Checks if payload variable is an AslRunState name."
  (= name "run"))

(df constructorFieldName [(ctor String) (idx Int64)] -> String
  :d "Returns the struct member name for a given constructor and parameter index."
  (let [(c (stripModulePrefix ctor))]
    (cond
      ((or (= c "topModule") (or (= c "topSchema") (or (= c "topEnum") (= c "topDefun"))))
       (if (= idx 0) "node" ""))
      ((= c "fEval")
       (if (= idx 0) "expr" ""))
      ((= c "fTryInner")
       (if (= idx 0) "valVar" ""))
      ((= c "fIfCond")
       (if (= idx 0) "thenE" (if (= idx 1) "elseE" (if (= idx 2) "env" ""))))
      ((= c "fIfThen")
       (if (= idx 0) "elseE" (if (= idx 1) "thenTy" (if (= idx 2) "env" ""))))
      ((= c "fLetVal")
       (if (= idx 0) "bname" (if (= idx 1) "bindingsRest" (if (= idx 2) "tailExprs" (if (= idx 3) "env" "")))))
      ((= c "fCall")
       (if (= idx 0) "calleeName" (if (= idx 1) "calleeTy" (if (= idx 2) "argsDone" (if (= idx 3) "argsPending" (if (= idx 4) "env" ""))))))
      ((= c "sexprAtom")
       (if (= idx 0) "val" ""))
      ((or (= c "sexprList") (= c "sexprVect"))
       (if (= idx 0) "items" ""))
      ((= c "stepContinue")
       (if (= idx 0) "mode" ""))
      ((or (= c "valInt") (or (= c "valFloat") (or (= c "valStr") (= c "valBool"))))
       (if (= idx 0) "v" ""))
      ((= c "valError")
       (if (= idx 0) "msg" ""))
      ((or (= c "valList") (= c "valVect"))
       (if (= idx 0) "items" ""))
      ((= c "valMap")
       (if (= idx 0) "entries" ""))
      ((= c "valClosure")
       (if (= idx 0) "name" (if (= idx 1) "params" (if (= idx 2) "body" (if (= idx 3) "env" "")))))
      ((= c "tyCon")
       (if (= idx 0) "name" (if (= idx 1) "args" (if (= idx 2) "mod" (if (= idx 3) "shown" "")))))
      ((= c "tyVar")
       (if (= idx 0) "id" (if (= idx 1) "kind" "")))
      ((= c "tyFun")
       (if (= idx 0) "params" (if (= idx 1) "ret" "")))
      ((= c "uOk")
       (if (= idx 0) "subst" ""))
      ((= c "uErr")
       (if (= idx 0) "msg" (if (= idx 1) "numeric" "")))
      ((= c "argPos")
       (if (= idx 0) "val" ""))
      ((= c "argKw")
       (if (= idx 0) "key" (if (= idx 1) "val" "")))
      ((= c "tokSymbol")
       (if (= idx 0) "name" ""))
      ((= c "tokKeyword")
       (if (= idx 0) "key" ""))
      ((= c "tokString")
       (if (= idx 0) "val" ""))
      ((= c "tokInt")
       (if (= idx 0) "n" ""))
      ((= c "tokFloat")
       (if (= idx 0) "f" ""))
      ((= c "tokError")
       (if (= idx 0) "msg" ""))
      (:else ""))))

(df isUnitExpr? [(e rd/SExpr)] -> Bool
  :d "Checks if expression is unit ()."
  (mt e
    ((rd/sexprAtom v) (or (= v "()") (= v "(void)0")))
    ((rd/sexprList items) (<= (list-length items) 0))
    ((rd/sexprVect items) false)))

(df makePayloadBinding [(subj String) (pHead String) (pItems (List rd/SExpr)) (idx Int64)] -> String
  :d "Lowers a single pattern match arm payload binding."
  (let [(rawName (nthAtom pItems (+ idx 1)))
        (vName (mangleCIdent rawName))]
    (if (or (= rawName "_") (or (= vName "_") (or (= rawName "") (= vName ""))))
        ""
        (if (or (= pHead "ok") (or (= pHead "some") (= pHead "err")))
            (if (isStringVarName? rawName)
                (str "asl_string_t " vName " = asl_opt_str(((" subj ").data." (mangleCIdent pHead) ")); ")
                (if (isMapVarName? rawName)
                    (str "AslMap " vName " = asl_opt_map(((" subj ").data." (mangleCIdent pHead) ")); ")
                    (if (isSliceVarName? rawName)
                        (str "AslSlice_void " vName " = asl_opt_slice(((" subj ").data." (mangleCIdent pHead) ")); ")
                        (if (isSExprVarName? rawName)
                            (str "AslSExpr " vName " = asl_opt_sexpr(((" subj ").data." (mangleCIdent pHead) ")); ")
                            (if (isParseErrVarName? rawName)
                                (str "AslParseError " vName " = asl_opt_perr(((" subj ").data." (mangleCIdent pHead) ")); ")
                                (if (isDefunVarName? rawName)
                                    (str "AslDefunNode " vName " = asl_opt_defun(((" subj ").data." (mangleCIdent pHead) ")); ")
                                    (if (isFrameVarName? rawName)
                                        (str "AslFrame " vName " = asl_opt_frame(((" subj ").data." (mangleCIdent pHead) ")); ")
                                        (if (isPosFormVarName? rawName)
                                            (str "AslPosForm " vName " = asl_opt_posform(((" subj ").data." (mangleCIdent pHead) ")); ")
                                            (if (isRunStateVarName? rawName)
                                                (str "AslRunState " vName " = asl_opt_runstate(((" subj ").data." (mangleCIdent pHead) ")); ")
                                                (if (isIntVarName? rawName)
                                                    (str "int64_t " vName " = (int64_t)((intptr_t)((" subj ").data." (mangleCIdent pHead) ")); ")
                                                    (str "__auto_type " vName " = ((" subj ").data." (mangleCIdent pHead) "); ")))))))))))
            (let [(baseH (stripModulePrefix pHead))
                  (mHead (mangleCIdent baseH))
                  (fld (constructorFieldName pHead idx))]
              (if (string-empty? fld)
                  (str "__auto_type " vName " = ((" subj ").data." mHead "); ")
                  (str "__auto_type " vName " = ((" subj ").data." mHead "." fld "); ")))))))

(df makePayloadBindingsStep [(subj String) (pHead String) (pItems (List rd/SExpr)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates payload bindings for pattern match arm."
  (if (>= idx len)
      acc
      (makePayloadBindingsStep subj pHead pItems (+ idx 1) len (list-append acc (list (makePayloadBinding subj pHead pItems idx))))))

(df lowerCMatchArmStmts [(bodyStmts (List String))] -> String
  :d "Lowers match arm body statements with return on final expression."
  (let [(cnt (list-length bodyStmts))]
    (cond
      ((<= cnt 0) "")
      ((= cnt 1)
       (let [(s (option-or (list-get bodyStmts 0) ""))]
         (if (or (string-starts-with? s "return")
                 (or (string-starts-with? s "switch")
                     (or (string-starts-with? s "abort")
                         (string-starts-with? s "{"))))
             (str s " ")
             (str "return " s " "))))
      (:else
       (let [(initStmts (option-or (list-slice bodyStmts 0 (- cnt 1)) (list)))
             (lastS (option-or (list-get bodyStmts (- cnt 1)) ""))
             (retLast (if (or (string-starts-with? lastS "return")
                              (or (string-starts-with? lastS "switch")
                                  (or (string-starts-with? lastS "abort")
                                      (string-starts-with? lastS "{"))))
                          lastS
                          (str "return " lastS)))]
         (str (string-join initStmts " ") " " retLast " "))))))

(df lowerCMatchArm [(arm rd/SExpr) (subj String)] -> String
  :d "Lowers a single pattern match arm into a C99 switch case with mandatory break."
  (mt arm
    ((rd/sexprList aItems)
     (if (<= (list-length aItems) 0)
         ""
         (let [(patNode (option-or (list-get aItems 0) (rd/sexprAtom "_")))
               (bodyTail (sliceFrom1 aItems))
               (bodyStmts (map lowerCLetBodyStmt bodyTail))
               (bodyStr (lowerCMatchArmStmts bodyStmts))]
           (mt patNode
             ((rd/sexprAtom v)
              (if (or (= v "_") (= v ":else") (= v "else"))
                  (str "default: { " bodyStr "break; }")
                  (let [(tag (caseTagConst v))]
                    (str "case " tag ": { " bodyStr "break; }"))))
             ((rd/sexprList pItems)
              (let [(pHead (nthAtom pItems 0))
                    (tag (caseTagConst pHead))
                    (argCount (- (list-length pItems) 1))
                    (payloadBindings (if (> argCount 0)
                                         (string-join (makePayloadBindingsStep subj pHead pItems 0 argCount (list)) "")
                                         ""))]
                (str "case " tag ": { " payloadBindings bodyStr "break; }")))
             ((rd/sexprVect _)
              "")))))
    ((rd/sexprVect aItems)
     (lowerCMatchArm (rd/sexprList aItems) subj))
    ((rd/sexprAtom _) "")))

(df isDefaultArm? [(s String)] -> Bool
  :d "Checks if arm string starts with default:."
  (string-starts-with? s "default:"))

(df lowerCMatchArmsStep [(arms (List rd/SExpr)) (subj String) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates lowered match arms."
  (if (>= idx len)
      acc
      (let [(armStr (lowerCMatchArm (option-or (list-get arms idx) (rd/sexprAtom "")) subj))]
        (lowerCMatchArmsStep arms subj (+ idx 1) len (list-append acc (list armStr))))))

(df lowerCMatch [(items (List rd/SExpr))] -> String
  :d "Lowers a match or mt form into an exhaustive C99 switch statement with unreachable default."
  (let [(subj (lowerCExpr (option-or (list-get items 1) (rd/sexprAtom "val"))))
        (arms (sliceTail items 2))
        (armStrs (lowerCMatchArmsStep arms subj 0 (list-length arms) (list)))
        (validArms (filter isNonEmptyStr? armStrs))
        (hasDefault (anyTrue? (map isDefaultArm? validArms)))
        (defaultGuard (if hasDefault "" "default: { abort(); break; }"))
        (allClauses (if (> (string-length defaultGuard) 0)
                        (list-append validArms (list defaultGuard))
                        validArms))]
    (str "switch ((" subj ").tag) { " (string-join allClauses " ") " }")))

(df isStringExpr? [(e rd/SExpr)] -> Bool
  :d "Heuristic check if SExpr produces a string value."
  (mt e
    ((rd/sexprAtom v)
     (or (string-starts-with? v "\"")
         (or (string-starts-with? v ".-")
             (or (= v "s")
                 (or (= v "str")
                     (or (= v "name")
                         (or (= v "fnName")
                             (or (= v "targetFn")
                                 (or (= v "p")
                                     (or (= v "path")
                                         (or (= v "msg")
                                             (or (= v "line")
                                                 (or (= v "op")
                                                     (or (= v "atomStr")
                                                         (or (= v "as")
                                                             (or (= v "bs")
                                                                 (or (= v "entryFile")
                                                                     (or (= v "retTy")
                                                                         (= v "typeName")))))))))))))))))))
    ((rd/sexprList items)
     (let [(h (nthAtom items 0))]
       (or (= h "str")
           (or (= h "string-replace")
               (or (= h "string-join")
                   (or (= h "sliceStrOr")
                       (or (= h "sliceOr")
                           (or (= h "string-trim")
                               (or (= h "string-upper")
                                   (or (= h "string-lower")
                                       (or (= h "int-to-string")
                                           (or (= h "string-from-int64")
                                               (or (= h "mangleCIdent")
                                                    (or (string-ends-with? h "sexprHead")
                                                        (string-ends-with? h "Head")))))))))))))))
    ((rd/sexprVect _) false)))

(df foldBinaryOpStep [(cOp String) (restArgs (List rd/SExpr)) (idx Int64) (len Int64) (acc String)] -> String
  :d "Accumulates binary operator expressions."
  (if (>= idx len)
      acc
      (let [(argNode (option-or (list-get restArgs idx) (rd/sexprAtom "0LL")))
            (nextAcc (str "((" acc ") " cOp " (" (lowerCExpr argNode) "))"))]
        (foldBinaryOpStep cOp restArgs (+ idx 1) len nextAcc))))

(df protectMacroArg [(s String)] -> String
  :d "Wraps compound literals or braced expressions in parentheses to protect macro commas."
  (if (string-contains? s "{")
      (str "(" s ")")
      s))

(df caseTagConst [(patHead String)] -> String
  :d "Builds the tag constant for a match arm using the bare case name, matching the alias emitCaseTagAlias emits; the module alias is dropped because the alias is keyed on the case name alone."
  (str "ASL_TAG_" (string-upper (string-replace (stripModulePrefix patHead) "-" "_"))))

(df lowerCStrConcat [(args (List rd/SExpr)) (idx Int64) (len Int64)] -> String
  :d "Right-nests the variadic str builtin into pairwise ISO C99 string concatenations, which needs no element type because str is variadic over String."
  (if (>= idx len)
      "((asl_string_t){ .data = \"\", .len = 0 })"
      (let [(here (lowerCExpr (option-or (list-get args idx) (rd/sexprAtom "\"\""))))]
        (if (= idx (- len 1))
            here
            (str "string_concat2(" here ", " (lowerCStrConcat args (+ idx 1) len) ")")))))

(df lowerCCall [(items (List rd/SExpr))] -> String
  :d "Lowers a call form, field access, or operator expression into ISO C99."
  (let [(head (nthAtom items 0))
        (rawArgs (sliceFrom1 items))]
    (cond
      ((string-starts-with? head ".-")
       (let [(field (sliceStrOr head 2 (string-length head) ""))
             (target (if (> (list-length rawArgs) 0)
                         (lowerCExpr (option-or (list-get rawArgs 0) (rd/sexprAtom "()")))
                         "()"))]
         (lowerCFieldAccess target field)))
      ((= head "not")
       (let [(arg (if (> (list-length rawArgs) 0)
                      (lowerCExpr (option-or (list-get rawArgs 0) (rd/sexprAtom "false")))
                      "false"))]
         (str "(!(" arg "))")))
      ((= head "str")
       (lowerCStrConcat rawArgs 0 (list-length rawArgs)))
      ((isBinaryOp? head)
       (let [(argCount (list-length rawArgs))
             (cOp (opToC head))]
         (cond
           ((= argCount 1)
            (let [(a0 (lowerCExpr (option-or (list-get rawArgs 0) (rd/sexprAtom "0LL"))))]
              (str "(-(" a0 "))")))
           ((>= argCount 2)
            (let [(raw0 (option-or (list-get rawArgs 0) (rd/sexprAtom "0LL")))
                  (raw1 (option-or (list-get rawArgs 1) (rd/sexprAtom "0LL")))
                  (firstArg (lowerCExpr raw0))
                  (secondArg (lowerCExpr raw1))
                  (isStr (or (string-contains? firstArg "asl_string_")
                             (or (string-contains? secondArg "asl_string_")
                                 (or (isStringExpr? raw0)
                                     (isStringExpr? raw1)))))]
              (if (and isStr (or (= head "=") (= head "!=")))
                  (if (= head "=")
                      (str "asl_string_eq(" firstArg ", " secondArg ")")
                      (str "(!asl_string_eq(" firstArg ", " secondArg "))"))
                  (let [(restArgs (sliceFrom1 rawArgs))]
                    (foldBinaryOpStep cOp restArgs 0 (list-length restArgs) firstArg)))))
           (:else ""))))
      ((and (> (string-length head) 0) (string-starts-with? head ":"))
       (lowerCRecordInit items))
      ((and (> (string-length (stripModulePrefix head)) 0)
            (let [(c0 (sliceStrOr (stripModulePrefix head) 0 1 ""))]
              (and (>= c0 "A") (<= c0 "Z")))
            (> (list-length items) 1)
            (string-starts-with? (nthAtom items 1) ":"))
       (lowerCRecordInit items))
      ((and (= (stripModulePrefix head) "ok")
            (or (<= (list-length rawArgs) 0)
                (or (= (nthAtom rawArgs 0) "()")
                    (isUnitExpr? (option-or (list-get rawArgs 0) (rd/sexprAtom ""))))))
       "okUnit()")
      (:else
       (let [(fnName (mangleCIdent (stripModulePrefix head)))
             (rawArgStrs (map lowerCExpr rawArgs))
             (args (map protectMacroArg rawArgStrs))]
         (str fnName "(" (string-join args ", ") ")"))))))

(df lowerCDo [(items (List rd/SExpr))] -> String
  :d "Lowers a sequential do block into a C comma expression."
  (let [(stmts (sliceFrom1 items))
        (stmtCount (list-length stmts))]
    (cond
      ((<= stmtCount 0) "(void)0")
      ((= stmtCount 1)
       (lowerCExpr (option-or (list-get stmts 0) (rd/sexprAtom "()"))))
      (:else
       (let [(exprs (map lowerCExpr stmts))]
         (str "(" (string-join exprs ", ") ")"))))))

(df lowerCExpr [(e rd/SExpr)] -> String
  :d "Lowers an arbitrary ASL S-expression into an ISO C99 expression."
  (mt e
    ((rd/sexprAtom v) (lowerCAtom v))
    ((rd/sexprVect items)
     (str "{" (string-join (map lowerCExpr items) ", ") "}"))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         "(void)0"
         (let [(head (nthAtom items 0))]
           (cond
             ((= head "fn") "(void*)0")
             ((= head "let") (lowerCLet items))
             ((= head "if") (lowerCIf items))
             ((= head "cond") (lowerCCond items))
             ((or (= head "match") (= head "mt")) (lowerCMatch items))
             ((= head "do") (lowerCDo items))
             (:else (lowerCCall items))))))))
