(module asl-target-llvm/regionInfer
  :x [inferRegions flatEntry regionThunk?]
  :i [(asl-ir/types :a ty)])

; (:m :ref SOAREGION :do "region inference: inside one block, a scalar result computed from lists or records that some loop builds and that nothing else reads moves into a thunk run by arenaRunFlat, so under untraced RC its cells come from one arena that is released whole. The guard (each alone keeps the call on the normal path): no value the slice makes is read after it (return); its result is a scalar, read only by unbox (store to an outer value that leaves the region); nothing reachable makes a closure (capture); nothing reachable calls a closure, a builtin, an extern, an opaque array kernel, reads a global or calls an entry outside the pure list (unknown call); every outer value entering it is raw or a constant made again inside (outer heap value). Then every cell the region makes holds only immediates and cells of the same arena, so release needs no walk")
schema Ctx
  owner: String
  fns: (Map String ty/SsaFunction)
  types: (Map String ty/SsaTy)
  defs: (Map String ty/SsaOp)
  count: (Map String Int64)
  unboxed: (Map String Int64)

schema Scan
  ok: Bool
  slice: (List Int64)
  need: (Map String Bool)
  uses: (Map String Int64)
  remat: (List ty/SsaInstr)
  caps: (List ty/SsaParam)
  barrier: Bool

schema Site
  label: String
  at: Int64
  scan: Scan

schema Reach
  ok: Bool
  loops: Bool
  seen: (Map String Bool)

fn flatEntry -> String
  "prelude.arenaRunFlat"

fn regionThunk? name: String -> Bool
  (stringContains? name "@region")

fn thunkName owner: String k: Int64 -> String
  (str owner "@region" k)

fn opaque? name: String -> Bool
  (or (stringStartsWith? name "asl-target-llvm/arrays.") (stringStartsWith? name "asl-target-llvm/parallel."))

fn pureEntry? name: String -> Bool
  (listContains? (list "+" "-" "*" "/" "mod" "<" "<=" ">" ">=" "=" "!=" "not" "cons" "listTail" "listHead" "listEmpty?"
                       "@listHeadOr" "@listTailOr" "@listGetOr" "@listFirst" "@listRest" "@listHeadEmpty?" "@listTailEmpty?")
                 name)

; (:m :ref SOAREGION :do "closure capture guard: a closure made in the region")
fn capturing? op: ty/SsaOp -> Bool
  (match op ((ty/opMakeClosure _ _) true) (_ false))

; (:m :ref SOAREGION :do "unknown call guard: code whose effect on the arena is not known from its text")
fn unknownCall? known: (fn [String] -> Bool) op: ty/SsaOp -> Bool
  (match op
    ((ty/opCallClosure _ _) true)
    ((ty/opBuiltin _ _) true)
    ((ty/opLoadGlobal _) true)
    ((ty/opGlobal _) true)
    ((ty/opEntry n _) (not (pureEntry? n)))
    ((ty/opCall c _) (not (known c)))
    (_ false))

fn flatOp? known: (fn [String] -> Bool) op: ty/SsaOp -> Bool
  (and (not (capturing? op)) (not (unknownCall? known op)))

fn localCall? c: String -> Bool
  (not (or (opaque? c) (= c (flatEntry))))

fn local? c: String -> Bool
  (not (or (opaque? c) (or (= c (flatEntry)) (regionThunk? c))))

; (:m :ref SOAREGION :do "an instruction the slice may be moved past: it neither traps nor has an effect")
fn quiet? op: ty/SsaOp -> Bool
  (match op
    ((ty/opConst _) true)
    ((ty/opBox _) true)
    ((ty/opUnbox _) true)
    ((ty/opList _) true)
    ((ty/opField _ _) true)
    ((ty/opVariantField _ _) true)
    (_ false))

; (:m :ref SOAREGION :do "a constant made again inside the thunk instead of entering it: no string, since a literal cell is shared")
fn rematOp? op: ty/SsaOp -> Bool
  (match op
    ((ty/opConst c) (match c ((ty/constStr _) false) (_ true)))
    ((ty/opList items) (listEmpty? items))
    ((ty/opConstruct _ _ fields) (listEmpty? fields))
    (_ false))

fn allocOp? op: ty/SsaOp -> Bool
  (match op
    ((ty/opEntry n _) (= n "cons"))
    ((ty/opRecord _ _ _) true)
    ((ty/opConstruct _ _ fields) (not (listEmpty? fields)))
    ((ty/opList items) (not (listEmpty? items)))
    (_ false))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)

fn calleeOf op: ty/SsaOp -> (List String)
  (match op ((ty/opCall c _) (list c)) (_ (list)))

fn allocLoop? f: ty/SsaFunction -> Bool
  (let [(is (instrsOf f))]
    (and (listAny? (fn [(ins ty/SsaInstr)] -> Bool (allocOp? ins.op)) is)
         (listAny? (fn [(ins ty/SsaInstr)] -> Bool (listContains? (calleeOf ins.op) f.name)) is)))

fn termOperands t: ty/SsaTerm -> (List String)
  (listAppend
    (match t ((ty/termReturn v) (list v)) ((ty/termBranch c _ _) (list c)) ((ty/termSwitch s _ _ _) (list s)) (_ (list)))
    (listFlatMap (fn [(e ty/SsaEdge)] -> (List String) e.args) (ty/termEdges t)))

fn bump m: (Map String Int64) k: String -> (Map String Int64)
  (mapSet m k (+ (mapGetOr m k 0) 1))

fn bumpAll m: (Map String Int64) ks: (List String) -> (Map String Int64)
  (fold bump m ks)

fn typed m: (Map String ty/SsaTy) ps: (List ty/SsaParam) -> (Map String ty/SsaTy)
  (fold (fn [(a (Map String ty/SsaTy)) (p ty/SsaParam)] -> (Map String ty/SsaTy) (mapSet a p.name p.ty)) m ps)

fn noteInstr a: Ctx ins: ty/SsaInstr -> Ctx
  (Ctx :owner a.owner :fns a.fns :types (mapSet a.types ins.dest ins.ty) :defs (mapSet a.defs ins.dest ins.op)
       :count (bumpAll a.count (ty/opOperands ins.op))
       :unboxed (match ins.op ((ty/opUnbox v) (bump a.unboxed v)) (_ a.unboxed)))

fn noteBlock c: Ctx b: ty/SsaBlock -> Ctx
  (termNoted (fold noteInstr (with c :types (typed c.types b.params)) b.instrs) b.term)

fn termNoted c: Ctx t: ty/SsaTerm -> Ctx
  (with c :count (bumpAll c.count (termOperands t)))

fn inDeep ctx: Ctx -> (fn [String] -> Bool)
  (fn [(c String)] -> Bool (and (mapHas? ctx.fns c) (localCall? c)))

fn ctxOf fns: (Map String ty/SsaFunction) f: ty/SsaFunction -> Ctx
  (fold noteBlock (Ctx :owner f.name :fns fns :types (typed (typed (mapEmpty) f.captures) f.params) :defs (mapEmpty) :count (mapEmpty) :unboxed (mapEmpty)) f.blocks)

fn hasRemat? xs: (List ty/SsaInstr) name: String -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (= i.dest name)) xs)

fn hasCap? xs: (List ty/SsaParam) name: String -> Bool
  (listAny? (fn [(p ty/SsaParam)] -> Bool (= p.name name)) xs)

fn used s: Scan v: String -> Scan
  (with s :uses (bump s.uses v))

fn rematAdd s: Scan ins: ty/SsaInstr -> Scan
  (if (hasRemat? s.remat ins.dest) s (with s :remat (cons ins s.remat)))

fn capAdd s: Scan p: ty/SsaParam -> Scan
  (if (hasCap? s.caps p.name) s (with s :caps (cons p s.caps)))

fn needAdd s: Scan v: String -> Scan
  (with s :need (mapSet s.need v true))

fn failed s: Scan -> Scan
  (with s :ok false)

; (:m :ref SOAREGION :do "an operand of a slice instruction: a raw one enters boxed, a constant is made again inside, a value of this block before it must itself join the slice, and any other value is an outer heap value, which ends the site")
fn addOperand ctx: Ctx pos: (Map String Int64) at: Int64 s: Scan v: String -> Scan
  (let [(t (mapGetOr ctx.types v (ty/tyVal)))]
    (match (mapGet ctx.defs v)
      ((some op) (cond
                   ((rematOp? op) (rematAdd (used s v) (ty/ssaInstr v t op)))
                   ((ty/ssaIsRaw? t) (capAdd (used s v) (ty/ssaParam v t)))
                   ((< (mapGetOr pos v at) at) (needAdd (used s v) v))
                   (else (failed s))))
      ((none) (if (ty/ssaIsRaw? t) (capAdd (used s v) (ty/ssaParam v t)) (failed s)))))

fn addInstr ctx: Ctx pos: (Map String Int64) s: Scan at: Int64 ins: ty/SsaInstr -> Scan
  (fold (fn [(a Scan) (v String)] -> Scan (if a.ok (addOperand ctx pos at a v) a))
        (with s :slice (cons at s.slice) :need (mapRemove s.need ins.dest))
        (ty/opOperands ins.op))

; (:m :ref SOAREGION :do "backward from the consumer: a needed value joins the slice only when the slice reads every use of it and no trapping or effectful instruction lies between, so moving the slice to the consumer keeps the order of every effect and trap")
fn scanBack ctx: Ctx pos: (Map String Int64) back: (List ty/SsaInstr) at: Int64 s: Scan -> Scan
  (cond
    ((not s.ok) s)
    ((= (mapSize s.need) 0) s)
    (else (match (listHead back)
            ((none) (with s :ok false))
            ((some ins)
              (if (mapHas? s.need ins.dest)
                (if (or s.barrier (or (not (flatOp? (inDeep ctx) ins.op)) (!= (mapGetOr s.uses ins.dest 0) (mapGetOr ctx.count ins.dest 0))))
                  (with s :ok false)
                  (scanBack ctx pos (listDrop back 1) (- at 1) (addInstr ctx pos s at ins)))
                (scanBack ctx pos (listDrop back 1) (- at 1) (with s :barrier (or s.barrier (not (quiet? ins.op))))))))))

; (:m :ref SOAREGION :do "return guard: the consumer's result is raw, or a value read only by unbox, so the region hands back a scalar")
fn scalar? ctx: Ctx ins: ty/SsaInstr -> Bool
  (or (ty/ssaIsRaw? ins.ty)
      (let [(n (mapGetOr ctx.count ins.dest 0))]
        (and (> n 0) (= n (mapGetOr ctx.unboxed ins.dest 0)))))

; (:m :ref SOAREGION :do "a candidate consumer calls a module function on a value an in-block call of a module function made")
fn candidate? ctx: Ctx pos: (Map String Int64) at: Int64 ins: ty/SsaInstr -> Bool
  (match ins.op
    ((ty/opCall c args) (and (mapHas? ctx.fns c)
                                  (listAny? (fn [(v String)] -> Bool
                                              (and (< (mapGetOr pos v at) at)
                                                   (and (not (ty/ssaIsRaw? (mapGetOr ctx.types v (ty/tyVal))))
                                                        (match (mapGet ctx.defs v) ((some op) (match op ((ty/opCall p _) (mapHas? ctx.fns p)) (_ false))) ((none) false)))))
                                            args)))
    (_ false))

fn emptyScan -> Scan
  (Scan :ok true :slice (list) :need (mapEmpty) :uses (mapEmpty) :remat (list) :caps (list) :barrier false)

fn siteAt ctx: Ctx pos: (Map String Int64) b: ty/SsaBlock at: Int64 ins: ty/SsaInstr -> (Option Site)
  (if (not (and (candidate? ctx pos at ins) (and (scalar? ctx ins) (flatOp? (inDeep ctx) ins.op))))
    (none)
    (let [(s0 (addInstr ctx pos (emptyScan) at ins))
          (s (scanBack ctx pos (listReverse (listTake b.instrs at)) (- at 1) s0))]
      (if (not s.ok)
        (none)
        (let [(chosen (filter (fn [(p (Pair Int64 ty/SsaInstr))] -> Bool (listContains? s.slice (pairFirst p))) (indexed b.instrs)))
              (made (listFlatMap (fn [(p (Pair Int64 ty/SsaInstr))] -> (List String) (if (or (= (pairFirst p) at) (ty/ssaIsRaw? (pairSecond p).ty)) (list) (calleeOf (pairSecond p).op))) chosen))
              (calls (listFlatMap (fn [(p (Pair Int64 ty/SsaInstr))] -> (List String) (calleeOf (pairSecond p).op)) chosen))]
          (if (and (reachInfo ctx.fns ctx.owner calls (freshReach) 512).ok (and (reachInfo ctx.fns ctx.owner made (freshReach) 512).loops (not (and (tail? ctx b ins) (recursive? ctx))))) (some (Site :label b.label :at at :scan s)) (none))))))

fn indexed xs: (List T) -> (List (Pair Int64 T))
  (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List (Pair Int64 T)))) (x T)] -> (Pair Int64 (List (Pair Int64 T)))
                                   (pair (+ (pairFirst acc) 1) (cons (pair (pairFirst acc) x) (pairSecond acc))))
                                 (pair 0 (list)) xs)))

fn positions b: ty/SsaBlock -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (p (Pair Int64 ty/SsaInstr))] -> (Map String Int64) (mapSet m (pairSecond p).dest (pairFirst p))) (mapEmpty) (indexed b.instrs))

fn siteInBlock ctx: Ctx b: ty/SsaBlock -> (Option Site)
  (let [(pos (positions b))]
    (fold (fn [(found (Option Site)) (p (Pair Int64 ty/SsaInstr))] -> (Option Site)
            (match found ((some _) found) ((none) (siteAt ctx pos b (pairFirst p) (pairSecond p)))))
          (none) (listReverse (indexed b.instrs))))

fn freshReach -> Reach
  (Reach :ok true :loops false :seen (mapEmpty))

fn knownIn fns: (Map String ty/SsaFunction) -> (fn [String] -> Bool)
  (fn [(c String)] -> Bool (and (mapHas? fns c) (localCall? c)))

fn flatBody? fns: (Map String ty/SsaFunction) g: ty/SsaFunction -> Bool
  (listAll? (fn [(b ty/SsaBlock)] -> Bool (listAll? (fn [(ins ty/SsaInstr)] -> Bool (flatOp? (knownIn fns) ins.op)) b.instrs)) g.blocks)

; (:m :ref SOAREGION :do "tail guard: the consumer result, raw or through an unbox in its block, is what the function returns, from this block or through jumps that pass it on as a block parameter")
fn tail? ctx: Ctx b: ty/SsaBlock ins: ty/SsaInstr -> Bool
  (let [(vs (cons ins.dest (listFlatMap (fn [(i ty/SsaInstr)] -> (List String) (match i.op ((ty/opUnbox u) (if (= u ins.dest) (list i.dest) (list))) (_ (list)))) b.instrs)))
        (blocks (match (mapGet ctx.fns ctx.owner) ((some g) g.blocks) ((none) (list))))]
    (flowsOut? blocks b.term vs 16))

fn flowsOut? blocks: (List ty/SsaBlock) t: ty/SsaTerm vs: (List String) fuel: Int64 -> Bool
  (match t
    ((ty/termReturn v) (listContains? vs v))
    ((ty/termJump e)
      (and (> fuel 0)
           (match (listHead (filter (fn [(x ty/SsaBlock)] -> Bool (= x.label e.target)) blocks))
             ((none) false)
             ((some tb) (let [(ps (listFlatMap (fn [(p (Pair Int64 String))] -> (List String) (if (listContains? vs (pairSecond p)) (match (listGet tb.params (pairFirst p)) ((some q) (list q.name)) ((none) (list))) (list))) (indexed e.args)))]
                          (and (not (listEmpty? ps)) (flowsOut? blocks tb.term ps (- fuel 1))))))))
    (_ false))

; (:m :ref SOAREGION :do "the owner calls itself directly or through a cycle of module functions; a walk past the bound counts as recursive")
fn recursive? ctx: Ctx -> Bool
  (match (mapGet ctx.fns ctx.owner)
    ((none) true)
    ((some h) (reaches? ctx.fns ctx.owner (calleesOf h) (mapEmpty) 512)))

fn calleesOf g: ty/SsaFunction -> (List String)
  (listFlatMap (fn [(ins ty/SsaInstr)] -> (List String) (calleeOf ins.op)) (instrsOf g))

fn reaches? fns: (Map String ty/SsaFunction) target: String todo: (List String) seen: (Map String Bool) fuel: Int64 -> Bool
  (match (listHead todo)
    ((none) false)
    ((some n)
      (let [(rest (optionOr (listTail todo) (list)))]
        (cond
          ((= n target) true)
          ((mapHas? seen n) (reaches? fns target rest seen fuel))
          ((<= fuel 0) true)
          (else (match (mapGet fns n)
                  ((none) (reaches? fns target rest (mapSet seen n true) fuel))
                  ((some g) (reaches? fns target (listAppend (listFlatMap (fn [(ins ty/SsaInstr)] -> (List String) (calleeOf ins.op)) (instrsOf g)) rest) (mapSet seen n true) (- fuel 1)))))))))

; (:m :ref SOAREGION :do "every function the slice reaches must pass the guards itself and none of them is the owner, so a region never opens inside its own owner (tail recursion through the thunk would nest arenas), and loops says whether one of them is a loop that allocates; the walk is bounded and a slice past the bound counts as reaching unknown code")
fn reachInfo fns: (Map String ty/SsaFunction) owner: String todo: (List String) r: Reach fuel: Int64 -> Reach
  (match (listHead todo)
    ((none) r)
    ((some n)
      (let [(rest (optionOr (listTail todo) (list)))]
        (cond
          ((= n owner) (with r :ok false))
          ((mapHas? r.seen n) (reachInfo fns owner rest r fuel))
          ((<= fuel 0) (with r :ok false))
          ((not (localCall? n)) (with r :ok false))
          (else (match (mapGet fns n)
                  ((none) (with r :ok false))
                  ((some g) (if (flatBody? fns g)
                              (reachInfo fns owner (listAppend (listFlatMap (fn [(ins ty/SsaInstr)] -> (List String) (calleeOf ins.op)) (instrsOf g)) rest)
                                         (Reach :ok true :loops (or r.loops (allocLoop? g)) :seen (mapSet r.seen n true)) (- fuel 1))
                              (with r :ok false)))))))))

; (:m :ref SOAREGION :do "cheap filter before any table: some block passes the value a module call made to a module call whose result is raw or later unboxed; made and fed keep the 8 latest values")
fn chained? f: ty/SsaFunction -> Bool
  (listAny? (fn [(b ty/SsaBlock)] -> Bool (chainedFrom b.instrs (list) (list))) f.blocks)

fn chainedFrom instrs: (List ty/SsaInstr) made: (List String) fed: (List String) -> Bool
  (match (listHead instrs)
    ((none) false)
    ((some ins)
      (let [(rest (optionOr (listTail instrs) (list)))]
        (match ins.op
          ((ty/opCall c args)
            (let [(reads (and (local? c) (listAny? (fn [(v String)] -> Bool (listContains? made v)) args)))
                  (raw (ty/ssaIsRaw? ins.ty))]
              (if (and reads raw)
                true
                (chainedFrom rest
                  (if (and (not raw) (local? c)) (listTake (cons ins.dest made) 8) made)
                  (if reads (listTake (cons ins.dest fed) 8) fed)))))
          ((ty/opUnbox v) (or (listContains? fed v) (chainedFrom rest made fed)))
          (_ (chainedFrom rest made fed))))))

fn findSite fns: (Map String ty/SsaFunction) f: ty/SsaFunction -> (Option Site)
  (let [(ctx (ctxOf fns f))]
    (fold (fn [(found (Option Site)) (b ty/SsaBlock)] -> (Option Site)
            (match found ((some _) found) ((none) (siteInBlock ctx b))))
          (none) f.blocks))

fn capName k: Int64 kind: String v: String -> String
  (str "rg" k "." kind "." v)

; (:m :ref SOAREGION :do "the caller boxes the raw values the slice reads, makes the thunk closure over them and calls arenaRunFlat where the consumer stood; the thunk unboxes them, makes the constants again, runs the slice in order and returns its result boxed when raw")
fn rewrite f: ty/SsaFunction site: Site k: Int64 -> (Pair ty/SsaFunction ty/SsaFunction)
  (let [(s site.scan)
        (name (thunkName f.name k))
        (caps (listReverse s.caps))
        (block (optionOr (listHead (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label site.label)) f.blocks)) (ty/ssaBlock "" (list) (list) (ty/termUnreachable))))
        (items (indexed block.instrs))
        (chosen (map (fn [(p (Pair Int64 ty/SsaInstr))] -> ty/SsaInstr (pairSecond p)) (filter (fn [(p (Pair Int64 ty/SsaInstr))] -> Bool (listContains? s.slice (pairFirst p))) items)))
        (y (optionOr (listGet block.instrs site.at) (ty/ssaInstr "" (ty/tyVal) (ty/opConst (ty/constUnit)))))
        (raw (ty/ssaIsRaw? y.ty))
        (boxes (map (fn [(p ty/SsaParam)] -> ty/SsaInstr (ty/ssaInstr (capName k "box" p.name) (ty/tyVal) (ty/opBox p.name))) caps))
        (clo (ty/ssaInstr (capName k "clo" "f") (ty/tyVal) (ty/opMakeClosure name (map (fn [(i ty/SsaInstr)] -> String i.dest) boxes))))
        (calls (if raw
                 (list (ty/ssaInstr (capName k "out" "r") (ty/tyVal) (ty/opCall (flatEntry) (list clo.dest)))
                       (ty/ssaInstr y.dest y.ty (ty/opUnbox (capName k "out" "r"))))
                 (list (ty/ssaInstr y.dest (ty/tyVal) (ty/opCall (flatEntry) (list clo.dest))))))
        (instrs (listFlatMap (fn [(p (Pair Int64 ty/SsaInstr))] -> (List ty/SsaInstr)
                               (cond ((= (pairFirst p) site.at) (listAppend boxes (cons clo calls)))
                                     ((listContains? s.slice (pairFirst p)) (list))
                                     (else (list (pairSecond p)))))
                             items))
        (unboxes (map (fn [(p ty/SsaParam)] -> ty/SsaInstr (ty/ssaInstr p.name p.ty (ty/opUnbox (capName k "cap" p.name)))) caps))
        (tail (if raw (list (ty/ssaInstr (capName k "ret" "r") (ty/tyVal) (ty/opBox y.dest))) (list)))
        (result (if raw (capName k "ret" "r") y.dest))
        (thunk (ty/ssaFunction name (map (fn [(p ty/SsaParam)] -> ty/SsaParam (ty/ssaParam (capName k "cap" p.name) (ty/tyVal))) caps) (list) (ty/tyVal)
                 (list (ty/ssaBlock "entry" (list) (listAppend unboxes (listAppend (listReverse s.remat) (listAppend chosen tail))) (ty/termReturn result)))))
        (g (with f :blocks (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock (if (= b.label site.label) (with b :instrs instrs) b)) f.blocks)))]
    (pair g thunk))

schema Done
  k: Int64
  thunks: (List ty/SsaFunction)

fn regionIn fns: (Map String ty/SsaFunction) d: Done f: ty/SsaFunction fuel: Int64 -> (Pair Done ty/SsaFunction)
  (if (<= fuel 0)
    (pair d f)
    (match (findSite fns f)
      ((none) (pair d f))
      ((some site) (let [(r (rewrite f site d.k))]
                     (regionIn fns (Done :k (+ d.k 1) :thunks (cons (pairSecond r) d.thunks)) (pairFirst r) (- fuel 1))))))

fn flatFunction -> ty/SsaFunction
  (ty/ssaFunction (flatEntry) (list) (list (ty/ssaParam "f" (ty/tyVal))) (ty/tyVal)
    (list (ty/ssaBlock "entry" (list) (list (ty/ssaInstr "%0" (ty/tyVal) (ty/opCallClosure "f" (list)))) (ty/termReturn "%0"))))

fn fnsOf fs: (List ty/SsaFunction) -> (Map String ty/SsaFunction)
  (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (if (local? f.name) (mapSet acc f.name f) acc)) (mapEmpty) fs)

; (:m :ref SOAREGION :do "a cheap structural filter picks the functions that chain two module calls; only when one exists is the function table built, and only those functions get per-function tables and a bounded walk of what their slice reaches; a module with none is returned as it came")
fn inferRegions m: ty/SsaModule -> ty/SsaModule
  (if (not (listAny? (fn [(f ty/SsaFunction)] -> Bool (and (local? f.name) (chained? f))) m.functions))
    m
    (let [(fns (fnsOf m.functions))
          (r (fold (fn [(acc (Pair Done (List ty/SsaFunction))) (f ty/SsaFunction)] -> (Pair Done (List ty/SsaFunction))
                     (if (and (local? f.name) (chained? f))
                       (let [(done (regionIn fns (pairFirst acc) f 4))] (pair (pairFirst done) (cons (pairSecond done) (pairSecond acc))))
                       (pair (pairFirst acc) (cons f (pairSecond acc)))))
                   (pair (Done :k 0 :thunks (list)) (list)) m.functions))
          (d (pairFirst r))]
      (if (listEmpty? d.thunks)
        m
        (with m :functions (listAppend (listReverse (pairSecond r))
                                       (listAppend (listReverse d.thunks)
                                                   (if (listAny? (fn [(f ty/SsaFunction)] -> Bool (= f.name (flatEntry))) m.functions) (list) (list (flatFunction)))))))))
