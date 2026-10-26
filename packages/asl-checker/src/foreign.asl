(module asl-checker/foreign
  :x [ForeignSig ForeignSpec argKinds returnKinds aslTypeOfKind parseSig cArgCount resultInner literalText libName? foreignCall? specOfTexts specOfCall specOfBody withReturnMode foreignDiags]
  :i [(types :a ty) (ast :a a) (reader :a rd)])

(schema ForeignSig
  (:f args (List String))
  (:f ret String))

(schema ForeignSpec
  (:f lib String)
  (:f symbol String)
  (:f sig ForeignSig))

fn argKinds -> (List String)
  (list "i32" "u32" "i64" "u64" "f64" "bool" "cstr" "str" "str32" "bytes" "bytes32")

fn returnKinds -> (List String)
  (list "i32" "u32" "i64" "u64" "f64" "bool" "cstr" "void")

fn aslTypeOfKind kind: String -> String
  (cond
    ((or (= kind "i32") (or (= kind "u32") (or (= kind "i64") (= kind "u64")))) "Int64")
    ((= kind "f64") "Float64")
    ((= kind "bool") "Bool")
    ((or (= kind "cstr") (or (= kind "str") (= kind "str32"))) "String")
    ((or (= kind "bytes") (= kind "bytes32")) "Bytes")
    ((= kind "void") "Unit")
    (else ""))

fn cArgCount kind: String -> Int64
  (if (or (= kind "str") (or (= kind "str32") (or (= kind "bytes") (= kind "bytes32")))) 2 1)

fn words text: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace text "\t" " ") "\n" " ") " "))

fn parseSig text: String -> (Result ForeignSig String)
  (let [(sides (stringSplit text "->"))]
    (if (!= (listLength sides) 2)
      (err (str "the signature \"" text "\" needs exactly one ->, as in \"f64 -> f64\""))
      (let [(args (words (optionOr (listGet sides 0) "")))
            (rets (words (optionOr (listGet sides 1) "")))
            (badArgs (filter (fn [(k String)] -> Bool (not (listContains? (argKinds) k))) args))]
        (cond
          ((not (listEmpty? badArgs)) (err (str "unknown C argument type " (optionOr (listHead badArgs) "") "; use one of " (stringJoin (argKinds) " "))))
          ((!= (listLength rets) 1) (err (str "the signature \"" text "\" needs one C result type after ->")))
          ((not (listContains? (returnKinds) (optionOr (listHead rets) ""))) (err (str "unknown C result type " (optionOr (listHead rets) "") "; use one of " (stringJoin (returnKinds) " "))))
          (else (ok (ForeignSig :args args :ret (optionOr (listHead rets) ""))))))))

fn normalType text: String -> String
  (stringReplace (stringReplace (stringJoin (words text) " ") "( " "(") " )" ")")

fn resultInner text: String -> (Option String)
  (let [(t (normalType text))]
    (if (and (stringStartsWith? t "(Result ") (stringEndsWith? t " String)"))
      (let [(inner (optionOr (stringSlice t 8 (- (stringLength t) 8)) ""))]
        (if (or (stringEmpty? inner) (stringContains? inner " ")) (none) (some inner)))
      (none)))

fn literalText e: rd/SExpr -> (Option String)
  (match e
    ((rd/sexprAtom v)
      (let [(n (stringLength v))]
        (if (and (>= n 2) (and (stringStartsWith? v "\"") (stringEndsWith? v "\"")))
          (let [(inner (optionOr (stringSlice v 1 (- n 1)) ""))]
            (if (or (stringContains? inner "\\") (stringContains? inner "\"")) (none) (some inner)))
          (none))))
    (_ (none)))

fn foreignCall? e: rd/SExpr -> Bool
  (match e
    ((rd/sexprList items) (and (match (listHead items) ((some h) (= (rd/sexprHead h) "foreign")) ((none) false))
                               (match (listGet items 1) ((some first) (some? (literalText first))) ((none) false))))
    (_ false))

fn libName? s: String -> Bool
  (and (not (stringEmpty? s))
       (and (not (stringStartsWith? s "-"))
            (listAll? (fn [(c String)] -> Bool (or (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.+-" c))) (stringChars s))))

fn symbolName? s: String -> Bool
  (and (not (stringEmpty? s))
       (and (not (stringContains? "0123456789" (optionOr (listHead (stringChars s)) "0")))
            (listAll? (fn [(c String)] -> Bool (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" c)) (stringChars s))))

fn specOfCall e: rd/SExpr -> (Result ForeignSpec String)
  (let [(args (optionOr (listTail (rd/sexprToList e)) (list)))
        (texts (map literalText args))]
    (if (or (!= (listLength args) 3) (listAny? (fn [(t (Option String))] -> Bool (none? t)) texts))
      (err "foreign takes three string literals without escapes: library, C symbol, signature")
      (specOfTexts (optionOr (optionOr (listGet texts 0) (none)) "")
                   (optionOr (optionOr (listGet texts 1) (none)) "")
                   (optionOr (optionOr (listGet texts 2) (none)) ""))))

fn specOfTexts lib: String symbol: String sigText: String -> (Result ForeignSpec String)
  (cond
    ((not (libName? lib)) (err (str "library \"" lib "\" is not a library name ([A-Za-z0-9_.+-], not starting with -)")))
    ((not (symbolName? symbol)) (err (str "symbol \"" symbol "\" is not a C identifier")))
    (else (match (parseSig sigText)
            ((err e) (err e))
            ((ok sig) (ok (ForeignSpec :lib lib :symbol symbol :sig sig))))))

fn specOfBody d: a/DefunNode -> (Option (Result ForeignSpec String))
  (match (listHead d.body)
    ((some only) (if (and (= (listLength d.body) 1) (foreignCall? only)) (some (specOfCall only)) (none)))
    ((none) (none)))

fn withReturnMode d: a/DefunNode -> a/DefunNode
  (match (listHead d.body)
    ((some only) (if (and (= (listLength d.body) 1) (and (foreignCall? only) (= (listLength (rd/sexprToList only)) 4)))
                   (with d :body (list (rd/makeList (listAppend (rd/sexprToList only) (list (rd/makeAtom (if (some? (resultInner d.retType)) "\"result\"" "\"value\"")))))))
                   d))
    ((none) d))

fn countForeign e: rd/SExpr -> Int64
  (match e
    ((rd/sexprAtom _) 0)
    ((rd/sexprList items) (+ (if (foreignCall? e) 1 0) (fold (fn [(n Int64) (x rd/SExpr)] -> Int64 (+ n (countForeign x))) 0 items)))
    ((rd/sexprVect items) (fold (fn [(n Int64) (x rd/SExpr)] -> Int64 (+ n (bindingForeign x))) 0 items)))

fn bindingForeign e: rd/SExpr -> Int64
  (match e
    ((rd/sexprList items) (fold (fn [(n Int64) (x rd/SExpr)] -> Int64 (+ n (countForeign x))) 0 (optionOr (listTail items) (list))))
    (_ (countForeign e)))

fn bodyForeign body: (List rd/SExpr) -> Int64
  (fold (fn [(n Int64) (x rd/SExpr)] -> Int64 (+ n (countForeign x))) 0 body)

fn diagAt code: String message: String path: String pos: (List a/PosForm) -> ty/Diagnostic
  (match (listHead pos)
    ((some p) (ty/Diagnostic :code code :message message :msg message :line p.line :col p.col :path path))
    ((none) (ty/Diagnostic :code code :message message :msg message :line 1 :col 1 :path path)))

fn paramDiags d: a/DefunNode sig: ForeignSig -> (List String)
  (if (!= (listLength d.params) (listLength sig.args))
    (list (str d.name " has " (stringFromInt64 (listLength d.params)) " parameter(s) but its C signature has " (stringFromInt64 (listLength sig.args))))
    (fold (fn [(acc (List String)) (i Int64)] -> (List String)
            (let [(p (optionOr (listGet d.params i) (a/Param :name "" :type "")))
                  (kind (optionOr (listGet sig.args i) ""))
                  (want (aslTypeOfKind kind))]
              (if (= (normalType p.type) want)
                acc
                (listAppend acc (list (str "parameter " p.name " of " d.name " is " (normalType p.type) " but C type " kind " crosses as " want))))))
          (list) (range 0 (listLength d.params))))

fn returnDiags d: a/DefunNode sig: ForeignSig -> (List String)
  (let [(declared (normalType d.retType))
        (base (optionOr (resultInner declared) declared))
        (want (aslTypeOfKind sig.ret))]
    (if (= base want)
      (list)
      (list (str d.name " returns " declared " but C result " sig.ret " crosses as " want " or (Result " want " String)"))))

fn defunDiags d: a/DefunNode path: String -> (List ty/Diagnostic)
  (let [(n (bodyForeign d.body))]
    (if (= n 0)
      (list)
      (match (specOfBody d)
        ((none) (list (diagAt "ERR_FOREIGN_PLACE" (str "foreign must be the whole body of a top-level fn; " d.name " uses it inside other code") path d.bodyPos)))
        ((some parsed) (match parsed
          ((err e) (list (diagAt "ERR_FOREIGN_SIG" (str d.name ": " e) path d.bodyPos)))
          ((ok spec)
          (let [(effect (if d.effect (list) (list (diagAt "ERR_FOREIGN_EFFECT" (str d.name " calls C symbol " spec.symbol " and must be marked ! (fn ! " d.name " ...)") path d.bodyPos))))
                (generic (if (listEmpty? d.typeVars) (list) (list (diagAt "ERR_FOREIGN_SIG" (str d.name ": a foreign fn takes no type variables") path d.bodyPos))))
                (shapes (map (fn [(m String)] -> ty/Diagnostic (diagAt "ERR_FOREIGN_SIG" m path d.bodyPos)) (listAppend (paramDiags d spec.sig) (returnDiags d spec.sig))))]
            (listAppend effect (listAppend generic shapes)))))))))

fn definesForeign? forms: (List a/TopForm) -> Bool
  (listAny? (fn [(t a/TopForm)] -> Bool (match t ((a/topDefun d) (= d.name "foreign")) (_ false))) forms)

fn foreignDiags forms: (List a/TopForm) path: String -> (List ty/Diagnostic)
  (if (definesForeign? forms)
    (list)
    (fold (fn [(acc (List ty/Diagnostic)) (t a/TopForm)] -> (List ty/Diagnostic)
            (match t
              ((a/topDefun d) (listAppend acc (defunDiags d path)))
              ((a/topExpr p) (if (> (countForeign p.expr) 0)
                               (listAppend acc (list (diagAt "ERR_FOREIGN_PLACE" "foreign must be the whole body of a top-level fn, not a top-level expression" path (list p))))
                               acc))
              (_ acc)))
          (list) forms))
