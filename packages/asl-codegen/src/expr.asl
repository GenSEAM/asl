(module asl-codegen/expr
  :d "Expression and pattern lowering to Rust expressions."
  :x [emitExpr
      emitAtom
      emitPattern
      emitBodySeq
      isIdent?
      cloneIfIdent
      resolveQualifiedCase
      sliceStrOr]
  :i [(reader :a rd) (mangle :a m) (builtins :a b) (rtypes :a cgTy)])

(df sliceStrOr [(s String) (start Int64) (end Int64) (fallback String)] -> String
  :d "Safe string slice."
  (option-or (string-slice s start end) fallback))

(df isIdent? [(s String)] -> Bool
  :d "True if string represents a simple variable identifier suitable for cloning."
  (let [(sLen (string-length s))]
    (if (<= sLen 0)
        false
        (let [(c0 (sliceStrOr s 0 1 ""))]
          (and (not (string-contains? s " "))
               (and (not (string-contains? s "("))
                    (and (not (string-contains? s "{"))
                         (and (not (string-contains? s "["))
                              (and (not (string-contains? s "\""))
                                   (and (not (string-contains? s "."))
                                        (and (not (string-contains? s "::"))
                                             (or (and (>= c0 "a") (<= c0 "z"))
                                                 (or (and (>= c0 "A") (<= c0 "Z"))
                                                     (= c0 "_"))))))))))))))

(df cloneIfIdent [(s String)] -> String
  :d "Appends .clone() if string is a bare identifier."
  (if (isIdent? s)
      (str s ".clone()")
      s))

(df caseCall [(tgt String) (args (List String))] -> String
  :d "Formats an enum constructor or unit variant."
  (if (> (list-length args) 0)
      (str tgt "(" (string-join args ", ") ")")
      tgt))

(df formatCall [(fnName String) (args (List String))] -> String
  :d "Formats a function call with comma-separated arguments."
  (str fnName "(" (string-join args ", ") ")"))

(df escapeRawString [(s String)] -> String
  :d "Escapes raw control characters in string literals."
  (let [(s1 (string-replace s "\n" "\\n"))
        (s2 (string-replace s1 "\r" "\\r"))
        (s3 (string-replace s2 "\t" "\\t"))]
    s3))

(df resolveEnumAlias [(v String) (aliases (Map String String))] -> String
  :d "Resolves an enum variant alias if present or returns mangled identifier."
  (mt (map-get aliases v)
    ((some tgt)
     (if (or (string-starts-with? tgt "crate::")
             (string-contains? tgt "::"))
         tgt
         (m/mangleIdent v)))
    ((none) (m/mangleIdent v))))

(df emitAtom [(s String) (aliases (Map String String))] -> String
  :d "Emits a terminal atom into a Rust expression."
  (cond
    ((= s "true") "true")
    ((= s "false") "false")
    ((or (= s "nil") (= s "()")) "()")
    ((string-starts-with? s "\"")
     (str (escapeRawString s) ".to_string()"))
    ((and (string-starts-with? s "-") (> (string-length s) 1))
     (str "(" s ")"))
    ((string-contains? s "/")
     (let [(parts (string-split s "/"))
           (alias (option-or (list-get parts 0) ""))
           (member (option-or (list-get parts 1) ""))
           (modOpt (map-get aliases alias))]
       (mt modOpt
         ((some mpath)
          (let [(enumOpt (map-get aliases (str mpath "/" member)))]
            (mt enumOpt
              ((some tgt) tgt)
              ((none) (str "crate::" (m/rustModName mpath) "::" (m/mangleIdent member))))))
         ((none)
          (let [(enumOpt (map-get aliases s))]
            (mt enumOpt
              ((some tgt) tgt)
              ((none) (str (m/mangleIdent alias) "::" (m/mangleIdent member)))))))))
    ((= s "none") "None")
    ((= s "ok") "Ok")
    ((= s "err") "Err")
    ((= s "some") "Some")
    ((= s "not-found") "rt::IoError::NotFound")
    ((= s "permission-denied") "rt::IoError::PermissionDenied")
    ((= s "already-exists") "rt::IoError::AlreadyExists")
    ((= s "invalid-path") "rt::IoError::InvalidPath")
    ((= s "interrupted") "rt::IoError::Interrupted")
    ((= s "other") "rt::IoError::Other")
    (:else (resolveEnumAlias s aliases))))

(df getAtomStr [(e rd/SExpr)] -> String
  :d "Extracts string value from an atom SExpr or returns empty."
  (mt e
    ((rd/sexprAtom v) v)
    ((rd/sexprList _) "")
    ((rd/sexprVect _) "")))

(df nthAtom [(items (List rd/SExpr)) (idx I64)] -> String
  :d "Extracts atom string from items at index or empty string."
  (getAtomStr (option-or (list-get items idx) (rd/sexprAtom ""))))

(df sliceFrom1 [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Slices items starting from index 1."
  (if (> (list-length items) 1)
      (option-or (list-slice items 1 (list-length items)) (list))
      (list)))

(df sliceTail [(items (List rd/SExpr)) (start I64)] -> (List rd/SExpr)
  :d "Slices list from start index or returns empty list."
  (if (> (list-length items) start)
      (option-or (list-slice items start (list-length items)) (list))
      (list)))

(df emitFnParam [(p rd/SExpr)] -> String
  :d "Emits closure parameter name."
  (mt p
    ((rd/sexprVect pItems) (m/mangleIdent (nthAtom pItems 0)))
    ((rd/sexprList pItems) (m/mangleIdent (nthAtom pItems 0)))
    ((rd/sexprAtom v) (m/mangleIdent v))))

(df resolveQualifiedCase [(head String) (aliases (Map String String))] -> String
  :d "Resolves an enum case constructor head to its Rust target path."
  (if (string-contains? head "/")
      (let [(parts (string-split head "/"))
            (alias (option-or (list-get parts 0) ""))
            (member (option-or (list-get parts 1) ""))
            (modOpt (map-get aliases alias))]
        (mt modOpt
          ((some mpath)
           (let [(enumOpt (map-get aliases (str mpath "/" member)))]
             (mt enumOpt
               ((some tgt) tgt)
               ((none) (str "crate::" (m/rustModName mpath) "::" (m/pascalIdent member))))))
          ((none)
           (let [(enumOpt (map-get aliases head))]
             (mt enumOpt
               ((some tgt) tgt)
               ((none) (str (m/mangleIdent alias) "::" (m/pascalIdent member))))))))
      (mt (map-get aliases head)
        ((some tgt) tgt)
        ((none) (m/pascalIdent head)))))

(df nthPattern [(items (List rd/SExpr)) (idx I64) (aliases (Map String String))] -> String
  :d "Extracts and lowers pattern at index."
  (emitPattern (option-or (list-get items idx) (rd/sexprAtom "_")) aliases))

(df emitPattern [(p rd/SExpr) (aliases (Map String String))] -> String
  :d "Lowers a match pattern to Rust match syntax."
  (mt p
    ((rd/sexprAtom v)
     (cond
       ((= v "_") "_")
       ((= v "none") "None")
       ((= v "true") "true")
       ((= v "false") "false")
       ((string-starts-with? v "\"") (escapeRawString v))
       (:else (resolveEnumAlias v aliases))))
    ((rd/sexprVect items)
     (if (<= (list-length items) 0)
         "[]"
         (str "[" (string-join (map (fn [(it rd/SExpr)] -> String (emitPattern it aliases)) items) ", ") "]")))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         "()"
         (let [(head (nthAtom items 0))]
           (cond
             ((= head "ok") (str "Ok(" (nthPattern items 1 aliases) ")"))
             ((= head "err") (str "Err(" (nthPattern items 1 aliases) ")"))
             ((= head "some") (str "Some(" (nthPattern items 1 aliases) ")"))
             ((= head "none") "None")
             ((= head "pair") (str "(" (nthPattern items 1 aliases) ", " (nthPattern items 2 aliases) ")"))
             ((= head "list") "[]")
             ((= head "cons") (str "[" (nthPattern items 1 aliases) ", " (nthPattern items 2 aliases) " @ ..]"))
             (:else
              (let [(pHead (resolveQualifiedCase head aliases))
                    (rest (if (> (list-length items) 1)
                              (list-tail items)
                              (none)))]
                (mt rest
                  ((none) pHead)
                  ((some rItems)
                   (if (<= (list-length rItems) 0)
                       pHead
                       (str pHead "(" (string-join (map (fn [(it rd/SExpr)] -> String (emitPattern it aliases)) rItems) ", ") ")"))))))))))))

(df emitBodySeq [(body (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Emits a sequence of body expressions."
  (let [(bodyLen (list-length body))]
    (if (<= bodyLen 0)
        "()"
        (if (= bodyLen 1)
            (emitExpr (option-or (list-get body 0) (rd/sexprAtom "()")) aliases)
            (let [(stmts (map (fn [(e rd/SExpr)] -> String
                                (str (emitExpr e aliases) "; "))
                              body))
                  (lastIdx (- bodyLen 1))
                  (lastExpr (emitExpr (option-or (list-get body lastIdx) (rd/sexprAtom "()")) aliases))
                  (priorStmts (list-slice stmts 0 lastIdx))]
              (mt priorStmts
                ((some ps) (str (string-join ps "") lastExpr))
                ((none) lastExpr)))))))

(df emitLet [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a let form to Rust block expression."
  (let [(bindingsNode (option-or (list-get items 1) (rd/sexprVect (list))))
        (body (sliceTail items 2))
        (bindList (rd/sexprToList bindingsNode))
        (letStmts (map (fn [(b rd/SExpr)] -> String
                          (let [(pair (rd/sexprToList b))]
                            (if (>= (list-length pair) 2)
                                (let [(bName (m/mangleIdent (nthAtom pair 0)))
                                      (bVal (cloneIfIdent (emitExpr (option-or (list-get pair 1) (rd/sexprAtom "()")) aliases)))]
                                  (str "let " bName " = " bVal "; "))
                                "")))
                        bindList))
        (bodyStr (emitBodySeq body aliases))]
    (str "{ " (string-join letStmts "") bodyStr " }")))

(df emitIf [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers an if form to Rust if-else expression."
  (let [(c (emitExpr (option-or (list-get items 1) (rd/sexprAtom "false")) aliases))
        (th (emitExpr (option-or (list-get items 2) (rd/sexprAtom "()")) aliases))
        (el (emitExpr (option-or (list-get items 3) (rd/sexprAtom "()")) aliases))]
    (str "if " c " { " th " } else { " el " }")))

(df emitCondClause [(c rd/SExpr) (isFirst Bool) (aliases (Map String String))] -> String
  :d "Emits a single cond clause."
  (mt c
    ((rd/sexprList cItems)
     (let [(head (nthAtom cItems 0))
           (bodyTail (sliceFrom1 cItems))]
       (if (or (= head ":else") (= head "else"))
           (str "} else { " (emitBodySeq bodyTail aliases) " }")
           (let [(condExpr (emitExpr (option-or (list-get cItems 0) (rd/sexprAtom "false")) aliases))
                 (prefix (if isFirst "if " "} else if "))]
             (str prefix condExpr " { " (emitBodySeq bodyTail aliases) " ")))))
    ((rd/sexprVect cItems)
     (emitCondClause (rd/sexprList cItems) isFirst aliases))
    ((rd/sexprAtom _) "")))

(df emitCond [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a cond form to Rust if-else if-else expression."
  (let [(clauses (sliceFrom1 items))]
    (if (<= (list-length clauses) 0)
        "()"
        (let [(c0 (emitCondClause (option-or (list-get clauses 0) (rd/sexprAtom "")) true aliases))
              (restClauses (sliceFrom1 clauses))
              (restParts (map (fn [(c rd/SExpr)] -> String
                                 (emitCondClause c false aliases))
                               restClauses))]
          (str c0 (string-join restParts " "))))))

(df isListArm? [(arm rd/SExpr)] -> Bool
  :d "True if arm pattern is a list or cons pattern."
  (mt arm
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         false
         (let [(pat (option-or (list-get items 0) (rd/sexprAtom "")))]
           (mt pat
             ((rd/sexprVect _) true)
             ((rd/sexprList pItems)
              (let [(pHead (nthAtom pItems 0))]
                (or (= pHead "list") (= pHead "cons"))))
             (_ false)))))
    (_ false)))

(df isStringArm? [(arm rd/SExpr)] -> Bool
  :d "True if arm pattern matches against a string literal."
  (mt arm
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         false
         (let [(pat (option-or (list-get items 0) (rd/sexprAtom "")))]
           (mt pat
             ((rd/sexprAtom v) (string-starts-with? v "\""))
             (_ false)))))
    (_ false)))

(df emitMatch [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a match or mt form to Rust match expression."
  (let [(subj (emitExpr (option-or (list-get items 1) (rd/sexprAtom "()")) aliases))
        (arms (sliceTail items 2))
        (isSlice (cgTy/anyTrue? (map isListArm? arms)))
        (isStr (cgTy/anyTrue? (map isStringArm? arms)))
        (subjBase (if (isIdent? subj) (str subj ".clone()") subj))
        (subjArg (cond
                    (isSlice (str subjBase ".as_slice()"))
                    (isStr (str subjBase ".as_str()"))
                    (:else subjBase)))
        (armStrs (map (fn [(arm rd/SExpr)] -> String
                         (mt arm
                           ((rd/sexprList aItems)
                            (let [(patNode (option-or (list-get aItems 0) (rd/sexprAtom "_")))
                                  (patStr (emitPattern patNode aliases))
                                  (body (sliceFrom1 aItems))
                                  (bodyStr (emitBodySeq body aliases))
                                  (isCons? (mt patNode
                                              ((rd/sexprList pItems) (= (nthAtom pItems 0) "cons"))
                                              (_ false)))]
                              (if isCons?
                                  (let [(pItems (mt patNode ((rd/sexprList pi) pi) (_ (list))))
                                        (hName (m/mangleIdent (nthAtom pItems 1)))
                                        (tName (m/mangleIdent (nthAtom pItems 2)))]
                                    (str patStr " => { let " hName " = " hName ".clone(); let " tName " = " tName ".to_vec(); " bodyStr " },"))
                                  (str patStr " => { " bodyStr " },"))))
                           ((rd/sexprVect aItems)
                            (emitMatch (list (rd/sexprAtom "mt") (option-or (list-get items 1) (rd/sexprAtom "()")) arm) aliases))
                           ((rd/sexprAtom _) "")))
                       arms))
        (unreach (if isSlice " _ => unreachable!()," ""))]
    (str "match " subjArg " { " (string-join armStrs " ") unreach " }")))

(df emitTry [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a try form to Rust ? propagation."
  (let [(inner (emitExpr (option-or (list-get items 1) (rd/sexprAtom "()")) aliases))]
    (str "(" inner ")?")))

(df emitFn [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers an anonymous lambda fn to Rust closure."
  (let [(hasBang? (and (> (list-length items) 1)
                        (= (nthAtom items 1) "!")))
        (pIdx (if hasBang? 2 1))
        (bIdx (if hasBang? 3 2))
        (paramsNode (option-or (list-get items pIdx) (rd/sexprVect (list))))
        (pList (rd/sexprToList paramsNode))
        (pStrs (map emitFnParam pList))
        (body (if (> (list-length items) bIdx)
                  (let [(tail (sliceTail items bIdx))
                        (firstHead (nthAtom tail 0))]
                    (if (and (= firstHead "->") (> (list-length tail) 2))
                        (sliceTail tail 2)
                        tail))
                  (list)))
        (bodyStr (emitBodySeq body aliases))]
    (str "|" (string-join pStrs ", ") "| { " bodyStr " }")))

(df emitRecordInit [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Emits struct constructor initialization: (Record :f1 v1 :f2 v2 ...)."
  (let [(recName (nthAtom items 0))
        (cleanRec (if (string-contains? recName "/")
                       (let [(parts (string-split recName "/"))
                             (alias (option-or (list-get parts 0) ""))
                             (member (option-or (list-get parts 1) ""))
                             (modOpt (map-get aliases alias))]
                         (mt modOpt
                           ((some mpath) (str "crate::" (m/rustModName mpath) "::" (m/pascalIdent member)))
                           ((none) (str (m/mangleIdent alias) "::" (m/pascalIdent member)))))
                       (m/pascalIdent recName)))
        (itemsLen (list-length items))]
    (let [(inits (range 0 (/ (- itemsLen 1) 2)))
          (fieldStrs (map (fn [(idx Int64)] -> String
                             (let [(kPos (+ 1 (* idx 2)))
                                   (vPos (+ 2 (* idx 2)))
                                   (kAtom (nthAtom items kPos))
                                   (kClean (if (string-starts-with? kAtom ":")
                                                (sliceStrOr kAtom 1 (string-length kAtom) kAtom)
                                                kAtom))
                                   (vNode (option-or (list-get items vPos) (rd/sexprAtom "()")))
                                   (vVal (emitExpr vNode aliases))
                                   (vCloned (cloneIfIdent vVal))]
                               (str (m/mangleIdent kClean) ": " vCloned)))
                           inits))]
      (str cleanRec " { " (string-join fieldStrs ", ") " }"))))

(df isPascalHead? [(head String)] -> Bool
  :d "True if head appears to be a PascalCase record or case constructor."
  (if (< (string-length head) 1)
      false
      (let [(member (if (string-contains? head "/")
                        (let [(parts (string-split head "/"))]
                          (option-or (list-get parts 1) head))
                        head))
            (c0 (sliceStrOr member 0 1 ""))]
        (and (= (string-upper c0) c0)
             (not (= c0 "_"))))))

(df emitCall [(items (List rd/SExpr)) (aliases (Map String String))] -> String
  :d "Lowers a general call form or builtin."
  (let [(head (nthAtom items 0))
        (rawArgs (sliceFrom1 items))
        (args (map (fn [(a rd/SExpr)] -> String
                     (cloneIfIdent (emitExpr a aliases)))
                   rawArgs))]
    (cond
      ((string-starts-with? head ".-")
       (let [(field (sliceStrOr head 2 (string-length head) ""))
             (target (option-or (list-get args 0) "()"))]
         (cond
           ((= field "first") (str target ".0.clone()"))
           ((= field "second") (str target ".1.clone()"))
           (:else (str target "." (m/mangleIdent field) ".clone()")))))
      ((is-some? (b/builtinTemplate head))
       (option-or (b/renderBuiltin head args) ""))
      ((and (>= (string-length head) 2)
            (string-starts-with? head ":"))
       (emitRecordInit items aliases))
      ((isPascalHead? head)
       (if (and (> (list-length items) 1)
                (string-starts-with? (nthAtom items 1) ":"))
           (emitRecordInit items aliases)
           (caseCall (resolveQualifiedCase head aliases) args)))
      ((string-contains? head "/")
       (let [(parts (string-split head "/"))
             (alias (option-or (list-get parts 0) ""))
             (member (option-or (list-get parts 1) ""))
             (modOpt (map-get aliases alias))]
         (mt modOpt
           ((some mpath)
            (let [(enumOpt (map-get aliases (str mpath "/" member)))]
              (mt enumOpt
                ((some tgt) (caseCall tgt args))
                ((none) (formatCall (str "crate::" (m/rustModName mpath) "::" (m/mangleIdent member)) args)))))
           ((none)
            (let [(enumOpt (map-get aliases head))]
              (mt enumOpt
                ((some tgt) (caseCall tgt args))
                ((none) (formatCall (str (m/mangleIdent alias) "::" (m/mangleIdent member)) args))))))))
      (:else
       (let [(enumOpt (map-get aliases head))]
         (mt enumOpt
           ((some tgt) (caseCall tgt args))
           ((none) (formatCall (emitAtom head aliases) args))))))))

(df emitExpr [(e rd/SExpr) (aliases (Map String String))] -> String
  :d "Lowers an arbitrary ASL S-Expression into a Rust expression."
  (mt e
    ((rd/sexprAtom v) (emitAtom v aliases))
    ((rd/sexprVect items)
     (str "vec![" (string-join (map (fn [(it rd/SExpr)] -> String (emitExpr it aliases)) items) ", ") "]"))
    ((rd/sexprList items)
     (if (<= (list-length items) 0)
         "()"
         (let [(head (nthAtom items 0))]
           (cond
             ((= head "let") (emitLet items aliases))
             ((= head "if") (emitIf items aliases))
             ((= head "cond") (emitCond items aliases))
             ((or (= head "match") (= head "mt")) (emitMatch items aliases))
             ((= head "try") (emitTry items aliases))
             ((= head "fn") (emitFn items aliases))
             (:else (emitCall items aliases))))))))
