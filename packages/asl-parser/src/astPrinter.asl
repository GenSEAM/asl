(module asl-parser/astPrinter :x [printAstModule printAstExpr printAstPattern printAstType printTopForm printAst] :i [(ast :a a) (astConverter :a cv) (reader :a rd) (indentPrinter :a ip)])

fn printAst expr: a/AstExpr -> String
  (printAstExpr expr 0)

fn indentPrefix level: Int64 -> String
  (stringRepeat "  " level)

fn formatFloat64 f: Float64 -> String
  (let [(s (stringFromFloat64 f))]
    (if (stringContains? s ".")
      s
      (let [(parts (stringSplit s "e"))]
        (if (= (listLength parts) 2)
          (str (optionOr (listGet parts 0) s) ".0e" (optionOr (listGet parts 1) ""))
          (if (or (= s "nan") (= s "inf") (= s "-inf"))
            s
            (str s ".0"))))))

fn printAstLit lit: a/AstLit -> String
  (mt lit ((a/litInt i) (stringFromInt64 i)) ((a/litFloat f) (formatFloat64 f)) ((a/litString s) (str "\"" s "\"")) ((a/litBool b) (if b "true" "false")) ((a/litUnit) "()"))

fn printFieldPattern f: (Pair String a/AstPattern) -> String
  (let [(k (pairFirst f)) (p (pairSecond f))] (mt p ((a/patVar v) (if (= v k) k (str k ": " v))) ((a/patWildcard) k) (_ (str k ": " (printAstPattern p)))))

fn printAstPattern pat: a/AstPattern -> String
  (mt pat ((a/patWildcard) "_") ((a/patVar name) name) ((a/patLit lit) (printAstLit lit)) ((a/patTuple elements) (str "[" (stringJoin (map (fn [(p a/AstPattern)] -> String (printAstPattern p)) elements) " ") "]")) ((a/patRecord fields) (str "{" (stringJoin (map (fn [(f (Pair String a/AstPattern))] -> String (printFieldPattern f)) fields) " ") "}")) ((a/patCtor name arg) (mt arg ((none) name) ((some a) (mt a ((a/patTuple elements) (if (listEmpty? elements) name (str name " " (stringJoin (map (fn [(p a/AstPattern)] -> String (printAstPattern p)) elements) " ")))) (_ (str name " " (printAstPattern a))))))))

fn printRecordFieldType f: (Pair String a/AstType) -> String
  (str (pairFirst f) ": " (printAstType (pairSecond f)))

fn printAstType t: a/AstType -> String
  (mt t ((a/typeNamed name) name) ((a/typeTuple elements) (str "[" (stringJoin (map (fn [(e a/AstType)] -> String (printAstType e)) elements) " ") "]")) ((a/typeRecord fields) (str "{" (stringJoin (map (fn [(f (Pair String a/AstType))] -> String (printRecordFieldType f)) fields) " ") "}")) ((a/typeFn paramTypes retType) (str "fn [" (stringJoin (map (fn [(p a/AstType)] -> String (printAstType p)) paramTypes) " ") "] -> " (printAstType retType))))

fn isBlockExpr? e: a/AstExpr -> Bool
  (mt e ((a/exprBlock _) true) ((a/exprLet _ _) true) ((a/exprMatch _ _) true) ((a/exprIf _ t el) (or (isBlockExpr? t) (isBlockExpr? el))) (_ false))

fn isMarkerCtorName? name: String -> Bool
  (or (= name ":empty-list") (or (= name ":empty-vect") (or (= name ":empty-paren") (or (= name ":flat") (or (= name ":nested-list") (= name ":vect"))))))

fn hasMarkerPattern? pat: a/AstPattern -> Bool
  (mt pat ((a/patCtor name _) (isMarkerCtorName? name)) (_ false))

fn isTypedBindingValue? val: a/AstExpr -> Bool
  (mt val ((a/exprCall func _) (mt func ((a/exprIdent name) (= name ":typed")) (_ false))) (_ false))

fn anyMarkerBinding? bindings: (List (Pair a/AstPattern a/AstExpr)) -> Bool
  (fold (fn [(acc Bool) (b (Pair a/AstPattern a/AstExpr))] -> Bool (or acc (or (hasMarkerPattern? (pairFirst b)) (isTypedBindingValue? (pairSecond b))))) false bindings)

fn simplePatVarOrWild? pat: a/AstPattern -> Bool
  (mt pat ((a/patVar _) true) ((a/patWildcard) true) ((a/patLit _) true) (_ false))

fn soleBindingIsUnmarkedSimple? bindings: (List (Pair a/AstPattern a/AstExpr)) -> Bool
  (mt (listHead bindings) ((some b) (simplePatVarOrWild? (pairFirst b))) ((none) false))

fn needsCanonicalLet? bindings: (List (Pair a/AstPattern a/AstExpr)) -> Bool
  (or (anyMarkerBinding? bindings) (or (> (listLength bindings) 1) (soleBindingIsUnmarkedSimple? bindings)))

fn isEmptyElse? e: a/AstExpr -> Bool
  (mt e ((a/exprIdent name) (= name ":empty-else")) (_ false))

fn isRecordExpr? e: a/AstExpr -> Bool
  (mt e ((a/exprRecord _ _) true) (_ false))

fn ifBranchNeedsCanonical? thenBranch: a/AstExpr elseBranch: a/AstExpr -> Bool
  (and (or (isBlockExpr? thenBranch) (isBlockExpr? elseBranch)) (or (isRecordExpr? thenBranch) (isRecordExpr? elseBranch)))

fn callFunc e: a/AstExpr -> a/AstExpr
  (mt e ((a/exprCall f _) f) (_ e))

fn callArgs e: a/AstExpr -> (List a/AstExpr)
  (mt e ((a/exprCall _ args) args) (_ (list)))

fn printCallBody func: a/AstExpr args: (List a/AstExpr) -> String
  (let [(fnStr (printAstExprInArg func))] (if (listEmpty? args) fnStr (let [(argStrs (map (fn [(a a/AstExpr)] -> String (printAstExprInArg a)) args))] (str fnStr " " (stringJoin argStrs " ")))))

fn allDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (fold (fn [(acc Bool) (c String)] -> Bool (and acc (stringContains? "0123456789" c))) true (stringChars s)))

fn stripSign s: String -> String
  (if (or (stringStartsWith? s "-") (stringStartsWith? s "+")) (optionOr (stringSlice s 1 (stringLength s)) "") s)

fn dotlessExponentSep tok: String -> String
  (if (stringContains? tok "e") "e" "E")

fn dotlessExponentAtom? tok: String -> Bool
  (and (not (stringContains? tok "."))
       (and (or (stringContains? tok "e") (stringContains? tok "E"))
            (let [(parts (stringSplit tok (dotlessExponentSep tok)))]
              (and (= (listLength parts) 2)
                   (and (allDigits? (stripSign (optionOr (listGet parts 0) "")))
                        (allDigits? (stripSign (optionOr (listGet parts 1) ""))))))))

fn fixExponentAtom tok: String -> String
  (if (dotlessExponentAtom? tok)
    (let [(sep (dotlessExponentSep tok)) (parts (stringSplit tok sep))]
      (str (optionOr (listGet parts 0) "") ".0" sep (optionOr (listGet parts 1) "")))
    tok)

fn flushAtom atomBuf: (List String) out: (List String) -> (List String)
  (if (listEmpty? atomBuf) out (cons (fixExponentAtom (stringJoin (listReverse atomBuf) "")) out))

fn isAtomBoundary? c: String -> Bool
  (or (= c " ") (or (= c "(") (or (= c ")") (or (= c "[") (or (= c "]") (or (= c "\n") (= c "\t")))))))

fn fixExponentsLoop chars: (List String) inStr: Bool afterEsc: Bool atomBuf: (List String) out: (List String) -> String
  (mt (listHead chars)
    ((none) (stringJoin (listReverse (flushAtom atomBuf out)) ""))
    ((some c)
     (let [(rest (optionOr (listTail chars) (list)))]
       (if inStr
         (if afterEsc
           (fixExponentsLoop rest true false atomBuf (cons c out))
           (if (= c "\\")
             (fixExponentsLoop rest true true atomBuf (cons c out))
             (if (= c "\"")
               (fixExponentsLoop rest false false atomBuf (cons c out))
               (fixExponentsLoop rest true false atomBuf (cons c out)))))
         (if (= c "\"")
           (fixExponentsLoop rest true false (list) (cons c (flushAtom atomBuf out)))
           (if (isAtomBoundary? c)
             (fixExponentsLoop rest false false (list) (cons c (flushAtom atomBuf out)))
             (fixExponentsLoop rest false false (cons c atomBuf) out)))))))

fn fixDotlessExponents text: String -> String
  (fixExponentsLoop (stringChars text) false false (list) (list))

fn printAstCanonical expr: a/AstExpr -> String
  (fixDotlessExponents (rd/renderSexpr (cv/lower expr)))

fn printSafeInline expr: a/AstExpr -> String
  (if (isBlockExpr? expr) (printAstCanonical expr) (printAstExpr expr 0))

fn printRecordBraces rawTokens: (List a/AstExpr) -> String
  (str "{" (stringJoin (map printAstExprInArg rawTokens) " ") "}")

fn printAstExprInArg expr: a/AstExpr -> String
  (if (isBlockExpr? expr)
    (printAstCanonical expr)
    (mt expr
      ((a/exprCall func args) (str "(" (printCallBody func args) ")"))
      ((a/exprIf _ _ _) (str "(" (printAstExpr expr 0) ")"))
      ((a/exprRecord _ rawTokens) (printRecordBraces rawTokens))
      ((a/exprCond _) (printAstCanonical expr))
      ((a/exprLambda _ _ _ _) (printAstCanonical expr))
      ((a/exprInterpolation _) (printAstCanonical expr))
      (_ (printAstExpr expr 0))))

fn printAstCall func: a/AstExpr args: (List a/AstExpr) indent: Int64 -> String
  (let [(pfx (indentPrefix indent))] (if (listEmpty? args) (str pfx "(" (printAstExprInArg func) ")") (str pfx (printCallBody func args))))

fn printMemberChain expr: a/AstExpr -> String
  (mt expr ((a/exprMember target field) (str (printMemberChain target) "." field)) (_ (printAstExprInArg expr)))

fn memberChainBase expr: a/AstExpr -> a/AstExpr
  (mt expr ((a/exprMember target _) (memberChainBase target)) (_ expr))

fn simpleMemberBase? expr: a/AstExpr -> Bool
  (mt expr ((a/exprIdent _) true) (_ false))

fn printTryExpr inner: a/AstExpr -> String
  (mt inner ((a/exprCall _ _) (str "(" (printCallBody (callFunc inner) (callArgs inner)) ")?")) (_ (str (printAstExpr inner 0) "?")))

fn printLetBindingLine b: (Pair a/AstPattern a/AstExpr) indent: Int64 -> String
  (let [(pat (pairFirst b)) (val (pairSecond b))] (str (indentPrefix indent) "let " (printAstPattern pat) " = " (printSafeInline val)))

fn printLetExpr bindings: (List (Pair a/AstPattern a/AstExpr)) body: (List a/AstExpr) indent: Int64 -> String
  (let [(bindingLines (map (fn [(b (Pair a/AstPattern a/AstExpr))] -> String (printLetBindingLine b indent)) bindings))] (if (listEmpty? body) (stringJoin bindingLines "\n") (let [(bodyLines (map (fn [(e a/AstExpr)] -> String (printBodyListItem e (+ indent 1))) body))] (str (stringJoin bindingLines "\n") "\n" (stringJoin bodyLines "\n")))))

fn printBlockExpr exprs: (List a/AstExpr) indent: Int64 -> String
  (let [(lines (map (fn [(e a/AstExpr)] -> String (printAstExpr e indent)) exprs))] (stringJoin lines "\n"))

fn printIfExpr cond: a/AstExpr thenBranch: a/AstExpr elseBranch: a/AstExpr indent: Int64 -> String
  (let [(noElse (isEmptyElse? elseBranch)) (pfx (indentPrefix indent))]
    (if noElse
      (if (isBlockExpr? thenBranch)
        (str pfx "if " (printAstExprInArg cond) "\n" (printAstExpr thenBranch (+ indent 1)))
        (str pfx "if " (printAstExprInArg cond) " " (printAstExprInArg thenBranch)))
      (if (or (isBlockExpr? thenBranch) (isBlockExpr? elseBranch))
        (str pfx "if " (printAstExprInArg cond) "\n" (printAstExpr thenBranch (+ indent 1)) "\n" pfx "else\n" (printAstExpr elseBranch (+ indent 1)))
        (str pfx "if " (printAstExprInArg cond) " " (printAstExprInArg thenBranch) " " (printAstExprInArg elseBranch)))))

fn printBodyListItem ast: a/AstExpr indent: Int64 -> String
  (mt ast
    ((a/exprBlock _) (str (indentPrefix indent) (printAstCanonical ast)))
    (_ (printAstExpr ast indent)))

fn safeguardBareKeyword pretty: String canonical: String -> String
  (if (stringContains? pretty "\":\"") canonical pretty)

fn printAstExpr expr: a/AstExpr indent: Int64 -> String
  (mt expr ((a/exprLit lit) (str (indentPrefix indent) (printAstLit lit))) ((a/exprIdent name) (str (indentPrefix indent) name)) ((a/exprMember _ _) (if (simpleMemberBase? (memberChainBase expr)) (str (indentPrefix indent) (printMemberChain expr)) (str (indentPrefix indent) (printAstCanonical expr)))) ((a/exprCall func args) (printAstCall func args indent)) ((a/exprIf cond thenBranch elseBranch) (if (ifBranchNeedsCanonical? thenBranch elseBranch) (str (indentPrefix indent) (printAstCanonical expr)) (safeguardBareKeyword (printIfExpr cond thenBranch elseBranch indent) (str (indentPrefix indent) (printAstCanonical expr))))) ((a/exprLet bindings body) (if (needsCanonicalLet? bindings) (str (indentPrefix indent) (printAstCanonical expr)) (safeguardBareKeyword (printLetExpr bindings body indent) (str (indentPrefix indent) (printAstCanonical expr))))) ((a/exprMatch _ _) (str (indentPrefix indent) (printAstCanonical expr))) ((a/exprTry inner) (str (indentPrefix indent) (printTryExpr inner))) ((a/exprBlock exprs) (printBlockExpr exprs indent)) ((a/exprRecord _ _) (str (indentPrefix indent) (printAstCanonical expr))) ((a/exprCond _) (str (indentPrefix indent) (printAstCanonical expr))) ((a/exprLambda _ _ _ _) (str (indentPrefix indent) (printAstCanonical expr))) ((a/exprInterpolation _) (str (indentPrefix indent) (printAstCanonical expr))))

fn listHeadedItems s: rd/SExpr -> (Option (List rd/SExpr))
  (mt s
    ((rd/sexprList items)
     (mt (listHead items)
       ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) "list")) (some (optionOr (listTail items) (list))) (none)))
       ((none) (none))))
    (_ (none)))

fn restoreSlotVect s: rd/SExpr -> rd/SExpr
  (mt (listHeadedItems s)
    ((some inner) (rd/makeVect (map hostSexpr inner)))
    ((none) (hostSexpr s)))

fn isVectSlotHead? h: String -> Bool
  (or (= h "let") (= h "fn"))

fn hostListItems items: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead items)
    ((none) (list))
    ((some h)
     (let [(rest (optionOr (listTail items) (list)))]
       (if (and (rd/isAtom? h) (isVectSlotHead? (rd/sexprHead h)))
         (mt (listHead rest)
           ((some slot) (cons h (cons (restoreSlotVect slot) (map hostSexpr (optionOr (listTail rest) (list))))))
           ((none) (list h)))
         (map hostSexpr items)))))

fn keywordTryName items: (List rd/SExpr) -> (Option String)
  (if (!= (listLength items) 4)
    (none)
    (let [(h (a/nthExpr items 0)) (target (a/nthExpr items 1))]
      (if (and (rd/isAtom? h)
               (and (= (rd/sexprHead h) "mt")
                    (and (rd/isAtom? target)
                         (and (stringStartsWith? (rd/sexprHead target) ":")
                              (and (= (rd/renderSexpr (a/nthExpr items 2)) "((ok __v) __v)")
                                   (= (rd/renderSexpr (a/nthExpr items 3)) "((err __e) (err __e))"))))))
        (some (str (rd/sexprHead target) "?"))
        (none))))

fn hostSexpr s: rd/SExpr -> rd/SExpr
  (mt s
    ((rd/sexprAtom _) s)
    ((rd/sexprList items)
     (mt (keywordTryName items)
       ((some kw) (rd/makeAtom kw))
       ((none) (rd/makeList (hostListItems items)))))
    ((rd/sexprVect items) (rd/makeVect (map hostSexpr items))))

fn printHostBody b: rd/SExpr -> String
  (str "  " (rd/renderSexpr (hostSexpr b)))

fn printParam p: a/Param -> String
  (str p.name ": " p.type)

fn printTopDefun d: a/DefunNode -> String
  (let [(mark (if d.effect "! " ""))
        (paramsText (stringJoin (map printParam d.params) " "))
        (inferredRet (= d.retType ":inferredUnit"))
        (sig (if inferredRet
               (if (stringEmpty? paramsText) (str "fn " mark d.name) (str "fn " mark d.name " " paramsText))
               (if (stringEmpty? paramsText) (str "fn " mark d.name " -> " d.retType) (str "fn " mark d.name " " paramsText " -> " d.retType))))
        (bodyLines (map printHostBody d.body))]
    (stringJoin (cons sig bodyLines) "\n"))

fn quotedDoc? s: String -> Bool
  (stringStartsWith? s "\"")

fn optPart key: String opt: (Option String) -> String
  (mt opt ((some v) (str " " key " " v)) ((none) ""))

fn printField f: a/AstField -> String
  (str "(:f " f.name " " f.type (if (quotedDoc? f.docstring) (str " " f.docstring) "") (optPart ":default" (optionMap rd/renderSexpr f.default)) (optPart ":json" f.json) ")")

fn printTopSchema s: a/SchemaNode -> String
  (str "(schema " s.name (optPart ":json-case" s.jsonCase) " " (stringJoin (map printField s.fields) " ") ")")

fn printParamVect ps: (List a/Param) -> String
  (str "[" (stringJoin (map (fn [(p a/Param)] -> String (str "(" p.name " " p.type ")")) ps) " ") "]")

fn hasPositionalEnumField? fields: (List a/Param) -> Bool
  (listAny? (fn [(p a/Param)] -> Bool (stringEmpty? p.name)) fields)

fn printPositionalCase c: a/EnumCase -> String
  (str "(:c " c.name " [" (stringJoin (map (fn [(p a/Param)] -> String (str "(_ " p.type ")")) c.fields) " ") "]" (if (quotedDoc? c.docstring) (str " " c.docstring) "") ")")

fn printCase c: a/EnumCase -> String
  (if (hasPositionalEnumField? c.fields)
    (printPositionalCase c)
    (str "(:c " c.name " " (printParamVect c.fields) (if (quotedDoc? c.docstring) (str " " c.docstring) "") ")"))

fn printTopEnum e: a/EnumNode -> String
  (str "(enum " e.name " " (stringJoin (map printCase e.cases) " ") ")")

fn printImport p: (Pair String String) -> String
  (if (stringEmpty? (pairSecond p)) (str "(" (pairFirst p) ")") (str "(" (pairFirst p) " :a " (pairSecond p) ")"))

fn printModuleHeader m: a/ModuleNode -> String
  (str "(module " m.path
       " :x [" (stringJoin m.exported " ") "]"
       " :i [" (stringJoin (map printImport m.imports) " ") "])")

fn printTopForm tf: a/TopForm -> String
  (mt tf ((a/topDefun d) (printTopDefun d)) ((a/topSchema s) (printTopSchema s)) ((a/topEnum e) (printTopEnum e)) ((a/topModule m) (printModuleHeader m)) ((a/topExpr p) (rd/renderSexpr p.expr)))

fn printAstModule mod: a/ModuleNode -> String
  (let [(header (printModuleHeader mod))] (if (listEmpty? mod.defs) header (let [(renderedDefs (map (fn [(tf a/TopForm)] -> String (printTopForm tf)) mod.defs))] (str header "\n\n" (stringJoin renderedDefs "\n\n")))))
