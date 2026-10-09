(module asl-port/translate
  :x [translateModule translateFn formatDraftFile formatPortGap PortGap FnDraft FileDraft]
  :i [(asl-json/json :a json) (asl-port/astUtil :a u)])

(schema PortGap
  (:f construct String)
  (:f line Int64)
  (:f fnName String)
  (:f file String))

(schema FnDraft
  (:f name String)
  (:f params (List String))
  (:f body String)
  (:f isGap Bool)
  (:f gap (Option PortGap)))

(schema FileDraft
  (:f file String)
  (:f functions (List FnDraft))
  (:f gaps (List PortGap)))

fn quoteStr s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\"")

fn supportedType? t: String -> Bool
  (listContains?
    (list "Module" "FunctionDef" "arguments" "arg" "Return" "Assign" "If" "For" "Try"
          "ExceptHandler" "Pass" "Expr" "Constant" "Name" "BinOp" "UnaryOp"
          "Compare" "BoolOp" "Call" "Attribute" "JoinedStr" "FormattedValue"
          "List" "Dict" "Load" "Store" "Add" "Sub" "Mult" "Div" "FloorDiv" "Mod"
          "USub" "Not" "Eq" "NotEq" "Lt" "LtE" "Gt" "GtE" "And" "Or")
    t)

fn findFirstGapInList xs: (List json/Json) fnName: String file: String -> (Option PortGap)
  (mt (listHead xs)
    ((some x)
      (let [(g (if (or (u/isType? x "FunctionDef") (u/isType? x "ClassDef")) (some (PortGap :construct (u/getType x) :line (u/getLineno x) :fnName fnName :file file)) (findFirstGap x fnName file)))]
        (mt g
          ((some _) g)
          ((none) (findFirstGapInList (optionOr (listTail xs) (list)) fnName file)))))
    ((none) (none)))

fn findFirstGapInPairs ps: (List (Pair String json/Json)) fnName: String file: String -> (Option PortGap)
  (mt (listHead ps)
    ((some p)
      (let [(v (pairSecond p))
            (g (if (and (= (pairFirst p) "func") (u/isType? v "Attribute")) (mt (u/getObjProp v "value") ((some value) (findFirstGap value fnName file)) ((none) (none))) (findFirstGap v fnName file)))]
        (mt g
          ((some _) g)
          ((none) (findFirstGapInPairs (optionOr (listTail ps) (list)) fnName file)))))
    ((none) (none)))

fn findFirstLoopBodyGap stmts: (List json/Json) fnName: String file: String -> (Option PortGap)
  (mt (listHead stmts)
    ((some stmt)
      (if (u/isType? stmt "Assign")
        (findFirstLoopBodyGap (optionOr (listTail stmts) (list)) fnName file)
        (if (u/isType? stmt "Expr")
          (mt (u/getObjProp stmt "value")
            ((some value)
              (mt (findFirstGap value fnName file)
                ((some gap) (some gap))
                ((none) (some (PortGap :construct "Expr" :line (u/getLineno stmt) :fnName fnName :file file)))))
            ((none) (some (PortGap :construct "Expr" :line (u/getLineno stmt) :fnName fnName :file file))))
          (some (PortGap :construct (u/getType stmt) :line (u/getLineno stmt) :fnName fnName :file file)))))
    ((none) (none)))

fn findUnanchoredLoopGap stmts: (List json/Json) previousAssign: Bool fnName: String file: String -> (Option PortGap)
  (mt (listHead stmts)
    ((some stmt)
      (if (and (u/isType? stmt "For") (not previousAssign))
        (some (PortGap :construct "For" :line (u/getLineno stmt) :fnName fnName :file file))
        (findUnanchoredLoopGap (optionOr (listTail stmts) (list)) (u/isType? stmt "Assign") fnName file)))
    ((none) (none)))

fn unsafeIf? node: json/Json -> Bool
  (and (listEmpty? (u/getListProp node "orelse"))
       (mt (listHead (u/getListProp node "body")) ((some b) (u/isType? b "Assign")) ((none) false)))

fn supportedTry? node: json/Json -> Bool
  (let [(handlers (u/getListProp node "handlers"))
        (handler (mt (listHead handlers) ((some h) h) ((none) (json/jnull))))
        (body (u/getListProp node "body"))
        (firstBody (mt (listHead body) ((some b) b) ((none) (json/jnull))))
        (value (mt (u/getObjProp firstBody "value") ((some v) v) ((none) (json/jnull))))
        (opType (mt (u/getObjProp value "op") ((some op) (u/getType op)) ((none) "")))]
    (and (= (listLength handlers) 1)
      (and (mt (u/getObjProp handler "type") ((some t) (= (u/getStringProp t "id") "Exception")) ((none) true))
        (and (u/isType? firstBody "Return")
          (and (u/isType? value "BinOp")
            (or (or (= opType "Div") (= opType "FloorDiv")) (= opType "Mod")))))))

fn unsupportedSemantic? node: json/Json -> Bool
  (let [(t (u/getType node))]
    (cond
      ((= t "Constant") (mt (u/getObjProp node "value") ((some value) (mt value ((json/jfloat _) true) ((json/jnum _) true) (_ false))) ((none) false)))
      ((= t "Compare") (> (listLength (u/getListProp node "ops")) 1))
      ((= t "BinOp") (mt (u/getObjProp node "op") ((some op) (= (u/getType op) "Div")) ((none) false)))
      ((= t "If") (unsafeIf? node))
      ((= t "Try") (not (supportedTry? node)))
      (else false)))

fn findFirstGap node: json/Json fnName: String file: String -> (Option PortGap)
  (let [(t (u/getType node))]
    (if (or (and (not (stringEmpty? t)) (not (supportedType? t))) (unsupportedSemantic? node) (= t "Attribute"))
      (some (PortGap :construct t :line (u/getLineno node) :fnName fnName :file file))
      (if (= t "For")
        (mt (findFirstLoopBodyGap (u/getListProp node "body") fnName file)
          ((some gap) (if (= gap.construct "Expr") (some (PortGap :construct "For" :line (u/getLineno node) :fnName fnName :file file)) (some gap)))
          ((none)
            (mt node
              ((json/jobj pairs) (findFirstGapInPairs pairs fnName file))
              ((json/jarr xs) (findFirstGapInList xs fnName file))
              (_ (none)))))
        (mt node
          ((json/jobj pairs) (findFirstGapInPairs pairs fnName file))
          ((json/jarr xs) (findFirstGapInList xs fnName file))
          (_ (none))))))

fn getFnParams node: json/Json -> (List String)
  (mt (u/getObjProp node "args")
    ((some a) (map (fn [(arg json/Json)] -> String (u/getStringProp arg "arg")) (u/getListProp a "args")))
    ((none) (list)))

fn binOpSymbol opType: String -> String
  (cond
    ((= opType "Add") "+")
    ((= opType "Sub") "-")
    ((= opType "Mult") "*")
    ((= opType "Div") "/")
    ((= opType "FloorDiv") "/")
    ((= opType "Mod") "mod")
    (else "+"))

fn cmpOpSymbol opType: String -> String
  (cond
    ((= opType "Eq") "=")
    ((= opType "NotEq") "!=")
    ((= opType "Lt") "<")
    ((= opType "LtE") "<=")
    ((= opType "Gt") ">")
    ((= opType "GtE") ">=")
    (else "="))

fn translateConstant node: json/Json -> String
  (mt (json/jsonGet node "value")
    ((some v)
      (mt v
        ((json/jstr s) (quoteStr s))
        ((json/jint i) (stringFromInt64 i))
        ((json/jbool b) (if b "true" "false"))
        ((json/jnull) "()")
        (_ "")))
    ((none) "()"))

fn translateJoinedStrPart part: json/Json -> String
  (if (u/isType? part "FormattedValue")
    (mt (u/getObjProp part "value")
      ((some v) (translateExpr v))
      ((none) "()"))
    (translateExpr part))

fn translateCall funcNode: json/Json args: (List json/Json) -> String
  (if (u/isType? funcNode "Attribute")
    (let [(objOpt (u/getObjProp funcNode "value"))
          (attr (u/getStringProp funcNode "attr"))
          (objStr (mt objOpt ((some o) (translateExpr o)) ((none) "()")))]
      (cond
        ((= attr "strip") (str "(stringTrim " objStr ")"))
        ((= attr "startswith")
          (let [(argStr (mt (listHead args) ((some a) (translateExpr a)) ((none) "")))]
            (str "(stringStartsWith? " objStr " " argStr ")")))
        ((= attr "replace")
          (let [(a0 (mt (listGet args 0) ((some a) (translateExpr a)) ((none) "")))
                (a1 (mt (listGet args 1) ((some a) (translateExpr a)) ((none) "")))]
            (str "(stringReplace " objStr " " a0 " " a1 ")")))
        ((= attr "split")
          (let [(argStr (mt (listHead args) ((some a) (translateExpr a)) ((none) "")))]
            (str "(stringSplit " objStr " " argStr ")")))
        ((= attr "join")
          (let [(listArg (mt (listHead args) ((some a) (translateExpr a)) ((none) "(list)")))]
            (str "(stringJoin " listArg " " objStr ")")))
        (else
          (let [(argStrs (map translateExpr args))]
            (if (listEmpty? argStrs)
              (str "(" attr " " objStr ")")
              (str "(" attr " " objStr " " (stringJoin argStrs " ") ")"))))))
    (let [(fnId (if (u/isType? funcNode "Name") (u/getStringProp funcNode "id") ""))]
      (cond
        ((= fnId "range")
          (if (= (listLength args) 1)
            (str "(range 0 " (translateExpr (optionOr (listHead args) (json/jnull))) ")")
            (str "(range " (translateExpr (optionOr (listGet args 0) (json/jnull))) " "
                           (translateExpr (optionOr (listGet args 1) (json/jnull))) ")")))
        ((= fnId "len")
          (str "(listLength " (translateExpr (optionOr (listHead args) (json/jnull))) ")"))
        (else
          (let [(argStrs (map translateExpr args))]
            (if (listEmpty? argStrs)
              (str "(" fnId ")")
              (str "(" fnId " " (stringJoin argStrs " ") ")")))))))

fn translateDictPair key: json/Json val: json/Json -> String
  (str "(pair " (translateExpr key) " " (translateExpr val) ")")

fn translateDictKeysValues keys: (List json/Json) vals: (List json/Json) acc: (List String) -> (List String)
  (mt (listHead keys)
    ((some k)
      (let [(v (optionOr (listHead vals) (json/jnull)))
            (p (translateDictPair k v))
            (restKeys (optionOr (listTail keys) (list)))
            (restVals (optionOr (listTail vals) (list)))]
        (translateDictKeysValues restKeys restVals (listAppend acc (list p)))))
    ((none) acc))

fn translateExpr node: json/Json -> String
  (let [(t (u/getType node))]
    (cond
      ((= t "Constant") (translateConstant node))
      ((= t "Name")
        (let [(id (u/getStringProp node "id"))]
          (cond
            ((= id "True") "true")
            ((= id "False") "false")
            ((= id "None") "()")
            (else id))))
      ((= t "BinOp")
        (let [(leftStr (mt (u/getObjProp node "left") ((some l) (translateExpr l)) ((none) "0")))
              (opType (mt (u/getObjProp node "op") ((some o) (u/getType o)) ((none) "Add")))
              (rightStr (mt (u/getObjProp node "right") ((some r) (translateExpr r)) ((none) "0")))]
          (str "(" (binOpSymbol opType) " " leftStr " " rightStr ")")))
      ((= t "UnaryOp")
        (let [(opType (mt (u/getObjProp node "op") ((some o) (u/getType o)) ((none) "USub")))
              (operandStr (mt (u/getObjProp node "operand") ((some op) (translateExpr op)) ((none) "0")))]
          (if (= opType "Not")
            (str "(not " operandStr ")")
            (str "(- " operandStr ")"))))
      ((= t "Compare")
        (let [(leftStr (mt (u/getObjProp node "left") ((some l) (translateExpr l)) ((none) "0")))
              (ops (u/getListProp node "ops"))
              (comps (u/getListProp node "comparators"))
              (opType (mt (listHead ops) ((some o) (u/getType o)) ((none) "Eq")))
              (rightStr (mt (listHead comps) ((some c) (translateExpr c)) ((none) "0")))]
          (str "(" (cmpOpSymbol opType) " " leftStr " " rightStr ")")))
      ((= t "BoolOp")
        (let [(opType (mt (u/getObjProp node "op") ((some o) (u/getType o)) ((none) "And")))
              (sym (if (= opType "And") "and" "or"))
              (vals (map translateExpr (u/getListProp node "values")))]
          (str "(" sym " " (stringJoin vals " ") ")")))
      ((= t "List")
        (let [(elts (map translateExpr (u/getListProp node "elts")))]
          (if (listEmpty? elts)
            "(list)"
            (str "(list " (stringJoin elts " ") ")"))))
      ((= t "Dict")
        (let [(keys (u/getListProp node "keys"))
              (vals (u/getListProp node "values"))
              (pairs (translateDictKeysValues keys vals (list)))]
          (if (listEmpty? pairs)
            "(mapEmpty)"
            (str "(mapFromPairs (list " (stringJoin pairs " ") "))"))))
      ((= t "JoinedStr")
        (let [(parts (map translateJoinedStrPart (u/getListProp node "values")))]
          (str "(str " (stringJoin parts " ") ")")))
      ((= t "Call")
        (let [(funcOpt (u/getObjProp node "func"))
              (args (u/getListProp node "args"))]
          (mt funcOpt
            ((some f) (translateCall f args))
            ((none) "()"))))
      (else "()")))

fn translateLoopBody stmts: (List json/Json) accVar: String -> String
  (mt (listHead stmts)
    ((some s)
      (let [(rest (optionOr (listTail stmts) (list)))
            (t (u/getType s))]
        (cond
          ((= t "Assign")
            (let [(tgts (u/getListProp s "targets"))
                  (tgtName (mt (listHead tgts) ((some tgt) (u/getStringProp tgt "id")) ((none) "")))
                  (valStr (mt (u/getObjProp s "value") ((some v) (translateExpr v)) ((none) "0")))]
              (if (= tgtName accVar)
                (if (listEmpty? rest)
                  valStr
                  (str "(let [(" accVar " " valStr ")] " (translateLoopBody rest accVar) ")"))
                (str "(let [(" tgtName " " valStr ")] " (translateLoopBody rest accVar) ")"))))
          (else
            (if (listEmpty? rest)
              (translateExpr s)
              (translateLoopBody rest accVar))))))
    ((none) accVar))

fn translateTry stmt: json/Json indent: String -> String
  (let [(bodyStrs (u/getListProp stmt "body"))
        (handlers (u/getListProp stmt "handlers"))
        (h (mt (listHead handlers) ((some handler) handler) ((none) (json/jnull))))
        (hBody (u/getListProp h "body"))
        (hCode (translateStmts hBody (str indent "    ")))
        (firstBody (mt (listHead bodyStrs) ((some b) b) ((none) (json/jnull))))]
    (if (u/isType? firstBody "Return")
      (let [(retVal (mt (u/getObjProp firstBody "value") ((some v) v) ((none) (json/jnull))))]
        (if (u/isType? retVal "BinOp")
          (let [(opType (mt (u/getObjProp retVal "op") ((some o) (u/getType o)) ((none) "")))
                (leftStr (mt (u/getObjProp retVal "left") ((some l) (translateExpr l)) ((none) "0")))
                (rightStr (mt (u/getObjProp retVal "right") ((some r) (translateExpr r)) ((none) "0")))]
            (if (or (or (= opType "Div") (= opType "FloorDiv")) (= opType "Mod"))
              (str "(mt (if (= " rightStr " 0) (err \"ZeroDivisionError\") (ok (" (binOpSymbol opType) " " leftStr " " rightStr ")))
"
                   indent "  ((ok res) res)
"
                   indent "  ((err _) " hCode "))")
              (str "(mt (ok " (translateExpr retVal) ")
"
                   indent "  ((ok res) res)
"
                   indent "  ((err _) " hCode "))")))
          (str "(mt (ok " (translateExpr retVal) ")
"
               indent "  ((ok res) res)
"
               indent "  ((err _) " hCode "))")))
      (str "(mt (ok " (translateStmts bodyStrs (str indent "  ")) ")
"
           indent "  ((ok res) res)
"
           indent "  ((err _) " hCode "))")))

fn translateIfChain testStr: String thenCode: String elseStmts: (List json/Json) indent: String -> String
  (let [(firstElse (mt (listHead elseStmts) ((some e) e) ((none) (json/jnull))))]
    (if (u/isType? firstElse "If")
      (let [(elifTest (mt (u/getObjProp firstElse "test") ((some t) (translateExpr t)) ((none) "false")))
            (elifThen (translateStmts (u/getListProp firstElse "body") (str indent "    ")))
            (subElse (u/getListProp firstElse "orelse"))]
        (str "(cond
"
             indent "  (" testStr "
" indent "    " thenCode ")
"
             indent "  (" elifTest "
" indent "    " elifThen ")
"
             indent "  (else
" indent "    " (translateStmts subElse (str indent "    ")) "))"))
      (str "(cond
"
           indent "  (" testStr "
" indent "    " thenCode ")
"
           indent "  (else
" indent "    " (translateStmts elseStmts (str indent "    ")) "))")))

fn translateStmts stmts: (List json/Json) indent: String -> String
  (mt (listHead stmts)
    ((some head)
      (let [(tail (optionOr (listTail stmts) (list)))
            (t (u/getType head))]
        (cond
          ((= t "Return")
            (mt (u/getObjProp head "value")
              ((some v) (translateExpr v))
              ((none) "()")))
          ((= t "Assign")
            (let [(tgts (u/getListProp head "targets"))
                  (tgtName (mt (listHead tgts) ((some tgt) (u/getStringProp tgt "id")) ((none) "x")))
                  (valStr (mt (u/getObjProp head "value") ((some v) (translateExpr v)) ((none) "0")))]
              (mt (listHead tail)
                ((some nextStmt)
                  (if (u/isType? nextStmt "For")
                    (let [(forIter (mt (u/getObjProp nextStmt "iter") ((some it) (translateExpr it)) ((none) "(list)")))
                          (forTarget (mt (u/getObjProp nextStmt "target") ((some ft) (u/getStringProp ft "id")) ((none) "item")))
                          (forBody (u/getListProp nextStmt "body"))
                          (loopBodyCode (translateLoopBody forBody tgtName))
                          (foldExpr (str "(fold (fn [" tgtName " " forTarget "] " loopBodyCode ") " tgtName " " forIter ")"))
                          (afterFor (optionOr (listTail tail) (list)))]
                      (if (listEmpty? afterFor)
                        (str "(let [(" tgtName " " valStr ")]
" indent "  " foldExpr ")")
                        (str "(let [(" tgtName " " valStr ")]
"
                             indent "  (let [(" tgtName " " foldExpr ")]
"
                             indent "    " (translateStmts afterFor (str indent "    ")) "))")))
                    (str "(let [(" tgtName " " valStr ")]
"
                         indent "  " (translateStmts tail indent) ")")))
                ((none)
                  (str "(let [(" tgtName " " valStr ")] ())
")))))
          ((= t "If")
            (let [(testStr (mt (u/getObjProp head "test") ((some ts) (translateExpr ts)) ((none) "false")))
                  (thenStmts (u/getListProp head "body"))
                  (elseStmts (u/getListProp head "orelse"))
                  (thenCode (translateStmts thenStmts (str indent "    ")))]
              (if (listEmpty? elseStmts)
                (str "(cond
"
                     indent "  (" testStr "
" indent "    " thenCode ")
"
                     indent "  (else
" indent "    " (translateStmts tail (str indent "    ")) "))")
                (translateIfChain testStr thenCode elseStmts indent))))
          ((= t "Try")
            (translateTry head indent))
          ((= t "Pass")
            (if (listEmpty? tail) "()" (translateStmts tail indent)))
          ((= t "Expr")
            (let [(vStr (mt (u/getObjProp head "value") ((some v) (translateExpr v)) ((none) "()")))]
              (if (listEmpty? tail)
                vStr
                (str "(do " vStr " " (translateStmts tail indent) ")"))))
          (else "()"))))
    ((none) "()"))

fn translateFn fnNode: json/Json file: String -> FnDraft
  (let [(name (u/getStringProp fnNode "name"))
        (params (getFnParams fnNode))
        (bodyStmts (u/getListProp fnNode "body"))
        (firstGap (findFirstGap fnNode name file))
        (gapOpt (mt firstGap ((some _) firstGap) ((none) (findUnanchoredLoopGap bodyStmts false name file))))]
    (mt gapOpt
      ((some gap)
        (FnDraft :name name :params params :body "" :isGap true :gap (some gap)))
      ((none)
        (let [(bodyStmts (u/getListProp fnNode "body"))
              (bodyCode (translateStmts bodyStmts "  "))]
          (FnDraft :name name :params params :body bodyCode :isGap false :gap (none))))))

fn collectGaps drafts: (List FnDraft) acc: (List PortGap) -> (List PortGap)
  (mt (listHead drafts)
    ((some d)
      (let [(rest (optionOr (listTail drafts) (list)))]
        (mt d.gap
          ((some g) (collectGaps rest (listAppend acc (list g))))
          ((none) (collectGaps rest acc)))))
    ((none) acc))

fn filterSelectedFns allFnNodes: (List json/Json) selected: (List String) -> (List json/Json)
  (if (listEmpty? selected)
    allFnNodes
    (filter (fn [(f json/Json)] -> Bool (listContains? selected (u/getStringProp f "name"))) allFnNodes))

fn translateModule file: String moduleAst: json/Json selectedFns: (List String) -> FileDraft
  (let [(body (u/getListProp moduleAst "body"))
        (fnDefs (filter (fn [(s json/Json)] -> Bool (u/isType? s "FunctionDef")) body))
        (targetFns (filterSelectedFns fnDefs selectedFns))
        (drafts (map (fn [(f json/Json)] -> FnDraft (translateFn f file)) targetFns))
        (gaps (collectGaps drafts (list)))]
    (FileDraft :file file :functions drafts :gaps gaps))

fn formatFnDraft fd: FnDraft -> String
  (if fd.isGap
    ""
    (let [(pStr (if (listEmpty? fd.params) "" (str " " (stringJoin fd.params " "))))]
      (str "fn " fd.name pStr "
  " fd.body)))

fn formatPortGap pg: PortGap -> String
  (str "(:portGap :file " (quoteStr pg.file)
       " :fn " (quoteStr pg.fnName)
       " :construct " (quoteStr pg.construct)
       " :line " (stringFromInt64 pg.line) ")")

fn formatDraftFile modName: String drafts: (List FnDraft) gaps: (List PortGap) -> String
  (let [(validDrafts (filter (fn [(d FnDraft)] -> Bool (not d.isGap)) drafts))
        (exportNames (map (fn [(d FnDraft)] -> String d.name) validDrafts))
        (header (str "(module " modName " :x [" (stringJoin exportNames " ") "] :i [])"))
        (fnTexts (map formatFnDraft validDrafts))
        (gapTexts (map formatPortGap gaps))
        (sections (listAppend (list header) fnTexts))
        (allSections (listAppend sections gapTexts))]
    (stringJoin allSections "

"))
