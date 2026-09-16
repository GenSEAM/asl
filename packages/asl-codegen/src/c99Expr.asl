(module asl-codegen/c99Expr
  :d "Pure ISO C99 expression lowering, control flow, and statement synthesis."
  :x [LowerCtx
      emptyLowerCtx
      ctxWithVar
      ctxVarType
      lowerCExpr
      lowerCAtom
      lowerCLet
      lowerCIf
      lowerCCond
      lowerCMatch
      lowerCCall
      lowerCFieldAccess
      lowerCRecordInit
      lowerCDo
      wrapBlockWithReturn
      isC99Keyword?
      mangleCIdent
      mangleCTypeName
      c99TypeStr
      isIntegerLiteral?
      isFloatLiteral?]
  :i [(reader :a rd)])

(dfs LowerCtx
  (:f vars (List (Pair String String)) "Variable name to its emitted C type, for the enclosing function")
  (:f substs (List (Pair String String)) "Name to the C expression it stands for, used for match payload binders so their type comes from the union member instead of being declared")
  (:f fns (List (Pair String String)) "Function name to its emitted C return type, for every defun in the translation unit")
  (:f retTy String "Emitted C return type of the enclosing function"))

(df emptyLowerCtx [] -> LowerCtx
  :d "The context used where no enclosing signature is known; a lookup in it fails rather than guessing a type."
  (LowerCtx :vars (list) :substs (list) :fns (list) :retTy ""))

(df ctxWithVar [(ctx LowerCtx) (name String) (cType String)] -> LowerCtx
  :d "Extends the lowering context with one variable binding, shadowing any earlier binding of the same name."
  (LowerCtx :vars (list-cons (pair name cType) (.-vars ctx)) :substs (.-substs ctx) :fns (.-fns ctx) :retTy (.-retTy ctx)))

(df ctxWithSubst [(ctx LowerCtx) (name String) (cExpr String)] -> LowerCtx
  :d "Binds a name to the C expression it stands for, so a match payload needs no declaration and therefore no guessed type."
  (LowerCtx :vars (.-vars ctx) :substs (list-cons (pair name cExpr) (.-substs ctx)) :fns (.-fns ctx) :retTy (.-retTy ctx)))

(df ctxFnRetType [(ctx LowerCtx) (name String)] -> (Option String)
  :d "Resolves a called function to its declared C return type, which is what gives a let binding its type instead of a guess from the lowered text."
  (ctxSubstStep (.-fns ctx) 0 (list-length (.-fns ctx)) name))

(df ctxSubstStep [(ss (List (Pair String String))) (idx Int64) (len Int64) (name String)] -> (Option String)
  :d "Scans substitutions innermost-first."
  (if (>= idx len)
      (none)
      (let [(p (option-or (list-get ss idx) (pair "" "")))]
        (if (= (.-first p) name)
            (some (.-second p))
            (ctxSubstStep ss (+ idx 1) len name)))))

(df ctxSubst [(ctx LowerCtx) (name String)] -> (Option String)
  :d "Resolves a name to the C expression it stands for, if one is bound."
  (ctxSubstStep (.-substs ctx) 0 (list-length (.-substs ctx)) name))

(df ctxVarTypeStep [(vars (List (Pair String String))) (idx Int64) (len Int64) (name String)] -> (Option String)
  :d "Scans the context bindings in innermost-first order."
  (if (>= idx len)
      (none)
      (let [(p (option-or (list-get vars idx) (pair "" "")))]
        (if (= (.-first p) name)
            (some (.-second p))
            (ctxVarTypeStep vars (+ idx 1) len name)))))

(df ctxVarType [(ctx LowerCtx) (name String)] -> (Option String)
  :d "Resolves a variable to its emitted C type, or none when the enclosing signature does not determine it."
  (ctxVarTypeStep (.-vars ctx) 0 (list-length (.-vars ctx)) name))

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

(df lowerCRecordField [(ctx LowerCtx) (items (List rd/SExpr)) (idx Int64)] -> String
  :d "Lowers a single record init key-value field."
  (let [(kPos (+ 1 (* idx 2)))
        (vPos (+ 2 (* idx 2)))
        (kAtom (nthAtom items kPos))
        (kClean (if (string-starts-with? kAtom ":")
                    (sliceStrOr kAtom 1 (string-length kAtom) kAtom)
                    kAtom))
        (vNode (option-or (list-get items vPos) (rd/sexprAtom "()")))
        (vVal (lowerCExpr ctx vNode))]
    (str "." (mangleCIdent kClean) " = " vVal)))

(df lowerCRecordFieldsStep [(ctx LowerCtx) (items (List rd/SExpr)) (idx Int64) (numPairs Int64) (acc (List String))] -> (List String)
  :d "Accumulates lowered record field initializers."
  (if (>= idx numPairs)
      acc
      (lowerCRecordFieldsStep ctx items (+ idx 1) numPairs (list-append acc (list (lowerCRecordField ctx items idx))))))

(df lowerCRecordInit [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers record construction into a C99 designated compound literal."
  (let [(rawName (nthAtom items 0))
        (recName (stripModulePrefix rawName))
        (recType (mangleCTypeName recName))
        (itemsLen (list-length items))]
    (if (<= itemsLen 1)
        (str "(" recType "){ 0 }")
        (let [(numPairs (/ (- itemsLen 1) 2))
              (fieldStrs (lowerCRecordFieldsStep ctx items 0 numPairs (list)))]
          (str "(" recType "){ " (string-join fieldStrs ", ") " }")))))

(df isNonEmptyStr? [(s String)] -> Bool
  :d "Checks if string is non-empty."
  (> (string-length s) 0))

(df wrapBlockWithReturn [(s String)] -> String
  :d "Wraps block with return on final expression without statement expressions."
  (let [(t (string-trim s))]
    (if (and (string-starts-with? t "{") (string-ends-with? t "}"))
        (if (or (string-starts-with? t "{ return")
                (or (string-contains? t "switch")
                    (or (string-contains? t "abort")
                        (string-contains? t "return"))))
            t
            (let [(inner (string-trim (sliceStrOr t 1 (- (string-length t) 1) "")))]
              (let [(parts (string-split inner ";"))
                    (pCount (list-length parts))]
                (if (<= pCount 1)
                    (if (string-empty? inner)
                        "{ return; }"
                        (if (or (string-starts-with? inner "return")
                                (or (string-starts-with? inner "switch")
                                    (or (string-starts-with? inner "abort")
                                        (string-starts-with? inner "if"))))
                            (str "{ " inner "; }")
                            (str "{ return " inner "; }")))
                    (let [(nonEmpty (filter isNonEmptyStr? (map string-trim parts)))
                          (nLen (list-length nonEmpty))]
                      (if (<= nLen 0)
                          "{ return; }"
                          (if (= nLen 1)
                              (let [(s0 (option-or (list-get nonEmpty 0) ""))]
                                (if (or (string-starts-with? s0 "return")
                                        (or (string-starts-with? s0 "switch")
                                            (or (string-starts-with? s0 "abort")
                                                (string-starts-with? s0 "if"))))
                                    (str "{ " s0 "; }")
                                    (str "{ return " s0 "; }")))
                              (let [(inits (option-or (list-slice nonEmpty 0 (- nLen 1)) (list)))
                                    (lastS (option-or (list-get nonEmpty (- nLen 1)) ""))
                                    (retLast (if (or (string-starts-with? lastS "return")
                                                     (or (string-starts-with? lastS "switch")
                                                         (or (string-starts-with? lastS "abort")
                                                             (string-starts-with? lastS "if"))))
                                                 lastS
                                                 (str "return " lastS)))]
                                (str "{ " (string-join inits "; ") "; " retLast "; }")))))))))
        (if (or (string-starts-with? t "return")
                (or (string-starts-with? t "switch")
                    (or (string-starts-with? t "abort")
                        (string-starts-with? t "if"))))
            t
            (str "return " t ";")))))

(df lowerCIf [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers an if form into if-statement with returns if branches have control flow or blocks, else ternary."
  (let [(condExpr (lowerCExpr ctx (option-or (list-get items 1) (rd/sexprAtom "false"))))
        (rawThen (lowerCExpr ctx (option-or (list-get items 2) (rd/sexprAtom "(void)0"))))
        (rawElse (if (> (list-length items) 3)
                     (lowerCExpr ctx (option-or (list-get items 3) (rd/sexprAtom "(void)0")))
                     "(void)0"))
        (tTrim (string-trim rawThen))
        (eTrim (string-trim rawElse))
        (thenIsBlock (string-starts-with? tTrim "{"))
        (elseIsBlock (string-starts-with? eTrim "{"))
        (thenHasFlow (or thenIsBlock (or (string-contains? rawThen "return ") (string-contains? rawThen "switch"))))
        (elseHasFlow (or elseIsBlock (or (string-contains? rawElse "return ") (string-contains? rawElse "switch"))))]
    (if (or thenHasFlow elseHasFlow)
        (let [(tStmt (wrapBlockWithReturn rawThen))
              (eStmt (wrapBlockWithReturn rawElse))]
          (let [(tFinal (if (string-starts-with? tStmt "{") tStmt (str "{ " tStmt " }")))
                (eFinal (if (string-starts-with? eStmt "{") eStmt (str "{ " eStmt " }")))]
            (str "if (" condExpr ") " tFinal " else " eFinal)))
        (str "((" condExpr ") ? (" rawThen ") : (" rawElse "))"))))

(df lowerCCondClause [(ctx LowerCtx) (clause rd/SExpr)] -> (Pair String String)
  :d "Extracts condition and expression from a single cond clause."
  (let [(cList (rd/sexprToList clause))]
    (if (<= (list-length cList) 0)
        (pair "false" "(void)0")
        (let [(head (nthAtom cList 0))
              (isElse (or (= head ":else") (= head "else")))]
          (if isElse
              (let [(bVal (lowerCExpr ctx (option-or (list-get cList 1) (rd/sexprAtom "(void)0"))))]
                (pair ":else" bVal))
              (let [(cVal (lowerCExpr ctx (option-or (list-get cList 0) (rd/sexprAtom "false"))))
                    (bVal (lowerCExpr ctx (option-or (list-get cList 1) (rd/sexprAtom "(void)0"))))]
                (pair cVal bVal)))))))

(df hasCondFlow? [(ctx LowerCtx) (clauses (List rd/SExpr)) (idx Int64)] -> Bool
  (if (>= idx (list-length clauses))
      false
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause ctx cNode))
            (rawBody (.-second p))]
        (if (or (string-starts-with? rawBody "return") (or (string-starts-with? rawBody "switch") (string-starts-with? rawBody "{")))
            true
            (hasCondFlow? ctx clauses (+ idx 1))))))

(df lowerCCondStmtLoop [(ctx LowerCtx) (clauses (List rd/SExpr)) (idx Int64)] -> String
  (if (>= idx (list-length clauses))
      ""
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause ctx cNode))
            (cCond (.-first p))
            (rawBody (.-second p))
            (stmt (wrapBlockWithReturn rawBody))]
        (let [(wrapped (if (string-starts-with? stmt "{") stmt (str "{ " stmt " }")))]
          (if (= cCond ":else")
              (str "else " wrapped " ")
              (if (= idx 0)
                  (str "if (" cCond ") " wrapped " " (lowerCCondStmtLoop ctx clauses (+ idx 1)))
                  (str "else if (" cCond ") " wrapped " " (lowerCCondStmtLoop ctx clauses (+ idx 1)))))))))

(df lowerCCondExprLoop [(ctx LowerCtx) (clauses (List rd/SExpr)) (idx Int64)] -> String
  (if (>= idx (list-length clauses))
      "(void)0"
      (let [(cNode (option-or (list-get clauses idx) (rd/sexprAtom "()")))
            (p (lowerCCondClause ctx cNode))
            (cCond (.-first p))
            (rawBody (.-second p))]
        (if (= cCond ":else")
            rawBody
            (let [(restExpr (lowerCCondExprLoop ctx clauses (+ idx 1)))]
              (str "((" cCond ") ? (" rawBody ") : (" restExpr "))"))))))

(df lowerCCond [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers a cond form into nested C99 ternary expressions or if-else statements."
  (let [(clauses (sliceFrom1 items))]
    (if (hasCondFlow? ctx clauses 0)
        (lowerCCondStmtLoop ctx clauses 0)
        (lowerCCondExprLoop ctx clauses 0))))

(df inferCTypeOfExpr [(ctx LowerCtx) (e rd/SExpr) (valExpr String)] -> String
  :d "Resolves the C type of a let binding from the binding expression and the enclosing context: a literal from its own shape, a variable or a call from a declared type. Falls back to the lowered text only when nothing declares it, which is the remaining gap the checker will close."
  (mt e
    ((rd/sexprVect _) "")
    ((rd/sexprAtom v)
     (cond
       ((isIntegerLiteral? v) "int64_t")
       ((isFloatLiteral? v) "double")
       ((or (= v "true") (= v "false")) "bool")
       ((string-starts-with? v "\"") "asl_string_t")
       (:else (mt (ctxVarType ctx v)
                ((some t) t)
                ((none) "")))))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         ""
         (let [(head (stripModulePrefix (nthAtom items 0)))]
           (mt (ctxFnRetType ctx head)
             ((some t) t)
             ((none) "")))))))

(df inferCType [(ctx LowerCtx) (e rd/SExpr) (valExpr String)] -> String
  :d "Infers a C99 variable type, preferring a declared type over any inspection of the lowered text."
  (let [(declared (inferCTypeOfExpr ctx e valExpr))]
    (if (not (= declared ""))
        declared
        (cond
          ((and (string-ends-with? valExpr "LL")
                (not (string-contains? valExpr "(")))
           "int64_t")
          ((or (= valExpr "true") (= valExpr "false"))
           "bool")
          (:else "__auto_type")))))

(df typeNodeToStr [(e rd/SExpr)] -> String
  :d "Renders a type SExpr node into a canonical C99 type name."
  (mt e
    ((rd/sexprAtom v) (mangleCTypeName v))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         "void"
         (let [(head (nthAtom items 0))]
           (cond
             ((= head "List")
              (let [(elem (if (> (list-length items) 1) (typeNodeToStr (option-or (list-get items 1) (rd/sexprAtom ""))) "asl_string_t"))]
                (str "AslSlice_" elem)))
             ((= head "Option")
              (let [(inner (if (> (list-length items) 1) (typeNodeToStr (option-or (list-get items 1) (rd/sexprAtom ""))) "void"))]
                (str "AslOption_" inner)))
             ((= head "Pair")
              (let [(t1 (if (> (list-length items) 1) (typeNodeToStr (option-or (list-get items 1) (rd/sexprAtom ""))) "asl_string_t"))
                    (t2 (if (> (list-length items) 2) (typeNodeToStr (option-or (list-get items 2) (rd/sexprAtom ""))) "asl_string_t"))]
                (str "AslPair_" t1 "_" t2)))
             ((= head "Map")
              (let [(t1 (if (> (list-length items) 1) (typeNodeToStr (option-or (list-get items 1) (rd/sexprAtom ""))) "asl_string_t"))
                    (t2 (if (> (list-length items) 2) (typeNodeToStr (option-or (list-get items 2) (rd/sexprAtom ""))) "asl_string_t"))]
                (str "AslMap_" t1 "_" t2)))
             ((= head "Result")
              (let [(t1 (if (> (list-length items) 1) (typeNodeToStr (option-or (list-get items 1) (rd/sexprAtom ""))) "void"))
                    (t2 (if (> (list-length items) 2) (typeNodeToStr (option-or (list-get items 2) (rd/sexprAtom ""))) "asl_string_t"))]
                (str "AslResult_" t1 "_" t2)))
             (:else (mangleCTypeName head))))))
    ((rd/sexprVect _) "")))

(df ctxWithBindingsStep [(ctx LowerCtx) (bs (List rd/SExpr)) (idx Int64) (len Int64)] -> LowerCtx
  :d "Extends lowering context with types of let bindings so accessors resolve per instantiation."
  (if (>= idx len)
      ctx
      (let [(b (option-or (list-get bs idx) (rd/sexprAtom "()")))
            (pair (rd/sexprToList b))
            (pLen (list-length pair))]
        (if (>= pLen 3)
            (let [(rawName (nthAtom pair 0))
                  (ty (typeNodeToStr (option-or (list-get pair 1) (rd/sexprAtom ""))))]
              (ctxWithBindingsStep (ctxWithVar ctx rawName ty) bs (+ idx 1) len))
            (if (= pLen 2)
                (let [(rawName (nthAtom pair 0))
                      (valNode (option-or (list-get pair 1) (rd/sexprAtom "()")))
                      (ty (inferCType ctx valNode (lowerCExpr ctx valNode)))]
                  (if (!= ty "__auto_type")
                      (ctxWithBindingsStep (ctxWithVar ctx rawName ty) bs (+ idx 1) len)
                      (ctxWithBindingsStep ctx bs (+ idx 1) len)))
                (ctxWithBindingsStep ctx bs (+ idx 1) len))))))

(df lowerCLetBinding [(ctx LowerCtx) (b rd/SExpr)] -> String
  :d "Lowers a single let binding into a C declaration."
  (let [(pair (rd/sexprToList b))
        (pairLen (list-length pair))]
    (cond
      ((>= pairLen 3)
       (let [(vName (mangleCIdent (nthAtom pair 0)))
             (vType (typeNodeToStr (option-or (list-get pair 1) (rd/sexprAtom ""))))
             (vVal (lowerCExpr ctx (option-or (list-get pair 2) (rd/sexprAtom "()"))))]
         (if (= vType "void")
             (str vVal ";")
             (if (string-starts-with? vVal "switch")
                 (str vType " " vName "; " (string-replace vVal "return " (str vName " = ")))
                 (str vType " " vName " = " vVal ";")))))
      ((= pairLen 2)
       (let [(rawName (nthAtom pair 0))
             (vName (mangleCIdent rawName))
             (vVal (lowerCExpr ctx (option-or (list-get pair 1) (rd/sexprAtom "()"))))
             (vType (inferCType ctx (option-or (list-get pair 1) (rd/sexprAtom "()")) vVal))]
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

(df isBlockStmt? [(s String)] -> Bool
  :d "Checks if statement is a block or switch statement."
  (and (string-ends-with? s "}")
       (or (string-starts-with? s "{")
           (string-starts-with? s "switch"))))

(df lowerCLetBodyStmt [(ctx LowerCtx) (e rd/SExpr)] -> String
  :d "Lowers a statement in a let body."
  (let [(s (lowerCExpr ctx e))]
    (if (or (string-ends-with? s ";") (isBlockStmt? s))
        s
        (str s ";"))))

(df lowerCLet [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers a let binding form into a scoped C99 compound statement block."
  (let [(bindingsNode (option-or (list-get items 1) (rd/sexprVect (list))))
        (bodyNodes (sliceTail items 2))
        (bindList (rd/sexprToList bindingsNode))
        (bodyCtx (ctxWithBindingsStep ctx bindList 0 (list-length bindList)))
        (decls (lowerCLetBindingsStep ctx bindList 0 (list-length bindList) (list)))
        (validDecls (filter isNonEmptyStr? decls))
        (bodyLen (list-length bodyNodes))]
    (if (<= bodyLen 0)
        (str "{ " (string-join validDecls " ") " }")
        (let [(bodyStmts (lowerCLetBodyStmtsStep bodyCtx bodyNodes 0 (list-length bodyNodes) (list)))]
          (str "{ " (string-join validDecls " ") " " (string-join bodyStmts " ") " }")))))

(df anyTrue? [(bools (List Bool))] -> Bool
  :d "Returns true if any boolean in list is true."
  (if (<= (list-length bools) 0)
      false
      (if (option-or (list-get bools 0) false)
          true
          (anyTrue? (sliceFrom1 bools)))))

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

(df payloadAccessor [(subj String) (pHead String) (idx Int64)] -> String
  :d "The C expression a match payload binder stands for: the union member itself, whose type therefore needs no declaration and no guess."
  (let [(mHead (mangleCIdent (stripModulePrefix pHead)))
        (fld (constructorFieldName pHead idx))]
    (if (string-empty? fld)
        (str "((" subj ").data." mHead ")")
        (str "((" subj ").data." mHead "." fld ")"))))

(df payloadSubstCtx [(ctx LowerCtx) (subj String) (pHead String) (pItems (List rd/SExpr)) (idx Int64) (len Int64)] -> LowerCtx
  :d "Binds every payload name of a match arm to the union member it stands for, replacing the declaration whose type used to be guessed from the binder's spelling."
  (if (>= idx len)
      ctx
      (let [(rawName (nthAtom pItems (+ idx 1)))]
        (if (or (= rawName "_") (= rawName ""))
            (payloadSubstCtx ctx subj pHead pItems (+ idx 1) len)
            (payloadSubstCtx (ctxWithSubst ctx rawName (payloadAccessor subj pHead idx))
                             subj pHead pItems (+ idx 1) len)))))

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
             (str (wrapBlockWithReturn s) " ")
             (str "return " s " "))))
      (:else
       (let [(initStmts (option-or (list-slice bodyStmts 0 (- cnt 1)) (list)))
             (lastS (option-or (list-get bodyStmts (- cnt 1)) ""))
             (retLast (if (or (string-starts-with? lastS "return")
                              (or (string-starts-with? lastS "switch")
                                  (or (string-starts-with? lastS "abort")
                                      (string-starts-with? lastS "{"))))
                          (wrapBlockWithReturn lastS)
                          (str "return " lastS)))]
         (str (string-join initStmts " ") " " retLast " "))))))

(df lowerCMatchArm [(ctx LowerCtx) (arm rd/SExpr) (subj String)] -> String
  :d "Lowers a single pattern match arm into a C99 switch case with mandatory break."
  (mt arm
    ((rd/sexprList aItems)
     (if (<= (list-length aItems) 0)
         ""
         (let [(patNode (option-or (list-get aItems 0) (rd/sexprAtom "_")))
               (bodyTail (sliceFrom1 aItems))]
           (mt patNode
             ((rd/sexprAtom v)
              (let [(bodyStr (lowerCMatchArmStmts (lowerCLetBodyStmtsStep ctx bodyTail 0 (list-length bodyTail) (list))))]
                (if (or (= v "_") (= v ":else") (= v "else"))
                    (str "default: { " bodyStr "break; }")
                    (str "case " (caseTagConst v) ": { " bodyStr "break; }"))))
             ((rd/sexprList pItems)
              (let [(pHead (nthAtom pItems 0))
                    (tag (caseTagConst pHead))
                    (argCount (- (list-length pItems) 1))
                    (armCtx (payloadSubstCtx ctx subj pHead pItems 0 argCount))
                    (bodyStr (lowerCMatchArmStmts (lowerCLetBodyStmtsStep armCtx bodyTail 0 (list-length bodyTail) (list))))]
                (str "case " tag ": { " bodyStr "break; }")))
             ((rd/sexprVect _)
              "")))))
    ((rd/sexprVect aItems)
     (lowerCMatchArm ctx (rd/sexprList aItems) subj))
    ((rd/sexprAtom _) "")))

(df isDefaultArm? [(s String)] -> Bool
  :d "Checks if arm string starts with default:."
  (string-starts-with? s "default:"))

(df lowerCMatchArmsStep [(ctx LowerCtx) (arms (List rd/SExpr)) (subj String) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates lowered match arms."
  (if (>= idx len)
      acc
      (let [(armStr (lowerCMatchArm ctx (option-or (list-get arms idx) (rd/sexprAtom "")) subj))]
        (lowerCMatchArmsStep ctx arms subj (+ idx 1) len (list-append acc (list armStr))))))

(df lowerCMatch [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers a match or mt form into an exhaustive C99 switch statement with unreachable default."
  (let [(subj (lowerCExpr ctx (option-or (list-get items 1) (rd/sexprAtom "val"))))
        (arms (sliceTail items 2))
        (armStrs (lowerCMatchArmsStep ctx arms subj 0 (list-length arms) (list)))
        (validArms (filter isNonEmptyStr? armStrs))
        (hasDefault (anyTrue? (map isDefaultArm? validArms)))
        (defaultGuard (if hasDefault "" "default: { abort(); break; }"))
        (allClauses (if (> (string-length defaultGuard) 0)
                        (list-append validArms (list defaultGuard))
                        validArms))]
    (str "switch ((int)((" subj ").tag)) { " (string-join allClauses " ") " }")))

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

(df foldBinaryOpStep [(ctx LowerCtx) (cOp String) (restArgs (List rd/SExpr)) (idx Int64) (len Int64) (acc String)] -> String
  :d "Accumulates binary operator expressions."
  (if (>= idx len)
      acc
      (let [(argNode (option-or (list-get restArgs idx) (rd/sexprAtom "0LL")))
            (nextAcc (str "((" acc ") " cOp " (" (lowerCExpr ctx argNode) "))"))]
        (foldBinaryOpStep ctx cOp restArgs (+ idx 1) len nextAcc))))

(df protectMacroArg [(s String)] -> String
  :d "Wraps compound literals or braced expressions in parentheses to protect macro commas."
  (if (string-contains? s "{")
      (str "(" s ")")
      s))

(df caseTagConst [(patHead String)] -> String
  :d "Builds the tag constant for a match arm using the bare case name, matching the alias emitCaseTagAlias emits; the module alias is dropped because the alias is keyed on the case name alone."
  (str "ASL_TAG_" (string-upper (string-replace (stripModulePrefix patHead) "-" "_"))))

(df lowerCExprsStep [(ctx LowerCtx) (es (List rd/SExpr)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Lowers a list of expressions in order, threading the lowering context explicitly rather than through a closure."
  (if (>= idx len)
      acc
      (let [(e (option-or (list-get es idx) (rd/sexprAtom "()")))]
        (lowerCExprsStep ctx es (+ idx 1) len (list-append acc (list (lowerCExpr ctx e)))))))

(df lowerCLetBindingsStep [(ctx LowerCtx) (bs (List rd/SExpr)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Lowers let bindings in order, threading the lowering context explicitly rather than through a closure."
  (if (>= idx len)
      acc
      (let [(b (option-or (list-get bs idx) (rd/sexprAtom "()")))]
        (lowerCLetBindingsStep ctx bs (+ idx 1) len (list-append acc (list (lowerCLetBinding ctx b)))))))

(df lowerCLetBodyStmtsStep [(ctx LowerCtx) (es (List rd/SExpr)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Lowers let body statements in order, threading the lowering context explicitly rather than through a closure."
  (if (>= idx len)
      acc
      (let [(e (option-or (list-get es idx) (rd/sexprAtom "()")))]
        (lowerCLetBodyStmtsStep ctx es (+ idx 1) len (list-append acc (list (lowerCLetBodyStmt ctx e)))))))

(df lowerCStrConcat [(ctx LowerCtx) (args (List rd/SExpr)) (idx Int64) (len Int64)] -> String
  :d "Right-nests the variadic str builtin into pairwise ISO C99 string concatenations, which needs no element type because str is variadic over String."
  (if (>= idx len)
      "((asl_string_t){ .data = \"\", .len = 0 })"
      (let [(here (lowerCExpr ctx (option-or (list-get args idx) (rd/sexprAtom "\"\""))))]
        (if (= idx (- len 1))
            here
            (str "string_concat2(" here ", " (lowerCStrConcat ctx args (+ idx 1) len) ")")))))

(df argCType [(ctx LowerCtx) (e rd/SExpr)] -> (Option String)
  :d "Resolves the emitted C type of an argument when it is a variable the enclosing signature declares; none otherwise, never a guess."
  (mt e
    ((rd/sexprAtom v) (ctxVarType ctx v))
    ((rd/sexprList _) (none))
    ((rd/sexprVect _) (none))))

(df typedAccessorCall [(ctx LowerCtx) (head String) (rawArgs (List rd/SExpr))] -> String
  :d "Emits the per-instantiation container accessor when the enclosing signature determines the container type, and the empty string when it does not so the caller keeps its existing lowering."
  (let [(bare (stripModulePrefix head))
        (a0 (option-or (list-get rawArgs 0) (rd/sexprAtom "()")))
        (retTy (.-retTy ctx))
        (tyOpt (argCType ctx a0))]
    (if (and (string-starts-with? retTy "AslResult_")
             (and (or (= bare "ok") (= bare "err")) (> (list-length rawArgs) 0)))
        (str "asl_" bare "_" retTy "(" (lowerCExpr ctx a0) ")")
    (mt tyOpt
      ((none) "")
      ((some cTy)
       (let [(isSlice (string-starts-with? cTy "AslSlice_"))
             (isOpt (string-starts-with? cTy "AslOption_"))
             (s0 (lowerCExpr ctx a0))]
         (cond
           ((and isSlice (= bare "list-get"))
            (str "asl_list_get_" cTy "(" s0 ", " (lowerCExpr ctx (option-or (list-get rawArgs 1) (rd/sexprAtom "0"))) ")"))
           ((and isSlice (= bare "list-head"))
            (str "asl_list_head_" cTy "(" s0 ")"))
           ((and isSlice (= bare "list-tail"))
            (str "asl_list_tail_" cTy "(" s0 ")"))
           ((and isOpt (= bare "option-or"))
            (str "asl_option_or_" cTy "(" s0 ", " (lowerCExpr ctx (option-or (list-get rawArgs 1) (rd/sexprAtom "()"))) ")"))
           (:else ""))))))))

(df lowerCCall [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers a call form, field access, or operator expression into ISO C99."
  (let [(head (nthAtom items 0))
        (rawArgs (sliceFrom1 items))]
    (cond
      ((string-starts-with? head ".-")
       (let [(field (sliceStrOr head 2 (string-length head) ""))
             (target (if (> (list-length rawArgs) 0)
                         (lowerCExpr ctx (option-or (list-get rawArgs 0) (rd/sexprAtom "()")))
                         "()"))]
         (lowerCFieldAccess target field)))
      ((= head "not")
       (let [(arg (if (> (list-length rawArgs) 0)
                      (lowerCExpr ctx (option-or (list-get rawArgs 0) (rd/sexprAtom "false")))
                      "false"))]
         (str "(!(" arg "))")))
      ((= head "str")
       (lowerCStrConcat ctx rawArgs 0 (list-length rawArgs)))
      ((isBinaryOp? head)
       (let [(argCount (list-length rawArgs))
             (cOp (opToC head))]
         (cond
           ((= argCount 1)
            (let [(a0 (lowerCExpr ctx (option-or (list-get rawArgs 0) (rd/sexprAtom "0LL"))))]
              (str "(-(" a0 "))")))
           ((>= argCount 2)
            (let [(raw0 (option-or (list-get rawArgs 0) (rd/sexprAtom "0LL")))
                  (raw1 (option-or (list-get rawArgs 1) (rd/sexprAtom "0LL")))
                  (firstArg (lowerCExpr ctx raw0))
                  (secondArg (lowerCExpr ctx raw1))
                  (isStr (or (string-contains? firstArg "asl_string_")
                             (or (string-contains? secondArg "asl_string_")
                                 (or (isStringExpr? raw0)
                                     (isStringExpr? raw1)))))]
              (if (and isStr (or (= head "=") (= head "!=")))
                  (if (= head "=")
                      (str "asl_string_eq(" firstArg ", " secondArg ")")
                      (str "(!asl_string_eq(" firstArg ", " secondArg "))"))
                  (let [(restArgs (sliceFrom1 rawArgs))]
                    (foldBinaryOpStep ctx cOp restArgs 0 (list-length restArgs) firstArg)))))
           (:else ""))))
      ((and (> (string-length head) 0) (string-starts-with? head ":"))
       (lowerCRecordInit ctx items))
      ((and (> (string-length (stripModulePrefix head)) 0)
            (let [(c0 (sliceStrOr (stripModulePrefix head) 0 1 ""))]
              (and (>= c0 "A") (<= c0 "Z")))
            (> (list-length items) 1)
            (string-starts-with? (nthAtom items 1) ":"))
       (lowerCRecordInit ctx items))
      ((and (= (stripModulePrefix head) "ok")
            (or (<= (list-length rawArgs) 0)
                (or (= (nthAtom rawArgs 0) "()")
                    (isUnitExpr? (option-or (list-get rawArgs 0) (rd/sexprAtom ""))))))
       (if (and (> (string-length (.-retTy ctx)) 0) (string-starts-with? (.-retTy ctx) "AslResult_"))
           (str "asl_ok_" (.-retTy ctx) "()")
           "okUnit()"))
      ((not (= "" (typedAccessorCall ctx head rawArgs)))
       (typedAccessorCall ctx head rawArgs))
      (:else
       (let [(fnName (mangleCIdent (stripModulePrefix head)))
             (rawArgStrs (lowerCExprsStep ctx rawArgs 0 (list-length rawArgs) (list)))
             (args (map protectMacroArg rawArgStrs))]
         (str fnName "(" (string-join args ", ") ")"))))))

(df lowerCDo [(ctx LowerCtx) (items (List rd/SExpr))] -> String
  :d "Lowers a sequential do block into a C comma expression."
  (let [(stmts (sliceFrom1 items))
        (stmtCount (list-length stmts))]
    (cond
      ((<= stmtCount 0) "(void)0")
      ((= stmtCount 1)
       (lowerCExpr ctx (option-or (list-get stmts 0) (rd/sexprAtom "()"))))
      (:else
       (let [(exprs (lowerCExprsStep ctx stmts 0 (list-length stmts) (list)))]
         (str "(" (string-join exprs ", ") ")"))))))

(df lowerCExpr [(ctx LowerCtx) (e rd/SExpr)] -> String
  :d "Lowers an arbitrary ASL S-expression into an ISO C99 expression."
  (mt e
    ((rd/sexprAtom v)
     (mt (ctxSubst ctx v)
       ((some cExpr) cExpr)
       ((none) (lowerCAtom v))))
    ((rd/sexprVect items)
     (str "{" (string-join (lowerCExprsStep ctx items 0 (list-length items) (list)) ", ") "}"))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         "(void)0"
         (let [(head (nthAtom items 0))]
           (cond
             ((= head "fn") "(void*)0")
             ((= head "let") (lowerCLet ctx items))
             ((= head "if") (lowerCIf ctx items))
             ((= head "cond") (lowerCCond ctx items))
             ((or (= head "match") (= head "mt")) (lowerCMatch ctx items))
             ((= head "do") (lowerCDo ctx items))
             (:else (lowerCCall ctx items))))))))
