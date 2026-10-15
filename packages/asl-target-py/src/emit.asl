(module asl-target-py/emit
  :x [pyIdent emitPyModule supportedBuiltins]
  :i [(asl-ir/types :a ty) (asl-ir/blocks :a bl) (asl-target-py/runtime :a rt)])

fn pyIdent prefix: String name: String -> String
  (bl/mangle prefix "_" name)

fn v name: String -> String
  (pyIdent "v_" name)

fn f name: String -> String
  (pyIdent "f_" name)

fn args xs: (List String) -> String
  (stringJoin (map v xs) ", ")

fn floatLiteral x: Float64 -> String
  (let [(s (stringFromFloat64 x))]
    (cond ((= s "inf") "float(\"inf\")") ((= s "-inf") "float(\"-inf\")") ((= s "nan") "float(\"nan\")") (else s)))

fn constText c: ty/SsaConst -> String
  (mt c
    ((ty/constInt n) (stringFromInt64 n))
    ((ty/constFloat x) (floatLiteral x))
    ((ty/constBool b) (if b "True" "False"))
    ((ty/constStr i) (str "_S[" (stringFromInt64 i) "]"))
    ((ty/constUnit) "UNIT")
    ((ty/constKeyword name) (str "_kw(" (bl/quoted name) ")"))
    ((ty/constSymbol name) (str "_sym(" (bl/quoted name) ")")))

fn infix op: String xs: (List String) -> String
  (str "(" (stringJoin (map v xs) (str " " op " ")) ")")

fn fitted op: String xs: (List String) -> String
  (str "_fit(" (infix op xs) ", " (bl/quoted op) ")")

fn primText name: String xs: (List String) -> String
  (cond
    ((or (= name "eqInt") (or (= name "eqBool") (= name "eqFloat"))) (infix "==" xs))
    ((or (= name "neInt") (or (= name "neBool") (= name "neFloat"))) (infix "!=" xs))
    ((or (= name "ltInt") (= name "ltFloat")) (infix "<" xs))
    ((or (= name "leInt") (= name "leFloat")) (infix "<=" xs))
    ((or (= name "gtInt") (= name "gtFloat")) (infix ">" xs))
    ((or (= name "geInt") (= name "geFloat")) (infix ">=" xs))
    ((or (= name "addInt") (= name "addIntHost")) (fitted "+" xs))
    ((or (= name "subInt") (= name "subIntHost")) (fitted "-" xs))
    ((or (= name "mulInt") (= name "mulIntHost")) (fitted "*" xs))
    ((= name "andBool") (infix "and" xs))
    ((= name "orBool") (infix "or" xs))
    ((= name "notBool") (str "(not " (args xs) ")"))
    ((= name "addFloat") (infix "+" xs))
    ((= name "subFloat") (infix "-" xs))
    ((= name "mulFloat") (infix "*" xs))
    ((= name "negFloat") (str "(-" (args xs) ")"))
    ((= name "intToFloat") (str "float(" (args xs) ")"))
    (else (str "prims[" (bl/quoted name) "](" (args xs) ")")))

fn supportedBuiltins -> (List String)
  (rt/builtinNames)

fn entryCall name: String xs: (List String) -> (Result String String)
  (if (listContains? (rt/entryNames) name) (ok (str "entries[" (bl/quoted name) "](" (args xs) ")")) (err name))

fn opText op: ty/SsaOp -> (Result String String)
  (mt op
    ((ty/opConst c) (ok (constText c)))
    ((ty/opCall callee xs) (ok (str (f callee) "(" (args xs) ")")))
    ((ty/opBuiltin name xs) (entryCall name xs))
    ((ty/opEntry name xs) (entryCall name xs))
    ((ty/opCallClosure c xs) (ok (str "_call(" (v c) (if (listEmpty? xs) "" (str ", " (args xs))) ")")))
    ((ty/opMakeClosure callee caps) (ok (if (listEmpty? caps) (f callee) (str "_closure(" (f callee) ", " (args caps) ")"))))
    ((ty/opConstruct typeName variant fields) (ok (str "Variant(" (bl/quoted typeName) ", " (bl/quoted variant) ", [" (args fields) "])")))
    ((ty/opRecord schemaName keys values) (ok (str "Rec(" (bl/quoted schemaName) ", [" (stringJoin (map bl/quoted keys) ", ") "], [" (args values) "])")))
    ((ty/opField base field) (ok (str (v base) ".d[" (bl/quoted field) "]")))
    ((ty/opVariantField base i) (ok (str (v base) ".fields[" (stringFromInt64 i) "]")))
    ((ty/opList items) (ok (str "_list(" (args items) ")")))
    ((ty/opGlobal name) (err (str "global " name)))
    ((ty/opLoadGlobal name) (err (str "load-global " name)))
    ((ty/opBox x) (ok (v x)))
    ((ty/opUnbox x) (ok (v x)))
    ((ty/opPrim name xs) (ok (primText name xs))))

fn line depth: Int64 text: String -> String
  (str (stringRepeat "    " depth) text "\n")

fn assignAll depth: Int64 targets: (List String) values: (List String) -> String
  (if (listEmpty? targets) "" (line depth (str (args targets) " = " (args values))))

fn edgeText ctx: bl/BlockCtx depth: Int64 e: ty/SsaEdge -> String
  (str (assignAll depth (optionOr (mapGet ctx.params0 e.target) []) e.args)
       (line depth (str "_b = " (bl/labelIndex ctx e.target)))
       (line depth "continue"))

fn caseText ctx: bl/BlockCtx depth: Int64 first: Bool k: ty/SsaCase -> String
  (str (line depth (str (if first "if" "elif") " _n == " (bl/quoted k.variant) ":")) (edgeText ctx (+ depth 1) k.edge))

fn termText ctx: bl/BlockCtx depth: Int64 t: ty/SsaTerm -> String
  (mt t
    ((ty/termReturn x) (line depth (str "return " (v x))))
    ((ty/termJump e) (edgeText ctx depth e))
    ((ty/termBranch c a b) (str (line depth (str "if " (v c) ":")) (edgeText ctx (+ depth 1) a) (line depth "else:") (edgeText ctx (+ depth 1) b)))
    ((ty/termSwitch s typeName cases d)
      (str (line depth (str "_n = " (v s) ".name"))
           (stringJoin (map (fn [(p (Pair Int64 ty/SsaCase))] -> String (caseText ctx depth (= (pairFirst p) 0) (pairSecond p))) (enumerate cases)) "")
           (if (listEmpty? cases) "" (line depth "else:"))
           (mt d ((some e) (edgeText ctx (if (listEmpty? cases) depth (+ depth 1)) e)) ((none) (line (if (listEmpty? cases) depth (+ depth 1)) "_unreachable()")))))
    ((ty/termUnreachable) (line depth "_unreachable()")))

fn instrLine i: ty/SsaInstr -> (Result String String)
  (mt (opText i.op) ((ok text) (ok (line 3 (str (v i.dest) " = " text)))) ((err e) (err e)))

fn blockText ctx: bl/BlockCtx index: Int64 b: ty/SsaBlock -> (Result String (List String))
  (let [(head (line 2 (str (if (= index 0) "if" "elif") " _b == " (stringFromInt64 index) ":")))]
    (mt (bl/tailCall ctx b)
      ((some xs)
        (mt (bl/collect (map instrLine (optionOr (listSlice b.instrs 0 (- (listLength b.instrs) 1)) [])))
          ((err es) (err es))
          ((ok lines) (ok (str head (stringJoin lines "") (assignAll 3 ctx.params xs) (line 3 "_b = 0") (line 3 "continue"))))))
      ((none)
        (mt (bl/collect (map instrLine b.instrs))
          ((err es) (err es))
          ((ok lines) (ok (str head (stringJoin lines "") (termText ctx 3 b.term))))))))

fn functionText fn0: ty/SsaFunction -> (Result String (List String))
  (let [(ctx (bl/blockCtx fn0))
        (blocks (map (fn [(p (Pair Int64 ty/SsaBlock))] -> (Result String (List String)) (blockText ctx (pairFirst p) (pairSecond p))) (enumerate fn0.blocks)))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] blocks))]
    (if (not (listEmpty? bad))
      (err bad)
      (ok (str "def " (f fn0.name) "(" (args (listAppend (bl/paramNames fn0.captures) (bl/paramNames fn0.params))) "):\n"
               (line 1 "_b = 0")
               (line 1 "while True:")
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) s) ((err _) ""))) blocks) "")
               (line 2 "else:")
               (line 3 "_unreachable()")))))

fn plainName? s: String -> Bool
  (and (not (stringEmpty? s))
    (and (not (and (>= (optionOr (stringSlice s 0 1) "") "0") (<= (optionOr (stringSlice s 0 1) "") "9")))
      (listAll? (fn [(c String)] -> Bool (or (= c "_") (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9")))))) (stringChars s))))

fn exportPairs m: ty/SsaModule -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (fn0 ty/SsaFunction)] -> (List (Pair String String))
          (mt (bl/exportName m.name fn0.name) ((some short) (listAppend acc [(pair short (f fn0.name))])) ((none) acc)))
        [] m.functions)

fn exportsText m: ty/SsaModule -> String
  (let [(pairs (exportPairs m))]
    (str (stringJoin (map (fn [(p (Pair String String))] -> String (if (plainName? (pairFirst p)) (str (pairFirst p) " = " (pairSecond p) "\n") "")) pairs) "")
         "exports = {" (stringJoin (map (fn [(p (Pair String String))] -> String (str (bl/quoted (pairFirst p)) ": " (pairSecond p))) pairs) ", ") "}\n"
         (if (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) "main")) pairs)
           "\nif __name__ == \"__main__\":\n    _run_main(main)\n"
           "")))

fn emitPyModule m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (let [(fns (map functionText m.functions))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] fns))]
    (if (not (listEmpty? bad))
      (err (map (fn [(name String)] -> ty/IrDiag (ty/makeIrDiag "ERR_CAPABILITY_ABSENT" (str name " is absent on target py") m.name)) bad))
      (ok (str "# Generated by asl-target-py from " m.name ".\n"
               (rt/runtimeText)
               "_S = [" (stringJoin (map bl/quoted m.strings) ", ") "]\n\n"
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) (str s "\n")) ((err _) ""))) fns) "")
               (exportsText m)))))
