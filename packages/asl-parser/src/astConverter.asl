(module asl-parser/astConverter
  :x [sexprToAst astToSexpr liftExpr lowerExpr lift lower liftPattern lowerPattern liftType lowerType sexprToTopForm topFormToSexpr]
  :i [(ast :a a) (reader :a rd)])

fn hasDigit? s: String -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (stringContains? "0123456789" c))) false (stringChars s))

fn isQuotedString? s: String -> Bool
  (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))

fn unquoteString s: String -> String
  (let [(len (stringLength s))] (if (>= len 2) (optionOr (stringSlice s 1 (- len 1)) "") ""))

fn quoteString s: String -> String
  (str "\"" s "\"")

fn liftLit s: String -> (Option a/AstLit)
  (cond
    ((= s "true") (some (a/litBool true)))
    ((= s "false") (some (a/litBool false)))
    ((= s "()") (some (a/litUnit)))
    ((isQuotedString? s) (some (a/litString (unquoteString s))))
    ((and (hasDigit? s) (stringContains? s "."))
     (mt (stringToFloat64 s)
       ((some f) (some (a/litFloat f)))
       ((none) (none))))
    ((hasDigit? s)
     (mt (stringToInt64 s)
       ((some i) (some (a/litInt i)))
       ((none) (none))))
    (else (none)))

fn lowerLit lit: a/AstLit -> rd/SExpr
  (mt lit
    ((a/litInt i) (rd/makeAtom (stringFromInt64 i)))
    ((a/litFloat f) (rd/makeAtom (stringFromFloat64 f)))
    ((a/litString s) (rd/makeAtom (quoteString s)))
    ((a/litBool b) (rd/makeAtom (if b "true" "false")))
    ((a/litUnit) (rd/makeList (list))))

fn lowerPattern pat: a/AstPattern -> rd/SExpr
  (mt pat
    ((a/patWildcard) (rd/makeAtom "_"))
    ((a/patVar name) (rd/makeAtom name))
    ((a/patLit lit) (lowerLit lit))
    ((a/patTuple elements) (rd/makeVect (map (fn [(p a/AstPattern)] -> rd/SExpr (lowerPattern p)) elements)))
    ((a/patRecord fields) (rd/makeList (cons (rd/makeAtom "record") (map (fn [(f (Pair String a/AstPattern))] -> rd/SExpr (rd/makeList (list (rd/makeAtom (pairFirst f)) (lowerPattern (pairSecond f))))) fields))))
    ((a/patCtor name arg)
     (cond
       ((or (= name ":flat") (or (= name ":nested-list") (or (= name ":vect") (or (= name ":match") (or (= name ":match-wrapped") (= name ":multi"))))))
        (mt arg
          ((some a) (lowerPattern a))
          ((none) (rd/makeAtom "_"))))
       (else
        (mt arg
          ((some a)
           (mt a
             ((a/patTuple elements)
              (rd/makeList (cons (rd/makeAtom name) (map (fn [(p a/AstPattern)] -> rd/SExpr (lowerPattern p)) elements))))
             (_ (rd/makeList (list (rd/makeAtom name) (lowerPattern a))))))
          ((none) (rd/makeList (list (rd/makeAtom name)))))))))

fn liftPattern s: rd/SExpr -> a/AstPattern
  (mt s
    ((rd/sexprAtom v) (if (= v "_") (a/patWildcard) (mt (liftLit v) ((some lit) (a/patLit lit)) ((none) (a/patVar v)))))
    ((rd/sexprVect items) (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) items)))
    ((rd/sexprList items)
     (if (listEmpty? items) (a/patLit (a/litUnit))
       (let [(h (rd/sexprHead (a/nthExpr items 0)))]
         (cond
           ((or (= h "record") (= h ":record"))
            (let [(fieldNodes (a/tailExprs items))]
              (a/patRecord (map (fn [(fNode rd/SExpr)] -> (Pair String a/AstPattern)
                                  (let [(fItems (a/sexprItems fNode))]
                                    (pair (rd/sexprHead (a/nthExpr fItems 0)) (liftPattern (a/nthExpr fItems 1)))))
                                fieldNodes))))
           ((= h "tuple") (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) (a/tailExprs items))))
           (else
            (let [(args (a/tailExprs items))]
              (if (listEmpty? args) (a/patCtor h (none))
                (if (= (listLength args) 1) (a/patCtor h (some (liftPattern (a/nthExpr args 0))))
                  (a/patCtor h (some (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) args)))))))))))))

fn lowerType t: a/AstType -> rd/SExpr
  (mt t
    ((a/typeNamed name) (rd/makeAtom name))
    ((a/typeTuple elements) (rd/makeList (cons (rd/makeAtom "tuple") (map (fn [(e a/AstType)] -> rd/SExpr (lowerType e)) elements))))
    ((a/typeRecord fields) (rd/makeList (cons (rd/makeAtom "record") (map (fn [(f (Pair String a/AstType))] -> rd/SExpr (rd/makeList (list (rd/makeAtom (pairFirst f)) (lowerType (pairSecond f))))) fields))))
    ((a/typeFn paramTypes retType) (rd/makeList (list (rd/makeAtom "fn") (rd/makeVect (map (fn [(p a/AstType)] -> rd/SExpr (lowerType p)) paramTypes)) (rd/makeAtom "->") (lowerType retType)))))

fn liftType s: rd/SExpr -> a/AstType
  (mt s
    ((rd/sexprAtom v) (a/typeNamed v))
    ((rd/sexprVect items) (a/typeTuple (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) items)))
    ((rd/sexprList items)
     (if (listEmpty? items) (a/typeNamed "Unit")
       (let [(h (rd/sexprHead (a/nthExpr items 0)))]
         (cond
           ((= h "tuple") (a/typeTuple (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) (a/tailExprs items))))
           ((or (= h "record") (= h ":record"))
            (let [(fieldNodes (a/tailExprs items))]
              (a/typeRecord (map (fn [(fNode rd/SExpr)] -> (Pair String a/AstType)
                                  (let [(fItems (a/sexprItems fNode))]
                                    (pair (rd/sexprHead (a/nthExpr fItems 0)) (liftType (a/nthExpr fItems 1)))))
                                fieldNodes))))
           ((or (= h "fn") (= h "Fn"))
            (let [(paramsNode (a/nthExpr items 1))
                  (paramTypes (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) (a/sexprItems paramsNode)))
                  (retNode (if (and (>= (listLength items) 4) (= (rd/sexprHead (a/nthExpr items 2)) "->")) (a/nthExpr items 3) (a/nthExpr items 2)))]
              (a/typeFn paramTypes (liftType retNode))))
           (else (a/typeNamed (rd/renderSexpr s))))))))

fn isBraceOpen? s: rd/SExpr -> Bool
  (mt s ((rd/sexprAtom v) (= v "{")) (_ false))

fn isBraceClose? s: rd/SExpr -> Bool
  (mt s ((rd/sexprAtom v) (= v "}")) (_ false))

fn collectBraceGroupLoop items: (List rd/SExpr) depth: Int64 acc: (List rd/SExpr) -> (Pair (List rd/SExpr) (List rd/SExpr))
  (if (listEmpty? items)
    (pair (listReverse acc) (list))
    (let [(hd (optionOr (listHead items) (rd/makeAtom "")))
          (tl (optionOr (listTail items) (list)))]
      (cond
        ((isBraceOpen? hd)
         (collectBraceGroupLoop tl (+ depth 1) (cons hd acc)))
        ((isBraceClose? hd)
         (if (<= depth 1)
           (pair (listReverse (cons hd acc)) tl)
           (collectBraceGroupLoop tl (- depth 1) (cons hd acc))))
        (else
         (collectBraceGroupLoop tl depth (cons hd acc))))))

fn isFullRecordList? items: (List rd/SExpr) -> Bool
  (and (>= (listLength items) 2)
       (and (isBraceOpen? (optionOr (listHead items) (rd/makeAtom "")))
            (isBraceClose? (optionOr (listGet items (- (listLength items) 1)) (rd/makeAtom "")))))

fn groupRecordInSexpr s: rd/SExpr -> rd/SExpr
  (mt s
    ((rd/sexprList items)
     (if (isFullRecordList? items)
       s
       (rd/makeList (groupRecordTokens items))))
    ((rd/sexprVect items) (rd/makeVect (groupRecordTokens items)))
    ((rd/sexprAtom _) s))

fn groupRecordTokensLoop items: (List rd/SExpr) acc: (List rd/SExpr) -> (List rd/SExpr)
  (if (listEmpty? items)
    (listReverse acc)
    (let [(hd (optionOr (listHead items) (rd/makeAtom "")))
          (tl (optionOr (listTail items) (list)))]
      (cond
        ((isBraceOpen? hd)
         (let [(res (collectBraceGroupLoop tl 1 (list hd)))
               (group (pairFirst res))
               (rest (pairSecond res))
               (inner (if (and (>= (listLength group) 2) (isBraceClose? (optionOr (listGet group (- (listLength group) 1)) (rd/makeAtom ""))))
                        (optionOr (listSlice group 1 (- (listLength group) 1)) (list))
                        (optionOr (listTail group) (list))))
               (groupedInner (groupRecordTokensLoop inner (list)))
               (groupedNode (rd/makeList (cons (rd/makeAtom "{") (listAppend groupedInner (list (rd/makeAtom "}"))))))]
           (groupRecordTokensLoop rest (cons groupedNode acc))))
        (else
         (let [(normHd (groupRecordInSexpr hd))]
           (groupRecordTokensLoop tl (cons normHd acc)))))))

fn groupRecordTokens items: (List rd/SExpr) -> (List rd/SExpr)
  (if (isFullRecordList? items)
    items
    (groupRecordTokensLoop items (list)))

fn lowerSpliced expr: a/AstExpr -> (List rd/SExpr)
  (mt expr
    ((a/exprRecord _ rawTokens)
     (let [(loweredInner (map (fn [(e a/AstExpr)] -> rd/SExpr (lowerExpr e)) rawTokens))]
       (cons (rd/makeAtom "{") (listAppend loweredInner (list (rd/makeAtom "}"))))))
    (_ (list (lowerExpr expr))))

fn isTypedMarker? func: a/AstExpr -> Bool
  (mt func ((a/exprIdent name) (= name ":typed")) (_ false))

fn lowerBindingValue val: a/AstExpr -> (List rd/SExpr)
  (mt val
    ((a/exprCall func parts)
     (if (isTypedMarker? func)
       (fold (fn [(acc (List rd/SExpr)) (e a/AstExpr)] -> (List rd/SExpr) (listAppend acc (lowerSpliced e))) (list) parts)
       (lowerSpliced val)))
    (_ (lowerSpliced val)))

fn lowerBinding b: (Pair a/AstPattern a/AstExpr) -> rd/SExpr
  (rd/makeList (cons (lowerPattern (pairFirst b)) (lowerBindingValue (pairSecond b))))

fn lowerBindingFlat b: (Pair a/AstPattern a/AstExpr) -> (List rd/SExpr)
  (cons (lowerPattern (pairFirst b)) (lowerBindingValue (pairSecond b)))

fn lowerMatchArm arm: a/AstMatchArm -> rd/SExpr
  (let [(rawPat arm.pat)
        (body arm.body)]
    (mt rawPat
      ((a/patCtor name arg)
       (if (= name ":multi")
         (let [(patSexpr (lowerPattern (optionOr arg (a/patWildcard))))]
           (mt body
             ((a/exprBlock exprs)
              (let [(bNodes (fold (fn [(acc (List rd/SExpr)) (e a/AstExpr)] -> (List rd/SExpr)
                                    (listAppend acc (lowerSpliced e)))
                                  (list) exprs))]
                (rd/makeList (cons patSexpr bNodes))))
             (_
              (rd/makeList (cons patSexpr (lowerSpliced body))))))
         (rd/makeList (cons (lowerPattern rawPat) (lowerSpliced body)))))
      (_
       (rd/makeList (cons (lowerPattern rawPat) (lowerSpliced body))))))

fn lowerExpr expr: a/AstExpr -> rd/SExpr
  (mt expr
    ((a/exprLit lit) (lowerLit lit))
    ((a/exprIdent name) (rd/makeAtom name))
    ((a/exprMember target field) (rd/makeList (list (rd/makeAtom (str ".-" field)) (lowerExpr target))))
    ((a/exprCall func args)
     (let [(fNode (lowerExpr func))
           (argNodes (fold (fn [(acc (List rd/SExpr)) (e a/AstExpr)] -> (List rd/SExpr)
                             (listAppend acc (lowerSpliced e)))
                           (list) args))]
       (rd/makeList (cons fNode argNodes))))
    ((a/exprLet bindings body)
     (let [(bodyNodes (fold (fn [(acc (List rd/SExpr)) (e a/AstExpr)] -> (List rd/SExpr)
                              (listAppend acc (lowerSpliced e)))
                            (list) body))]
       (if (listEmpty? bindings)
         (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList (list)) bodyNodes)))
         (let [(firstB (optionOr (listHead bindings) (pair (a/patWildcard) (a/exprLit (a/litUnit)))))
               (firstPat (pairFirst firstB))]
           (mt firstPat
             ((a/patCtor name _)
              (cond
                ((= name ":empty-list")
                 (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList (list (rd/makeAtom "list"))) bodyNodes))))
                ((= name ":empty-vect")
                 (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeVect (list)) bodyNodes))))
                ((= name ":empty-paren")
                 (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList (list)) bodyNodes))))
                ((= name ":flat")
                 (let [(flatItems (fold (fn [(acc (List rd/SExpr)) (b (Pair a/AstPattern a/AstExpr))] -> (List rd/SExpr)
                                          (listAppend acc (lowerBindingFlat b)))
                                        (list) bindings))]
                   (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList (cons (rd/makeAtom "list") flatItems)) bodyNodes)))))
                ((= name ":nested-list")
                 (let [(bindingSexprs (map lowerBinding bindings))]
                   (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList (cons (rd/makeAtom "list") bindingSexprs)) bodyNodes)))))
                ((= name ":vect")
                 (let [(bindingSexprs (map lowerBinding bindings))]
                   (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeVect bindingSexprs) bodyNodes)))))
                (else
                 (let [(bindingSexprs (map lowerBinding bindings))]
                   (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList bindingSexprs) bodyNodes)))))))
             (_
              (let [(bindingSexprs (map lowerBinding bindings))]
                (rd/makeList (cons (rd/makeAtom "let") (cons (rd/makeList bindingSexprs) bodyNodes))))))))))
    ((a/exprIf cond thenBranch elseBranch)
     (let [(cNode (lowerExpr cond))
           (tNodes (lowerSpliced thenBranch))]
       (mt elseBranch
         ((a/exprIdent name)
          (if (= name ":empty-else")
            (rd/makeList (cons (rd/makeAtom "if") (cons cNode tNodes)))
            (let [(eNodes (lowerSpliced elseBranch))]
              (rd/makeList (cons (rd/makeAtom "if") (cons cNode (listAppend tNodes eNodes)))))))
         (_
          (let [(eNodes (lowerSpliced elseBranch))]
            (rd/makeList (cons (rd/makeAtom "if") (cons cNode (listAppend tNodes eNodes)))))))))
    ((a/exprMatch target arms)
     (let [(isMatchWrapped
             (mt (listHead arms)
               ((some firstArm)
                (mt firstArm.pat
                  ((a/patCtor name _) (= name ":match-wrapped"))
                  (_ false)))
               ((none) false)))
           (isMatchHead
             (or isMatchWrapped
                 (mt (listHead arms)
                   ((some firstArm)
                    (mt firstArm.pat
                      ((a/patCtor name _) (= name ":match"))
                      (_ false)))
                   ((none) false))))
           (headStr (if isMatchHead "match" "mt"))
           (armNodes (map lowerMatchArm arms))]
       (if isMatchWrapped
         (rd/makeList (list (rd/makeAtom headStr) (lowerExpr target) (rd/makeList armNodes)))
         (rd/makeList (cons (rd/makeAtom headStr) (cons (lowerExpr target) armNodes))))))
    ((a/exprTry inner)
     (mt inner
       ((a/exprCall f args)
        (mt f
          ((a/exprIdent n)
           (if (= n ":raw-try")
             (rd/makeList (list (rd/makeAtom "try") (lowerExpr (optionOr (listHead args) (a/exprLit (a/litUnit))))))
             (rd/makeList (list (rd/makeAtom "mt") (lowerExpr inner)
                                (rd/makeList (list (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "__v"))) (rd/makeAtom "__v")))
                                (rd/makeList (list (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e"))) (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e")))))))))
          (_ (rd/makeList (list (rd/makeAtom "try") (lowerExpr inner))))))
       (_ (rd/makeList (list (rd/makeAtom "try") (lowerExpr inner))))))
    ((a/exprBlock exprs)
     (let [(bNodes (fold (fn [(acc (List rd/SExpr)) (e a/AstExpr)] -> (List rd/SExpr)
                           (listAppend acc (lowerSpliced e)))
                         (list) exprs))]
       (rd/makeList (cons (rd/makeAtom "do") bNodes))))
    ((a/exprRecord fields rawTokens)
     (let [(loweredInner (map (fn [(e a/AstExpr)] -> rd/SExpr (lowerExpr e)) rawTokens))]
       (rd/makeList (cons (rd/makeAtom "{") (listAppend loweredInner (list (rd/makeAtom "}")))))))
    ((a/exprCond clauses)
     (let [(clauseNodes (map (fn [(cl (Pair a/AstExpr (List a/AstExpr)))] -> rd/SExpr
                               (let [(testNode (lowerExpr (pairFirst cl)))
                                     (bodyNodes (fold (fn [(acc (List rd/SExpr)) (b a/AstExpr)] -> (List rd/SExpr)
                                                        (listAppend acc (lowerSpliced b)))
                                                      (list) (pairSecond cl)))]
                                 (rd/makeList (cons testNode bodyNodes))))
                             clauses))]
       (rd/makeList (cons (rd/makeAtom "cond") clauseNodes))))
    ((a/exprLambda params retType body rawParams)
     (let [(retSexprs (mt retType ((some r) (list (rd/makeAtom "->") (rd/makeAtom r))) ((none) (list))))
           (bodySexprs (map (fn [(b a/AstExpr)] -> rd/SExpr (lowerExpr b)) body))]
       (rd/makeList (cons (rd/makeAtom "fn") (cons rawParams (listAppend retSexprs bodySexprs))))))
    ((a/exprInterpolation parts)
     (rd/makeList (cons (rd/makeAtom "str") (map (fn [(p a/AstExpr)] -> rd/SExpr (lowerExpr p)) parts)))))

fn astToSexpr expr: a/AstExpr -> rd/SExpr
  (lowerExpr expr)

fn lower expr: a/AstExpr -> rd/SExpr
  (lowerExpr expr)

fn liftBindingPair bNode: rd/SExpr -> (Pair a/AstPattern a/AstExpr)
  (let [(rawItems (a/sexprItems bNode))
        (bItems (groupRecordTokens rawItems))
        (patNode (a/nthExpr bItems 0))
        (count (listLength bItems))
        (val (cond
               ((<= count 1) (liftExpr (rd/makeAtom "")))
               ((= count 2) (liftExpr (a/nthExpr bItems 1)))
               (else (a/exprCall (a/exprIdent ":typed") (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) (a/tailExprs bItems))))))]
    (pair (liftPattern patNode) val))

fn liftMatchArmForm aNode: rd/SExpr -> a/AstMatchArm
  (let [(rawItems (a/sexprItems aNode))
        (aItems (groupRecordTokens rawItems))
        (rawPat (liftPattern (a/nthExpr aItems 0)))
        (isMulti (> (listLength aItems) 2))
        (pat (if isMulti (a/patCtor ":multi" (some rawPat)) rawPat))
        (body (if (<= (listLength aItems) 2) (liftExpr (a/nthExpr aItems 1)) (a/exprBlock (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) (a/tailExprs aItems)))))]
    (a/matchArm pat body))

fn pairFlatBindingsLoop items: (List rd/SExpr) isFirst: Bool acc: (List (Pair a/AstPattern a/AstExpr)) -> (List (Pair a/AstPattern a/AstExpr))
  (if (< (listLength items) 2)
    (listReverse acc)
    (let [(patNode (a/nthExpr items 0))
          (valNode (a/nthExpr items 1))
          (rest (if (> (listLength items) 2) (optionOr (listSlice items 2 (listLength items)) (list)) (list)))
          (rawPat (liftPattern patNode))
          (pat (if isFirst (a/patCtor ":flat" (some rawPat)) rawPat))
          (val (liftExpr valNode))]
      (pairFlatBindingsLoop rest false (cons (pair pat val) acc))))

fn liftFlatBindings items: (List rd/SExpr) -> (List (Pair a/AstPattern a/AstExpr))
  (pairFlatBindingsLoop (groupRecordTokens items) true (list))

fn liftNestedListBindings items: (List rd/SExpr) -> (List (Pair a/AstPattern a/AstExpr))
  (let [(pairs (map liftBindingPair items))]
    (mt (listHead pairs)
      ((some firstPair)
       (let [(firstPat (pairFirst firstPair))
             (markedPat (a/patCtor ":nested-list" (some firstPat)))
             (markedFirst (pair markedPat (pairSecond firstPair)))
             (tailPairs (optionOr (listTail pairs) (list)))]
         (cons markedFirst tailPairs)))
      ((none) (list))))

fn liftVectBindings items: (List rd/SExpr) -> (List (Pair a/AstPattern a/AstExpr))
  (if (listEmpty? items)
    (list)
    (let [(firstItem (a/nthExpr items 0))]
      (if (or (rd/isList? firstItem) (rd/isVect? firstItem))
        (let [(pairs (map liftBindingPair items))
              (firstPair (optionOr (listHead pairs) (pair (a/patWildcard) (a/exprLit (a/litUnit)))))
              (markedFirst (pair (a/patCtor ":vect" (some (pairFirst firstPair))) (pairSecond firstPair)))
              (tailPairs (optionOr (listTail pairs) (list)))]
          (cons markedFirst tailPairs))
        (pairFlatBindingsLoop (groupRecordTokens items) true (list)))))

fn isDesugaredTryMatch? items: (List rd/SExpr) -> Bool
  (if (!= (listLength items) 4)
    false
    (let [(target (a/nthExpr items 1))]
      (if (and (rd/isAtom? target) (stringStartsWith? (rd/sexprHead target) ":"))
        false
        (let [(arm1 (a/nthExpr items 2))
              (arm2 (a/nthExpr items 3))
              (a1Items (a/sexprItems arm1))
              (a2Items (a/sexprItems arm2))]
          (if (or (!= (listLength a1Items) 2) (!= (listLength a2Items) 2))
            false
            (let [(p1 (a/nthExpr a1Items 0))
                  (b1 (a/nthExpr a1Items 1))
                  (p2 (a/nthExpr a2Items 0))
                  (b2 (a/nthExpr a2Items 1))
                  (p1Items (a/sexprItems p1))
                  (p2Items (a/sexprItems p2))
                  (b2Items (a/sexprItems b2))]
              (and (= (rd/sexprHead p1) "ok")
                   (and (= (listLength p1Items) 2)
                        (and (= (rd/sexprHead (a/nthExpr p1Items 1)) (rd/sexprHead b1))
                             (and (= (rd/sexprHead p2) "err")
                                  (and (= (listLength p2Items) 2)
                                       (and (= (listLength b2Items) 2)
                                            (and (= (rd/sexprHead b2) "err")
                                                 (= (rd/sexprHead (a/nthExpr p2Items 1)) (rd/sexprHead (a/nthExpr b2Items 1))))))))))))))))

fn isWrappedMatchArms? node: rd/SExpr -> Bool
  (mt node
    ((rd/sexprList items)
     (and (not (listEmpty? items))
          (fold (fn [(allArms Bool) (item rd/SExpr)] -> Bool
                  (and allArms (rd/isList? item)))
                true items)))
    (_ false))

fn liftExpr s: rd/SExpr -> a/AstExpr
  (mt s
    ((rd/sexprAtom v) (mt (liftLit v) ((some lit) (a/exprLit lit)) ((none) (a/exprIdent v))))
    ((rd/sexprVect items) (if (listEmpty? items) (a/exprBlock (list)) (a/exprBlock (map (fn [(it rd/SExpr)] -> a/AstExpr (liftExpr it)) items))))
    ((rd/sexprList rawItems)
     (if (listEmpty? rawItems) (a/exprLit (a/litUnit))
       (let [(items (if (isFullRecordList? rawItems) rawItems (groupRecordTokens rawItems)))
             (headNode (a/nthExpr items 0))
             (h (rd/sexprHead headNode))]
         (cond
           ((and (rd/isAtom? headNode) (= h "{"))
            (let [(rawInner (if (and (>= (listLength items) 2) (isBraceClose? (a/nthExpr items (- (listLength items) 1))))
                              (optionOr (listSlice items 1 (- (listLength items) 1)) (list))
                              (a/tailExprs items)))
                  (liftedInner (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) rawInner))]
              (a/exprRecord (list) liftedInner)))
           ((and (rd/isAtom? headNode) (stringStartsWith? h ".-"))
            (let [(field (optionOr (stringSlice h 2 (stringLength h)) "")) (target (liftExpr (a/nthExpr items 1)))] (a/exprMember target field)))
           ((and (rd/isAtom? headNode) (and (= h "if") (<= (listLength items) 4)))
            (let [(c (liftExpr (a/nthExpr items 1)))
                  (t (liftExpr (a/nthExpr items 2)))]
              (if (<= (listLength items) 3)
                (a/exprIf c t (a/exprIdent ":empty-else"))
                (let [(e (liftExpr (a/nthExpr items 3)))]
                  (a/exprIf c t e)))))
           ((and (rd/isAtom? headNode) (= h "cond"))
            (let [(clauseNodes (a/tailExprs items))
                  (clauses (map (fn [(cNode rd/SExpr)] -> (Pair a/AstExpr (List a/AstExpr))
                                  (let [(cItems (groupRecordTokens (a/sexprItems cNode)))
                                        (testExpr (liftExpr (a/nthExpr cItems 0)))
                                        (bodyExprs (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) (a/tailExprs cItems)))]
                                    (pair testExpr bodyExprs)))
                                clauseNodes))]
              (a/exprCond clauses)))
           ((and (rd/isAtom? headNode) (= h "let"))
            (let [(bindingsNode (a/nthExpr items 1))
                  (bindings
                    (mt bindingsNode
                      ((rd/sexprVect vItems)
                       (if (listEmpty? vItems)
                         (list (pair (a/patCtor ":empty-vect" (none)) (a/exprLit (a/litUnit))))
                         (liftVectBindings vItems)))
                      ((rd/sexprList lItems)
                       (if (and (not (listEmpty? lItems)) (= (rd/sexprHead (a/nthExpr lItems 0)) "list"))
                         (let [(content (a/tailExprs lItems))]
                           (if (listEmpty? content)
                             (list (pair (a/patCtor ":empty-list" (none)) (a/exprLit (a/litUnit))))
                             (let [(firstContent (a/nthExpr content 0))]
                               (if (or (rd/isList? firstContent) (rd/isVect? firstContent))
                                 (liftNestedListBindings content)
                                 (liftFlatBindings content)))))
                         (if (listEmpty? lItems)
                           (list (pair (a/patCtor ":empty-paren" (none)) (a/exprLit (a/litUnit))))
                           (map liftBindingPair lItems))))
                      (_ (list))))
                  (bodyNodes (if (> (listLength items) 2) (optionOr (listSlice items 2 (listLength items)) (list)) (list)))
                  (body (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) bodyNodes))]
              (a/exprLet bindings body)))
           ((and (rd/isAtom? headNode) (or (= h "match") (= h "mt")))
            (if (isDesugaredTryMatch? items)
              (a/exprTry (liftExpr (a/nthExpr items 1)))
              (let [(target (liftExpr (a/nthExpr items 1)))
                    (rawTail (if (> (listLength items) 2) (optionOr (listSlice items 2 (listLength items)) (list)) (list)))
                    (isMatchWrapped (and (= h "match") (and (= (listLength rawTail) 1) (isWrappedMatchArms? (a/nthExpr rawTail 0)))))
                    (rawArms (if isMatchWrapped (a/sexprItems (a/nthExpr rawTail 0)) rawTail))
                    (arms (map liftMatchArmForm rawArms))
                    (markedArms
                      (cond
                        (isMatchWrapped
                         (mt (listHead arms)
                           ((some firstArm)
                            (let [(firstPat firstArm.pat)
                                  (mPat (a/patCtor ":match-wrapped" (some firstPat)))
                                  (mArm (a/matchArm mPat firstArm.body))
                                  (tailArms (optionOr (listTail arms) (list)))]
                              (cons mArm tailArms)))
                           ((none) arms)))
                        ((= h "match")
                         (mt (listHead arms)
                           ((some firstArm)
                            (let [(firstPat firstArm.pat)
                                  (mPat (a/patCtor ":match" (some firstPat)))
                                  (mArm (a/matchArm mPat firstArm.body))
                                  (tailArms (optionOr (listTail arms) (list)))]
                              (cons mArm tailArms)))
                           ((none) arms)))
                        (else arms)))]
                (a/exprMatch target markedArms))))
           ((and (rd/isAtom? headNode) (= h "|>"))
            (let [(subExprs (a/tailExprs items))]
              (if (listEmpty? subExprs) (a/exprLit (a/litUnit))
                (fold (fn [(acc a/AstExpr) (step rd/SExpr)] -> a/AstExpr
                        (let [(stepAst (liftExpr step))]
                          (mt stepAst
                            ((a/exprCall f args) (a/exprCall f (cons acc args)))
                            (_ (a/exprCall stepAst (list acc))))))
                      (liftExpr (a/nthExpr subExprs 0)) (a/tailExprs subExprs)))))
           ((and (rd/isAtom? headNode) (= h "do"))
            (let [(formNodes (a/tailExprs items))] (a/exprBlock (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) formNodes))))
           ((and (rd/isAtom? headNode) (= h "try"))
            (let [(inner (liftExpr (a/nthExpr items 1)))] (a/exprTry (a/exprCall (a/exprIdent ":raw-try") (list inner)))))
           (else
            (let [(func (liftExpr headNode)) (args (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) (a/tailExprs items)))] (a/exprCall func args))))))))

fn sexprToAst s: rd/SExpr -> a/AstExpr
  (liftExpr (groupRecordInSexpr s))

fn lift s: rd/SExpr -> a/AstExpr
  (liftExpr (groupRecordInSexpr s))

fn nthString items: (List rd/SExpr) i: Int64 -> String
  (mt (listGet items i) ((some node) (mt node ((rd/sexprAtom v) v) (_ (rd/renderSexpr node)))) ((none) ""))

fn sexprToTopForm s: rd/SExpr -> (Result a/TopForm String)
  (let [(h (rd/sexprHead s))]
    (cond
      ((or (= h "df") (= h "fn"))
       (let [(items (a/sexprItems s))]
         (if (< (listLength items) 5)
           (err "Malformed fn form: expected at least (fn name params -> retType)")
           (let [(name (nthString items 1))
                 (paramsNode (a/nthExpr items 2))
                 (rawParams (a/sexprItems paramsNode))
                 (params (map (fn [(p rd/SExpr)] -> a/Param
                                (let [(pItems (a/sexprItems p))]
                                  (a/Param :name (nthString pItems 0) :type (nthString pItems 1))))
                              rawParams))
                 (retSlot (a/nthExpr items 4))
                 (hasInline (and (= (listLength items) 5) (a/isInlineBodyCandidate? retSlot)))
                 (retType (if hasInline (nthString (a/sexprItems retSlot) 0) (nthString items 4)))
                 (bodyForms (if hasInline
                              (a/tailExprs (a/sexprItems retSlot))
                              (if (> (listLength items) 5) (optionOr (listSlice items 5 (listLength items)) (list)) (list))))]
             (ok (a/topDefun (a/DefunNode :name name :typeVars (list) :isExported false :effect false :params params :retType retType :docstring "" :body bodyForms :bodyPos (list))))))))
      ((or (= h "dfs") (= h "schema"))
       (let [(items (a/sexprItems s))]
         (if (< (listLength items) 2)
           (err "Malformed schema form: missing schema name")
           (let [(name (nthString items 1))
                 (fieldForms (a/tailExprs (a/tailExprs items)))
                 (fields (map (fn [(f rd/SExpr)] -> a/AstField
                                (let [(fItems (a/sexprItems f))]
                                  (a/AstField :name (nthString fItems 1) :type (nthString fItems 2) :docstring (unquoteString (nthString fItems 3)) :default (none) :json (none))))
                              fieldForms))]
             (ok (a/topSchema (a/SchemaNode :name name :typeVars (list) :fields fields :jsonCase (none))))))))
      ((or (= h "dfe") (= h "enum"))
       (let [(items (a/sexprItems s))]
         (if (< (listLength items) 2)
           (err "Malformed enum form: missing enum name")
           (let [(name (nthString items 1))
                 (caseForms (a/tailExprs (a/tailExprs items)))
                 (cases (map (fn [(c rd/SExpr)] -> a/EnumCase
                               (let [(cItems (a/sexprItems c))
                                     (cName (nthString cItems 1))
                                     (rawParams (if (> (listLength cItems) 2) (a/sexprItems (a/nthExpr cItems 2)) (list)))
                                     (cParams (map (fn [(p rd/SExpr)] -> a/Param
                                                     (let [(pItems (a/sexprItems p))]
                                                       (a/Param :name (nthString pItems 0) :type (nthString pItems 1))))
                                                   rawParams))
                                     (cDoc (unquoteString (nthString cItems 3)))]
                                 (a/EnumCase :name cName :fields cParams :docstring cDoc)))
                             caseForms))]
             (ok (a/topEnum (a/EnumNode :name name :typeVars (list) :cases cases)))))))
      ((= h "module")
       (let [(path (nthString (a/sexprItems s) 1))]
         (if (stringEmpty? path)
           (err "Malformed module form: missing module path")
           (ok (a/topModule (a/moduleNode s path (list)))))))
      (else (err (str "Unrecognized declaration head: " h)))))

fn topFormToSexpr tf: a/TopForm -> rd/SExpr
  (mt tf
    ((a/topDefun d)
     (let [(paramsSexpr (rd/makeVect (map (fn [(p a/Param)] -> rd/SExpr (rd/makeList (list (rd/makeAtom p.name) (rd/makeAtom p.type)))) d.params)))]
       (rd/makeList (listAppend (list (rd/makeAtom "fn") (rd/makeAtom d.name) paramsSexpr (rd/makeAtom "->") (rd/makeAtom d.retType)) d.body))))
    ((a/topSchema s)
     (let [(fieldSexprs (map (fn [(f a/AstField)] -> rd/SExpr (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom f.name) (rd/makeAtom f.type) (rd/makeAtom (quoteString f.docstring))))) s.fields))]
       (rd/makeList (cons (rd/makeAtom "schema") (cons (rd/makeAtom s.name) fieldSexprs)))))
    ((a/topEnum e)
     (let [(caseSexprs (map (fn [(c a/EnumCase)] -> rd/SExpr (let [(fieldsVect (rd/makeVect (map (fn [(p a/Param)] -> rd/SExpr (rd/makeList (list (rd/makeAtom p.name) (rd/makeAtom p.type)))) c.fields)))] (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom c.name) fieldsVect (rd/makeAtom (quoteString c.docstring)))))) e.cases))]
       (rd/makeList (cons (rd/makeAtom "enum") (cons (rd/makeAtom e.name) caseSexprs)))))
    ((a/topModule m)
     (rd/makeList (listAppend (list (rd/makeAtom "module") (rd/makeAtom m.path)) (listAppend (if (stringEmpty? m.docstring) (list) (list (rd/makeAtom ":doc") (rd/makeAtom m.docstring))) (list (rd/makeAtom ":export") (rd/makeVect (map (fn [(x String)] -> rd/SExpr (rd/makeAtom x)) m.exported)) (rd/makeAtom ":import") (rd/makeVect (map (fn [(p (Pair String String))] -> rd/SExpr (rd/makeList (list (rd/makeAtom (pairFirst p)) (rd/makeAtom ":as") (rd/makeAtom (pairSecond p))))) m.imports)))))))
    ((a/topExpr p) p.expr))
