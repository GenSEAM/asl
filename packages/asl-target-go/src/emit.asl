(module asl-target-go/emit
  :x [goIdent emitGoModule supportedBuiltins]
  :i [(asl-ir/types :a ty) (asl-ir/blocks :a bl) (asl-target-go/runtime :a rt)])

fn goIdent prefix: String name: String -> String
  (bl/mangle prefix "_" name)

fn v name: String -> String
  (goIdent "v_" name)

fn f name: String -> String
  (goIdent "f_" name)

fn e name: String -> String
  (goIdent "e_" name)

fn args xs: (List String) -> String
  (stringJoin (map v xs) ", ")

fn floatLiteral x: Float64 -> String
  (let [(s (stringFromFloat64 x))]
    (cond ((= s "inf") "math.Inf(1)") ((= s "-inf") "math.Inf(-1)") ((= s "nan") "math.NaN()") (else (str "float64(" s ")"))))

fn constText c: ty/SsaConst -> String
  (mt c
    ((ty/constInt n) (str "int64(" (stringFromInt64 n) ")"))
    ((ty/constFloat x) (floatLiteral x))
    ((ty/constBool b) (if b "true" "false"))
    ((ty/constStr i) (str "S[" (stringFromInt64 i) "]"))
    ((ty/constUnit) "Unit")
    ((ty/constKeyword name) (str "kw(" (bl/quoted name) ")"))
    ((ty/constSymbol name) (str "sym(" (bl/quoted name) ")")))

fn suffixType name: String -> String
  (cond ((stringEndsWith? name "Int") "int64") ((stringEndsWith? name "Float") "float64") (else "bool"))

fn typed name: String xs: (List String) -> (List String)
  (map (fn [(x String)] -> String (str (v x) ".(" (suffixType name) ")")) xs)

fn infix op: String name: String xs: (List String) -> String
  (str "(" (stringJoin (typed name xs) (str " " op " ")) ")")

fn runtimeCall fnName: String xs: (List String) -> String
  (str fnName "(" (args xs) ")")

fn comparison name: String -> (Option String)
  (cond
    ((stringStartsWith? name "eq") (some "=="))
    ((stringStartsWith? name "ne") (some "!="))
    ((stringStartsWith? name "lt") (some "<"))
    ((stringStartsWith? name "le") (some "<="))
    ((stringStartsWith? name "gt") (some ">"))
    ((stringStartsWith? name "ge") (some ">="))
    (else (none)))

fn primText name: String xs: (List String) -> (Result String String)
  (mt (comparison name)
    ((some op) (ok (infix op name xs)))
    ((none)
      (cond
        ((or (= name "addInt") (= name "addIntHost")) (ok (runtimeCall "addInt" xs)))
        ((or (= name "subInt") (= name "subIntHost")) (ok (runtimeCall "subInt" xs)))
        ((or (= name "mulInt") (= name "mulIntHost")) (ok (runtimeCall "mulInt" xs)))
        ((= name "divIntHost") (ok (runtimeCall "divInt" xs)))
        ((= name "modIntHost") (ok (runtimeCall "modInt" xs)))
        ((= name "negIntHost") (ok (runtimeCall "negInt" xs)))
        ((= name "quotInt") (ok (runtimeCall "quotInt" xs)))
        ((= name "remInt") (ok (runtimeCall "remInt" xs)))
        ((= name "floatToInt") (ok (runtimeCall "floatToInt" xs)))
        ((= name "andBool") (ok (infix "&&" name xs)))
        ((= name "orBool") (ok (infix "||" name xs)))
        ((= name "notBool") (ok (str "(!" (v (optionOr (listHead xs) "")) ".(bool))")))
        ((= name "addFloat") (ok (infix "+" name xs)))
        ((= name "subFloat") (ok (infix "-" name xs)))
        ((= name "mulFloat") (ok (infix "*" name xs)))
        ((= name "divFloat") (ok (infix "/" name xs)))
        ((= name "negFloat") (ok (str "(-" (v (optionOr (listHead xs) "")) ".(float64))")))
        ((= name "intToFloat") (ok (str "float64(" (v (optionOr (listHead xs) "")) ".(int64))")))
        (else (err (str "prim " name))))))

fn supportedBuiltins -> (List String)
  (rt/builtinNames)

fn entryCall name: String xs: (List String) -> (Result String String)
  (if (listContains? (rt/entryNames) name) (ok (str (e name) "(" (args xs) ")")) (err name))

fn indices n: Int64 -> (List String)
  (map (fn [(i Int64)] -> String (str "a[" (stringFromInt64 i) "]")) (range 0 n))

fn closureText arity: (Map String Int64) callee: String caps: (List String) -> String
  (let [(n (optionOr (mapGet arity callee) 0))
        (capNames (map (fn [(i Int64)] -> String (str "c" (stringFromInt64 i))) (range 0 (listLength caps))))
        (body (str "func(a ...V) V { return " (f callee) "(" (stringJoin (listAppend capNames (indices n)) ", ") ") }"))]
    (if (listEmpty? caps)
      (str "Fn(" body ")")
      (str "func(" (stringJoin capNames ", ") " V) Fn { return " body " }(" (args caps) ")")))

fn opText arity: (Map String Int64) op: ty/SsaOp -> (Result String String)
  (mt op
    ((ty/opConst c) (ok (constText c)))
    ((ty/opCall callee xs) (ok (str (f callee) "(" (args xs) ")")))
    ((ty/opBuiltin name xs) (entryCall name xs))
    ((ty/opEntry name xs) (entryCall name xs))
    ((ty/opCallClosure c xs) (ok (str "call(" (v c) (if (listEmpty? xs) "" (str ", " (args xs))) ")")))
    ((ty/opMakeClosure callee caps) (ok (closureText arity callee caps)))
    ((ty/opConstruct typeName variant fields) (ok (str "&Variant{" (bl/quoted typeName) ", " (bl/quoted variant) ", []V{" (args fields) "}}")))
    ((ty/opRecord schemaName keys values) (ok (str "newRec(" (bl/quoted schemaName) ", []string{" (stringJoin (map bl/quoted keys) ", ") "}, []V{" (args values) "})")))
    ((ty/opField base field) (ok (str "field(" (v base) ", " (bl/quoted field) ")")))
    ((ty/opVariantField base i) (ok (str "vfield(" (v base) ", " (stringFromInt64 i) ")")))
    ((ty/opList items) (ok (str "list(" (args items) ")")))
    ((ty/opGlobal name) (err (str "global " name)))
    ((ty/opLoadGlobal name) (err (str "load-global " name)))
    ((ty/opBox x) (ok (v x)))
    ((ty/opUnbox x) (ok (v x)))
    ((ty/opPrim name xs) (primText name xs)))

fn line depth: Int64 text: String -> String
  (str (stringRepeat "\t" depth) text "\n")

fn assignAll depth: Int64 targets: (List String) values: (List String) -> String
  (if (listEmpty? targets) "" (line depth (str (args targets) " = " (args values))))

fn edgeText ctx: bl/BlockCtx depth: Int64 edge: ty/SsaEdge -> String
  (str (assignAll depth (optionOr (mapGet ctx.params0 edge.target) []) edge.args)
       (line depth (str "b = " (bl/labelIndex ctx edge.target)))
       (line depth "continue"))

fn caseText ctx: bl/BlockCtx depth: Int64 k: ty/SsaCase -> String
  (str (line depth (str "case " (bl/quoted k.variant) ":")) (edgeText ctx (+ depth 1) k.edge))

fn termText ctx: bl/BlockCtx depth: Int64 t: ty/SsaTerm -> String
  (mt t
    ((ty/termReturn x) (line depth (str "return " (v x))))
    ((ty/termJump edge) (edgeText ctx depth edge))
    ((ty/termBranch c a b) (str (line depth (str "if " (v c) ".(bool) {")) (edgeText ctx (+ depth 1) a) (line depth "} else {") (edgeText ctx (+ depth 1) b) (line depth "}")))
    ((ty/termSwitch s typeName cases d)
      (str (line depth (str "switch vname(" (v s) ") {"))
           (stringJoin (map (fn [(k ty/SsaCase)] -> String (caseText ctx depth k)) cases) "")
           (line depth "default:")
           (mt d ((some edge) (edgeText ctx (+ depth 1) edge)) ((none) (line (+ depth 1) "return unreachable()")))
           (line depth "}")))
    ((ty/termUnreachable) (line depth "return unreachable()")))

fn instrLine arity: (Map String Int64) i: ty/SsaInstr -> (Result String String)
  (mt (opText arity i.op) ((ok text) (ok (line 3 (str (v i.dest) " = " text)))) ((err x) (err x)))

fn blockText arity: (Map String Int64) ctx: bl/BlockCtx index: Int64 b: ty/SsaBlock -> (Result String (List String))
  (let [(head (line 2 (str "case " (stringFromInt64 index) ":")))
        (lineOf (fn [(i ty/SsaInstr)] -> (Result String String) (instrLine arity i)))]
    (mt (bl/tailCall ctx b)
      ((some xs)
        (mt (bl/collect (map lineOf (optionOr (listSlice b.instrs 0 (- (listLength b.instrs) 1)) [])))
          ((err es) (err es))
          ((ok lines) (ok (str head (stringJoin lines "") (assignAll 3 ctx.params xs) (line 3 "b = 0") (line 3 "continue"))))))
      ((none)
        (mt (bl/collect (map lineOf b.instrs))
          ((err es) (err es))
          ((ok lines) (ok (str head (stringJoin lines "") (termText ctx 3 b.term))))))))

fn paramList names: (List String) -> String
  (if (listEmpty? names) "" (str (args names) " V"))

fn functionText arity: (Map String Int64) fn0: ty/SsaFunction -> (Result String (List String))
  (let [(ctx (bl/blockCtx fn0))
        (params (listAppend (bl/paramNames fn0.captures) (bl/paramNames fn0.params)))
        (vars (filter (fn [(x String)] -> Bool (not (listContains? params x))) (bl/locals fn0)))
        (blocks (map (fn [(p (Pair Int64 ty/SsaBlock))] -> (Result String (List String)) (blockText arity ctx (pairFirst p) (pairSecond p))) (enumerate fn0.blocks)))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] blocks))]
    (if (not (listEmpty? bad))
      (err bad)
      (ok (str "func " (f fn0.name) "(" (paramList params) ") V {\n"
               (if (listEmpty? vars) "" (str (line 1 (str "var " (args vars) " V")) (line 1 (str "_ = []V{" (args vars) "}"))))
               (line 1 "b := 0")
               (line 1 "for {")
               (line 1 "switch b {")
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) s) ((err _) ""))) blocks) "")
               (line 2 "default:")
               (line 3 "return unreachable()")
               (line 1 "}")
               (line 1 "}")
               "}\n"))))

fn plainName? s: String -> Bool
  (and (not (stringEmpty? s))
    (and (not (and (>= (optionOr (stringSlice s 0 1) "") "0") (<= (optionOr (stringSlice s 0 1) "") "9")))
      (listAll? (fn [(c String)] -> Bool (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9"))))) (stringChars s))))

fn exported s: String -> String
  (str (stringUpper (optionOr (stringSlice s 0 1) "")) (optionOr (stringSlice s 1 (stringLength s)) ""))

fn exportText arity: (Map String Int64) m: ty/SsaModule -> String
  (fold (fn [(acc String) (fn0 ty/SsaFunction)] -> String
          (mt (bl/exportName m.name fn0.name)
            ((some short)
              (if (plainName? short)
                (let [(ps (map (fn [(i Int64)] -> String (str "a" (stringFromInt64 i))) (range 0 (listLength fn0.params))))]
                  (str acc "func " (exported short) "(" (if (listEmpty? ps) "" (str (stringJoin ps ", ") " V")) ") V { return " (f fn0.name) "(" (stringJoin ps ", ") ") }\n"))
                acc))
            ((none) acc)))
        "" m.functions)

fn hasMain? m: ty/SsaModule -> Bool
  (listAny? (fn [(fn0 ty/SsaFunction)] -> Bool (= (bl/exportName m.name fn0.name) (some "main"))) m.functions)

fn entryDecls -> String
  (stringJoin (map (fn [(name String)] -> String (str "var " (e name) " = entries[" (bl/quoted name) "]\n")) (rt/entryNames)) "")

fn emitGoModule pkg: String m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (let [(arity (fold (fn [(acc (Map String Int64)) (fn0 ty/SsaFunction)] -> (Map String Int64) (mapSet acc fn0.name (listLength fn0.params))) (mapEmpty) m.functions))
        (fns (map (fn [(fn0 ty/SsaFunction)] -> (Result String (List String)) (functionText arity fn0)) m.functions))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] fns))]
    (if (not (listEmpty? bad))
      (err (map (fn [(name String)] -> ty/IrDiag (ty/makeIrDiag "ERR_CAPABILITY_ABSENT" (str name " is absent on target go") m.name)) bad))
      (ok (str "// Code generated by asl-target-go from " m.name ". DO NOT EDIT.\n\npackage " pkg "\n\n"
               (rt/runtimeText)
               "\n" (entryDecls)
               "\nvar S = []string{" (stringJoin (map bl/quoted m.strings) ", ") "}\n\n"
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) (str s "\n")) ((err _) ""))) fns) "")
               (exportText arity m)
               (if (and (= pkg "main") (hasMain? m)) "\nfunc main() { runMain(Main) }\n" "")))))
