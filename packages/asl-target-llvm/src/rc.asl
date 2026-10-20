(module asl-target-llvm/rc
  :x [rcModule rcFinishText rcFinishTextWith sanitized routeArrayAlloc dupName dropName pinName wrapperName runtimeText]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/ssaOpt :a opt)])

schema Ctx
  user: (Map String Bool)
  opaque: (Map String Bool)
  builders: (Map String Bool)
  borrows: (Map String (List Bool))
  scc: (Map String String)
  proj: (Map String Int64)

schema Use
  name: String
  kind: String

schema Facts
  heap: (Map String Bool)
  immortal: (Map String Bool)
  anchors: (Map String String)
  dupAfter: (Map String Bool)
  pinAfter: (Map String Bool)
  wrapAfter: (Map String Bool)
  borrowed: (Map String Bool)
  flow: (Map String Bool)
  parts: (Map String (Pair String Int64))
  cells: (Map String Bool)

schema Walk
  live: (Map String Bool)
  out: (List ty/SsaInstr)
  n: Int64
  pend: (List (Pair String Int64))

schema Flow
  ok: Bool
  param: Int64
  keys: (Map String Bool)
  names: (Map String Bool)
  values: (Map String Bool)

schema Edges
  term: ty/SsaTerm
  blocks: (List ty/SsaBlock)
  prefix: (Map String (List ty/SsaInstr))
  n: Int64

fn dupName -> String
  "aslRcDup"

fn dropName -> String
  "aslRcDrop"

fn pinName -> String
  "aslRcPin"

fn deferFirstName -> String
  "aslRcDeferFirst"

fn deferName -> String
  "aslRcDefer"

fn dupKidsName -> String
  "aslRcDupKids"

fn rcNames -> (List String)
  (list (dupName) (dropName) (pinName) (deferFirstName) (deferName) (dupKidsName))

fn wrapperName name: String -> String
  (str name "@rc")

fn dupSameName -> String
  "aslRcDupSame"

fn rcExterns -> (List ty/SsaExtern)
  (listAppend (map (fn [(n String)] -> ty/SsaExtern (ty/ssaExternTyped n (list (ty/tyVal)) (ty/tyI64))) (rcNames))
              (list (ty/ssaExternTyped (dupSameName) (list (ty/tyVal) (ty/tyVal)) (ty/tyI64))))

fn setOf names: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapSet acc n true)) (mapEmpty) names)

fn union a: (Map String Bool) b: (Map String Bool) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapSet acc n true)) a (mapKeys b))

fn without a: (Map String Bool) names: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapRemove acc n)) a names)

fn heapTy? t: ty/SsaTy -> Bool
  (= (ty/ssaAbiName t) "val")

fn rcCall dest: String callee: String v: String -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opCall callee (stringSplit v "\t")))

fn opaqueFunction? ctx: Ctx name: String -> Bool
  (or (not (mapHas? ctx.user name)) (mapHas? ctx.opaque name))

fn builderFunction? ctx: Ctx name: String -> Bool
  (mapHas? ctx.builders name)

fn arrayFresh? name: String -> Bool
  (listContains? (fold (fn [(acc (List String)) (k String)] -> (List String)
                         (listAppend acc (map (fn [(op String)] -> String (str "asl-target-llvm/arrays." k "Array" op)) (list "Len" "Get" "Slice" "Concat" "Generate" "Sum" "CountEq"))))
                       (list) (list "f64" "i64" "i8"))
                 name)

; (:m :ref RC-UNPIN :do "runtime externs the system routes call that read their Val arguments without keeping them and return a fresh value, a raw pointer to a malloc copy or a tag word (abs, the route's tag read)")
fn borrowExtern? name: String -> Bool
  (listContains? (list "mkStr" "mkBytes" "valToCStr" "valToCStrN" "abs") name)

; (:m :ref RC-UNPIN :do "functions the system route adds (sysRoute wrappers and the sys helpers they call) are plain SSA over fresh allocations, so they are counted like user code; array kernels and parallel workers stay opaque")
fn countedRoute? name: String -> Bool
  (not (or (stringStartsWith? name "asl-target-llvm/arrays.") (stringStartsWith? name "asl-target-llvm/parallel.")))

fn borrowBuiltin? name: String -> Bool
  (listContains? (list "+" "-" "*" "/" "mod" "<" "<=" ">" ">=" "=" "!=" "not" "str" "print" "println" "eprintln" "stringFromFloat64" "stringToFloat64" "abs" "int64ToFloat64" "float64ToInt64" "~"
                       "min" "max" "<<" ">>" "&" "|" "^" "clamp" "assert" "refute" "trap")
                 name)

fn freshEntry? name: String -> Bool
  (listContains? (list "+" "-" "*" "/" "mod" "stringConcat" "stringFromInt64" "stringSlice" "stringFromFloat64" "stringToFloat64" "bytesAlloc" "bytesSet" "stringToBytes") name)

fn wrapEntry? name: String -> Bool
  (or (= name "listHead") (= name "listTail"))

fn sameEntry? name: String -> Bool
  (= name "@stringSliceOr")

fn sameAnchor ins: ty/SsaInstr -> (List (Pair String String))
  (mt ins.op
    ((ty/opEntry name args) (if (sameEntry? name) (mt (listHead (listReverse args)) ((some d) (list (pair (dupSameName) (str ins.dest "\t" d)))) ((none) (list))) (list)))
    (_ (list)))

fn heapUses facts: Facts names: (List String) kind: String -> (List Use)
  (map (fn [(n String)] -> Use (Use :name n :kind kind)) (filter (fn [(n String)] -> Bool (mapHas? facts.heap n)) names))

fn consumeEntry? name: String -> Bool
  (= name "cons")

fn childEntry? name: String -> Bool
  (or (= name "@listFirst") (= name "@listRest"))

fn childOrEntry? name: String -> Bool
  (listContains? (list "@listHeadOr" "@listTailOr" "@listGetOr") name)

fn instrUses ctx: Ctx facts: Facts ins: ty/SsaInstr -> (List Use)
  (mt ins.op
    ((ty/opCall callee args) (cond ((builderFunction? ctx callee) (heapUses facts args "borrow")) ((or (arrayFresh? callee) (borrowExtern? callee)) (heapUses facts args "borrow")) ((opaqueFunction? ctx callee) (heapUses facts args "pin")) (else (callUses ctx facts callee args))))
    ((ty/opBuiltin name args) (heapUses facts args (if (borrowBuiltin? name) "borrow" "pin")))
    ((ty/opEntry name args) (heapUses facts args (if (consumeEntry? name) "consume" "borrow")))
    ((ty/opCallClosure c args) (heapUses facts (cons c args) "borrow"))
    ((ty/opMakeClosure _ caps) (heapUses facts caps "consume"))
    ((ty/opConstruct _ _ fields) (heapUses facts fields "consume"))
    ((ty/opRecord _ _ values) (heapUses facts values "consume"))
    ((ty/opList items) (heapUses facts items "consume"))
    ((ty/opField b _) (heapUses facts (list b) "borrow"))
    ((ty/opVariantField b _) (heapUses facts (list b) "borrow"))
    ((ty/opBox v) (heapUses facts (list v) "consume"))
    ((ty/opUnbox v) (heapUses facts (list v) (cond ((heapTy? ins.ty) "consume") ((= (ty/ssaTyName ins.ty) "ptr") "pin") (else "borrow"))))
    ((ty/opPrim _ args) (heapUses facts args "borrow"))
    (_ (list)))

fn termUses facts: Facts t: ty/SsaTerm -> (List Use)
  (listAppend
    (mt t
      ((ty/termReturn v) (heapUses facts (list v) (if (mapHas? facts.flow "$ret") "borrow" "consume")))
      ((ty/termBranch c _ _) (heapUses facts (list c) "borrow"))
      ((ty/termSwitch s _ _ _) (heapUses facts (list s) "borrow"))
      (_ (list)))
    (fold (fn [(acc (List Use)) (e ty/SsaEdge)] -> (List Use)
            (listAppend acc (fold (fn [(a (List Use)) (j Int64)] -> (List Use)
                                    (listAppend a (heapUses facts (list (optionOr (listGet e.args j) "")) (if (flowEdge? facts e.target j) "borrow" "consume"))))
                                  (list) (range 0 (listLength e.args)))))
          (list) (ty/termEdges t)))

fn flowKey label: String j: Int64 -> String
  (str label "\t" j)

fn flowEdge? facts: Facts label: String j: Int64 -> Bool
  (mapHas? facts.flow (flowKey label j))

fn resultKind ctx: Ctx ins: ty/SsaInstr -> String
  (if (not (heapTy? ins.ty))
    "raw"
    (mt ins.op
      ((ty/opConst c) (mt c ((ty/constStr _) "source") ((ty/constSymbol _) "source") (_ "immortal")))
      ((ty/opCall callee _) (if (mapHas? ctx.proj callee) "source" (if (and (opaqueFunction? ctx callee) (and (not (builderFunction? ctx callee)) (not (or (arrayFresh? callee) (borrowExtern? callee))))) "opaque" "owned")))
      ((ty/opBuiltin name _) (if (borrowBuiltin? name) "owned" "opaque"))
      ((ty/opEntry name _) (cond ((consumeEntry? name) "owned") ((childEntry? name) "source") ((childOrEntry? name) "sourceDup") ((freshEntry? name) "owned") ((sameEntry? name) "owned") ((wrapEntry? name) "wrap") (else "opaque")))
      ((ty/opField _ _) "source")
      ((ty/opVariantField _ _) "source")
      ((ty/opGlobal _) "source")
      ((ty/opBox _) "owned")
      ((ty/opUnbox _) "owned")
      ((ty/opLoadGlobal _) "raw")
      ((ty/opPrim _ _) "immortal")
      (_ "owned")))

fn functionInstrs f: ty/SsaFunction -> (List ty/SsaInstr)
  (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn heapNames f: ty/SsaFunction -> (Map String Bool)
  (let [(params (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (heapTy? p.ty)) (listAppend f.captures f.params))))
        (blockParams (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
                             (listAppend acc (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (heapTy? p.ty)) b.params))))
                           (list) f.blocks))
        (dests (map (fn [(i ty/SsaInstr)] -> String i.dest) (filter (fn [(i ty/SsaInstr)] -> Bool (heapTy? i.ty)) (functionInstrs f))))]
    (setOf (listAppend params (listAppend blockParams dests))))

fn allUseKinds ctx: Ctx facts: Facts f: ty/SsaFunction -> (Map String (List String))
  (let [(note (fn [(acc (Map String (List String))) (u Use)] -> (Map String (List String)) (mapSet acc u.name (cons u.kind (optionOr (mapGet acc u.name) (list))))))]
    (fold (fn [(acc (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String))
            (fold note (fold (fn [(a (Map String (List String))) (ins ty/SsaInstr)] -> (Map String (List String)) (fold note a (instrUses ctx facts ins))) acc b.instrs)
                  (termUses facts b.term)))
          (mapEmpty) f.blocks))

fn sourceBase ctx: Ctx op: ty/SsaOp -> String
  (mt op ((ty/opCall callee args) (mt (mapGet ctx.proj callee) ((some i) (optionOr (listGet args i) "")) ((none) ""))) ((ty/opField b _) b) ((ty/opVariantField b _) b) ((ty/opEntry name args) (if (childEntry? name) (optionOr (listHead args) "") "")) (_ ""))

fn anchorOf ctx: Ctx defs: (Map String ty/SsaOp) derived: (Map String Bool) immortal: (Map String Bool) v: String fuel: Int64 -> String
  (cond
    ((<= fuel 0) "")
    ((mapHas? immortal v) "")
    ((mapHas? derived v) (mt (mapGet defs v)
                           ((some op) (let [(b (sourceBase ctx op))] (if (= b "") "" (anchorOf ctx defs derived immortal b (- fuel 1)))))
                           ((none) "")))
    (else v))

fn immortalBase? ctx: Ctx defs: (Map String ty/SsaOp) immortal: (Map String Bool) v: String fuel: Int64 -> Bool
  (cond
    ((<= fuel 0) false)
    ((mapHas? immortal v) true)
    (else (mt (mapGet defs v)
            ((some op) (let [(b (sourceBase ctx op))] (if (= b "") false (immortalBase? ctx defs immortal b (- fuel 1)))))
            ((none) false))))

; (:m :ref RC-PERF :do "a raw i64, f64 or i1 boxed into a Val is an immediate, never a heap object, so its box needs no RC")
fn rawNames f: ty/SsaFunction instrs: (List ty/SsaInstr) -> (Map String Bool)
  (let [(params (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (ty/ssaIsRaw? p.ty)) (listAppend f.captures f.params))))
        (blockParams (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (listAppend acc (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (ty/ssaIsRaw? p.ty)) b.params)))) (list) f.blocks))
        (dests (map (fn [(i ty/SsaInstr)] -> String i.dest) (filter (fn [(i ty/SsaInstr)] -> Bool (ty/ssaIsRaw? i.ty)) instrs)))]
    (setOf (listAppend params (listAppend blockParams dests))))

fn rawBox? raws: (Map String Bool) ins: ty/SsaInstr -> Bool
  (mt ins.op ((ty/opBox v) (mapHas? raws v)) (_ false))

fn functionFacts ctx: Ctx f: ty/SsaFunction -> Facts
  (let [(instrs (functionInstrs f))
        (heap (heapNames f))
        (raws (rawNames f instrs))
        (kinds (fold (fn [(acc (Map String String)) (i ty/SsaInstr)] -> (Map String String) (mapSet acc i.dest (if (rawBox? raws i) "immortal" (resultKind ctx i)))) (mapEmpty) instrs))
        (defs (fold (fn [(acc (Map String ty/SsaOp)) (i ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet acc i.dest i.op)) (mapEmpty) instrs))
        (base0 (setOf (filter (fn [(n String)] -> Bool (let [(k (optionOr (mapGet kinds n) ""))] (or (= k "immortal") (= k "opaque")))) (mapKeys heap))))
        (sources (filter (fn [(n String)] -> Bool (let [(k (optionOr (mapGet kinds n) ""))] (or (= k "source") (= k "sourceDup")))) (mapKeys heap)))
        (immortal (union base0 (setOf (filter (fn [(n String)] -> Bool (let [(b (mt (mapGet defs n) ((some op) (sourceBase ctx op)) ((none) "")))] (and (!= b "") (immortalBase? ctx defs base0 b 64)))) sources))))
        (flow (if (mapHas? ctx.proj f.name) (flowOf ctx f) (flowNone)))
        (borrowed (union (borrowedParams ctx f) flow.names))
        (parts (partsOf instrs))
        (probe (Facts :heap heap :immortal immortal :anchors (mapEmpty) :dupAfter (mapEmpty) :pinAfter (mapEmpty) :wrapAfter (mapEmpty) :borrowed borrowed :flow flow.keys :parts parts :cells (cellBases parts)))
        (useKinds (allUseKinds ctx probe f))
        (borrowOnly (fn [(n String)] -> Bool (listAll? (fn [(k String)] -> Bool (!= k "consume")) (optionOr (mapGet useKinds n) (list)))))
        (termConsumed (setOf (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (listAppend acc (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (= u.kind "consume")) (termUses probe b.term))))) (list) f.blocks)))
        (tailArgs (setOf (fold (fn [(acc (List String)) (c (Pair String (List String)))] -> (List String) (listAppend acc (pairSecond c))) (list) (tailCalls f))))
        (sinkable (fn [(n String)] -> Bool (and (not (mapHas? termConsumed n)) (not (mapHas? tailArgs n)))))
        (derived (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? immortal n)) (and (or (borrowOnly n) (sinkable n)) (= (optionOr (mapGet kinds n) "") "source")))) sources)))
        (anchors (fold (fn [(acc (Map String String)) (n String)] -> (Map String String)
                         (mapSet acc n (mt (mapGet defs n) ((some op) (let [(b (sourceBase ctx op))] (if (= b "") "" (anchorOf ctx defs derived immortal b 64)))) ((none) ""))))
                       (mapEmpty) (mapKeys derived)))
        (dupAfter (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? immortal n)) (not (mapHas? derived n)))) sources)))
        (pinAfter (setOf (filter (fn [(n String)] -> Bool (= (optionOr (mapGet kinds n) "") "opaque")) (mapKeys heap))))
        (wrapAfter (setOf (filter (fn [(n String)] -> Bool (= (optionOr (mapGet kinds n) "") "wrap")) (mapKeys heap))))]
    (Facts :heap heap :immortal immortal :anchors anchors :dupAfter dupAfter :pinAfter pinAfter :wrapAfter wrapAfter :borrowed borrowed :flow flow.keys :parts parts :cells probe.cells))

fn tracked? facts: Facts v: String -> Bool
  (and (mapHas? facts.heap v) (and (not (mapHas? facts.immortal v)) (and (not (mapHas? facts.anchors v)) (not (mapHas? facts.borrowed v)))))

fn liveName facts: Facts v: String -> String
  (cond
    ((tracked? facts v) v)
    ((mapHas? facts.anchors v) (let [(a (optionOr (mapGet facts.anchors v) ""))] (if (and (!= a "") (tracked? facts a)) a "")))
    (else ""))

fn liveNames facts: Facts uses: (List Use) -> (List String)
  (filter (fn [(n String)] -> Bool (!= n "")) (map (fn [(u Use)] -> String (liveName facts u.name)) uses))

fn blockParamNames facts: Facts b: ty/SsaBlock -> (List String)
  (filter (fn [(n String)] -> Bool (tracked? facts n)) (map (fn [(p ty/SsaParam)] -> String p.name) b.params))

fn liveBack ctx: Ctx facts: Facts b: ty/SsaBlock liveOut: (Map String Bool) -> (Map String Bool)
  (let [(atTerm (union liveOut (setOf (liveNames facts (termUses facts b.term)))))
        (atStart (fold (fn [(live (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool)
                         (union (mapRemove live ins.dest) (setOf (liveNames facts (instrUses ctx facts ins)))))
                       atTerm (listReverse b.instrs)))]
    (without atStart (map (fn [(p ty/SsaParam)] -> String p.name) b.params)))

fn successors b: ty/SsaBlock -> (List String)
  (map (fn [(e ty/SsaEdge)] -> String e.target) (ty/termEdges b.term))

fn liveOutOf liveIn: (Map String (Map String Bool)) b: ty/SsaBlock -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (s String)] -> (Map String Bool) (union acc (optionOr (mapGet liveIn s) (mapEmpty)))) (mapEmpty) (successors b))

fn liveSize liveIn: (Map String (Map String Bool)) -> Int64
  (fold (fn [(acc Int64) (s (Map String Bool))] -> Int64 (+ acc (mapSize s))) 0 (mapValues liveIn))

fn liveness ctx: Ctx facts: Facts f: ty/SsaFunction liveIn: (Map String (Map String Bool)) fuel: Int64 -> (Map String (Map String Bool))
  (let [(next (fold (fn [(acc (Map String (Map String Bool))) (b ty/SsaBlock)] -> (Map String (Map String Bool))
                      (mapSet acc b.label (liveBack ctx facts b (liveOutOf acc b))))
                    liveIn (listReverse f.blocks)))]
    (if (or (<= fuel 0) (= (liveSize next) (liveSize liveIn))) next (liveness ctx facts f next (- fuel 1))))

fn fresh w: Walk -> String
  (str "rc." w.n)

fn emitRc w: Walk callee: String v: String -> Walk
  (Walk :live w.live :out (cons (rcCall (fresh w) callee v) w.out) :n (+ w.n 1) :pend w.pend)

fn prependAll w: Walk xs: (List ty/SsaInstr) -> Walk
  (Walk :live w.live :out (listAppend xs w.out) :n w.n :pend w.pend)

fn rcInstrs label: String w0: Int64 calls: (List (Pair String String)) -> (List ty/SsaInstr)
  (map (fn [(i Int64)] -> ty/SsaInstr
         (let [(c (optionOr (listGet calls i) (pair "" "")))]
           (rcCall (str "rc." label "." (+ w0 i)) (pairFirst c) (pairSecond c))))
       (range 0 (listLength calls)))

fn beforeCalls facts: Facts uses: (List Use) after: (Map String Bool) -> (List (Pair String String))
  (pairSecond
    (fold (fn [(acc (Pair (Map String Bool) (List (Pair String String)))) (u Use)] -> (Pair (Map String Bool) (List (Pair String String)))
            (let [(seen (pairFirst acc)) (calls (pairSecond acc)) (v u.name)]
              (cond
                ((= u.kind "pin") (if (mapHas? facts.immortal v) acc (pair seen (listAppend calls (list (pair (pinName) v))))))
                ((and (= u.kind "consume") (mapHas? facts.borrowed v)) (pair seen (listAppend calls (list (pair (dupName) v)))))
                ((and (= u.kind "consume") (mapHas? facts.anchors v)) (pair seen (listAppend calls (list (pair (dupName) v)))))
                ((and (= u.kind "consume") (tracked? facts v))
                  (if (or (mapHas? after v) (mapHas? seen v))
                    (pair (mapSet seen v true) (listAppend calls (list (pair (dupName) v))))
                    (pair (mapSet seen v true) calls)))
                (else acc))))
          (pair (mapEmpty) (list)) uses))

fn dropsAfter facts: Facts uses: (List Use) after: (Map String Bool) -> (List String)
  (let [(taken (setOf (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (or (= u.kind "consume") (= u.kind "pin"))) uses))))
        (names (liveNames facts uses))]
    (pairSecond (fold (fn [(acc (Pair (Map String Bool) (List String))) (n String)] -> (Pair (Map String Bool) (List String))
                        (if (or (mapHas? after n) (or (mapHas? taken n) (mapHas? (pairFirst acc) n)))
                          acc
                          (pair (mapSet (pairFirst acc) n true) (listAppend (pairSecond acc) (list n)))))
                      (pair (mapEmpty) (list)) names)))

fn resultCalls facts: Facts ins: ty/SsaInstr after: (Map String Bool) -> (List (Pair String String))
  (let [(d ins.dest)]
    (listAppend (listAppend (if (mapHas? facts.wrapAfter d) (list (pair (dupKidsName) d)) (list)) (sameAnchor ins))
    (cond
      ((mapHas? facts.pinAfter d) (list (pair (pinName) d)))
      ((and (mapHas? facts.dupAfter d) (mapHas? after d)) (list (pair (dupName) d)))
      ((mapHas? facts.dupAfter d) (list))
      ((and (tracked? facts d) (not (mapHas? after d))) (list (pair (dropName) d)))
      (else (list)))))

fn deferCalls drops: (List String) -> (List (Pair String String))
  (map (fn [(k Int64)] -> (Pair String String) (pair (if (= k 0) (deferFirstName) (deferName)) (optionOr (listGet drops k) "")))
       (range 0 (listLength drops)))

; (:m :ref RC-FBIP :do "a construct that allocates a pooled cell (a ctor of one to thirty-one fields, a cons) where an owned value read through its fields dies is preceded by a reset of that value: if it is unique its kids other than the fields moved into the construct are released and its cell becomes the construct's when the size class matches; moved fields are duplicated only when the value was shared")
fn allocClass ins: ty/SsaInstr -> Int64
  (mt ins.op
    ((ty/opConstruct _ _ fields) (if (or (listEmpty? fields) (> (listLength fields) 31)) -1 (* 2 (listLength fields))))
    ((ty/opEntry name _) (if (consumeEntry? name) 3 -1))
    (_ -1))

fn partOf op: ty/SsaOp -> (Option (Pair String Int64))
  (mt op
    ((ty/opVariantField b i) (some (pair b i)))
    ((ty/opEntry name args) (cond ((= name "@listFirst") (mt (listHead args) ((some b) (some (pair b 0))) ((none) (none))))
                                  ((= name "@listRest") (mt (listHead args) ((some b) (some (pair b 1))) ((none) (none))))
                                  (else (none))))
    (_ (none)))

fn partsOf instrs: (List ty/SsaInstr) -> (Map String (Pair String Int64))
  (fold (fn [(acc (Map String (Pair String Int64))) (i ty/SsaInstr)] -> (Map String (Pair String Int64))
          (mt (partOf i.op) ((some p) (mapSet acc i.dest p)) ((none) acc)))
        (mapEmpty) instrs)

fn cellBases parts: (Map String (Pair String Int64)) -> (Map String Bool)
  (setOf (map (fn [(p (Pair String Int64))] -> String (pairFirst p)) (mapValues parts)))

fn tokenName dest: String -> String
  (str "rcTok_" dest)

fn resetName cls: Int64 mask: Int64 -> String
  (str "aslRcReset_" cls "_" mask)

fn dupSharedName -> String
  "aslRcDupShared"

fn reusableDest? dest: String -> Bool
  (let [(b (stringToBytes dest))]
    (and (> (bytesLength b) 0) (let [(c (bytesGet b 0))] (not (and (>= c 48) (<= c 57))))))

fn movedFields facts: Facts x: String fields: (List String) -> (List String)
  (filter (fn [(f String)] -> Bool
            (and (= (listLength (filter (fn [(g String)] -> Bool (= g f)) fields)) 1)
                 (and (= (optionOr (mapGet facts.anchors f) "") x)
                      (mt (mapGet facts.parts f) ((some p) (and (= (pairFirst p) x) (< (pairSecond p) 62))) ((none) false)))))
          fields)

fn maskOf facts: Facts moved: (List String) -> Int64
  (fold (fn [(acc Int64) (f String)] -> Int64 (| acc (<< 1 (mt (mapGet facts.parts f) ((some p) (pairSecond p)) ((none) 0))))) 0 moved)

fn constructFields ins: ty/SsaInstr -> (List String)
  (mt ins.op ((ty/opConstruct _ _ fields) fields) ((ty/opEntry _ args) args) (_ (list)))

schema Reuse
  cell: String
  moved: (List String)
  callee: String

fn reusePlan facts: Facts ins: ty/SsaInstr dead: (List String) -> (Option Reuse)
  (let [(cls (allocClass ins))]
    (if (or (< cls 0) (or (listEmpty? dead) (not (reusableDest? ins.dest))))
      (none)
      (mt (listHead (filter (fn [(x String)] -> Bool (and (mapHas? facts.cells x) (tracked? facts x))) dead))
        ((none) (none))
        ((some x) (let [(moved (movedFields facts x (constructFields ins)))]
                    (some (Reuse :cell x :moved moved :callee (resetName cls (maskOf facts moved)))))))))

fn withoutDups calls: (List (Pair String String)) moved: (List String) -> (List (Pair String String))
  (if (listEmpty? moved) calls (pairSecond (fold (fn [(acc (Pair (Map String Bool) (List (Pair String String)))) (c (Pair String String))] -> (Pair (Map String Bool) (List (Pair String String)))
                      (let [(v (pairSecond c))]
                        (if (and (= (pairFirst c) (dupName)) (and (listContains? moved v) (not (mapHas? (pairFirst acc) v))))
                          (pair (mapSet (pairFirst acc) v true) (pairSecond acc))
                          (pair (pairFirst acc) (listAppend (pairSecond acc) (list c))))))
                    (pair (mapEmpty) (list)) calls)))

fn rewriteInstr ctx: Ctx facts: Facts label: String tail: Bool w: Walk ins: ty/SsaInstr -> Walk
  (let [(after w.live)
        (uses (instrUses ctx facts ins))
        (results (resultCalls facts ins after))
        (dead0 (dropsAfter facts uses after))
        (plan (if tail (none) (reusePlan facts ins dead0)))
        (moved (mt plan ((some r) r.moved) ((none) (list))))
        (before (withoutDups (beforeCalls facts uses after) moved))
        (late (mt plan ((some _) (none)) ((none) (if tail (none) (latePlan facts w.pend dead0)))))
        (gone (mt plan ((some r) (some r.cell)) ((none) (mt late ((some l) (some l.cell)) ((none) (none))))))
        (dead (mt gone ((some c) (filter (fn [(n String)] -> Bool (!= n c)) dead0)) ((none) dead0)))
        (deferred (and tail (and (listEmpty? results) (not (listEmpty? dead)))))
        (pre (if deferred (listAppend before (deferCalls dead)) before))
        (post (if deferred (list) (listAppend results (map (fn [(n String)] -> (Pair String String) (pair (dropName) n)) dead))))
        (n0 w.n)
        (shared (map (fn [(f String)] -> (Pair String String) (pair (dupSharedName) (str (tokenName ins.dest) "\t" f))) moved))
        (reuseIs (mt plan ((some r) (cons (rcCall (tokenName ins.dest) r.callee r.cell) (rcInstrs label (+ n0 (listLength pre)) shared))) ((none) (list))))
        (lateIs (mt late ((some l) (list (rcCall (tokenName l.target) l.callee l.cell))) ((none) (list))))
        (nPre (+ (listLength pre) (listLength shared)))
        (beforeIs (listAppend (rcInstrs label n0 pre) reuseIs))
        (afterIs (listAppend (rcInstrs label (+ n0 nPre) post) lateIs))
        (pend (cond ((some? late) (optionOr (listTail w.pend) (list)))
                    ((and (none? plan) (and (not tail) (and (>= (allocClass ins) 0) (reusableDest? ins.dest)))) (cons (pair ins.dest (allocClass ins)) w.pend))
                    (else w.pend)))
        (live (union (mapRemove after ins.dest) (setOf (liveNames facts uses))))]
    (Walk :live live :out (listAppend beforeIs (cons ins (listAppend afterIs w.out))) :n (+ n0 (+ nPre (listLength post))) :pend pend))

schema Late
  cell: String
  target: String
  callee: String

; (:m :ref RC-FBIP :do "an owned value read through its fields that dies before a later construct of the same block resets into the nearest such construct still without a cell; nothing it holds moves, so all its kids are released")
fn latePlan facts: Facts pend: (List (Pair String Int64)) dead: (List String) -> (Option Late)
  (mt (listHead pend)
    ((none) (none))
    ((some p) (mt (listHead (filter (fn [(x String)] -> Bool (and (mapHas? facts.cells x) (tracked? facts x))) dead))
                ((none) (none))
                ((some x) (some (Late :cell x :target (pairFirst p) :callee (resetName (pairSecond p) 0)))))))

fn trapBlock? blocks: (Map String ty/SsaBlock) target: String -> Bool
  (mt (mapGet blocks target)
    ((some b) (and (listEmpty? b.instrs) (mt b.term ((ty/termUnreachable) true) (_ false))))
    ((none) false))

fn edgeCalls facts: Facts liveIn: (Map String (Map String Bool)) atTerm: (Map String Bool) e: ty/SsaEdge -> (List (Pair String String))
  (let [(target (optionOr (mapGet liveIn e.target) (mapEmpty)))
        (passed (setOf e.args))
        (dups (pairSecond (fold (fn [(acc (Pair (Map String Bool) (List (Pair String String)))) (j Int64)] -> (Pair (Map String Bool) (List (Pair String String)))
                                  (let [(a (optionOr (listGet e.args j) ""))]
                                    (cond
                                      ((flowEdge? facts e.target j) acc)
                                      ((not (tracked? facts a))
                                        (if (mapHas? facts.borrowed a) (pair (pairFirst acc) (listAppend (pairSecond acc) (list (pair (dupName) a)))) acc))
                                      ((or (mapHas? target a) (mapHas? (pairFirst acc) a))
                                        (pair (mapSet (pairFirst acc) a true) (listAppend (pairSecond acc) (list (pair (dupName) a)))))
                                      (else (pair (mapSet (pairFirst acc) a true) (pairSecond acc))))))
                                (pair (mapEmpty) (list)) (range 0 (listLength e.args)))))
        (drops (map (fn [(n String)] -> (Pair String String) (pair (dropName) n))
                    (filter (fn [(n String)] -> Bool (and (not (mapHas? target n)) (not (mapHas? passed n)))) (mapKeys atTerm))))]
    (listAppend dups drops))

fn termWithEdges t: ty/SsaTerm edges: (List ty/SsaEdge) -> ty/SsaTerm
  (let [(at (fn [(k Int64)] -> ty/SsaEdge (optionOr (listGet edges k) (ty/ssaEdge "" (list)))))]
    (mt t
      ((ty/termJump _) (ty/termJump (at 0)))
      ((ty/termBranch c _ _) (ty/termBranch c (at 0) (at 1)))
      ((ty/termSwitch s typeName cases d)
        (ty/termSwitch s typeName
          (map (fn [(k Int64)] -> ty/SsaCase (let [(c (optionOr (listGet cases k) (ty/ssaCase "" (ty/ssaEdge "" (list)))))] (ty/ssaCase c.variant (at k)))) (range 0 (listLength cases)))
          (mt d ((some _) (some (at (listLength cases)))) ((none) (none)))))
      (_ t)))

fn predCounts blocks: (List ty/SsaBlock) -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (b ty/SsaBlock)] -> (Map String Int64)
          (fold (fn [(a (Map String Int64)) (s String)] -> (Map String Int64) (mapSet a s (+ 1 (optionOr (mapGet a s) 0)))) acc (successors b)))
        (mapEmpty) blocks)

fn placeEdges facts: Facts liveIn: (Map String (Map String Bool)) byLabel: (Map String ty/SsaBlock) preds: (Map String Int64) b: ty/SsaBlock atTerm: (Map String Bool) prefix: (Map String (List ty/SsaInstr)) -> Edges
  (let [(edges (ty/termEdges b.term))
        (single (= (listLength edges) 1))
        (step (fn [(acc Edges) (k Int64)] -> Edges
                (let [(e (optionOr (listGet edges k) (ty/ssaEdge "" (list))))
                      (calls (edgeCalls facts liveIn atTerm e))
                      (label (str "rc.e." b.label "." k))
                      (made (rcInstrs label 0 calls))
                      (lone (and (= (optionOr (mapGet preds e.target) 0) 1) (not single)))]
                  (cond
                    ((or (listEmpty? calls) (or single (trapBlock? byLabel e.target)))
                      (Edges :term acc.term :blocks acc.blocks :prefix acc.prefix :n acc.n))
                    (lone (Edges :term acc.term :blocks acc.blocks :prefix (mapSet acc.prefix e.target (listAppend (optionOr (mapGet acc.prefix e.target) (list)) made)) :n acc.n))
                    (else (Edges :term (termWithEdges acc.term (map (fn [(j Int64)] -> ty/SsaEdge (if (= j k) (ty/ssaEdge label (list)) (optionOr (listGet (ty/termEdges acc.term) j) (ty/ssaEdge "" (list))))) (range 0 (listLength edges))))
                                 :blocks (listAppend acc.blocks (list (ty/ssaBlock label (list) made (ty/termJump e))))
                                 :prefix acc.prefix :n (+ acc.n 1)))))))]
    (fold step (Edges :term b.term :blocks (list) :prefix prefix :n 0) (range 0 (listLength edges))))

fn jumpDups facts: Facts liveIn: (Map String (Map String Bool)) t: ty/SsaTerm -> (List (Pair String String))
  (mt t
    ((ty/termJump e) (edgeCalls facts liveIn (mapEmpty) e))
    ((ty/termReturn v) (if (and (mapHas? facts.borrowed v) (not (mapHas? facts.flow "$ret"))) (list (pair (dupName) v)) (list)))
    (_ (list)))

fn tailClosureDest b: ty/SsaBlock -> String
  (mt b.term
    ((ty/termReturn v) (mt (listHead (listReverse b.instrs))
                         ((some ins) (mt ins.op ((ty/opCallClosure _ _) (if (= ins.dest v) v "")) (_ "")))
                         ((none) "")))
    (_ ""))

fn rewriteBlock ctx: Ctx facts: Facts liveIn: (Map String (Map String Bool)) byLabel: (Map String ty/SsaBlock) preds: (Map String Int64) entry: Bool fnParams: (List String) b: ty/SsaBlock prefix: (Map String (List ty/SsaInstr)) -> (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))
  (let [(liveOut (liveOutOf liveIn b))
        (termUsed (termUses facts b.term))
        (atTerm (union liveOut (setOf (liveNames facts termUsed))))
        (placed (placeEdges facts liveIn byLabel preds b atTerm prefix))
        (jumpCalls (jumpDups facts liveIn b.term))
        (start (Walk :live atTerm :out (rcInstrs (str b.label ".j") 0 jumpCalls) :n 0 :pend (list)))
        (tailDest (tailClosureDest b))
        (walked (fold (fn [(w Walk) (ins ty/SsaInstr)] -> Walk (rewriteInstr ctx facts b.label (and (!= tailDest "") (and (= ins.dest tailDest) (listEmpty? w.out))) w ins)) start (listReverse b.instrs)))
        (defined (listAppend (blockParamNames facts b) (if entry fnParams (list))))
        (deadAtStart (filter (fn [(n String)] -> Bool (not (mapHas? walked.live n))) defined))
        (startDrops (rcInstrs (str b.label ".s") 0 (map (fn [(n String)] -> (Pair String String) (pair (dropName) n)) deadAtStart)))
        (main (ty/ssaBlock b.label b.params (listAppend startDrops walked.out) placed.term))]
    (pair (cons main placed.blocks) placed.prefix))

fn withPrefix b: ty/SsaBlock prefix: (Map String (List ty/SsaInstr)) -> ty/SsaBlock
  (mt (mapGet prefix b.label)
    ((none) b)
    ((some xs) (ty/ssaBlock b.label b.params (listAppend xs b.instrs) b.term)))

fn closureCallee op: ty/SsaOp -> (Option String)
  (mt op ((ty/opMakeClosure callee _) (some callee)) (_ (none)))

fn retarget targets: (Map String Bool) ins: ty/SsaInstr -> ty/SsaInstr
  (mt ins.op
    ((ty/opMakeClosure callee caps) (if (mapHas? targets callee) (ty/ssaInstr ins.dest ins.ty (ty/opMakeClosure (wrapperName callee) caps)) ins))
    (_ ins))

fn retargetClosures targets: (Map String Bool) f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock (ty/ssaBlock b.label b.params (map (fn [(ins ty/SsaInstr)] -> ty/SsaInstr (retarget targets ins)) b.instrs) b.term)) f.blocks))

fn rcFunction ctx: Ctx f: ty/SsaFunction -> ty/SsaFunction
  (let [(facts (functionFacts ctx f))
        (liveIn (liveness ctx facts f (mapEmpty) 1000))
        (byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))
        (preds (predCounts f.blocks))
        (fnParams (filter (fn [(n String)] -> Bool (tracked? facts n)) (map (fn [(p ty/SsaParam)] -> String p.name) (listAppend f.captures f.params))))
        (entryLabel (mt (listHead f.blocks) ((some b) b.label) ((none) "")))
        (rewritten (fold (fn [(acc (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))) (b ty/SsaBlock)] -> (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))
                           (let [(r (rewriteBlock ctx facts liveIn byLabel preds (= b.label entryLabel) fnParams b (pairSecond acc)))]
                             (pair (listAppend (pairFirst acc) (pairFirst r)) (pairSecond r))))
                         (pair (list) (mapEmpty)) f.blocks))
        (blocks (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock (withPrefix b (pairSecond rewritten))) (pairFirst rewritten)))]
    (ty/ssaFunction f.name f.captures f.params f.retTy blocks))

fn wrapperFunction f: ty/SsaFunction opaque: Bool -> ty/SsaFunction
  (let [(all (listAppend f.captures f.params))
        (heap (filter (fn [(p ty/SsaParam)] -> Bool (heapTy? p.ty)) all))
        (names (map (fn [(p ty/SsaParam)] -> String p.name) all))
        (heapNames (map (fn [(p ty/SsaParam)] -> String p.name) heap))
        (pre (map (fn [(i Int64)] -> ty/SsaInstr (rcCall (str "rc.w." i) (if opaque (pinName) (dupName)) (optionOr (listGet heapNames i) "")))
                  (range 0 (listLength heapNames))))
        (call (ty/ssaInstr "rc.r" f.retTy (ty/opCall f.name names)))
        (post (if (and opaque (heapTy? f.retTy)) (list (rcCall "rc.rp" (pinName) "rc.r")) (list)))]
    (ty/ssaFunction (wrapperName f.name) f.captures f.params f.retTy
      (list (ty/ssaBlock "entry" (list) (listAppend pre (cons call post)) (ty/termReturn "rc.r")))))

fn uncaptured f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name (list) (listAppend f.captures f.params) f.retTy f.blocks)

fn distinctNames xs: (List String) -> (List String)
  (mapKeys (setOf xs))

fn rcModule m: ty/SsaModule user: (Map String Bool) -> ty/SsaModule
  (let [(builders (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) (filter ssa/listBuilder? m.functions))))
        (names (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) m.functions)))
        (singletons (setOf (filter opt/singleton? (mapKeys names))))
        (routed (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? user n)) (countedRoute? n))) (mapKeys names))))
        (ctx0 (Ctx :user (union (union user singletons) routed) :opaque builders :builders builders :borrows (mapEmpty) :scc (mapEmpty) :proj (mapEmpty)))
        (targets (setOf (filter (fn [(n String)] -> Bool (mapHas? names n))
                                (distinctNames (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                                                       (listAppend acc (fold (fn [(a (List String)) (ins ty/SsaInstr)] -> (List String) (mt (closureCallee ins.op) ((some c) (cons c a)) ((none) a))) (list) (functionInstrs f))))
                                                     (list) m.functions)))))
        (counted (fn [(f ty/SsaFunction)] -> Bool (not (opaqueFunction? ctx0 f.name))))
        (countedFns (filter counted m.functions))
        (ctxS (Ctx :user ctx0.user :opaque ctx0.opaque :builders ctx0.builders :borrows ctx0.borrows :scc (sccOf m.functions targets) :proj (mapEmpty)))
        (borrows0 (initialBorrows countedFns targets))
        (ctxB (withBorrows ctxS borrows0))
        (ctx (settleProj (withProj ctxB (growProj ctxB (filter (fn [(f ty/SsaFunction)] -> Bool (borrowable? targets f)) countedFns) 50)) countedFns borrows0 50))
        (bodies (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction
                       (let [(g (retargetClosures targets (if (counted f) (rcFunction ctx f) f)))]
                         (if (mapHas? targets f.name) (uncaptured g) g)))
                     m.functions))
        (wrappers (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (wrapperFunction f (not (counted f))))
                       (filter (fn [(f ty/SsaFunction)] -> Bool (mapHas? targets f.name)) m.functions)))
        (have (setOf (map (fn [(e ty/SsaExtern)] -> String e.name) m.externs)))
        (externs (listAppend m.externs (filter (fn [(e ty/SsaExtern)] -> Bool (not (mapHas? have e.name))) (listAppend (rcExterns) (reuseExterns bodies)))))]
    (ty/ssaModule m.name m.strings m.types m.records externs m.globals (listAppend bodies wrappers)))

fn sticky -> Int64
  71776119061217280

fn countOne -> Int64
  281474976710656

fn keepMask -> Int64
  -71777218572845056

fn sentinel -> Int64
  -559038737

fn classes -> Int64
  63

fn lines xs: (List String) -> String
  (stringJoin xs "\n")

fn objText notrace: Bool -> String
  (lines (list "define internal ptr @aslRc.obj(%Val %v) alwaysinline {"
               "entry:"
               "  %w0 = extractvalue %Val %v, 0"
               "  %tag = and i64 %w0, 4294967295"
               "  %ow = extractvalue %Val %v, 1"
               "  %lo = icmp sge i64 %tag, 5"
               "  %hi = icmp sle i64 %tag, 15"
               "  %nb = icmp ne i64 %tag, 10"
               "  %nz = icmp ne i64 %ow, 0"
               "  %a = and i1 %lo, %hi"
               "  %b = and i1 %nb, %nz"
               "  %has = and i1 %a, %b"
               "  br i1 %has, label %obj, label %none"
               "obj:"
               "  %o = inttoptr i64 %ow to ptr"
               "  %h = load i64, ptr %o"
               "  %ty = lshr i64 %h, 32"
               "  %ty8 = and i64 %ty, 255"
               "  %small = icmp ule i64 %ty8, 4"
               "  %cls = lshr i64 %h, 56"
               "  %pooled = icmp ne i64 %cls, 255"
               (if notrace "  %arr = icmp eq i64 %ty8, 6\n  %hnd = icmp eq i64 %ty8, 7\n  %ext = or i1 %arr, %hnd\n  %ok = or i1 %small, %ext" "  %ok = and i1 %small, %pooled")
               "  br i1 %ok, label %yes, label %none"
               "yes:"
               "  ret ptr %o"
               "none:"
               "  ret ptr null"
               "}"))

fn liveCheckText -> String
  (lines (list "define internal void @aslRc.live(ptr %o, i64 %h) alwaysinline {"
               "entry:"
               "  %ty = lshr i64 %h, 32"
               "  %ty8 = and i64 %ty, 255"
               "  %ctor = icmp eq i64 %ty8, 3"
               "  br i1 %ctor, label %id, label %ok"
               "id:"
               "  %idp = getelementptr inbounds i8, ptr %o, i64 8"
               "  %idv = load i32, ptr %idp"
               (str "  %freed = icmp eq i32 %idv, " (sentinel))
               "  br i1 %freed, label %bad, label %ok"
               "bad:"
               "  call void @llvm.trap()"
               "  unreachable"
               "ok:"
               "  ret void"
               "}"))

fn dupText asan: Bool -> String
  (lines (list (str "define internal tailcc i64 @" (dupName) "(%Val %v) alwaysinline {")
               "entry:"
               "  %o = call ptr @aslRc.obj(%Val %v)"
               "  %z = icmp eq ptr %o, null"
               (opStats asan)
               "  br i1 %z, label %done, label %live"
               "live:"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.live(ptr %o, i64 %h)"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %stuck = icmp eq i64 %c8, 255"
               "  br i1 %stuck, label %done, label %inc"
               "inc:"
               (str "  %h1 = add i64 %h, " (countOne))
               "  store i64 %h1, ptr %o"
               "  br label %done"
               "done:"
               "  ret i64 0"
               "}"))

fn dropText asan: Bool -> String
  (lines (list (str "define internal tailcc i64 @" (dropName) "(%Val %v) alwaysinline {")
               "entry:"
               "  %o = call ptr @aslRc.obj(%Val %v)"
               "  %z = icmp eq ptr %o, null"
               (opStats asan)
               "  br i1 %z, label %done, label %live"
               "live:"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.live(ptr %o, i64 %h)"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %stuck = icmp eq i64 %c8, 255"
               "  br i1 %stuck, label %done, label %count"
               "count:"
               "  %last = icmp eq i64 %c8, 0"
               "  br i1 %last, label %free, label %dec"
               "dec:"
               (str "  %h1 = sub i64 %h, " (countOne))
               "  store i64 %h1, ptr %o"
               "  br label %done"
               "free:"
               "  call void @aslRc.freeOne(ptr %o)"
               "  br label %done"
               "done:"
               "  ret i64 0"
               "}"))

; (:m :ref RC-PERF :do "a cell whose count is zero frees; a list spine frees in one loop, each tail whose count reaches zero taking the next turn instead of a push and pop through the pending stack")
fn claimText -> String
  (lines (list "define internal i1 @aslRc.claim(ptr %o) alwaysinline {"
               "entry:"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.live(ptr %o, i64 %h)"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %stuck = icmp eq i64 %c8, 255"
               "  br i1 %stuck, label %kept, label %count"
               "count:"
               "  %last = icmp eq i64 %c8, 0"
               "  br i1 %last, label %free, label %dec"
               "dec:"
               (str "  %h1 = sub i64 %h, " (countOne))
               "  store i64 %h1, ptr %o"
               "  br label %kept"
               "kept:"
               "  ret i1 false"
               "free:"
               "  ret i1 true"
               "}"))


; (:m :ref RC-RELEASEKIDS :do "a freed object's dying kids never go through release: a kid without kids (string, bytes, box, array) is recycled on the spot, and of the kids that have kids one becomes the next turn of the loop while only the others are pushed, so a list spine, a tree path or a record chain frees with no pending-stack traffic")
fn kidText p: String k: String go: String -> (List String)
  (list (str p "Claim:")
        (str "  %" p "Free = call i1 @aslRc.claim(ptr %" k ")")
        (str "  br i1 %" p "Free, label %" p "Dies, label %" go)
        (str p "Dies:")
        (str "  %" p "H = load i64, ptr %" k)
        (str "  %" p "Ty = lshr i64 %" p "H, 32")
        (str "  %" p "Ty8 = and i64 %" p "Ty, 255")
        (str "  %" p "Ty1 = sub i64 %" p "Ty8, 1")
        (str "  %" p "Nest = icmp ult i64 %" p "Ty1, 4")
        (str "  br i1 %" p "Nest, label %" p "Keep, label %" p "Leaf")
        (str p "Leaf:")
        (str "  call void @aslRc.recycle(ptr %" k ", i64 %" p "H)")
        (str "  br label %" go))

fn freeChainText asan: Bool -> String
  (lines (listAppend
           (list "define internal void @aslRc.freeChain(ptr %o) {"
                 "entry:"
                 "  br label %top"
                 "top:"
                 "  %p = phi ptr [ %o, %entry ], [ %t, %next ], [ %hn, %headNext ], [ %nx, %kidsNext ]"
                 "  %ph = load i64, ptr %p"
                 "  %ty = lshr i64 %ph, 32"
                 "  %ty8 = and i64 %ty, 255"
                 "  switch i64 %ty8, label %leaf [ i64 1, label %cons i64 2, label %rec i64 3, label %ctor i64 4, label %clo ]"
                 "cons:"
                 "  %hp = getelementptr inbounds i8, ptr %p, i64 8"
                 "  %hd = load %Val, ptr %hp"
                 "  %tp = getelementptr inbounds i8, ptr %p, i64 24"
                 "  %tl = load %Val, ptr %tp"
                 "  %h = call ptr @aslRc.obj(%Val %hd)"
                 "  %hz = icmp eq ptr %h, null"
                 "  br i1 %hz, label %consTail, label %headClaim")
           (listAppend (kidText "head" "h" "consTail")
           (listAppend
             (list "headKeep:"
                   "  br label %consTail"
                   "consTail:"
                   "  %hn = phi ptr [ null, %cons ], [ null, %headClaim ], [ null, %headLeaf ], [ %h, %headKeep ]"
                   "  call void @aslRc.recycle(ptr %p, i64 %ph)"
                   "  %t = call ptr @aslRc.obj(%Val %tl)"
                   "  %tz = icmp eq ptr %t, null"
                   "  br i1 %tz, label %headOnly, label %tail"
                   "tail:"
                   "  %free = call i1 @aslRc.claim(ptr %t)"
                   "  br i1 %free, label %both, label %headOnly"
                   "both:"
                   "  %hk = icmp ne ptr %hn, null"
                   "  br i1 %hk, label %headPush, label %next"
                   "headPush:"
                   "  call void @aslRc.push(ptr %hn)"
                   (if asan (statBump "pushedHead" (statPushed)) "")
                   "  br label %next"
                   "next:"
                   "  br label %top"
                   "headOnly:"
                   "  %hgo = icmp ne ptr %hn, null"
                   "  br i1 %hgo, label %headNext, label %done"
                   "headNext:"
                   "  br label %top"
                   "rec:"
                   "  %rnp = getelementptr inbounds i8, ptr %p, i64 12"
                   "  %rn32 = load i32, ptr %rnp"
                   "  %rn = sext i32 %rn32 to i64"
                   "  %rb = getelementptr inbounds i8, ptr %p, i64 24"
                   "  br label %kids"
                   "ctor:"
                   "  %fnp = getelementptr inbounds i8, ptr %p, i64 12"
                   "  %fn32 = load i32, ptr %fnp"
                   "  %fn = sext i32 %fn32 to i64"
                   "  %fb = getelementptr inbounds i8, ptr %p, i64 16"
                   "  br label %kids"
                   "clo:"
                   "  %unp = getelementptr inbounds i8, ptr %p, i64 16"
                   "  %un32 = load i32, ptr %unp"
                   "  %un = sext i32 %un32 to i64"
                   "  %ub = getelementptr inbounds i8, ptr %p, i64 24"
                   "  br label %kids"
                   "leaf:"
                   "  br label %kids"
                   "kids:"
                   "  %base = phi ptr [ %rb, %rec ], [ %fb, %ctor ], [ %ub, %clo ], [ %p, %leaf ]"
                   "  %n = phi i64 [ %rn, %rec ], [ %fn, %ctor ], [ %un, %clo ], [ 0, %leaf ]"
                   "  br label %loop"
                   "loop:"
                   "  %i = phi i64 [ 0, %kids ], [ %i1, %step ]"
                   "  %nx = phi ptr [ null, %kids ], [ %nx1, %step ]"
                   "  %more = icmp slt i64 %i, %n"
                   "  br i1 %more, label %body, label %kidsDone"
                   "body:"
                   "  %off = mul i64 %i, 16"
                   "  %at = getelementptr inbounds i8, ptr %base, i64 %off"
                   "  %kid = load %Val, ptr %at"
                   "  %k = call ptr @aslRc.obj(%Val %kid)"
                   "  %kz = icmp eq ptr %k, null"
                   "  br i1 %kz, label %step, label %kidClaim")
           (listAppend (kidText "kid" "k" "step")
             (list "kidKeep:"
                   "  %had = icmp ne ptr %nx, null"
                   "  br i1 %had, label %kidPush, label %step"
                   "kidPush:"
                   "  call void @aslRc.push(ptr %nx)"
                   (if asan (statBump "pushedKid" (statPushed)) "")
                   "  br label %step"
                   "step:"
                   "  %nx1 = phi ptr [ %nx, %body ], [ %nx, %kidClaim ], [ %nx, %kidLeaf ], [ %k, %kidKeep ], [ %k, %kidPush ]"
                   "  %i1 = add i64 %i, 1"
                   "  br label %loop"
                   "kidsDone:"
                   "  call void @aslRc.recycle(ptr %p, i64 %ph)"
                   "  %go = icmp ne ptr %nx, null"
                   "  br i1 %go, label %kidsNext, label %done"
                   "kidsNext:"
                   "  br label %top"
                   "done:"
                   "  ret void"
                   "}"))))))

fn freeOneText -> String
  (lines (list "define internal void @aslRc.freeOne(ptr %o) noinline {"
               "entry:"
               "  call void @aslRc.freeChain(ptr %o)"
               "  %sp = load i64, ptr @aslRc.sp"
               "  %pending = icmp ne i64 %sp, 0"
               "  br i1 %pending, label %drain, label %done"
               "drain:"
               "  call void @aslRc.drain()"
               "  br label %done"
               "done:"
               "  ret void"
               "}"))

fn pushText -> String
  (lines (list "define internal void @aslRc.push(ptr %o) {"
               "entry:"
               "  %sp = load i64, ptr @aslRc.sp"
               "  %cap = load i64, ptr @aslRc.cap"
               "  %full = icmp eq i64 %sp, %cap"
               "  br i1 %full, label %grow, label %put"
               "grow:"
               "  %zero = icmp eq i64 %cap, 0"
               "  %twice = mul i64 %cap, 2"
               "  %ncap = select i1 %zero, i64 1024, i64 %twice"
               "  %bytes = mul i64 %ncap, 8"
               "  %old = load ptr, ptr @aslRc.stack"
               "  %new = call ptr @realloc(ptr %old, i64 %bytes)"
               "  %dead = icmp eq ptr %new, null"
               "  br i1 %dead, label %oom, label %grown"
               "oom:"
               "  call void @llvm.trap()"
               "  unreachable"
               "grown:"
               "  store ptr %new, ptr @aslRc.stack"
               "  store i64 %ncap, ptr @aslRc.cap"
               "  br label %put"
               "put:"
               "  %stk = load ptr, ptr @aslRc.stack"
               "  %at = getelementptr ptr, ptr %stk, i64 %sp"
               "  store ptr %o, ptr %at"
               "  %sp1 = add i64 %sp, 1"
               "  store i64 %sp1, ptr @aslRc.sp"
               "  ret void"
               "}"))

fn childrenText name: String visit: String -> String
  (lines (list (str "define internal void @aslRc." name "(ptr %o, i64 %h) {")
               "entry:"
               "  %ty = lshr i64 %h, 32"
               "  %ty8 = and i64 %ty, 255"
               "  switch i64 %ty8, label %done [ i64 1, label %cons i64 2, label %rec i64 3, label %ctor i64 4, label %clo ]"
               "cons:"
               "  %cb = getelementptr inbounds i8, ptr %o, i64 8"
               "  br label %kids"
               "rec:"
               "  %rnp = getelementptr inbounds i8, ptr %o, i64 12"
               "  %rn32 = load i32, ptr %rnp"
               "  %rn = sext i32 %rn32 to i64"
               "  %rb = getelementptr inbounds i8, ptr %o, i64 24"
               "  br label %kids"
               "ctor:"
               "  %fnp = getelementptr inbounds i8, ptr %o, i64 12"
               "  %fn32 = load i32, ptr %fnp"
               "  %fn = sext i32 %fn32 to i64"
               "  %fb = getelementptr inbounds i8, ptr %o, i64 16"
               "  br label %kids"
               "clo:"
               "  %unp = getelementptr inbounds i8, ptr %o, i64 16"
               "  %un32 = load i32, ptr %unp"
               "  %un = sext i32 %un32 to i64"
               "  %ub = getelementptr inbounds i8, ptr %o, i64 24"
               "  br label %kids"
               "kids:"
               "  %base = phi ptr [ %cb, %cons ], [ %rb, %rec ], [ %fb, %ctor ], [ %ub, %clo ]"
               "  %n = phi i64 [ 2, %cons ], [ %rn, %rec ], [ %fn, %ctor ], [ %un, %clo ]"
               "  br label %loop"
               "loop:"
               "  %i = phi i64 [ 0, %kids ], [ %i1, %body ]"
               "  %more = icmp slt i64 %i, %n"
               "  br i1 %more, label %body, label %done"
               "body:"
               "  %off = mul i64 %i, 16"
               "  %at = getelementptr inbounds i8, ptr %base, i64 %off"
               "  %kid = load %Val, ptr %at"
               (str "  call void @aslRc." visit "(%Val %kid)")
               "  %i1 = add i64 %i, 1"
               "  br label %loop"
               "done:"
               "  ret void"
               "}"))

fn drainText -> String
  (lines (list "define internal void @aslRc.drain() {"
               "entry:"
               "  br label %loop"
               "loop:"
               "  %sp = load i64, ptr @aslRc.sp"
               "  %empty = icmp eq i64 %sp, 0"
               "  br i1 %empty, label %done, label %pop"
               "pop:"
               "  %sp1 = sub i64 %sp, 1"
               "  store i64 %sp1, ptr @aslRc.sp"
               "  %stk = load ptr, ptr @aslRc.stack"
               "  %at = getelementptr ptr, ptr %stk, i64 %sp1"
               "  %o = load ptr, ptr %at"
               "  call void @aslRc.freeChain(ptr %o)"
               "  br label %loop"
               "done:"
               "  ret void"
               "}"))

fn statFreed -> Int64
  0

fn statStuck -> Int64
  1

fn statReused -> Int64
  2

fn statPinned -> Int64
  3

fn statFresh -> Int64
  4

fn statLarge -> Int64
  5

fn statLargeFreed -> Int64
  6

fn statPushed -> Int64
  7

fn statOps -> Int64
  8

fn statImmediate -> Int64
  9

fn statFbip -> Int64
  10

fn statResets -> Int64
  11

fn statSpare -> Int64
  12

fn statSlots -> Int64
  13

fn statBump p: String slot: Int64 -> String
  (lines (list (str "  %" p ".sp = getelementptr [" (statSlots) " x i64], ptr @aslRc.stats, i64 0, i64 " slot)
               (str "  %" p ".sv = load i64, ptr %" p ".sp")
               (str "  %" p ".sv1 = add i64 %" p ".sv, 1")
               (str "  store i64 %" p ".sv1, ptr %" p ".sp")))

; (:m :ref RC-FBIP :do "under ASan every dup and drop is counted, and so is each one whose value is no heap object, so a gate can observe RC traffic on a fixed program without a counter on the production path")
fn opStats asan: Bool -> String
  (if asan
    (lines (list (statBump "ops" (statOps))
                 (str "  %imm.sp = getelementptr [" (statSlots) " x i64], ptr @aslRc.stats, i64 0, i64 " (statImmediate))
                 "  %imm.sv = load i64, ptr %imm.sp"
                 "  %imm.z = zext i1 %z to i64"
                 "  %imm.sv1 = add i64 %imm.sv, %imm.z"
                 "  store i64 %imm.sv1, ptr %imm.sp"))
    "")

fn poisonText asan: Bool -> (List String)
  (if asan
    (list "  %big32 = icmp ugt i64 %ss, 32"
          "  br i1 %big32, label %poison, label %linked"
          "poison:"
          "  %body = getelementptr inbounds i8, ptr %o, i64 32"
          "  %plen = sub i64 %ss, 32"
          "  call void @__asan_poison_memory_region(ptr %body, i64 %plen)"
          "  br label %linked"
          "linked:")
    (list))

; (:m :ref RC-PERF :do "with a rooted runtime the common case, a pooled class of two or more, is inlined into the free path; large, small and sticky cells take the outlined slow path, so the hot path carries no spills for the rare ones")
fn recycleText asan: Bool rooted: Bool notrace: Bool -> String
  (if rooted
    (lines (list (recycleFastText asan) (recycleBody "recycleSlow" asan rooted notrace)))
    (recycleBody "recycle" asan rooted notrace))

fn recycleFastText asan: Bool -> String
  (lines (listAppend (list "define internal void @aslRc.recycle(ptr %o, i64 %h) alwaysinline {"
                           "entry:"
                           "  %cls = lshr i64 %h, 56"
                           "  %big = icmp uge i64 %cls, 2"
                           "  %pooled = icmp ne i64 %cls, 255"
                           "  %fast = and i1 %big, %pooled"
                           "  br i1 %fast, label %node, label %slow"
                           "slow:"
                           "  call void @aslRc.recycleSlow(ptr %o, i64 %h)"
                           "  ret void"
                           "node:"
                           (statBump "freed" (statFreed)))
                     (listAppend (recycleNodeText) (listAppend (poisonText asan) (recycleLinkText)))))

fn recycleBody name: String asan: Bool rooted: Bool notrace: Bool -> String
  (lines (listAppend
           (list (str "define internal void @aslRc." name "(ptr %o, i64 %h) {")
                 "entry:"
                 "  %cls = lshr i64 %h, 56"
                 "  %big = icmp uge i64 %cls, 2"
                 (if notrace "  %isLarge = icmp eq i64 %cls, 255\n  br i1 %isLarge, label %largeFree, label %classed\nclassed:" "")
                 (if rooted "  br i1 %big, label %node, label %smallNode" "  br label %small")
                 (if notrace (largeFreeText) "")
                 "small:"
                 (str "  %hs = or i64 %h, " (sticky))
                 "  store i64 %hs, ptr %o"
                 (statBump "stuck" (statStuck))
                 "  ret void")
           (if rooted
             (cons "smallNode:" (cons (statBump "smallFreed" (statFreed))
               (listAppend (smallNodeText)
                 (cons "node:" (cons (statBump "freed" (statFreed)) (listAppend (recycleNodeText) (listAppend (poisonText asan) (recycleLinkText))))))))
             (list "}"))))

fn largeFreeText -> String
  (lines (list "largeFree:"
               (statBump "largeFreed" (statLargeFreed))
               "  %lty = lshr i64 %h, 32"
               "  %lty8 = and i64 %lty, 255"
               "  %isArr = icmp eq i64 %lty8, 6"
               "  br i1 %isArr, label %largeData, label %largeHandle"
               "largeData:"
               "  %ldp = getelementptr inbounds i8, ptr %o, i64 24"
               "  %ld = load ptr, ptr %ldp"
               "  call void @free(ptr %ld)"
               "  br label %largeRelease"
               "largeHandle:"
               "  %isHnd = icmp eq i64 %lty8, 7"
               "  br i1 %isHnd, label %largeFin, label %largeRelease"
               "largeFin:"
               "  %lfp = getelementptr inbounds i8, ptr %o, i64 24"
               "  %lf = load ptr, ptr %lfp"
               "  %lnf = icmp eq ptr %lf, null"
               "  br i1 %lnf, label %largeRelease, label %largeCall"
               "largeCall:"
               "  %lap = getelementptr inbounds i8, ptr %o, i64 16"
               "  %la = load ptr, ptr %lap"
               "  call void %lf(ptr %la)"
               "  br label %largeRelease"
               "largeRelease:"
               "  %lo = getelementptr inbounds i8, ptr %o, i64 -24"
               "  call void @free(ptr %lo)"
               "  ret void"))

fn recycleNodeText -> (List String)
  (list "  %cls2 = add i64 %cls, 2"
        "  %ss = mul i64 %cls2, 8"
        (str "  %keep = and i64 %h, " (keepMask))
        "  %h1 = or i64 %keep, %ss"
        "  %h2 = or i64 %h1, 12884901888"
        "  store i64 %h2, ptr %o"
        "  %idp = getelementptr inbounds i8, ptr %o, i64 8"
        (str "  store i32 " (sentinel) ", ptr %idp")
        "  %np = getelementptr inbounds i8, ptr %o, i64 12"
        "  store i32 1, ptr %np")

fn recycleLinkText -> (List String)
  (list (str "  %headp = getelementptr [" (classes) " x %Val], ptr @aslRc.free, i64 0, i64 %cls")
        "  %head = load %Val, ptr %headp"
        "  %fp = getelementptr inbounds i8, ptr %o, i64 16"
        "  store %Val %head, ptr %fp"
        "  %ow = ptrtoint ptr %o to i64"
        "  %nv = insertvalue %Val { i64 8, i64 0 }, i64 %ow, 1"
        "  store %Val %nv, ptr %headp"
        (str "  %rp = getelementptr [" (classes) " x i8], ptr @aslRc.rooted, i64 0, i64 %cls")
        "  %r = load i8, ptr %rp"
        "  %fresh = icmp eq i8 %r, 0"
        "  br i1 %fresh, label %root, label %done"
        "root:"
        "  store i8 1, ptr %rp"
        "  call void @asl_rt_global_root(ptr %headp)"
        "  br label %done"
        "done:"
        "  ret void"
        "}")

fn pinValText notrace: Bool -> String
  (lines (list "define internal void @aslRc.pinVal(%Val %v) {"
               "entry:"
               "  %w0 = extractvalue %Val %v, 0"
               "  %tag = and i64 %w0, 4294967295"
               "  %ow = extractvalue %Val %v, 1"
               "  %lo = icmp sge i64 %tag, 5"
               "  %hi = icmp sle i64 %tag, 15"
               "  %nb = icmp ne i64 %tag, 10"
               "  %nz = icmp ne i64 %ow, 0"
               "  %a = and i1 %lo, %hi"
               "  %b = and i1 %nb, %nz"
               "  %has = and i1 %a, %b"
               "  br i1 %has, label %obj, label %done"
               "obj:"
               "  %o = inttoptr i64 %ow to ptr"
               "  %h = load i64, ptr %o"
               "  %ty = lshr i64 %h, 32"
               "  %ty8 = and i64 %ty, 255"
               (if notrace "  %over = icmp ugt i64 %ty8, 7\n  %raw = icmp eq i64 %ty8, 5\n  %leafy = or i1 %over, %raw" "  %leafy = icmp ugt i64 %ty8, 4")
               "  br i1 %leafy, label %done, label %kind"
               "kind:"
               "  %cls = lshr i64 %h, 56"
               "  %pooled = icmp ne i64 %cls, 255"
               (if notrace "  br label %counted" "  br i1 %pooled, label %counted, label %walk")
               "counted:"
               "  call void @aslRc.live(ptr %o, i64 %h)"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %stuck = icmp eq i64 %c8, 255"
               "  br i1 %stuck, label %done, label %stick"
               "stick:"
               (str "  %hs = or i64 %h, " (sticky))
               "  store i64 %hs, ptr %o"
               (statBump "pinned" (statPinned))
               "  br label %walk"
               "walk:"
               "  call void @aslRc.push(ptr %o)"
               "  br label %done"
               "done:"
               "  ret void"
               "}"))

fn pinText -> String
  (lines (list (str "define internal tailcc i64 @" (pinName) "(%Val %v) {")
               "entry:"
               "  %sp0 = load i64, ptr @aslRc.sp"
               "  call void @aslRc.pinVal(%Val %v)"
               "  br label %loop"
               "loop:"
               "  %sp = load i64, ptr @aslRc.sp"
               "  %more = icmp ugt i64 %sp, %sp0"
               "  br i1 %more, label %pop, label %done"
               "pop:"
               "  %sp1 = sub i64 %sp, 1"
               "  store i64 %sp1, ptr @aslRc.sp"
               "  %stk = load ptr, ptr @aslRc.stack"
               "  %at = getelementptr ptr, ptr %stk, i64 %sp1"
               "  %o = load ptr, ptr %at"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.pinKids(ptr %o, i64 %h)"
               "  br label %loop"
               "done:"
               "  ret i64 0"
               "}"))

fn allocFastSym sc: Int64 -> String
  (str "@gcAsl.allocFast." sc)

fn rcAllocSym sc: Int64 -> String
  (str "@aslRc.allocFast." sc)

fn unpoisonText asan: Bool sc: Int64 -> (List String)
  (if asan (list (str "  call void @__asan_unpoison_memory_region(ptr %o, i64 " (* 8 (+ sc 2)) ")")) (list))

fn allocText sym: String fallback: String sc: Int64 asan: Bool -> String
  (lines (listAppend
           (list (str "define internal ptr " sym "(i32 %t, i64 %n) {")
                 "entry:"
                 (str "  %slot = getelementptr [" (classes) " x %Val], ptr @aslRc.free, i64 0, i64 " sc)
                 "  %head = load %Val, ptr %slot"
                 "  %hw = extractvalue %Val %head, 1"
                 "  %has = icmp ne i64 %hw, 0"
                 "  br i1 %has, label %reuse, label %fresh"
                 "reuse:"
                 "  %o = inttoptr i64 %hw to ptr"
                 "  %np = getelementptr inbounds i8, ptr %o, i64 16"
                 "  %next = load %Val, ptr %np"
                 "  store %Val %next, ptr %slot")
           (listAppend (unpoisonText asan sc)
             (list "  %t64 = sext i32 %t to i64"
                   "  %ty = shl i64 %t64, 32"
                   "  %h1 = or i64 %n, %ty"
                   (str "  %h = or i64 %h1, " (* sc 72057594037927936))
                   "  store i64 %h, ptr %o"
                   (statBump "reused" (statReused))
                   "  ret ptr %o"
                   "fresh:"
                   (statBump "fresh" (statFresh))
                   (str "  %r = tail call ptr " fallback "(i32 %t, i64 %n)")
                   "  ret ptr %r"
                   "}"))))

fn declareSection text: String -> String
  (mt (stringIndexOf text "\ndeclare ")
    ((some at) (optionOr (stringSlice text at (stringLength text)) ""))
    ((none) ""))

fn declared? section: String sym: String -> Bool
  (listAny? (fn [(l String)] -> Bool (and (stringStartsWith? l "declare ") (stringContains? l (str " " sym "("))))
            (stringLines section))

fn declIfAbsent section: String sym: String decl: String -> (List String)
  (if (declared? section sym) (list) (list decl))

fn cString name: String plain: String -> String
  (str "@" name " = private unnamed_addr constant [" (+ (stringLength plain) 1) " x i8] c\"" (stringReplace plain "\n" "\\0A") "\\00\"")

fn statsFormat -> String
  "(:rcStats :freed %llu :stuck %llu :reused %llu :pinned %llu :fresh %llu :large %llu :largeFreed %llu :pushed %llu :ops %llu :immediate %llu :fbip %llu :resets %llu :spare %llu)\n"

fn statLoad k: Int64 -> String
  (lines (list (str "  %p" k " = getelementptr [" (statSlots) " x i64], ptr @aslRc.stats, i64 0, i64 " k)
               (str "  %v" k " = load i64, ptr %p" k)))

fn statsText -> String
  (lines (list (str "@aslRc.stats = internal global [" (statSlots) " x i64] zeroinitializer, align 8")
               (cString "aslRc.statsEnv" "ASL_RC_STATS")
               (cString "aslRc.statsFmt" (statsFormat))
               "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @aslRc.ctor, ptr null }]"
               "define internal void @aslRc.ctor() {"
               "entry:"
               "  %e = call ptr @getenv(ptr @aslRc.statsEnv)"
               "  %none = icmp eq ptr %e, null"
               "  br i1 %none, label %done, label %check"
               "check:"
               "  %c = load i8, ptr %e"
               "  %one = icmp eq i8 %c, 49"
               "  br i1 %one, label %on, label %done"
               "on:"
               "  %r = call i32 @atexit(ptr @aslRc.report)"
               "  br label %done"
               "done:"
               "  ret void"
               "}"
               "define internal void @aslRc.report() {"
               "entry:"
               (lines (map statLoad (range 0 (statSlots))))
               "  %r = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @aslRc.statsFmt, i64 %v0, i64 %v1, i64 %v2, i64 %v3, i64 %v4, i64 %v5, i64 %v6, i64 %v7, i64 %v8, i64 %v9, i64 %v10, i64 %v11, i64 %v12)"
               "  ret void"
               "}"))

fn rootedRuntime? section: String -> Bool
  (or (declared? section "@asl_rt_init") (declared? section "@asl_rt_main"))

fn runtimeDecls section: String asan: Bool rooted: Bool -> (List String)
  (listAppend
    (if (and rooted (not (declared? section "@asl_rt_global_root"))) (list "declare void @asl_rt_global_root(ptr)") (list))
  (listAppend
    (fold (fn [(acc (List String)) (d (Pair String String))] -> (List String) (listAppend acc (declIfAbsent section (pairFirst d) (pairSecond d))))
          (list)
          (list (pair "@realloc" "declare ptr @realloc(ptr, i64)") (pair "@llvm.trap" "declare void @llvm.trap()") (pair "@llvm.memset.p0.i64" "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)")
                (pair "@getenv" "declare ptr @getenv(ptr)") (pair "@free" "declare void @free(ptr)")
                (pair "@atexit" "declare i32 @atexit(ptr)") (pair "@dprintf" "declare i32 @dprintf(i32, ptr, ...)")))
    (if asan (list "declare void @__asan_poison_memory_region(ptr, i64)" "declare void @__asan_unpoison_memory_region(ptr, i64)") (list))))

fn runtimeText text: String asan: Bool -> String
  (runtimeTextWith text asan false)

fn runtimeTextWith text: String asan: Bool notrace: Bool -> String
  (let [(section (declareSection text)) (rooted (rootedRuntime? section))]
    (liveChecked asan (lines (listAppend
           (list (str "@aslRc.free = internal global [" (classes) " x %Val] zeroinitializer, align 16")
                 (str "@aslRc.rooted = internal global [" (classes) " x i8] zeroinitializer")
                 "@aslRc.stack = internal global ptr null"
                 "@aslRc.sp = internal global i64 0"
                 "@aslRc.cap = internal global i64 0"
                 (statsText)
                 (objText notrace) (liveCheckText) (dupText asan) (dropText asan) (pushText)
                 (childrenText "pinKids" "pinVal") (drainText) (recycleText asan rooted notrace) (pinValText notrace) (pinText) (deferText rooted)
                 (dupValText) (childrenText "dupKids" "dupVal") (dupKidsText) (dupSameText) (freeOneText) (claimText) (freeChainText asan))
           (listAppend (if rooted (listAppend (smallGlobals text) (list (smallSyncText) (smallPushText))) (list))
             (runtimeDecls section asan rooted))))))

fn liveChecked asan: Bool text: String -> String
  (if asan
    text
    (fold (fn [(t String) (line String)] -> String (stringReplace t line ""))
          text
          (list "  call void @aslRc.live(ptr %o, i64 %h)\n" (str "  store i32 " (sentinel) ", ptr %idp\n") (str "  store i32 " (sentinel) ", ptr %sidp\n"))))

fn routeAlloc text: String sc: Int64 asan: Bool -> (Pair String (List String))
  (let [(callText (str "call ptr " (allocFastSym sc) "("))]
    (if (stringContains? text callText)
      (pair (stringReplace text callText (str "call ptr " (rcAllocSym sc) "(")) (list (allocText (rcAllocSym sc) (allocFastSym sc) sc asan)))
      (pair text (list))))

fn routeArrayAlloc text: String -> String
  (let [(plain "define internal ptr @aslArrAlloc(i32 %t, i64 %n) {\n  %o = call ptr @asl_alloc(i32 %t, i64 %n)")]
    (if (and (stringContains? text "\ndefine internal ptr @aslRc.alloc(i32 %t, i64 %n) {\n") (stringContains? text plain))
      (stringReplace text plain "define internal ptr @aslArrAlloc(i32 %t, i64 %n) {\n  %o = call ptr @aslRc.alloc(i32 %t, i64 %n)")
      text))

fn sanitized text: String asan: Bool -> String
  (if asan (stringReplace text " {\n" " sanitize_address {\n") text)

fn reuseExterns bodies: (List ty/SsaFunction) -> (List ty/SsaExtern)
  (let [(names (distinctNames (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                                      (fold (fn [(a (List String)) (ins ty/SsaInstr)] -> (List String)
                                              (mt ins.op ((ty/opCall callee _) (if (stringStartsWith? callee "aslRcReset_") (cons callee a) a)) (_ a)))
                                            acc (functionInstrs f)))
                                    (list) bodies)))]
    (if (listEmpty? names)
      (list)
      (cons (ty/ssaExternTyped (dupSharedName) (list (ty/tyI64) (ty/tyVal)) (ty/tyI64))
            (map (fn [(n String)] -> ty/SsaExtern (ty/ssaExternTyped n (list (ty/tyVal)) (ty/tyI64))) names))))

fn resetKidsText -> (List String)
  (list "unique:"
        "  %ty = lshr i64 %h, 32"
        "  %ty8 = and i64 %ty, 255"
        "  switch i64 %ty8, label %kidsDone [ i64 1, label %cons i64 2, label %rec i64 3, label %ctor i64 4, label %clo ]"
        "cons:"
        "  %cb = getelementptr inbounds i8, ptr %o, i64 8"
        "  br label %kids"
        "rec:"
        "  %rnp = getelementptr inbounds i8, ptr %o, i64 12"
        "  %rn32 = load i32, ptr %rnp"
        "  %rn = sext i32 %rn32 to i64"
        "  %rb = getelementptr inbounds i8, ptr %o, i64 24"
        "  br label %kids"
        "ctor:"
        "  %fnp = getelementptr inbounds i8, ptr %o, i64 12"
        "  %fn32 = load i32, ptr %fnp"
        "  %fn = sext i32 %fn32 to i64"
        "  %fb = getelementptr inbounds i8, ptr %o, i64 16"
        "  br label %kids"
        "clo:"
        "  %unp = getelementptr inbounds i8, ptr %o, i64 16"
        "  %un32 = load i32, ptr %unp"
        "  %un = sext i32 %un32 to i64"
        "  %ub = getelementptr inbounds i8, ptr %o, i64 24"
        "  br label %kids"
        "kids:"
        "  %base = phi ptr [ %cb, %cons ], [ %rb, %rec ], [ %fb, %ctor ], [ %ub, %clo ]"
        "  %n = phi i64 [ 2, %cons ], [ %rn, %rec ], [ %fn, %ctor ], [ %un, %clo ]"
        "  br label %loop"
        "loop:"
        "  %i = phi i64 [ 0, %kids ], [ %i1, %step ]"
        "  %more = icmp slt i64 %i, %n"
        "  br i1 %more, label %body, label %kidsDone"
        "body:"
        "  %bit = shl i64 1, %i"
        "  %kept = and i64 %mask, %bit"
        "  %moved = icmp ne i64 %kept, 0"
        "  br i1 %moved, label %step, label %release"
        "release:"
        "  %off = mul i64 %i, 16"
        "  %at = getelementptr inbounds i8, ptr %base, i64 %off"
        "  %kid = load %Val, ptr %at"
        "  %k = call ptr @aslRc.obj(%Val %kid)"
        "  %kz = icmp eq ptr %k, null"
        "  br i1 %kz, label %step, label %claimKid"
        "claimKid:"
        "  %dies = call i1 @aslRc.claim(ptr %k)"
        "  br i1 %dies, label %freeKid, label %step"
        "freeKid:"
        "  call void @aslRc.freeOne(ptr %k)"
        "  br label %step"
        "step:"
        "  %i1 = add i64 %i, 1"
        "  br label %loop")

; (:m :ref RC-FBIP :do "a reset of a unique value releases its kids except the moved ones and hands its cell over when its size class is the construct's, else recycles it and answers 1 (moved, no cell); a shared value is decremented and answers 0, so the moved fields are then duplicated; the shared test is inlined and only a unique value calls out")
fn resetText asan: Bool cls: Int64 mask: Int64 -> String
  (let [(slow (str "@aslRc.resetSlow." cls "." mask))]
    (lines (listAppend
             (list (str "define internal tailcc i64 @" (resetName cls mask) "(%Val %v) alwaysinline {")
                   "entry:"
                   (if asan (statBump "resets" (statResets)) "")
                   "  %o = call ptr @aslRc.obj(%Val %v)"
                   "  %z = icmp eq ptr %o, null"
                   "  br i1 %z, label %shared, label %live"
                   "live:"
                   "  %h = load i64, ptr %o"
                   "  call void @aslRc.live(ptr %o, i64 %h)"
                   "  %c = lshr i64 %h, 48"
                   "  %c8 = and i64 %c, 255"
                   "  %stuck = icmp eq i64 %c8, 255"
                   "  br i1 %stuck, label %shared, label %count"
                   "count:"
                   "  %last = icmp eq i64 %c8, 0"
                   "  br i1 %last, label %unique, label %dec"
                   "dec:"
                   (str "  %h1 = sub i64 %h, " (countOne))
                   "  store i64 %h1, ptr %o"
                   "  br label %shared"
                   "shared:"
                   "  ret i64 0"
                   "unique:"
                   (str "  %u = call i64 " slow "(ptr %o, i64 %h)")
                   "  ret i64 %u"
                   "}"
                   (str "define internal i64 " slow "(ptr %o, i64 %h) {")
                   "entry:"
                   (str "  %mask = add i64 0, " mask)
                   "  br label %unique")
             (listAppend (resetKidsText)
               (list "kidsDone:"
                     "  %cls = lshr i64 %h, 56"
                     (str "  %fits = icmp eq i64 %cls, " cls)
                     "  br i1 %fits, label %give, label %spare"
                     "give:"
                     (if asan (statBump "fbip" (statFbip)) "")
                     "  %w = ptrtoint ptr %o to i64"
                     "  ret i64 %w"
                     "spare:"
                     (if asan (statBump "spare" (statSpare)) "")
                     "  call void @aslRc.recycle(ptr %o, i64 %h)"
                     "  ret i64 1"
                     "}")))))


fn reuseOrName cls: Int64 -> String
  (if (= cls 3) "@aslRc.reuseOrCons" (str "@aslRc.reuseOr." cls))

fn reuseOrText cls: Int64 -> String
  (lines (list (str "define internal ptr " (reuseOrName cls) "(i64 %tok, i32 %t, i64 %n) alwaysinline {")
               "entry:"
               "  %has = icmp ugt i64 %tok, 1"
               "  br i1 %has, label %reuse, label %fresh"
               "reuse:"
               "  %o = inttoptr i64 %tok to ptr"
               "  %t64 = sext i32 %t to i64"
               "  %ty = shl i64 %t64, 32"
               "  %h1 = or i64 %n, %ty"
               (str "  %h = or i64 %h1, " (* cls 72057594037927936))
               "  store i64 %h, ptr %o"
               "  ret ptr %o"
               "fresh:"
               (str "  %r = call ptr " (if (= cls 3) "@gcAsl.allocFastCons" (allocFastSym cls)) "(i32 %t, i64 %n)")
               "  ret ptr %r"
               "}"))

fn dupSharedText -> String
  (lines (list (str "define internal tailcc i64 @" (dupSharedName) "(i64 %tok, %Val %v) alwaysinline {")
               "entry:"
               "  %shared = icmp eq i64 %tok, 0"
               "  br i1 %shared, label %dup, label %done"
               "dup:"
               (str "  %d = call tailcc i64 @" (dupName) "(%Val %v)")
               "  br label %done"
               "done:"
               "  ret i64 0"
               "}"))

fn tokenOf line: String -> String
  (let [(head (str "  %" (tokenName "")))]
    (if (and (stringStartsWith? line head) (stringContains? line (str " = call tailcc i64 @aslRcReset_")))
      (optionOr (listHead (stringSplit (optionOr (stringSlice line (stringLength head) (stringLength line)) "") " ")) "")
      ""))

fn resetOf line: String -> String
  (mt (stringIndexOf line "@aslRcReset_")
    ((none) "")
    ((some at) (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ at 1) (stringLength line)) "") "(")) "")))

fn allocClassOf line: String -> Int64
  (cond
    ((stringContains? line "= call ptr @gcAsl.allocFastCons(") 3)
    (else (mt (stringIndexOf line "= call ptr @gcAsl.allocFast.")
            ((none) -1)
            ((some at) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ at 28) (stringLength line)) "") "(")) "")) -1)))))

fn allocTarget line: String -> String
  (if (and (>= (allocClassOf line) 0) (stringStartsWith? line "  %"))
    (optionOr (listHead (stringSplit (optionOr (stringSlice line 3 (stringLength line)) "") ".objp = ")) "")
    "")

fn reroute line: String toks: (Map String Bool) -> String
  (let [(x (allocTarget line))]
    (if (or (= x "") (not (mapHas? toks x)))
      line
      (str "  %" x ".objp = call ptr " (reuseOrName (allocClassOf line)) "(i64 %" (tokenName x) ", " (optionOr (listHead (listReverse (stringSplit line "("))) ""))))

fn unclaimed line: String consumed: (Map String Bool) -> String
  (let [(t (tokenOf line))]
    (if (or (= t "") (mapHas? consumed t))
      line
      (str (optionOr (listHead (stringSplit line "@aslRcReset_")) "") "@aslRcReset_" (noCell) "_" (optionOr (listGet (stringSplit (resetOf line) "_") 2) "0") "(" (optionOr (listHead (listReverse (stringSplit line "("))) ""))))

fn noCell -> Int64
  99

; (:m :ref RC-FBIP :do "within one function the construct a reset precedes takes its cell through reuseOr, named by the token the reset defines; a reset whose construct allocates no pooled cell asks for a class no cell has, so it never hands one over; only functions that hold a reset are split into lines")
fn routeChunk ls: (List String) -> (Pair (List String) (List Int64))
  (let [(toks (setOf (filter (fn [(t String)] -> Bool (!= t "")) (map tokenOf ls))))]
    (if (= (mapSize toks) 0)
      (pair ls (list))
      (let [(consumed (setOf (filter (fn [(x String)] -> Bool (mapHas? toks x)) (map allocTarget ls))))]
        (pair (map (fn [(l String)] -> String (unclaimed (reroute l toks) consumed)) ls)
              (map allocClassOf (filter (fn [(l String)] -> Bool (mapHas? consumed (allocTarget l))) ls))))))

fn resetDecl? l: String -> Bool
  (or (stringStartsWith? l "declare tailcc i64 @aslRcReset_") (stringStartsWith? l (str "declare tailcc i64 @" (dupSharedName) "(")))

schema Routed
  text: String
  classes: (List Int64)
  resets: (List String)

fn routeFunction last: Bool part: String -> Routed
  (if (not (or last (stringContains? part "= call tailcc i64 @aslRcReset_")))
    (Routed :text part :classes (list) :resets (list))
    (let [(r (routeChunk (filter (fn [(l String)] -> Bool (not (resetDecl? l))) (stringSplit part "\n"))))]
      (Routed :text (stringJoin (pairFirst r) "\n") :classes (pairSecond r)
              :resets (filter (fn [(x String)] -> Bool (!= x "")) (map resetOf (filter (fn [(l String)] -> Bool (!= (tokenOf l) "")) (pairFirst r)))))))

fn routeReuse text: String asan: Bool -> (Pair String (List String))
  (if (not (stringContains? text "= call tailcc i64 @aslRcReset_"))
    (pair text (list))
    (let [(parts (stringSplit text "\ndefine "))
          (n (listLength parts))
          (done (map (fn [(i Int64)] -> Routed (routeFunction (= i (- n 1)) (optionOr (listGet parts i) ""))) (range 0 n)))]
      (pair (stringJoin (map (fn [(r Routed)] -> String r.text) done) "\ndefine ")
            (cons (dupSharedText)
                  (listAppend (map reuseOrText (distinctInts (fold (fn [(acc (List Int64)) (r Routed)] -> (List Int64) (listAppend r.classes acc)) (list) done)))
                              (map (fn [(r String)] -> String (resetFrom asan r)) (distinctNames (fold (fn [(acc (List String)) (r Routed)] -> (List String) (listAppend r.resets acc)) (list) done))))))))


fn distinctInts xs: (List Int64) -> (List Int64)
  (fold (fn [(acc (List Int64)) (x Int64)] -> (List Int64) (if (listContains? acc x) acc (cons x acc))) (list) xs)

fn resetFrom asan: Bool name: String -> String
  (let [(parts (stringSplit name "_"))]
    (resetText asan (optionOr (stringToInt64 (optionOr (listGet parts 1) "")) 0) (optionOr (stringToInt64 (optionOr (listGet parts 2) "")) 0)))

fn rcFinishText text: String asan: Bool -> String
  (rcFinishTextWith text asan false)

fn rcFinishTextWith text: String asan: Bool notrace: Bool -> String
  (let [(undeclared (stringReplace (fold (fn [(t String) (n String)] -> String (stringReplace t (str "declare tailcc i64 @" n "(%Val)\n") "")) text (rcNames))
                                    (str "declare tailcc i64 @" (dupSameName) "(%Val, %Val)\n") ""))
        (reuse (routeReuse undeclared asan))
        (reused (if (listEmpty? (pairSecond reuse)) undeclared (str (pairFirst reuse) "\n" (lines (pairSecond reuse)) "\n")))
        (routed (fold (fn [(acc (Pair String (List String))) (sc Int64)] -> (Pair String (List String))
                        (let [(r (routeAlloc (pairFirst acc) sc asan))] (pair (pairFirst r) (listAppend (pairSecond acc) (pairSecond r)))))
                      (pair reused (list)) (range 2 (classes))))
        (consCall "call ptr @gcAsl.allocFastCons(")
        (body (pairFirst routed))
        (consed (if (stringContains? body consCall) (stringReplace body consCall "call ptr @aslRc.allocFastCons(") body))
        (consDef (if (stringContains? body consCall) (list (allocText "@aslRc.allocFastCons" "@gcAsl.allocFastCons" 3 asan)) (list)))
        (rooted (rootedRuntime? (declareSection consed)))
        (sized (stringContains? consed (sizedCall)))
        (small (if rooted (routeSmall (routeSized (filterDup consed))) (pair (routeSized (filterDup consed)) (list))))
        (sizedDef (if sized (list (sizedAllocText asan rooted)) (list)))]
    (str (pairFirst small) "\n" (runtimeTextWith (pairFirst small) asan notrace) "\n" (lines (listAppend (pairSecond routed) (listAppend consDef (listAppend (pairSecond small) sizedDef)))) "\n"))

fn routeSmall text: String -> (Pair String (List String))
  (fold (fn [(acc (Pair String (List String))) (sc Int64)] -> (Pair String (List String))
          (let [(callText (str "call ptr " (allocFastSym sc) "("))]
            (if (stringContains? (pairFirst acc) callText)
              (pair (stringReplace (pairFirst acc) callText (str "call ptr " (rcAllocSym sc) "(")) (listAppend (pairSecond acc) (list (smallAllocText sc))))
              acc)))
        (pair text (list)) (range 0 (smallClasses)))

fn pendSlots -> Int64
  16

fn deferText rooted: Bool -> String
  (lines (listAppend
           (list (str "@aslRc.pend = internal global [" (pendSlots) " x %Val] zeroinitializer, align 16")
                 "@aslRc.pendN = internal global i64 0"
                 "@aslRc.pendRooted = internal global i8 0"
                 (str "define internal tailcc i64 @" (deferFirstName) "(%Val %v) {")
                 "entry:"
                 "  call void @aslRc.flushPending()"
                 (str "  %r = call tailcc i64 @" (deferName) "(%Val %v)")
                 "  ret i64 %r"
                 "}"
                 "define internal void @aslRc.flushPending() {"
                 "entry:"
                 "  %n = load i64, ptr @aslRc.pendN"
                 "  br label %loop"
                 "loop:"
                 "  %i = phi i64 [ 0, %entry ], [ %i1, %body ]"
                 "  %more = icmp slt i64 %i, %n"
                 "  br i1 %more, label %body, label %done"
                 "body:"
                 (str "  %p = getelementptr [" (pendSlots) " x %Val], ptr @aslRc.pend, i64 0, i64 %i")
                 "  %v = load %Val, ptr %p"
                 "  store %Val zeroinitializer, ptr %p"
                 (str "  %d = call tailcc i64 @" (dropName) "(%Val %v)")
                 "  %i1 = add i64 %i, 1"
                 "  br label %loop"
                 "done:"
                 "  store i64 0, ptr @aslRc.pendN"
                 "  ret void"
                 "}"
                 (str "define internal tailcc i64 @" (deferName) "(%Val %v) {")
                 "entry:"
                 "  %o = call ptr @aslRc.obj(%Val %v)"
                 "  %z = icmp eq ptr %o, null"
                 "  br i1 %z, label %done, label %counted"
                 "counted:"
                 "  %n = load i64, ptr @aslRc.pendN"
                 (str "  %full = icmp uge i64 %n, " (if rooted (pendSlots) 0))
                 "  br i1 %full, label %pin, label %put"
                 "pin:"
                 (str "  %pr = call tailcc i64 @" (pinName) "(%Val %v)")
                 "  br label %done"
                 "put:"
                 (str "  %p = getelementptr [" (pendSlots) " x %Val], ptr @aslRc.pend, i64 0, i64 %n")
                 "  store %Val %v, ptr %p"
                 "  %n1 = add i64 %n, 1"
                 "  store i64 %n1, ptr @aslRc.pendN"
                 "  %rooted = load i8, ptr @aslRc.pendRooted"
                 "  %fresh = icmp eq i8 %rooted, 0"
                 "  br i1 %fresh, label %root, label %done")
           (listAppend
             (if rooted
               (list "root:"
                     "  store i8 1, ptr @aslRc.pendRooted"
                     "  br label %rloop"
                     "rloop:"
                     "  %k = phi i64 [ 0, %root ], [ %k1, %rbody ]"
                     (str "  %rmore = icmp slt i64 %k, " (pendSlots))
                     "  br i1 %rmore, label %rbody, label %done"
                     "rbody:"
                     (str "  %rp = getelementptr [" (pendSlots) " x %Val], ptr @aslRc.pend, i64 0, i64 %k")
                     "  call void @asl_rt_global_root(ptr %rp)"
                     "  %k1 = add i64 %k, 1"
                     "  br label %rloop")
               (list "root:"
                     "  br label %done"))
             (list "done:"
                   "  ret i64 0"
                   "}"))))

fn smallClasses -> Int64
  2

fn collectionsOffset -> Int64
  64

fn smallSyncText -> String
  (lines (list "define internal void @aslRc.smallSync() {"
               "entry:"
               "  %s = load ptr, ptr @asl_gc_state_ptr"
               "  %unpublished = icmp eq ptr %s, null"
               "  br i1 %unpublished, label %done, label %read"
               "read:"
               (str "  %cp = getelementptr inbounds i8, ptr %s, i64 " (collectionsOffset))
               "  %c = load i64, ptr %cp"
               "  %e = load i64, ptr @aslRc.smallEpoch"
               "  %same = icmp eq i64 %c, %e"
               "  br i1 %same, label %done, label %reset"
               "reset:"
               "  store i64 %c, ptr @aslRc.smallEpoch"
               (str "  store [" (smallClasses) " x i64] zeroinitializer, ptr @aslRc.smallSp")
               "  br label %done"
               "done:"
               "  ret void"
               "}"))

fn smallPushText -> String
  (lines (list "define internal void @aslRc.smallPush(ptr %o, i64 %cls) {"
               "entry:"
               "  call void @aslRc.smallSync()"
               (str "  %spp = getelementptr [" (smallClasses) " x i64], ptr @aslRc.smallSp, i64 0, i64 %cls")
               (str "  %capp = getelementptr [" (smallClasses) " x i64], ptr @aslRc.smallCap, i64 0, i64 %cls")
               (str "  %stkp = getelementptr [" (smallClasses) " x ptr], ptr @aslRc.smallStack, i64 0, i64 %cls")
               "  %sp = load i64, ptr %spp"
               "  %cap = load i64, ptr %capp"
               "  %full = icmp eq i64 %sp, %cap"
               "  br i1 %full, label %grow, label %put"
               "grow:"
               "  %zero = icmp eq i64 %cap, 0"
               "  %twice = mul i64 %cap, 2"
               "  %ncap = select i1 %zero, i64 1024, i64 %twice"
               "  %bytes = mul i64 %ncap, 8"
               "  %old = load ptr, ptr %stkp"
               "  %new = call ptr @realloc(ptr %old, i64 %bytes)"
               "  %dead = icmp eq ptr %new, null"
               "  br i1 %dead, label %oom, label %grown"
               "oom:"
               "  call void @llvm.trap()"
               "  unreachable"
               "grown:"
               "  store ptr %new, ptr %stkp"
               "  store i64 %ncap, ptr %capp"
               "  br label %put"
               "put:"
               "  %stk = load ptr, ptr %stkp"
               "  %at = getelementptr ptr, ptr %stk, i64 %sp"
               "  store ptr %o, ptr %at"
               "  %sp1 = add i64 %sp, 1"
               "  store i64 %sp1, ptr %spp"
               "  ret void"
               "}"))

fn smallNodeText -> (List String)
  (list "  %scls2 = add i64 %cls, 2"
        "  %sss = mul i64 %scls2, 8"
        (str "  %skeep = and i64 %h, " (keepMask))
        "  %sh1 = or i64 %skeep, %sss"
        "  %sh2 = or i64 %sh1, 12884901888"
        "  store i64 %sh2, ptr %o"
        "  %sidp = getelementptr inbounds i8, ptr %o, i64 8"
        (str "  store i32 " (sentinel) ", ptr %sidp")
        "  %snp = getelementptr inbounds i8, ptr %o, i64 12"
        "  store i32 0, ptr %snp"
        "  call void @aslRc.smallPush(ptr %o, i64 %cls)"
        "  ret void")

fn smallAllocText sc: Int64 -> String
  (lines (list (str "define internal ptr " (rcAllocSym sc) "(i32 %t, i64 %n) {")
               "entry:"
               "  call void @aslRc.smallSync()"
               (str "  %spp = getelementptr [" (smallClasses) " x i64], ptr @aslRc.smallSp, i64 0, i64 " sc)
               "  %sp = load i64, ptr %spp"
               "  %has = icmp ne i64 %sp, 0"
               "  br i1 %has, label %reuse, label %fresh"
               "reuse:"
               "  %sp1 = sub i64 %sp, 1"
               "  store i64 %sp1, ptr %spp"
               (str "  %stkp = getelementptr [" (smallClasses) " x ptr], ptr @aslRc.smallStack, i64 0, i64 " sc)
               "  %stk = load ptr, ptr %stkp"
               "  %at = getelementptr ptr, ptr %stk, i64 %sp1"
               "  %o = load ptr, ptr %at"
               "  %t64 = sext i32 %t to i64"
               "  %ty = shl i64 %t64, 32"
               "  %h1 = or i64 %n, %ty"
               (str "  %h = or i64 %h1, " (* sc 72057594037927936))
               "  store i64 %h, ptr %o"
               (statBump "reused" (statReused))
               "  ret ptr %o"
               "fresh:"
               (statBump "fresh" (statFresh))
               (str "  %r = tail call ptr " (allocFastSym sc) "(i32 %t, i64 %n)")
               "  ret ptr %r"
               "}"))

fn smallGlobals text: String -> (List String)
  (listAppend
    (list (str "@aslRc.smallStack = internal global [" (smallClasses) " x ptr] zeroinitializer")
          (str "@aslRc.smallSp = internal global [" (smallClasses) " x i64] zeroinitializer")
          (str "@aslRc.smallCap = internal global [" (smallClasses) " x i64] zeroinitializer")
          "@aslRc.smallEpoch = internal global i64 0")
    (if (stringContains? text "@asl_gc_state_ptr = ") (list) (list "@asl_gc_state_ptr = weak global ptr null, align 8")))

fn dupValText -> String
  (lines (list "define internal void @aslRc.dupVal(%Val %v) {"
               "entry:"
               (str "  %r = call tailcc i64 @" (dupName) "(%Val %v)")
               "  ret void"
               "}"))

fn dupKidsText -> String
  (lines (list (str "define internal tailcc i64 @" (dupKidsName) "(%Val %v) {")
               "entry:"
               "  %o = call ptr @aslRc.obj(%Val %v)"
               "  %z = icmp eq ptr %o, null"
               "  br i1 %z, label %done, label %live"
               "live:"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.dupKids(ptr %o, i64 %h)"
               "  br label %done"
               "done:"
               "  ret i64 0"
               "}"))

fn filterStore -> String
  "  store %Val %x, ptr %ccar\n"

fn filterDup text: String -> String
  (stringReplace text (filterStore) (str "  %x.rc = call tailcc i64 @" (dupName) "(%Val %x)\n" (filterStore)))

fn sizedAllocText asan: Bool rooted: Bool -> String
  (lines (listAppend
           (list "define internal ptr @aslRc.alloc(i32 %t, i64 %n) {"
                 "entry:"
                 "  %big = icmp ugt i64 %n, 512"
                 "  %arr = icmp eq i32 %t, 6"
                 "  %hnd = icmp eq i32 %t, 7"
                 "  %o1 = or i1 %big, %arr"
                 "  %large = or i1 %o1, %hnd"
                 "  br i1 %large, label %unpooled, label %sized"
                 "sized:"
                 "  %tiny = icmp ult i64 %n, 16"
                 "  %b = select i1 %tiny, i64 16, i64 %n"
                 "  %b7 = add i64 %b, 7"
                 "  %b8 = lshr i64 %b7, 3"
                 "  %sc = sub i64 %b8, 2"
                 (str "  %small = icmp ult i64 %sc, " (smallClasses))
                 "  br i1 %small, label %smallCls, label %listCls"
                 "listCls:"
                 (str "  %slot = getelementptr [" (classes) " x %Val], ptr @aslRc.free, i64 0, i64 %sc")
                 "  %head = load %Val, ptr %slot"
                 "  %hw = extractvalue %Val %head, 1"
                 "  %has = icmp ne i64 %hw, 0"
                 "  br i1 %has, label %reuse, label %fallback"
                 "reuse:"
                 "  %o = inttoptr i64 %hw to ptr"
                 "  %np = getelementptr inbounds i8, ptr %o, i64 16"
                 "  %next = load %Val, ptr %np"
                 "  store %Val %next, ptr %slot"
                 "  br label %got"
                 "smallCls:")
           (listAppend
             (if rooted
               (list "  call void @aslRc.smallSync()"
                     (str "  %spp = getelementptr [" (smallClasses) " x i64], ptr @aslRc.smallSp, i64 0, i64 %sc")
                     "  %sp = load i64, ptr %spp"
                     "  %shas = icmp ne i64 %sp, 0"
                     "  br i1 %shas, label %smallPop, label %fallback"
                     "smallPop:"
                     "  %sp1 = sub i64 %sp, 1"
                     "  store i64 %sp1, ptr %spp"
                     (str "  %stkp = getelementptr [" (smallClasses) " x ptr], ptr @aslRc.smallStack, i64 0, i64 %sc")
                     "  %stk = load ptr, ptr %stkp"
                     "  %at = getelementptr ptr, ptr %stk, i64 %sp1"
                     "  %so = load ptr, ptr %at"
                     "  br label %got"
                     "got:"
                     "  %g = phi ptr [ %o, %reuse ], [ %so, %smallPop ]")
               (list "  br label %fallback"
                     "got:"
                     "  %g = phi ptr [ %o, %reuse ]"))
             (list "  %sc2 = add i64 %sc, 2"
                   "  %ss = mul i64 %sc2, 8"
                   (if asan "  call void @__asan_unpoison_memory_region(ptr %g, i64 %ss)" "  %noAsan = add i64 0, 0")
                   "  call void @llvm.memset.p0.i64(ptr %g, i8 0, i64 %ss, i1 false)"
                   "  %t64 = sext i32 %t to i64"
                   "  %ty = shl i64 %t64, 32"
                   "  %h1 = or i64 %n, %ty"
                   "  %cls = shl i64 %sc, 56"
                   "  %h = or i64 %h1, %cls"
                   "  store i64 %h, ptr %g"
                   (statBump "reused" (statReused))
                   "  ret ptr %g"
                   "fallback:"
                   (statBump "fresh" (statFresh))
                   "  %r = tail call ptr @asl_alloc(i32 %t, i64 %n)"
                   "  ret ptr %r"
                   "unpooled:"
                   (statBump "large" (statLarge))
                   "  %u = tail call ptr @asl_alloc(i32 %t, i64 %n)"
                   "  ret ptr %u"
                   "}"))))

fn sizedCall -> String
  "call ptr @asl_alloc("

fn routeSized text: String -> String
  (stringJoin (map (fn [(l String)] -> String (if (and (stringContains? l (sizedCall)) (stringStartsWith? l "  ")) (stringReplace l (sizedCall) "call ptr @aslRc.alloc(") l))
                   (stringSplit text "\n"))
              "\n")

fn dupSameText -> String
  (lines (list (str "define internal tailcc i64 @" (dupSameName) "(%Val %r, %Val %d) {")
               "entry:"
               "  %rw = extractvalue %Val %r, 1"
               "  %dw = extractvalue %Val %d, 1"
               "  %same = icmp eq i64 %rw, %dw"
               "  br i1 %same, label %dup, label %done"
               "dup:"
               (str "  %x = call tailcc i64 @" (dupName) "(%Val %r)")
               "  br label %done"
               "done:"
               "  ret i64 0"
               "}"))

fn borrowFlags ctx: Ctx name: String -> (List Bool)
  (optionOr (mapGet ctx.borrows name) (list))

fn callUses ctx: Ctx facts: Facts callee: String args: (List String) -> (List Use)
  (let [(flags (borrowFlags ctx callee))]
    (filter (fn [(u Use)] -> Bool (mapHas? facts.heap u.name))
            (map (fn [(i Int64)] -> Use (Use :name (optionOr (listGet args i) "") :kind (if (optionOr (listGet flags i) false) "borrow" "consume")))
                 (range 0 (listLength args)))))

fn borrowedParams ctx: Ctx f: ty/SsaFunction -> (Map String Bool)
  (let [(flags (borrowFlags ctx f.name))]
    (setOf (map (fn [(i Int64)] -> String (mt (listGet f.params i) ((some p) p.name) ((none) "")))
                (filter (fn [(i Int64)] -> Bool (optionOr (listGet flags i) false)) (range 0 (listLength f.params))))))

fn borrowable? targets: (Map String Bool) f: ty/SsaFunction -> Bool
  (and (listEmpty? f.captures) (not (mapHas? targets f.name)))

fn initialBorrows counted: (List ty/SsaFunction) targets: (Map String Bool) -> (Map String (List Bool))
  (fold (fn [(acc (Map String (List Bool))) (f ty/SsaFunction)] -> (Map String (List Bool))
          (if (borrowable? targets f)
            (mapSet acc f.name (map (fn [(p ty/SsaParam)] -> Bool (heapTy? p.ty)) f.params))
            acc))
        (mapEmpty) counted)

fn withBorrows ctx: Ctx borrows: (Map String (List Bool)) -> Ctx
  (Ctx :user ctx.user :opaque ctx.opaque :builders ctx.builders :borrows borrows :scc ctx.scc :proj ctx.proj)

fn ownParam borrows: (Map String (List Bool)) name: String i: Int64 -> (Map String (List Bool))
  (mt (mapGet borrows name)
    ((none) borrows)
    ((some flags) (if (optionOr (listGet flags i) false)
                    (mapSet borrows name (map (fn [(k Int64)] -> Bool (if (= k i) false (optionOr (listGet flags k) false))) (range 0 (listLength flags))))
                    borrows)))

fn returnsVia byLabel: (Map String ty/SsaBlock) t: ty/SsaTerm v: String fuel: Int64 -> Bool
  (mt t
    ((ty/termReturn r) (= r v))
    ((ty/termJump e) (and (> fuel 0)
                          (and (= e.args (list v))
                               (mt (mapGet byLabel e.target)
                                 ((some j) (and (listEmpty? j.instrs) (and (= (listLength j.params) 1) (mt (listHead j.params) ((some p) (returnsVia byLabel j.term p.name (- fuel 1))) ((none) false)))))
                                 ((none) false)))))
    (_ false))

fn tailCalls f: ty/SsaFunction -> (List (Pair String (List String)))
  (let [(byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))]
    (fold (fn [(acc (List (Pair String (List String)))) (b ty/SsaBlock)] -> (List (Pair String (List String)))
            (mt (listHead (listReverse b.instrs))
              ((some ins) (mt ins.op ((ty/opCall callee args) (if (returnsVia byLabel b.term ins.dest 16) (cons (pair callee args) acc) acc)) (_ acc)))
              ((none) acc)))
          (list) f.blocks))

; (:m :ref RC-PERF :do "a tail call keeps its musttail only when no drop follows it, so a callee whose parameter is borrowed forces the owned argument of a tail call to own it; that is needed only where the call can recur without growing the stack, a cycle of tail calls (a cycle through a plain call grows it anyway), so the force is limited to callers in the callee's strongly connected component of the tail-call graph and other tail calls become plain calls followed by the drop; closure calls in tail position go through one node that reaches every closure target")
fn callTargets f: ty/SsaFunction -> (List String)
  (let [(byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))
        (closures (listAny? (fn [(b ty/SsaBlock)] -> Bool
                              (mt (listHead (listReverse b.instrs))
                                ((some ins) (mt ins.op ((ty/opCallClosure _ _) (returnsVia byLabel b.term ins.dest 16)) (_ false)))
                                ((none) false)))
                            f.blocks))]
    (listAppend (map pairFirst (tailCalls f)) (if closures (list "$closure") (list))))

fn callGraph fns: (List ty/SsaFunction) targets: (Map String Bool) -> (Map String (List String))
  (let [(names (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) fns)))
        (g0 (fold (fn [(acc (Map String (List String))) (f ty/SsaFunction)] -> (Map String (List String))
                    (mapSet acc f.name (distinctNames (filter (fn [(n String)] -> Bool (or (= n "$closure") (mapHas? names n))) (callTargets f)))))
                  (mapEmpty) fns))]
    (mapSet g0 "$closure" (filter (fn [(n String)] -> Bool (mapHas? names n)) (mapKeys targets))))

fn dfsOrder g: (Map String (List String)) stack: (List (Pair String (List String))) seen: (Map String Bool) order: (List String) -> (Pair (Map String Bool) (List String))
  (mt (listHead stack)
    ((none) (pair seen order))
    ((some top) (let [(rest (optionOr (listTail stack) (list)))]
                  (mt (listHead (pairSecond top))
                    ((none) (dfsOrder g rest seen (cons (pairFirst top) order)))
                    ((some c) (let [(top1 (pair (pairFirst top) (optionOr (listTail (pairSecond top)) (list))))]
                                (if (mapHas? seen c)
                                  (dfsOrder g (cons top1 rest) seen order)
                                  (dfsOrder g (cons (pair c (optionOr (mapGet g c) (list))) (cons top1 rest)) (mapSet seen c true) order))))))))

fn finishOrder g: (Map String (List String)) nodes: (List String) seen: (Map String Bool) order: (List String) -> (List String)
  (mt (listHead nodes)
    ((none) order)
    ((some n) (let [(rest (optionOr (listTail nodes) (list)))]
                (if (mapHas? seen n)
                  (finishOrder g rest seen order)
                  (let [(r (dfsOrder g (list (pair n (optionOr (mapGet g n) (list)))) (mapSet seen n true) order))]
                    (finishOrder g rest (pairFirst r) (pairSecond r)))))))

fn transposed g: (Map String (List String)) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (n String)] -> (Map String (List String))
          (fold (fn [(a (Map String (List String))) (c String)] -> (Map String (List String)) (mapSet a c (cons n (optionOr (mapGet a c) (list)))))
                acc (optionOr (mapGet g n) (list))))
        (mapEmpty) (mapKeys g))

fn claim gT: (Map String (List String)) stack: (List String) root: String comp: (Map String String) -> (Map String String)
  (mt (listHead stack)
    ((none) comp)
    ((some n) (let [(kids (filter (fn [(c String)] -> Bool (not (mapHas? comp c))) (optionOr (mapGet gT n) (list))))
                    (marked (fold (fn [(acc (Map String String)) (c String)] -> (Map String String) (mapSet acc c root)) comp kids))]
                (claim gT (listAppend kids (optionOr (listTail stack) (list))) root marked))))

fn components gT: (Map String (List String)) order: (List String) comp: (Map String String) -> (Map String String)
  (mt (listHead order)
    ((none) comp)
    ((some n) (components gT (optionOr (listTail order) (list)) (if (mapHas? comp n) comp (claim gT (list n) n (mapSet comp n n))))))

fn sccOf fns: (List ty/SsaFunction) targets: (Map String Bool) -> (Map String String)
  (let [(g (callGraph fns targets))]
    (components (transposed g) (finishOrder g (mapKeys g) (mapEmpty) (list)) (mapEmpty)))

fn sameScc? ctx: Ctx a: String b: String -> Bool
  (mt (mapGet ctx.scc a)
    ((none) true)
    ((some ca) (mt (mapGet ctx.scc b) ((none) true) ((some cb) (= ca cb)))))

fn settleFunction ctx: Ctx borrows: (Map String (List Bool)) f: ty/SsaFunction -> (Map String (List Bool))
  (let [(facts (functionFacts ctx f))
        (kinds (allUseKinds ctx facts f))
        (flags (borrowFlags ctx f.name))
        (consumed (fold (fn [(acc (Map String (List Bool))) (i Int64)] -> (Map String (List Bool))
                          (let [(p (mt (listGet f.params i) ((some q) q.name) ((none) "")))]
                            (if (and (optionOr (listGet flags i) false) (listContains? (optionOr (mapGet kinds p) (list)) "consume")) (ownParam acc f.name i) acc)))
                        borrows (range 0 (listLength f.params))))]
    (fold (fn [(acc (Map String (List Bool))) (c (Pair String (List String)))] -> (Map String (List Bool))
            (let [(args (pairSecond c))]
              (fold (fn [(a (Map String (List Bool))) (i Int64)] -> (Map String (List Bool))
                      (if (and (!= (liveName facts (optionOr (listGet args i) "")) "") (sameScc? ctx f.name (pairFirst c))) (ownParam a (pairFirst c) i) a))
                    acc (range 0 (listLength args)))))
          consumed (tailCalls f)))

fn borrowCount borrows: (Map String (List Bool)) -> Int64
  (fold (fn [(acc Int64) (flags (List Bool))] -> Int64 (+ acc (listLength (filter (fn [(b Bool)] -> Bool b) flags)))) 0 (mapValues borrows))

fn settleBorrows ctx: Ctx counted: (List ty/SsaFunction) borrows: (Map String (List Bool)) fuel: Int64 -> (Map String (List Bool))
  (let [(c (withBorrows ctx borrows))
        (next (fold (fn [(acc (Map String (List Bool))) (f ty/SsaFunction)] -> (Map String (List Bool)) (settleFunction c acc f)) borrows counted))]
    (if (or (<= fuel 0) (= (borrowCount next) (borrowCount borrows))) next (settleBorrows ctx counted next (- fuel 1))))

; (:m :ref RC-PERF :do "a projection returns a part of one borrowed parameter (the parameter, a field, a list cell's head or rest, a projection of those, or a join of them) without a dup; its callers treat the result as derived from that argument, so a read-only accessor or a list walk that returns a suffix costs no RC traffic in the loop and the caller dups once only if it keeps the result")
fn flowNone -> Flow
  (Flow :ok false :param -1 :keys (mapEmpty) :names (mapEmpty) :values (mapEmpty))

fn flowFail acc: Flow -> Flow
  (Flow :ok false :param acc.param :keys acc.keys :names acc.names :values acc.values)

fn flowWalk ctx: Ctx defs: (Map String ty/SsaInstr) owners: (Map String (Pair String Int64)) incoming: (Map String (List (List String))) params: (Map String Int64) todo: (List String) acc: Flow -> Flow
  (mt (listHead todo)
    ((none) acc)
    ((some v) (let [(rest (optionOr (listTail todo) (list)))]
                (cond
                  ((not acc.ok) acc)
                  ((mapHas? acc.values v) (flowWalk ctx defs owners incoming params rest acc))
                  (else
                    (let [(seen (Flow :ok true :param acc.param :keys acc.keys :names acc.names :values (mapSet acc.values v true)))]
                      (mt (mapGet params v)
                        ((some i) (if (or (= acc.param -1) (= acc.param i))
                                    (flowWalk ctx defs owners incoming params rest (Flow :ok true :param i :keys seen.keys :names seen.names :values seen.values))
                                    (flowFail seen)))
                        ((none) (mt (mapGet defs v)
                                  ((some ins) (let [(b (sourceBase ctx ins.op))]
                                                (cond
                                                  ((!= b "") (flowWalk ctx defs owners incoming params (cons b rest) seen))
                                                  ((listContains? (list "immortal" "opaque") (resultKind ctx ins)) (flowWalk ctx defs owners incoming params rest seen))
                                                  (else (flowFail seen)))))
                                  ((none) (mt (mapGet owners v)
                                            ((none) (flowFail seen))
                                            ((some o) (let [(label (pairFirst o)) (j (pairSecond o))
                                                            (args (map (fn [(xs (List String))] -> String (optionOr (listGet xs j) "")) (optionOr (mapGet incoming label) (list))))]
                                                        (if (listContains? args "")
                                                          (flowFail seen)
                                                          (flowWalk ctx defs owners incoming params (listAppend args rest)
                                                                    (Flow :ok true :param seen.param :keys (mapSet seen.keys (flowKey label j) true) :names (mapSet seen.names v true) :values seen.values))))))))))))))))

fn flowOf ctx: Ctx f: ty/SsaFunction -> Flow
  (if (or (not (heapTy? f.retTy)) (not (listEmpty? f.captures)))
    (flowNone)
    (let [(defs (fold (fn [(acc (Map String ty/SsaInstr)) (i ty/SsaInstr)] -> (Map String ty/SsaInstr) (mapSet acc i.dest i)) (mapEmpty) (functionInstrs f)))
          (owners (fold (fn [(acc (Map String (Pair String Int64))) (b ty/SsaBlock)] -> (Map String (Pair String Int64))
                          (fold (fn [(a (Map String (Pair String Int64))) (j Int64)] -> (Map String (Pair String Int64))
                                  (mt (listGet b.params j) ((some p) (mapSet a p.name (pair b.label j))) ((none) a)))
                                acc (range 0 (listLength b.params))))
                        (mapEmpty) f.blocks))
          (incoming (fold (fn [(acc (Map String (List (List String)))) (b ty/SsaBlock)] -> (Map String (List (List String)))
                            (fold (fn [(a (Map String (List (List String)))) (e ty/SsaEdge)] -> (Map String (List (List String))) (mapSet a e.target (cons e.args (optionOr (mapGet a e.target) (list)))))
                                  acc (ty/termEdges b.term)))
                          (mapEmpty) f.blocks))
          (params (fold (fn [(acc (Map String Int64)) (i Int64)] -> (Map String Int64)
                          (mt (listGet f.params i) ((some p) (if (heapTy? p.ty) (mapSet acc p.name i) acc)) ((none) acc)))
                        (mapEmpty) (range 0 (listLength f.params))))
          (returns (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (mt b.term ((ty/termReturn v) (cons v acc)) (_ acc))) (list) f.blocks))
          (walked (flowWalk ctx defs owners incoming params returns (Flow :ok true :param -1 :keys (mapSet (mapEmpty) "$ret" true) :names (mapEmpty) :values (mapEmpty))))]
      (if (and walked.ok (and (>= walked.param 0) (not (listEmpty? returns)))) walked (flowNone))))

fn withProj ctx: Ctx proj: (Map String Int64) -> Ctx
  (Ctx :user ctx.user :opaque ctx.opaque :builders ctx.builders :borrows ctx.borrows :scc ctx.scc :proj proj)

fn heapParamIndices f: ty/SsaFunction -> (List Int64)
  (filter (fn [(i Int64)] -> Bool (mt (listGet f.params i) ((some p) (heapTy? p.ty)) ((none) false))) (range 0 (listLength f.params)))

fn projGuess ctx: Ctx f: ty/SsaFunction -> Int64
  (fold (fn [(acc Int64) (i Int64)] -> Int64
          (if (>= acc 0) acc (let [(w (flowOf (withProj ctx (mapSet ctx.proj f.name i)) f))] (if (and w.ok (= w.param i)) i -1))))
        -1 (heapParamIndices f))

fn growProj ctx: Ctx fns: (List ty/SsaFunction) fuel: Int64 -> (Map String Int64)
  (let [(next (fold (fn [(acc (Map String Int64)) (f ty/SsaFunction)] -> (Map String Int64)
                      (if (mapHas? acc f.name) acc (let [(i (projGuess (withProj ctx acc) f))] (if (>= i 0) (mapSet acc f.name i) acc))))
                    ctx.proj fns))]
    (if (or (<= fuel 0) (= (mapSize next) (mapSize ctx.proj))) next (growProj (withProj ctx next) fns (- fuel 1))))

fn projOk? ctx: Ctx f: ty/SsaFunction -> Bool
  (let [(w (flowOf ctx f))
        (facts (functionFacts ctx f))
        (p (mt (listGet f.params w.param) ((some q) q.name) ((none) "")))]
    (and w.ok (and (= (optionOr (mapGet ctx.proj f.name) -1) w.param)
                   (and (mapHas? facts.borrowed p) (listAll? (fn [(v String)] -> Bool (not (tracked? facts v))) (mapKeys w.values))))))

fn settleProj ctx: Ctx counted: (List ty/SsaFunction) borrows: (Map String (List Bool)) fuel: Int64 -> Ctx
  (let [(b (settleBorrows ctx counted borrows 50))
        (c (withBorrows ctx b))
        (kept (fold (fn [(acc (Map String Int64)) (f ty/SsaFunction)] -> (Map String Int64)
                      (if (and (mapHas? ctx.proj f.name) (projOk? c f)) (mapSet acc f.name (optionOr (mapGet ctx.proj f.name) -1)) acc))
                    (mapEmpty) counted))]
    (cond
      ((= (mapSize kept) (mapSize ctx.proj)) c)
      ((<= fuel 0) (let [(none0 (withProj c (mapEmpty)))] (withBorrows none0 (settleBorrows none0 counted b 50))))
      (else (settleProj (withProj c kept) counted b (- fuel 1)))))
