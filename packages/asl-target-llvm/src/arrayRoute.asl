(module asl-target-llvm/arrayRoute
  :x [arrayCalls routes? routeModule routeLinked routedNames? finishText]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/arrays :a arr)
      (asl-target-llvm/sysRoute :a rt)])

fn arity name: String -> Int64
  (cond
    ((or (stringEndsWith? name "ArrayLen") (or (stringEndsWith? name "ArrayConcat") (stringEndsWith? name "ArraySum"))) 1)
    ((or (stringEndsWith? name "ArrayGet") (or (stringEndsWith? name "ArrayGenerate") (or (stringEndsWith? name "ArrayCountEq") (= name "dot")))) 2)
    ((= name "gemm") 5)
    (else 3))

fn arrayCalls m: ty/SsaModule -> (List (Pair String Int64))
  (fold (fn [(acc (List (Pair String Int64))) (f ty/SsaFunction)] -> (List (Pair String Int64))
          (fold (fn [(acc2 (List (Pair String Int64))) (b ty/SsaBlock)] -> (List (Pair String Int64))
                  (fold (fn [(acc3 (List (Pair String Int64))) (i ty/SsaInstr)] -> (List (Pair String Int64))
                          (match i.op
                            ((ty/opBuiltin n args)
                              (let [(p (pair n (listLength args)))]
                                (if (and (listContains? (arr/arrayBuiltinNames) n) (not (listContains? acc3 p))) (listAppend acc3 (list p)) acc3)))
                            (_ acc3)))
                        acc2 b.instrs))
                acc f.blocks))
        (list) m.functions)

fn routes? m: ty/SsaModule -> Bool
  (not (listEmpty? (arrayCalls m)))

fn readerOps -> (List String)
  (list "Len" "Get" "Sum" "CountEq")

fn kindOf name: String -> String
  (optionOr (listFind (fn [(k String)] -> Bool (stringStartsWith? name (str k "Array"))) (list "f64" "i64" "i8")) "")

fn reader? name: String -> Bool
  (let [(k (kindOf name))]
    (and (!= k "") (listContains? (map (fn [(op String)] -> String (str k "Array" op)) (readerOps)) name)))

fn slice? name: String -> Bool
  (and (!= (kindOf name) "") (= name (str (kindOf name) "ArraySlice")))

; (:m :ref SLICEVIEW :do "a Unit window is the whole array; the reader kernels take it as their last two operands")
fn unitName dest: String -> String
  (str dest ".arrWhole")

fn instrNames i: ty/SsaInstr -> (List String)
  (ty/opOperands i.op)

fn termNames t: ty/SsaTerm -> (List String)
  (listAppend
    (match t ((ty/termReturn v) (list v)) ((ty/termBranch c _ _) (list c)) ((ty/termSwitch v _ _ _) (list v)) (_ (list)))
    (fold (fn [(acc (List String)) (e ty/SsaEdge)] -> (List String) (listAppend acc e.args)) (list) (ty/termEdges t)))

fn countIn name: String names: (List String) -> Int64
  (listLength (filter (fn [(n String)] -> Bool (= n name)) names))

fn usesIn f: ty/SsaFunction name: String -> Int64
  (fold (fn [(acc Int64) (b ty/SsaBlock)] -> Int64
          (+ acc (+ (countIn name (termNames b.term))
                    (fold (fn [(acc2 Int64) (i ty/SsaInstr)] -> Int64 (+ acc2 (countIn name (instrNames i)))) 0 b.instrs))))
        0 f.blocks)

fn quiet? op: ty/SsaOp -> Bool
  (match op ((ty/opConst _) true) ((ty/opBox _) true) ((ty/opGlobal _) true) ((ty/opLoadGlobal _) true) (_ false))

fn readsView? kind: String dest: String i: ty/SsaInstr -> Bool
  (match i.op
    ((ty/opBuiltin n args) (and (reader? n) (and (= (kindOf n) kind) (and (= (optionOr (listHead args) "") dest) (= (countIn dest args) 1)))))
    (_ false))

fn beforeFirst stop: (fn [ty/SsaInstr] -> Bool) xs: (List ty/SsaInstr) -> (List ty/SsaInstr)
  (pairFirst
    (fold (fn [(st (Pair (List ty/SsaInstr) Bool)) (x ty/SsaInstr)] -> (Pair (List ty/SsaInstr) Bool)
            (if (or (pairSecond st) (stop x)) (pair (pairFirst st) true) (pair (listAppend (pairFirst st) (list x)) false)))
          (pair (list) false) xs))

; (:m :ref SLICEVIEW :do "a slice fuses into its readers when every use of it is the array operand of a Len, Get, Sum or CountEq of its kind later in its block and only quiet instructions (constants, boxes, globals) run before the first one, so its checks still raise before any other effect; it then copies nothing and its parent stays alive through the readers' operands")
fn fusable? f: ty/SsaFunction instrs: (List ty/SsaInstr) i: ty/SsaInstr -> Bool
  (match i.op
    ((ty/opBuiltin n args)
      (and (slice? n)
        (and (= (listLength args) 3)
          (let [(after (listDrop instrs 1))
                (readers (filter (fn [(x ty/SsaInstr)] -> Bool (readsView? (kindOf n) i.dest x)) after))
                (before (beforeFirst (fn [(x ty/SsaInstr)] -> Bool (readsView? (kindOf n) i.dest x)) after))]
            (and (not (listEmpty? readers))
                 (and (= (usesIn f i.dest) (listLength readers))
                      (listAll? (fn [(x ty/SsaInstr)] -> Bool (quiet? x.op)) before)))))))
    (_ false))

fn rewriteInstr views: (Map String (List String)) i: ty/SsaInstr -> (List ty/SsaInstr)
  (match i.op
    ((ty/opBuiltin n args)
      (cond
        ((not (listContains? (arr/arrayBuiltinNames) n)) (list i))
        ((not (reader? n)) (list (ty/ssaInstr i.dest i.ty (ty/opCall (arr/functionName n) args))))
        (else
          (match (mapGet views (optionOr (listHead args) ""))
            ((some w) (list (ty/ssaInstr i.dest i.ty (ty/opCall (arr/functionName n) (listAppend (cons (optionOr (listHead w) "") (listDrop args 1)) (listDrop w 1))))))
            ((none) (list (ty/ssaInstr (unitName i.dest) (ty/tyVal) (ty/opConst (ty/constUnit)))
                          (ty/ssaInstr i.dest i.ty (ty/opCall (arr/functionName n) (listAppend args (list (unitName i.dest) (unitName i.dest)))))))))))
    (_ (list i)))

fn viewsOf f: ty/SsaFunction instrs: (List ty/SsaInstr) acc: (Map String (List String)) -> (Map String (List String))
  (pairFirst
    (fold (fn [(st (Pair (Map String (List String)) Int64)) (i ty/SsaInstr)] -> (Pair (Map String (List String)) Int64)
            (let [(m (pairFirst st)) (at (pairSecond st))]
              (pair (match i.op
                      ((ty/opBuiltin n args) (if (and (slice? n) (fusable? f (listDrop instrs at) i)) (mapSet m i.dest args) m))
                      (_ m))
                    (+ at 1))))
          (pair acc 0) instrs))

fn rewriteFunction f: ty/SsaFunction -> ty/SsaFunction
  (let [(views (fold (fn [(acc (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String)) (viewsOf f b.instrs acc)) (mapEmpty) f.blocks))]
    (ty/ssaFunction f.name f.captures f.params f.retTy
      (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
             (ty/ssaBlock b.label b.params
               (listFlatMap (fn [(i ty/SsaInstr)] -> (List ty/SsaInstr) (if (mapHas? views i.dest) (list) (rewriteInstr views i))) b.instrs)
               b.term))
           f.blocks)))

fn diag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn poolWith strings: (List String) wanted: (List String) -> (Pair (List String) (Map String Int64))
  (fold (fn [(acc (Pair (List String) (Map String Int64))) (s String)] -> (Pair (List String) (Map String Int64))
          (let [(have (pairFirst acc))]
            (match (listIndexOf have s)
              ((some i) (pair have (mapSet (pairSecond acc) s i)))
              ((none) (pair (listAppend have (list s)) (mapSet (pairSecond acc) s (listLength have)))))))
        (pair strings (mapEmpty)) wanted)

fn mergeExterns own: (List ty/SsaExtern) added: (List ty/SsaExtern) locus: String -> (Result (List ty/SsaExtern) (List ty/IrDiag))
  (let [(clashes (filter (fn [(e ty/SsaExtern)] -> Bool (listAny? (fn [(o ty/SsaExtern)] -> Bool (and (= o.name e.name) (not (rt/sameSignature? o e)))) own)) added))
        (fresh (filter (fn [(e ty/SsaExtern)] -> Bool (not (listAny? (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) own))) added))]
    (if (listEmpty? clashes)
      (ok (listAppend (map (fn [(o ty/SsaExtern)] -> ty/SsaExtern (rt/nativeIfAny o added)) own) fresh))
      (err (map (fn [(e ty/SsaExtern)] -> ty/IrDiag (diag "ERR_LLVM_ARRROUTE_EXTERN" (str "extern '" e.name "' is declared with another signature than asl-target-llvm/arrays needs") locus)) clashes))))

fn arityDiags m: ty/SsaModule calls: (List (Pair String Int64)) -> (List ty/IrDiag)
  (map (fn [(p (Pair String Int64))] -> ty/IrDiag
         (diag "ERR_LLVM_ARRROUTE_ARITY" (str "'" (pairFirst p) "' is called with " (pairSecond p) " operands; it takes " (arity (pairFirst p))) m.name))
       (filter (fn [(p (Pair String Int64))] -> Bool (!= (pairSecond p) (arity (pairFirst p)))) calls))

fn callees f: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
          (fold (fn [(acc2 (List String)) (i ty/SsaInstr)] -> (List String)
                  (match i.op ((ty/opCall n _) (if (listContains? acc2 n) acc2 (listAppend acc2 (list n)))) (_ acc2)))
                acc b.instrs))
        (list) f.blocks)

fn reachable all: (List ty/SsaFunction) names: (List String) -> (List String)
  (let [(more (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                      (if (listContains? names f.name)
                        (fold (fn [(acc2 (List String)) (n String)] -> (List String)
                                (if (and (not (listContains? acc2 n)) (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name n)) all)) (listAppend acc2 (list n)) acc2))
                              acc (callees f))
                        acc))
                    names all))]
    (if (= (listLength more) (listLength names)) names (reachable all more)))

fn routeVerified m: ty/SsaModule calls: (List (Pair String Int64)) -> (Result rt/Routed (List ty/IrDiag))
  (let [(pooled (poolWith m.strings (arr/arrStrings)))
        (all (arr/arrFunctions (pairSecond pooled)))
        (wanted (reachable all (map (fn [(p (Pair String Int64))] -> String (arr/functionName (pairFirst p))) calls)))
        (added (filter (fn [(f ty/SsaFunction)] -> Bool (listContains? wanted f.name)) all))
        (names (map (fn [(f ty/SsaFunction)] -> String f.name) added))
        (clashes (filter (fn [(f ty/SsaFunction)] -> Bool (listContains? names f.name)) m.functions))]
    (if (not (listEmpty? clashes))
      (err (map (fn [(f ty/SsaFunction)] -> ty/IrDiag (diag "ERR_LLVM_ARRROUTE_NAME" (str "module function '" f.name "' has the name of a routed arrays function") f.name)) clashes))
      (match (mergeExterns m.externs (arr/arrExterns) m.name)
        ((err ds) (err ds))
        ((ok externs)
          (ok (rt/Routed :result (ty/ssaModule m.name (pairFirst pooled) m.types m.records externs m.globals
                                   (listAppend (map rewriteFunction m.functions) added))
                         :internal names))))))

fn routeModule m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (routeModuleAs m true)

fn routeLinked m: ty/SsaModule -> (Result rt/Routed (List ty/IrDiag))
  (routeModuleAs m false)

; (:m :ref PERF-VERIFY-ONCE :do "check false skips the input verify: the native entry routes a linked module, which the link verified, and the emit verifies the routed, RC-rewritten module again")
fn routeModuleAs m: ty/SsaModule check: Bool -> (Result rt/Routed (List ty/IrDiag))
  (let [(calls (arrayCalls m))]
    (if (listEmpty? calls)
      (ok (rt/Routed :result m :internal (list)))
      (match (if check (vfy/verifySsa m) (ok ()))
        ((err ds) (err ds))
        ((ok _)
          (let [(bad (arityDiags m calls))]
            (if (listEmpty? bad) (routeVerified m calls) (err bad)))))))

fn routedNames? internal: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringStartsWith? n "asl-target-llvm/arrays.")) internal)

fn extraDecls -> (List String)
  (list "declare ptr @asl_alloc(i32, i64)" "declare double @llvm.fabs.f64(double)" "declare double @llvm.fmuladd.f64(double, double, double)")

fn raiseDefinition -> String
  "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {"

fn finishLines lines: (List String) -> (Result (List String) String)
  (let [(missing (filter (fn [(d (Pair String String))] -> Bool (!= (listLength (filter (fn [(l String)] -> Bool (= l (pairFirst d))) lines)) 1)) (arr/helperDefinitions)))]
    (cond
      ((not (listEmpty? missing))
        (err (str "the emitted text does not declare exactly once: " (stringJoin (map (fn [(d (Pair String String))] -> String (pairFirst d)) missing) "; "))))
      ((not (listContains? lines (raiseDefinition)))
        (err "the emitted text does not define rterr.raise, which aslArrRaise calls"))
      (else
        (let [(replaced (map (fn [(l String)] -> String
                               (fold (fn [(acc String) (d (Pair String String))] -> String (if (= l (pairFirst d)) (pairSecond d) acc)) l (arr/helperDefinitions)))
                             lines))]
          (ok (listAppend replaced (filter (fn [(d String)] -> Bool (not (listContains? lines d))) (extraDecls))))))))

fn finishText routed: Bool res: (Result String (List ty/IrDiag)) -> (Result String (List ty/IrDiag))
  (match res
    ((err ds) (err ds))
    ((ok text)
      (if (not routed)
        (ok text)
        (match (finishLines (stringSplit text "\n"))
          ((err e) (err (list (diag "ERR_LLVM_ARRROUTE_TEXT" e "asl-target-llvm/arrayRoute"))))
          ((ok lines) (ok (stringJoin lines "\n")))))))
