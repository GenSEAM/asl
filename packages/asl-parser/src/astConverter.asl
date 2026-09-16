(module asl-parser/astConverter
  :d "Bidirectional AST Converter and Roundtrip Equivalence between generic S-expressions and Typed AST."
  :x [sexprToAst astToSexpr liftExpr lowerExpr liftPattern lowerPattern liftType lowerType]
  :i [(ast :a a) (reader :a rd)])

(df charsWithin? [(allowed String) (s String)] -> Bool
  :d "True when every character of s appears in allowed."
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (string-contains? allowed c)))
        true
        (string-chars s)))

(df hasDigit? [(s String)] -> Bool
  :d "True when s contains at least one decimal digit."
  (fold (fn [(acc Bool) (c String)] -> Bool (or acc (string-contains? "0123456789" c)))
        false
        (string-chars s)))

(df isQuotedString? [(s String)] -> Bool
  :d "True when s is enclosed in double quotes."
  (and (>= (string-length s) 2)
       (and (string-starts-with? s "\"")
            (string-ends-with? s "\""))))

(df unquoteString [(s String)] -> String
  :d "Strips leading and trailing double quotes from string literal."
  (let [(len (string-length s))]
    (if (>= len 2)
      (option-or (string-slice s 1 (- len 1)) "")
      "")))

(df quoteString [(s String)] -> String
  :d "Encloses string in double quotes."
  (str "\"" s "\""))

(df liftLit [(s String)] -> (Option a/AstLit)
  :d "Lifts an atom string to an AstLit variant if recognized as a literal."
  (cond
    ((= s "true") (some (a/litBool true)))
    ((= s "false") (some (a/litBool false)))
    ((or (= s "()") (= s "unit")) (some (a/litUnit)))
    ((isQuotedString? s) (some (a/litString (unquoteString s))))
    ((hasDigit? s)
     (mt (string-to-int64 s)
       ((some i) (some (a/litInt i)))
       ((none)
        (mt (string-to-float64 s)
          ((some f) (some (a/litFloat f)))
          ((none) (none))))))
    (:else (none))))

(df lowerLit [(lit a/AstLit)] -> rd/SExpr
  :d "Lowers an AstLit variant to canonical SExpr."
  (mt lit
    ((a/litInt i)    (rd/makeAtom (string-from-int64 i)))
    ((a/litFloat f)  (rd/makeAtom (string-from-float64 f)))
    ((a/litString s) (rd/makeAtom (quoteString s)))
    ((a/litBool b)   (rd/makeAtom (if b "true" "false")))
    ((a/litUnit)     (rd/makeList (list)))))

(df sexprItems [(s rd/SExpr)] -> (List rd/SExpr)
  :d "Extracts items from list or vect SExpr, empty list otherwise."
  (mt s
    ((rd/sexprList items) items)
    ((rd/sexprVect items) items)
    ((rd/sexprAtom _)     (list))))

(df nthExpr [(items (List rd/SExpr)) (i Int64)] -> rd/SExpr
  :d "Gets i-th element of SExpr list or empty atom."
  (mt (list-get items i)
    ((some node) node)
    ((none)      (rd/makeAtom ""))))

(df tailExprs [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "The list without its head."
  (option-or (list-tail items) (list)))

(df lowerPattern [(pat a/AstPattern)] -> rd/SExpr
  :d "Lowers an AstPattern node to canonical SExpr representation."
  (mt pat
    ((a/patWildcard)
     (rd/makeAtom "_"))
    ((a/patVar name)
     (rd/makeAtom name))
    ((a/patLit lit)
     (lowerLit lit))
    ((a/patTuple elements)
     (rd/makeVect (map (fn [(p a/AstPattern)] -> rd/SExpr (lowerPattern p)) elements)))
    ((a/patRecord fields)
     (rd/makeList
       (list-cons (rd/makeAtom "record")
                  (map (fn [(f (Pair String a/AstPattern))] -> rd/SExpr
                         (rd/makeList (list (rd/makeAtom (.-first f))
                                            (lowerPattern (.-second f)))))
                       fields))))
    ((a/patCtor name arg)
     (mt arg
       ((some a)
        (rd/makeList (list (rd/makeAtom name) (lowerPattern a))))
       ((none)
        (rd/makeList (list (rd/makeAtom name))))))))

(df liftPattern [(s rd/SExpr)] -> a/AstPattern
  :d "Lifts an SExpr to an AstPattern node."
  (mt s
    ((rd/sexprAtom v)
     (if (= v "_")
       (a/patWildcard)
       (mt (liftLit v)
         ((some lit) (a/patLit lit))
         ((none)     (a/patVar v)))))
    ((rd/sexprVect items)
     (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) items)))
    ((rd/sexprList items)
     (if (list-empty? items)
       (a/patLit (a/litUnit))
       (let [(h (rd/sexprHead (nthExpr items 0)))]
         (cond
           ((or (= h "record") (= h ":record"))
            (let [(fieldNodes (tailExprs items))]
              (a/patRecord
                (map (fn [(fNode rd/SExpr)] -> (Pair String a/AstPattern)
                       (let [(fItems (sexprItems fNode))]
                         (pair (rd/sexprHead (nthExpr fItems 0))
                               (liftPattern (nthExpr fItems 1)))))
                     fieldNodes))))
           ((= h "tuple")
            (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) (tailExprs items))))
           (:else
            (let [(args (tailExprs items))]
              (if (list-empty? args)
                (a/patCtor h (none))
                (if (= (list-length args) 1)
                  (a/patCtor h (some (liftPattern (nthExpr args 0))))
                  (a/patCtor h (some (a/patTuple (map (fn [(it rd/SExpr)] -> a/AstPattern (liftPattern it)) args))))))))))))))

(df lowerType [(t a/AstType)] -> rd/SExpr
  :d "Lowers an AstType node to canonical SExpr representation."
  (mt t
    ((a/typeNamed name)
     (rd/makeAtom name))
    ((a/typeTuple elements)
     (rd/makeList
       (list-cons (rd/makeAtom "tuple")
                  (map (fn [(e a/AstType)] -> rd/SExpr (lowerType e)) elements))))
    ((a/typeRecord fields)
     (rd/makeList
       (list-cons (rd/makeAtom "record")
                  (map (fn [(f (Pair String a/AstType))] -> rd/SExpr
                         (rd/makeList (list (rd/makeAtom (.-first f))
                                            (lowerType (.-second f)))))
                       fields))))
    ((a/typeFn paramTypes retType)
     (rd/makeList
       (list (rd/makeAtom "fn")
             (rd/makeVect (map (fn [(p a/AstType)] -> rd/SExpr (lowerType p)) paramTypes))
             (rd/makeAtom "->")
             (lowerType retType))))))

(df liftType [(s rd/SExpr)] -> a/AstType
  :d "Lifts an SExpr to an AstType node."
  (mt s
    ((rd/sexprAtom v)
     (a/typeNamed v))
    ((rd/sexprVect items)
     (a/typeTuple (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) items)))
    ((rd/sexprList items)
     (if (list-empty? items)
       (a/typeNamed "Unit")
       (let [(h (rd/sexprHead (nthExpr items 0)))]
         (cond
           ((= h "tuple")
            (a/typeTuple (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) (tailExprs items))))
           ((or (= h "record") (= h ":record"))
            (let [(fieldNodes (tailExprs items))]
              (a/typeRecord
                (map (fn [(fNode rd/SExpr)] -> (Pair String a/AstType)
                       (let [(fItems (sexprItems fNode))]
                         (pair (rd/sexprHead (nthExpr fItems 0))
                               (liftType (nthExpr fItems 1)))))
                     fieldNodes))))
           ((or (= h "fn") (= h "Fn"))
            (let [(paramsNode (nthExpr items 1))
                  (paramTypes (map (fn [(it rd/SExpr)] -> a/AstType (liftType it)) (sexprItems paramsNode)))
                  (retNode (if (and (>= (list-length items) 4) (= (rd/sexprHead (nthExpr items 2)) "->"))
                             (nthExpr items 3)
                             (nthExpr items 2)))]
              (a/typeFn paramTypes (liftType retNode))))
           (:else
            (a/typeNamed (rd/renderSexpr s)))))))))

(df lowerBinding [(b (Pair a/AstPattern a/AstExpr))] -> rd/SExpr
  :d "Lowers a let binding pair to an SExpr list form."
  (rd/makeList (list (lowerPattern (.-first b)) (lowerExpr (.-second b)))))

(df lowerMatchArm [(arm a/AstMatchArm)] -> rd/SExpr
  :d "Lowers a match arm to an SExpr list form."
  (rd/makeList (list (lowerPattern (.-pat arm)) (lowerExpr (.-body arm)))))

(df lowerExpr [(expr a/AstExpr)] -> rd/SExpr
  :d "Converts typed AstExpr to canonical SExpr representation."
  (mt expr
    ((a/exprLit lit)
     (lowerLit lit))
    ((a/exprIdent name)
     (rd/makeAtom name))
    ((a/exprMember target field)
     (rd/makeList (list (rd/makeAtom (str ".-" field)) (lowerExpr target))))
    ((a/exprCall func args)
     (rd/makeList (list-cons (lowerExpr func)
                             (map (fn [(arg a/AstExpr)] -> rd/SExpr (lowerExpr arg)) args))))
    ((a/exprLet bindings body)
     (rd/makeList
       (list-cons (rd/makeAtom "let")
                  (list-cons (rd/makeVect (map lowerBinding bindings))
                             (map (fn [(e a/AstExpr)] -> rd/SExpr (lowerExpr e)) body)))))
    ((a/exprIf cond thenBranch elseBranch)
     (rd/makeList (list (rd/makeAtom "if")
                        (lowerExpr cond)
                        (lowerExpr thenBranch)
                        (lowerExpr elseBranch))))
    ((a/exprMatch target arms)
     (rd/makeList
       (list-cons (rd/makeAtom "match")
                  (list-cons (lowerExpr target)
                             (map lowerMatchArm arms)))))
    ((a/exprTry inner)
     (rd/makeList (list (rd/makeAtom "try") (lowerExpr inner))))
    ((a/exprBlock exprs)
     (rd/makeList (list-cons (rd/makeAtom "do")
                             (map (fn [(e a/AstExpr)] -> rd/SExpr (lowerExpr e)) exprs))))))

(df astToSexpr [(expr a/AstExpr)] -> rd/SExpr
  :d "Converts typed AstExpr to canonical SExpr."
  (lowerExpr expr))

(df liftBindingPair [(bNode rd/SExpr)] -> (Pair a/AstPattern a/AstExpr)
  :d "Lifts an SExpr representing a let binding pair."
  (let [(bItems (sexprItems bNode))]
    (pair (liftPattern (nthExpr bItems 0))
          (liftExpr (nthExpr bItems 1)))))

(df liftMatchArmForm [(aNode rd/SExpr)] -> a/AstMatchArm
  :d "Lifts an SExpr representing a match arm."
  (let [(aItems (sexprItems aNode))
        (pat (liftPattern (nthExpr aItems 0)))
        (body (if (<= (list-length aItems) 2)
                (liftExpr (nthExpr aItems 1))
                (a/exprBlock (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e))
                                  (tailExprs aItems)))))]
    (a/matchArm pat body)))

(df liftExpr [(s rd/SExpr)] -> a/AstExpr
  :d "Converts generic SExpr to typed AstExpr node."
  (mt s
    ((rd/sexprAtom v)
     (mt (liftLit v)
       ((some lit) (a/exprLit lit))
       ((none)     (a/exprIdent v))))
    ((rd/sexprVect items)
     (if (list-empty? items)
       (a/exprBlock (list))
       (a/exprBlock (map (fn [(it rd/SExpr)] -> a/AstExpr (liftExpr it)) items))))
    ((rd/sexprList items)
     (if (list-empty? items)
       (a/exprLit (a/litUnit))
       (let [(headNode (nthExpr items 0))
             (h (rd/sexprHead headNode))]
         (cond
           ((string-starts-with? h ".-")
            (let [(field (option-or (string-slice h 2 (string-length h)) ""))
                  (target (liftExpr (nthExpr items 1)))]
              (a/exprMember target field)))
           ((= h "if")
            (let [(c (liftExpr (nthExpr items 1)))
                  (t (liftExpr (nthExpr items 2)))
                  (e (liftExpr (nthExpr items 3)))]
              (a/exprIf c t e)))
           ((= h "let")
            (let [(bindingsNode (nthExpr items 1))
                  (rawBindings (sexprItems bindingsNode))
                  (bindings (map liftBindingPair rawBindings))
                  (bodyNodes (if (> (list-length items) 2)
                               (option-or (list-slice items 2 (list-length items)) (list))
                               (list)))
                  (body (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) bodyNodes))]
              (a/exprLet bindings body)))
           ((or (= h "match") (= h "mt"))
            (let [(target (liftExpr (nthExpr items 1)))
                  (armNodes (if (> (list-length items) 2)
                              (option-or (list-slice items 2 (list-length items)) (list))
                              (list)))
                  (arms (map liftMatchArmForm armNodes))]
              (a/exprMatch target arms)))
           ((= h "do")
            (let [(formNodes (tailExprs items))]
              (a/exprBlock (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) formNodes))))
           ((= h "try")
            (let [(inner (liftExpr (nthExpr items 1)))]
              (a/exprTry inner)))
           (:else
            (let [(func (liftExpr headNode))
                  (args (map (fn [(e rd/SExpr)] -> a/AstExpr (liftExpr e)) (tailExprs items)))]
              (a/exprCall func args)))))))))

(df sexprToAst [(s rd/SExpr)] -> a/AstExpr
  :d "Converts generic SExpr to typed AstExpr."
  (liftExpr s))
