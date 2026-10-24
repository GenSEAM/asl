(module asl-target-llvm/ssaOpt
  :x [hoistConstants nativePrelude constantKey singletonPrefix singleton?]
  :i [(asl-ir/types :a ty) (asl-target-llvm/recordScalar :a rs)])

schema Hoisted
  keys: (Map String Int64)
  ops: (List ty/SsaOp)
  count: Int64

fn singletonPrefix moduleName: String -> String
  (str moduleName ".@ssaOpt$")

fn singleton? name: String -> Bool
  (stringContains? name ".@ssaOpt$")

fn constantKey ins: ty/SsaInstr -> (Option String)
  (if (!= (ty/ssaTyName ins.ty) "val")
    (none)
    (match ins.op
      ((ty/opConstruct t v fields) (if (listEmpty? fields) (some (str "c " t " " v)) (none)))
      ((ty/opMakeClosure callee caps) (if (listEmpty? caps) (some (str "k " callee)) (none)))
      (_ (none))))

fn initName prefix: String i: Int64 -> String
  (str prefix "s" (stringFromInt64 i))

fn globalName prefix: String i: Int64 -> String
  (str (initName prefix i) "$g")

fn noteInstr acc: Hoisted ins: ty/SsaInstr -> Hoisted
  (match (constantKey ins)
    ((none) acc)
    ((some k) (if (mapHas? acc.keys k)
                acc
                (Hoisted :keys (mapSet acc.keys k acc.count) :ops (cons ins.op acc.ops) :count (+ acc.count 1)))))

fn collect fs: (List ty/SsaFunction) -> Hoisted
  (fold (fn [(acc Hoisted) (f ty/SsaFunction)] -> Hoisted
          (fold (fn [(a Hoisted) (b ty/SsaBlock)] -> Hoisted (fold noteInstr a b.instrs)) acc f.blocks))
        (Hoisted :keys (mapEmpty) :ops (list) :count 0) fs)

fn rewriteInstr prefix: String keys: (Map String Int64) ins: ty/SsaInstr -> ty/SsaInstr
  (match (constantKey ins)
    ((none) ins)
    ((some k) (match (mapGet keys k)
                ((none) ins)
                ((some i) (ty/ssaInstr ins.dest ins.ty (ty/opGlobal (globalName prefix i)))))))

fn rewriteFunction prefix: String keys: (Map String Int64) f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params (map (fn [(ins ty/SsaInstr)] -> ty/SsaInstr (rewriteInstr prefix keys ins)) b.instrs) b.term))
         f.blocks))

fn initFunction prefix: String i: Int64 op: ty/SsaOp -> ty/SsaFunction
  (ty/ssaFunction (initName prefix i) (list) (list) (ty/tyVal)
    (list (ty/ssaBlock "entry" (list) (list (ty/ssaInstr "v" (ty/tyVal) op)) (ty/termReturn "v"))))

fn hoistConstants m: ty/SsaModule -> ty/SsaModule
  (let [(prefix (singletonPrefix m.name))
        (own? (fn [(f ty/SsaFunction)] -> Bool (stringStartsWith? f.name prefix)))
        (user (filter (fn [(f ty/SsaFunction)] -> Bool (not (own? f))) m.functions))
        (found (collect user))]
    (if (= found.count 0)
      m
      (let [(inits (pairSecond (fold (fn [(acc (Pair Int64 (List ty/SsaFunction))) (op ty/SsaOp)] -> (Pair Int64 (List ty/SsaFunction))
                                       (pair (- (pairFirst acc) 1) (cons (initFunction prefix (pairFirst acc) op) (pairSecond acc))))
                                     (pair (- found.count 1) (list)) found.ops)))
            (globals (map (fn [(i Int64)] -> ty/SsaGlobal (ty/ssaGlobal (globalName prefix i) (initName prefix i))) (range 0 found.count)))]
        (ty/ssaModule m.name m.strings m.types m.records m.externs
          (listAppend globals m.globals)
          (listAppend (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (if (own? f) f (rewriteFunction prefix found.keys f))) m.functions) inits)))))

; (:m :ref (PERF-MONO-MAPKEY PERF-MAPRANK) :do "LLVM-only bodies for two prelude treap helpers, so the go, js and py targets keep the prelude bodies, which lack keyCompare and bit primitives: the key order runs as one native three-way compare (opsrt.keyCmp) instead of a generic = and a generic <, and the rank byte step as FNV-1a in 31 bits (xor, multiply, mask) instead of a mod-prime step; only the bodies are replaced and clang inlines the small calls")
; (:m :ref RECSROA :do "then records threaded through self calls become one parameter per field (recordScalar), before the routes and the RC pass see the module")
fn nativePrelude m: ty/SsaModule -> ty/SsaModule
  (rs/scalarizeRecords (with m :functions (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rankByteBody (keyOrderBody f))) m.functions)))

fn typedAs? f: ty/SsaFunction params: String ret: String -> Bool
  (and (= (listLength f.params) 2)
       (and (= (ty/ssaTyName f.retTy) ret) (listAll? (fn [(p ty/SsaParam)] -> Bool (= (ty/ssaTyName p.ty) params)) f.params)))

fn paramNames f: ty/SsaFunction -> (List String)
  (map (fn [(p ty/SsaParam)] -> String p.name) f.params)

fn rankByteBody f: ty/SsaFunction -> ty/SsaFunction
  (if (and (= f.name "prelude.preludeRankByte") (typedAs? f "i64" "i64"))
    (with f :blocks (list (ty/ssaBlock "entry" (list)
                            (list (ty/ssaInstr "%0" (ty/tyI64) (ty/opPrim "rawXorI64" (paramNames f)))
                                  (ty/ssaInstr "%1" (ty/tyI64) (ty/opConst (ty/constInt 16777619)))
                                  (ty/ssaInstr "%2" (ty/tyI64) (ty/opPrim "mulIntHost" (list "%0" "%1")))
                                  (ty/ssaInstr "%3" (ty/tyI64) (ty/opConst (ty/constInt 2147483647)))
                                  (ty/ssaInstr "%4" (ty/tyI64) (ty/opPrim "rawAndI64" (list "%2" "%3"))))
                            (ty/termReturn "%4"))))
    f)

fn keyOrderBody f: ty/SsaFunction -> ty/SsaFunction
  (if (and (= f.name "prelude.preludeKeyOrder") (typedAs? f "val" "i64"))
    (with f :blocks (list (ty/ssaBlock "entry" (list)
                            (list (ty/ssaInstr "%0" (ty/tyVal) (ty/opBuiltin "keyCompare" (paramNames f)))
                                  (ty/ssaInstr "%1" (ty/tyI64) (ty/opUnbox "%0")))
                            (ty/termReturn "%1"))))
    f)
