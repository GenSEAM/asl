(module asl-target-js/emit
  :x [jsIdent jsString emitJsModule supportedBuiltins]
  :i [(asl-ir/types :a ty) (asl-target-js/runtime :a rt)])

fn identChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9"))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn escapeChar c: String -> String
  (if (identChar? c) c (let [(n (charCode c))] (str "$" (hexDigit (/ n 16)) (hexDigit (mod n 16)))))

fn jsIdent prefix: String name: String -> String
  (str prefix (stringJoin (map escapeChar (stringChars name)) ""))

fn replaceIn s: String old: String new: String -> String
  (if (stringContains? s old) (stringReplace s old new) s)

fn jsString s: String -> String
  (str "\"" (replaceIn (replaceIn (replaceIn (replaceIn (replaceIn s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

fn v name: String -> String
  (jsIdent "v_" name)

fn f name: String -> String
  (jsIdent "f_" name)

fn args xs: (List String) -> String
  (stringJoin (map v xs) ", ")

fn floatLiteral x: Float64 -> String
  (let [(s (stringFromFloat64 x))]
    (cond ((= s "inf") "Infinity") ((= s "-inf") "-Infinity") ((= s "nan") "NaN") (else s)))

fn constText c: ty/SsaConst -> String
  (mt c
    ((ty/constInt n) (str (stringFromInt64 n) "n"))
    ((ty/constFloat x) (floatLiteral x))
    ((ty/constBool b) (if b "true" "false"))
    ((ty/constStr i) (str "$S[" (stringFromInt64 i) "]"))
    ((ty/constUnit) "$.UNIT")
    ((ty/constKeyword name) (str "$.kw(" (jsString name) ")"))
    ((ty/constSymbol name) (str "$.sym(" (jsString name) ")")))

fn infix op: String xs: (List String) -> String
  (str "(" (stringJoin (map v xs) (str " " op " ")) ")")

fn primText name: String xs: (List String) -> String
  (cond
    ((or (= name "eqInt") (or (= name "eqBool") (= name "eqFloat"))) (infix "===" xs))
    ((or (= name "neInt") (or (= name "neBool") (= name "neFloat"))) (infix "!==" xs))
    ((or (= name "ltInt") (= name "ltFloat")) (infix "<" xs))
    ((or (= name "leInt") (= name "leFloat")) (infix "<=" xs))
    ((or (= name "gtInt") (= name "gtFloat")) (infix ">" xs))
    ((or (= name "geInt") (= name "geFloat")) (infix ">=" xs))
    ((= name "andBool") (infix "&&" xs))
    ((= name "orBool") (infix "||" xs))
    ((= name "notBool") (str "(!" (args xs) ")"))
    ((= name "addFloat") (infix "+" xs))
    ((= name "subFloat") (infix "-" xs))
    ((= name "mulFloat") (infix "*" xs))
    ((= name "divFloat") (infix "/" xs))
    ((= name "negFloat") (str "(-" (args xs) ")"))
    ((= name "intToFloat") (str "Number(" (args xs) ")"))
    (else (str "$.prims." name "(" (args xs) ")")))

fn supportedBuiltins -> (List String)
  (rt/builtinNames)

fn closureText callee: String caps: (List String) -> String
  (if (listEmpty? caps) (f callee) (str "((...a) => " (f callee) "(" (args caps) ", ...a))"))

fn opText op: ty/SsaOp -> (Result String String)
  (mt op
    ((ty/opConst c) (ok (constText c)))
    ((ty/opCall callee xs) (ok (str (f callee) "(" (args xs) ")")))
    ((ty/opBuiltin name xs) (if (listContains? (rt/builtinNames) name) (ok (str "$.builtins[" (jsString name) "](" (args xs) ")")) (err name)))
    ((ty/opEntry name xs) (if (listContains? (rt/entryNames) name) (ok (str "$.entries[" (jsString name) "](" (args xs) ")")) (err name)))
    ((ty/opCallClosure c xs) (ok (str "$.callClosure(" (v c) (if (listEmpty? xs) "" (str ", " (args xs))) ")")))
    ((ty/opMakeClosure callee caps) (ok (closureText callee caps)))
    ((ty/opConstruct typeName variant fields) (ok (str "new $.Variant(" (jsString typeName) ", " (jsString variant) ", [" (args fields) "])")))
    ((ty/opRecord schemaName keys values) (ok (str "new $.Rec(" (jsString schemaName) ", [" (stringJoin (map jsString keys) ", ") "], [" (args values) "])")))
    ((ty/opField base field) (ok (str (v base) "[" (jsString field) "]")))
    ((ty/opVariantField base i) (ok (str (v base) ".fields[" (stringFromInt64 i) "]")))
    ((ty/opList items) (ok (str "$.list(" (args items) ")")))
    ((ty/opGlobal name) (err (str "global " name)))
    ((ty/opLoadGlobal name) (err (str "load-global " name)))
    ((ty/opBox x) (ok (v x)))
    ((ty/opUnbox x) (ok (v x)))
    ((ty/opPrim name xs) (ok (primText name xs))))

(schema Ctx (:f self String) (:f params (List String)) (:f labels (Map String Int64)) (:f params0 (Map String (List String))) (:f returners (List String)))

fn labelIndex ctx: Ctx label: String -> String
  (stringFromInt64 (optionOr (mapGet ctx.labels label) -1))

fn assignAll targets: (List String) values: (List String) -> String
  (if (listEmpty? targets)
    ""
    (let [(temps (map (fn [(t String)] -> String (str "t" (v t))) targets))]
      (str "const [" (stringJoin temps ", ") "] = [" (args values) "]; "
           (stringJoin (map (fn [(t String)] -> String (str (v t) " = t" (v t) "; ")) targets) ""))))

fn edgeText ctx: Ctx e: ty/SsaEdge -> String
  (str "{ " (assignAll (optionOr (mapGet ctx.params0 e.target) []) e.args) "$b = " (labelIndex ctx e.target) "; continue; }")

fn termText ctx: Ctx t: ty/SsaTerm -> String
  (mt t
    ((ty/termReturn x) (str "return " (v x) ";"))
    ((ty/termJump e) (edgeText ctx e))
    ((ty/termBranch c a b) (str "if (" (v c) ") " (edgeText ctx a) " else " (edgeText ctx b)))
    ((ty/termSwitch s typeName cases d)
      (str "switch (" (v s) ".name) { "
           (stringJoin (map (fn [(k ty/SsaCase)] -> String (str "case " (jsString k.variant) ": " (edgeText ctx k.edge) " ")) cases) "")
           "default: " (mt d ((some e) (edgeText ctx e)) ((none) "$.unreachable();")) " }"))
    ((ty/termUnreachable) "$.unreachable();"))

fn soleParam b: ty/SsaBlock -> String
  (optionOr (listHead (map (fn [(p ty/SsaParam)] -> String p.name) b.params)) "")

fn forwards? known: (List String) b: ty/SsaBlock -> Bool
  (and (= (listLength b.params) 1)
    (and (listEmpty? b.instrs)
      (mt b.term
        ((ty/termReturn x) (= x (soleParam b)))
        ((ty/termJump e) (and (listContains? known e.target) (= e.args [(soleParam b)])))
        (_ false))))

fn returners known: (List String) blocks: (List ty/SsaBlock) -> (List String)
  (let [(next (map (fn [(b ty/SsaBlock)] -> String b.label) (filter (fn [(b ty/SsaBlock)] -> Bool (forwards? known b)) blocks)))]
    (if (= (listLength next) (listLength known)) known (returners next blocks)))

fn tailCall ctx: Ctx b: ty/SsaBlock -> (Option (List String))
  (mt (listLast b.instrs)
    ((none) (none))
    ((some last)
      (mt last.op
        ((ty/opCall callee xs)
          (let [(returnsIt (mt b.term
                             ((ty/termReturn x) (= x last.dest))
                             ((ty/termJump e) (and (listContains? ctx.returners e.target) (= e.args [last.dest])))
                             (_ false)))]
            (if (and returnsIt (and (= callee ctx.self) (= (listLength xs) (listLength ctx.params)))) (some xs) (none))))
        (_ (none)))))

fn instrLine i: ty/SsaInstr -> (Result String String)
  (mt (opText i.op) ((ok text) (ok (str (v i.dest) " = " text "; "))) ((err e) (err e)))

fn collect results: (List (Result String String)) -> (Result (List String) (List String))
  (let [(bad (fold (fn [(acc (List String)) (r (Result String String))] -> (List String) (mt r ((err e) (cons e acc)) ((ok _) acc))) [] results))]
    (if (listEmpty? bad) (ok (map (fn [(r (Result String String))] -> String (mt r ((ok s) s) ((err _) ""))) results)) (err (listReverse bad))))

fn blockText ctx: Ctx index: Int64 b: ty/SsaBlock -> (Result String (List String))
  (mt (tailCall ctx b)
    ((some xs)
      (mt (collect (map instrLine (optionOr (listSlice b.instrs 0 (- (listLength b.instrs) 1)) [])))
        ((err es) (err es))
        ((ok lines) (ok (str "case " (stringFromInt64 index) ": { " (stringJoin lines "") (assignAll ctx.params xs) "$b = 0; continue; }")))))
    ((none)
      (mt (collect (map instrLine b.instrs))
        ((err es) (err es))
        ((ok lines) (ok (str "case " (stringFromInt64 index) ": { " (stringJoin lines "") (termText ctx b.term) " }"))))))

fn paramNames ps: (List ty/SsaParam) -> (List String)
  (map (fn [(p ty/SsaParam)] -> String p.name) ps)

fn locals fn0: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
          (listAppend acc (listAppend (paramNames b.params) (map (fn [(i ty/SsaInstr)] -> String i.dest) b.instrs))))
        [] fn0.blocks)

fn functionText fn0: ty/SsaFunction -> (Result String (List String))
  (let [(indexed (enumerate fn0.blocks))
        (ctx (Ctx :self fn0.name :params (paramNames fn0.params)
                  :labels (fold (fn [(m (Map String Int64)) (p (Pair Int64 ty/SsaBlock))] -> (Map String Int64) (mapSet m (pairSecond p).label (pairFirst p))) (mapEmpty) indexed)
                  :params0 (fold (fn [(m (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String)) (mapSet m b.label (paramNames b.params))) (mapEmpty) fn0.blocks)
                  :returners (returners [] fn0.blocks)))
        (blocks (map (fn [(p (Pair Int64 ty/SsaBlock))] -> (Result String (List String)) (blockText ctx (pairFirst p) (pairSecond p))) indexed))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] blocks))
        (vars (locals fn0))]
    (if (not (listEmpty? bad))
      (err bad)
      (ok (str "function " (f fn0.name) "(" (args (listAppend (paramNames fn0.captures) (paramNames fn0.params))) ") {\n"
               (if (listEmpty? vars) "" (str "  let " (args vars) ";\n"))
               "  let $b = 0;\n  for (;;) switch ($b) {\n"
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) (str "    " s "\n")) ((err _) ""))) blocks) "")
               "    default: $.unreachable();\n  }\n}\n"))))

fn exportName moduleName: String fnName: String -> (Option String)
  (let [(prefix (str moduleName "."))]
    (if (and (stringStartsWith? fnName prefix) (not (stringContains? fnName "@")))
      (stringSlice fnName (stringLength prefix) (stringLength fnName))
      (none)))

fn exportsText m: ty/SsaModule -> String
  (let [(pairs (fold (fn [(acc (List String)) (fn0 ty/SsaFunction)] -> (List String)
                       (mt (exportName m.name fn0.name) ((some short) (cons (str (f fn0.name) " as " (jsString short)) acc)) ((none) acc)))
                     [] m.functions))]
    (str "export { " (stringJoin (listReverse pairs) ", ") " };\n"))

fn emitJsModule m: ty/SsaModule -> (Result String (List ty/IrDiag))
  (let [(fns (map functionText m.functions))
        (bad (fold (fn [(acc (List String)) (r (Result String (List String)))] -> (List String) (mt r ((err es) (listAppend acc es)) ((ok _) acc))) [] fns))]
    (if (not (listEmpty? bad))
      (err (map (fn [(name String)] -> ty/IrDiag (ty/makeIrDiag "ERR_CAPABILITY_ABSENT" (str name " is absent on target js") m.name)) bad))
      (ok (str "// Generated by asl-target-js from " m.name ".\n"
               (rt/runtimeText)
               "const $S = [" (stringJoin (map jsString m.strings) ", ") "];\n"
               (stringJoin (map (fn [(r (Result String (List String)))] -> String (mt r ((ok s) s) ((err _) ""))) fns) "")
               (exportsText m)
               "export const setOutput = $.setOutput;\nexport const AslTrap = $.AslTrap;\n"))))
