(module asl-target-llvm/rc
  :x [rcModule rcFinishText rcFinishTextWith rcFinishTextCounted sanitized routeArrayAlloc dupName dropName pinName wrapperName runtimeText gcConsCall arenaCallText appendCallText]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/hashRt :a hashRt)
      (asl-target-llvm/treapRt :a treapRt)])

schema Ctx
  user: (Map String Bool)
  opaque: (Map String Bool)
  builders: (Map String Bool)
  borrows: (Map String (List Bool))
  scc: (Map String String)
  proj: (Map String Int64)
  cache: (Map String Facts)
  arity: (Map String Int64)

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
  takes: (Map String (Pair String Int64))
  guards: (Map String (List String))
  rawSet: (Map String Bool)
  known: (Map String Int64)

schema Walk
  live: (Map String Bool)
  out: (List ty/SsaInstr)
  n: Int64
  pend: (List (Pair String Int64))
  raw: (Map String Bool)
  quiet: (Map String (Map String Bool))
  moves: (Map String Bool)

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

; (:m :ref CLOSPEC :do "a closureSpec clone of a fresh kernel (its name followed by $cs) is fresh as the kernel is")
fn arrayFresh? name: String -> Bool
  (and (stringStartsWith? name "asl-target-llvm/arrays.") (arrayKernel? name))

; (:m :ref RCCOST2 :do "arrayFresh? runs per call instruction; the kernel names are all under the arrays. prefix, so any other callee is rejected before the 21 names are built")
fn arrayKernel? name: String -> Bool
  (listContains? (fold (fn [(acc (List String)) (k String)] -> (List String)
                         (listAppend acc (map (fn [(op String)] -> String (str "asl-target-llvm/arrays." k "Array" op)) (list "Len" "Get" "Slice" "Concat" "Generate" "Sum" "CountEq"))))
                       (list) (list "f64" "i64" "i8"))
                 (optionOr (listHead (stringSplit name "$cs")) name))

; (:m :ref RC-UNPIN :do "runtime externs the system routes call that read their Val arguments without keeping them and return a fresh value, a raw pointer to a malloc copy or a tag word (abs, the route's tag read)")
; (:m :ref FFI2 :do "ffiMkHandle returns a fresh Handle and the foreign wrappers' Handle reads (ffiHandlePtr, ffiHandleFin) and close (ffiHandleClear) borrow their Val, so a Handle is counted, not pinned, and its finaliser runs when the count reaches zero")
fn borrowExtern? name: String -> Bool
  (listContains? (list "mkStr" "mkBytes" "mkBytesOwn" "valToCStr" "valToCStrN" "abs" "ffiMkHandle" "ffiHandlePtr" "ffiHandleFin" "ffiHandleClear") name)

; (:m :ref RC-UNPIN :do "functions the system route adds (sysRoute wrappers and the sys helpers they call) are plain SSA over fresh allocations, so they are counted like user code; array kernels and parallel workers stay opaque")
fn countedRoute? name: String -> Bool
  (not (or (stringStartsWith? name "asl-target-llvm/arrays.") (stringStartsWith? name "asl-target-llvm/parallel.")))

fn borrowBuiltin? name: String -> Bool
  (listContains? (list "+" "-" "*" "/" "mod" "<" "<=" ">" ">=" "=" "!=" "not" "str" "print" "println" "eprintln" "stringFromFloat64" "stringToFloat64" "abs" "int64ToFloat64" "float64ToInt64" "~"
                       "min" "max" "<<" ">>" "&" "|" "^" "mulWrap" "addWrap" "subWrap" "rotateLeft" "rotateRight" "clamp" "assert" "refute" "trap" "keyCompare")
                 name)

fn freshEntry? name: String -> Bool
  (listContains? (list "+" "-" "*" "/" "mod" "stringConcat" "stringFromInt64" "stringSlice" "stringFromFloat64" "stringToFloat64" "bytesAlloc" "bytesSet" "stringToBytes") name)

fn wrapEntry? name: String -> Bool
  (or (= name "listHead") (= name "listTail"))

fn sameEntry? name: String -> Bool
  (= name "@stringSliceOr")

fn sameAnchor ins: ty/SsaInstr -> (List (Pair String String))
  (match ins.op
    ((ty/opEntry name args) (if (sameEntry? name) (match (listHead (listReverse args)) ((some d) (list (pair (dupSameName) (str ins.dest "\t" d)))) ((none) (list))) (list)))
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
  (match ins.op
    ((ty/opCall callee args) (cond ((arenaEntry? callee) (heapUses facts args "consume")) ((builderFunction? ctx callee) (heapUses facts args "borrow")) ((or (arrayFresh? callee) (borrowExtern? callee)) (heapUses facts args "borrow")) ((opaqueFunction? ctx callee) (heapUses facts args "pin")) (else (callUses ctx facts callee args))))
    ((ty/opBuiltin name args) (heapUses facts args (if (borrowBuiltin? name) "borrow" "pin")))
    ((ty/opEntry name args) (heapUses facts args (if (consumeEntry? name) "consume" "borrow")))
    ((ty/opCallClosure c args) (if (ownedCall? facts ins) (ownedUses facts ins) (heapUses facts (cons c args) "borrow")))
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
    (match t
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
    (match ins.op
      ((ty/opConst c) (match c ((ty/constStr _) "source") ((ty/constSymbol _) "source") (_ "immortal")))
      ((ty/opCall callee _) (if (and (mapHas? ctx.proj callee) (not (arenaEntry? callee))) "source" (if (and (opaqueFunction? ctx callee) (and (not (builderFunction? ctx callee)) (not (or (arrayFresh? callee) (borrowExtern? callee))))) "opaque" "owned")))
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

; (:m :ref RCCOST2 :do "both readers of the per-name use kinds only ask whether a name has a consume use, so the set of consumed names replaces a map of kind lists that consed per use")
fn consumedNames ctx: Ctx facts: Facts f: ty/SsaFunction -> (Map String Bool)
  (let [(note (fn [(acc (Map String Bool)) (u Use)] -> (Map String Bool) (if (= u.kind "consume") (mapSet acc u.name true) acc)))]
    (fold (fn [(acc (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
            (fold note (fold (fn [(a (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool) (fold note a (instrUses ctx facts ins))) acc b.instrs)
                  (termUses facts b.term)))
          (mapEmpty) f.blocks))

fn sourceBase ctx: Ctx op: ty/SsaOp -> String
  (match op ((ty/opCall callee args) (match (mapGet ctx.proj callee) ((some i) (optionOr (listGet args i) "")) ((none) ""))) ((ty/opField b _) b) ((ty/opVariantField b _) b) ((ty/opEntry name args) (if (childEntry? name) (optionOr (listHead args) "") "")) (_ ""))

fn anchorOf ctx: Ctx defs: (Map String ty/SsaOp) derived: (Map String Bool) immortal: (Map String Bool) v: String fuel: Int64 -> String
  (cond
    ((<= fuel 0) "")
    ((mapHas? immortal v) "")
    ((mapHas? derived v) (match (mapGet defs v)
                           ((some op) (let [(b (sourceBase ctx op))] (if (= b "") "" (anchorOf ctx defs derived immortal b (- fuel 1)))))
                           ((none) "")))
    (else v))

fn immortalBase? ctx: Ctx defs: (Map String ty/SsaOp) immortal: (Map String Bool) v: String fuel: Int64 -> Bool
  (cond
    ((<= fuel 0) false)
    ((mapHas? immortal v) true)
    (else (match (mapGet defs v)
            ((some op) (let [(b (sourceBase ctx op))] (if (= b "") false (immortalBase? ctx defs immortal b (- fuel 1)))))
            ((none) false))))

; (:m :ref RC-PERF :do "a raw i64, f64 or i1 boxed into a Val is an immediate, never a heap object, so its box needs no RC")
fn rawNames f: ty/SsaFunction instrs: (List ty/SsaInstr) -> (Map String Bool)
  (let [(params (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (ty/ssaIsRaw? p.ty)) (listAppend f.captures f.params))))
        (blockParams (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (listAppend acc (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (ty/ssaIsRaw? p.ty)) b.params)))) (list) f.blocks))
        (dests (map (fn [(i ty/SsaInstr)] -> String i.dest) (filter (fn [(i ty/SsaInstr)] -> Bool (ty/ssaIsRaw? i.ty)) instrs)))]
    (setOf (listAppend params (listAppend blockParams dests))))

fn rawBox? raws: (Map String Bool) ins: ty/SsaInstr -> Bool
  (match ins.op ((ty/opBox v) (mapHas? raws v)) (_ false))

fn functionFacts ctx: Ctx f: ty/SsaFunction -> Facts
  (let [(instrs (functionInstrs f))
        (heap (heapNames f))
        (raws (rawNames f instrs))
        (kinds (fold (fn [(acc (Map String String)) (i ty/SsaInstr)] -> (Map String String) (mapSet acc i.dest (if (rawBox? raws i) "immortal" (resultKind ctx i)))) (mapEmpty) instrs))
        (defs (fold (fn [(acc (Map String ty/SsaOp)) (i ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet acc i.dest i.op)) (mapEmpty) instrs))
        (base0 (setOf (filter (fn [(n String)] -> Bool (let [(k (optionOr (mapGet kinds n) ""))] (or (= k "immortal") (= k "opaque")))) (mapKeys heap))))
        (sources (filter (fn [(n String)] -> Bool (let [(k (optionOr (mapGet kinds n) ""))] (or (= k "source") (= k "sourceDup")))) (mapKeys heap)))
        (immortal (union base0 (setOf (filter (fn [(n String)] -> Bool (let [(b (match (mapGet defs n) ((some op) (sourceBase ctx op)) ((none) "")))] (and (!= b "") (immortalBase? ctx defs base0 b 64)))) sources))))
        (flow (if (mapHas? ctx.proj f.name) (flowOf ctx f) (flowNone)))
        (borrowed (union (borrowedParams ctx f) flow.names))
        (parts (partsOf instrs))
        (probe (Facts :heap heap :immortal immortal :anchors (mapEmpty) :dupAfter (mapEmpty) :pinAfter (mapEmpty) :wrapAfter (mapEmpty) :borrowed borrowed :flow flow.keys :parts parts :cells (cellBases parts)
                      :takes (mapEmpty) :guards (mapEmpty) :rawSet (mapEmpty) :known (mapEmpty)))
        (consumeSet (consumedNames ctx probe f))
        (borrowOnly (fn [(n String)] -> Bool (not (mapHas? consumeSet n))))
        (termConsumed (setOf (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (listAppend acc (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (= u.kind "consume")) (termUses probe b.term))))) (list) f.blocks)))
        (tailArgs (setOf (fold (fn [(acc (List String)) (c (Pair String (List String)))] -> (List String) (listAppend acc (pairSecond c))) (list) (tailCalls f))))
        (sinkable (fn [(n String)] -> Bool (and (not (mapHas? termConsumed n)) (not (mapHas? tailArgs n)))))
        (derived (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? immortal n)) (and (or (borrowOnly n) (sinkable n)) (= (optionOr (mapGet kinds n) "") "source")))) sources)))
        (anchors (fold (fn [(acc (Map String String)) (n String)] -> (Map String String)
                         (mapSet acc n (match (mapGet defs n) ((some op) (let [(b (sourceBase ctx op))] (if (= b "") "" (anchorOf ctx defs derived immortal b 64)))) ((none) ""))))
                       (mapEmpty) (mapKeys derived)))
        (dupAfter (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? immortal n)) (not (mapHas? derived n)))) sources)))
        (pinAfter (setOf (filter (fn [(n String)] -> Bool (= (optionOr (mapGet kinds n) "") "opaque")) (mapKeys heap))))
        (wrapAfter (setOf (filter (fn [(n String)] -> Bool (= (optionOr (mapGet kinds n) "") "wrap")) (mapKeys heap))))
        (owned (fn [(x String)] -> Bool (and (mapHas? heap x) (and (not (mapHas? immortal x)) (and (not (mapHas? anchors x)) (not (mapHas? borrowed x)))))))
        (labels (fold (fn [(acc (Map String String)) (b ty/SsaBlock)] -> (Map String String) (fold (fn [(a (Map String String)) (i ty/SsaInstr)] -> (Map String String) (mapSet a i.dest b.label)) acc b.instrs)) (mapEmpty) f.blocks))
        (known (knownClasses ctx f instrs))
        (takes (takeCandidates parts anchors owned (exclusiveSlots parts labels known)))
        (guards (takeGuards takes anchors parts))]
    (Facts :heap heap :immortal immortal :anchors anchors :dupAfter dupAfter :pinAfter pinAfter :wrapAfter wrapAfter :borrowed borrowed :flow flow.keys :parts (orParts parts instrs) :cells (recordCells probe.cells instrs)
           :takes takes :guards guards
           :rawSet (fold (fn [(acc (Map String Bool)) (xs (List String))] -> (Map String Bool) (union acc (setOf xs))) (setOf (mapKeys takes)) (mapValues guards))
           :known known))

; (:m :ref RC-OWN-FOR-REUSE :do "a part read straight from an owned cell (a ctor field, a cons head or rest) that no other read of the function takes from the same slot can be taken out of the cell instead of duplicated: when the cell is unique its slot is cleared, so a callee that consumes the part sees it unique and resets it in place, while the cell itself still dies into a later construct")
; (:m :ref PERCEUS :do "a slot read once per block counts as read once when every block that reads it is a case block of a switch on the cell entered only from that switch: the arms of one match are exclusive, so a take in one arm zeroes a slot no other read on its path sees")
fn exclusiveSlots parts: (Map String (Pair String Int64)) labels: (Map String String) known: (Map String Int64) -> (Map String Int64)
  (let [(reads (fold (fn [(acc (Map String (List String))) (v String)] -> (Map String (List String))
                       (match (mapGet parts v)
                         ((some p) (let [(k (str (pairFirst p) "\t" (pairSecond p)))] (mapSet acc k (cons (optionOr (mapGet labels v) "") (optionOr (mapGet acc k) (list))))))
                         ((none) acc)))
                     (mapEmpty) (mapKeys parts)))]
    (fold (fn [(acc (Map String Int64)) (k String)] -> (Map String Int64)
            (let [(ls (optionOr (mapGet reads k) (list)))
                  (x (optionOr (listHead (stringSplit k "\t")) ""))
                  (ok (and (= (listLength (distinctNames ls)) (listLength ls))
                           (or (= (listLength ls) 1) (listAll? (fn [(l String)] -> Bool (mapHas? known (str l "\t" x))) ls))))]
              (mapSet acc k (if ok 1 (listLength ls)))))
          (mapEmpty) (mapKeys reads)))

fn takeCandidates parts: (Map String (Pair String Int64)) anchors: (Map String String) owned: (fn [String] -> Bool) slots: (Map String Int64) -> (Map String (Pair String Int64))
  (fold (fn [(acc (Map String (Pair String Int64))) (v String)] -> (Map String (Pair String Int64))
            (match (mapGet parts v)
              ((some p) (let [(x (pairFirst p)) (i (pairSecond p))]
                          (if (and (= (optionOr (mapGet anchors v) "") x)
                                   (and (owned x) (and (< i 31) (= (optionOr (mapGet slots (str x "\t" i)) 0) 1))))
                            (mapSet acc v p)
                            acc)))
              ((none) acc)))
          (mapEmpty) (mapKeys anchors))

; (:m :ref RC-OWN-FOR-REUSE :do "the names through which a cell could still be read after one of its parts was taken: the cell itself and every value anchored on it that is not a part read straight from it (a projection call may return the cell whole)")
fn takeGuards takes: (Map String (Pair String Int64)) anchors: (Map String String) parts: (Map String (Pair String Int64)) -> (Map String (List String))
  (let [(bases (setOf (map pairFirst (mapValues takes))))]
    (fold (fn [(acc (Map String (List String))) (d String)] -> (Map String (List String))
            (let [(x (optionOr (mapGet anchors d) ""))
                  (direct (match (mapGet parts d) ((some p) (= (pairFirst p) x)) ((none) false)))]
              (if (and (mapHas? bases x) (not direct)) (mapSet acc x (cons d (optionOr (mapGet acc x) (list)))) acc)))
          (fold (fn [(acc (Map String (List String))) (x String)] -> (Map String (List String)) (mapSet acc x (list x))) (mapEmpty) (mapKeys bases))
          (mapKeys anchors)))

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
  (Walk :live w.live :out (cons (rcCall (fresh w) callee v) w.out) :n (+ w.n 1) :pend w.pend :raw w.raw :quiet w.quiet :moves w.moves)

fn prependAll w: Walk xs: (List ty/SsaInstr) -> Walk
  (Walk :live w.live :out (listAppend xs w.out) :n w.n :pend w.pend :raw w.raw :quiet w.quiet :moves w.moves)

fn rcInstrs label: String w0: Int64 calls: (List (Pair String String)) -> (List ty/SsaInstr)
  (map (fn [(i Int64)] -> ty/SsaInstr
         (let [(c (optionOr (listGet calls i) (pair "" "")))]
           (rcCall (str "rc." label "." (+ w0 i)) (pairFirst c) (pairSecond c))))
       (range 0 (listLength calls)))

; (:m :ref RC-BORROW-CONSUME-CLASH :do "the names one instruction both borrows and consumes: the consumed copy is duplicated and the borrowed one dropped after, so the callee cannot free cells it still reads through the borrowed parameter")
fn clashNames uses: (List Use) -> (Map String Bool)
  (let [(lent (setOf (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (= u.kind "borrow")) uses))))]
    (if (= (mapSize lent) 0)
      lent
      (setOf (filter (fn [(n String)] -> Bool (mapHas? lent n)) (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (= u.kind "consume")) uses))))))

fn beforeCalls facts: Facts uses: (List Use) after: (Map String Bool) -> (List (Pair String String))
  (let [(clash (clashNames uses))]
  (pairSecond
    (fold (fn [(acc (Pair (Map String Bool) (List (Pair String String)))) (u Use)] -> (Pair (Map String Bool) (List (Pair String String)))
            (let [(seen (pairFirst acc)) (calls (pairSecond acc)) (v u.name)]
              (cond
                ((= u.kind "pin") (if (mapHas? facts.immortal v) acc (pair seen (listAppend calls (list (pair (pinName) v))))))
                ((and (= u.kind "consume") (mapHas? facts.borrowed v)) (pair seen (listAppend calls (list (pair (dupName) v)))))
                ((and (= u.kind "consume") (mapHas? facts.anchors v)) (pair seen (listAppend calls (list (pair (dupName) v)))))
                ((and (= u.kind "consume") (tracked? facts v))
                  (if (or (mapHas? after v) (or (mapHas? seen v) (mapHas? clash v)))
                    (pair (mapSet seen v true) (listAppend calls (list (pair (dupName) v))))
                    (pair (mapSet seen v true) calls)))
                (else acc))))
          (pair (mapEmpty) (list)) uses)))

fn dropsAfter facts: Facts uses: (List Use) after: (Map String Bool) -> (List String)
  (let [(clash (clashNames uses))
        (taken (setOf (filter (fn [(n String)] -> Bool (not (mapHas? clash n))) (map (fn [(u Use)] -> String u.name) (filter (fn [(u Use)] -> Bool (or (= u.kind "consume") (= u.kind "pin"))) uses)))))
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
; (:m :ref PERCEUS :do "a record literal of n fields in declared order takes 24 + 16 n bytes, class 1 + 2 n; raw or reordered layouts differ, and routeChunk reclasses the reset to the emitted alloc line")
fn allocClass ins: ty/SsaInstr -> Int64
  (match ins.op
    ((ty/opConstruct _ _ fields) (if (or (listEmpty? fields) (> (listLength fields) 31)) -1 (* 2 (listLength fields))))
    ((ty/opRecord _ fields _) (if (or (listEmpty? fields) (> (listLength fields) 30)) -1 (+ 1 (* 2 (listLength fields)))))
    ((ty/opEntry name _) (if (consumeEntry? name) 3 -1))
    (_ -1))

fn partOf op: ty/SsaOp -> (Option (Pair String Int64))
  (match op
    ((ty/opVariantField b i) (some (pair b i)))
    ((ty/opEntry name args) (cond ((= name "@listFirst") (match (listHead args) ((some b) (some (pair b 0))) ((none) (none))))
                                  ((= name "@listRest") (match (listHead args) ((some b) (some (pair b 1))) ((none) (none))))
                                  (else (none))))
    (_ (none)))

; (:m :ref FREECHAINLOOP :do "listHeadOr and listTailOr read slot 0 or 1 of a non-empty list and the default otherwise; they count as parts for the slot a reset or a drop may keep, never as anchored reads nor as cells, since on an empty list there is no cell and the reset duplicates the default as the read did")
fn orParts parts: (Map String (Pair String Int64)) instrs: (List ty/SsaInstr) -> (Map String (Pair String Int64))
  (fold (fn [(acc (Map String (Pair String Int64))) (i ty/SsaInstr)] -> (Map String (Pair String Int64))
          (match i.op
            ((ty/opEntry name args) (match (listHead args)
                                      ((some b) (cond ((= name "@listHeadOr") (mapSet acc i.dest (pair b 0)))
                                                      ((= name "@listTailOr") (mapSet acc i.dest (pair b 1)))
                                                      (else acc)))
                                      ((none) acc)))
            (_ acc)))
        parts instrs)

fn partsOf instrs: (List ty/SsaInstr) -> (Map String (Pair String Int64))
  (fold (fn [(acc (Map String (Pair String Int64))) (i ty/SsaInstr)] -> (Map String (Pair String Int64))
          (match (partOf i.op) ((some p) (mapSet acc i.dest p)) ((none) acc)))
        (mapEmpty) instrs)

fn cellBases parts: (Map String (Pair String Int64)) -> (Map String Bool)
  (setOf (map (fn [(p (Pair String Int64))] -> String (pairFirst p)) (mapValues parts)))

; (:m :ref PERCEUS :do "a record read through opField is a reuse cell too, marked false: its slot order is not static, so nothing moves out of it and the reset releases every kid")
fn recordCells cells: (Map String Bool) instrs: (List ty/SsaInstr) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (i ty/SsaInstr)] -> (Map String Bool)
          (match i.op ((ty/opField b _) (if (mapHas? acc b) acc (mapSet acc b false))) (_ acc)))
        cells instrs)

fn variantArity types: (List ty/SsaTypeDecl) -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (d ty/SsaTypeDecl)] -> (Map String Int64)
          (fold (fn [(a (Map String Int64)) (v ty/SsaVariant)] -> (Map String Int64) (mapSet a (str d.name "\t" v.name) v.arity)) acc d.variants))
        (mapEmpty) types)

; (:m :ref PERCEUS :do "the size class a cell is known to have: a list part's base is a cons (class 3) everywhere; a switch scrutinee holds the case's variant (class 2 x arity, or no cell for arity 0: -1) only inside the case block itself when that block is entered only from that case, not in the blocks it dominates, where a reset finds the class at run time; keys are block label, tab, name, and tab, name for the everywhere facts")
fn knownClasses ctx: Ctx f: ty/SsaFunction instrs: (List ty/SsaInstr) -> (Map String Int64)
  (let [(preds (predCounts f.blocks))
        (lists (fold (fn [(acc (Map String Int64)) (i ty/SsaInstr)] -> (Map String Int64)
                       (match i.op
                         ((ty/opEntry name args) (if (or (= name "@listFirst") (= name "@listRest"))
                                                   (match (listHead args) ((some b) (mapSet acc (str "\t" b) 3)) ((none) acc))
                                                   acc))
                         (_ acc)))
                     (mapEmpty) instrs))]
    (fold (fn [(acc (Map String Int64)) (b ty/SsaBlock)] -> (Map String Int64)
            (match b.term
              ((ty/termSwitch x tn cases _)
               (fold (fn [(a (Map String Int64)) (c ty/SsaCase)] -> (Map String Int64)
                       (match (mapGet ctx.arity (str tn "\t" c.variant))
                         ((some n) (if (= (optionOr (mapGet preds c.edge.target) 0) 1) (mapSet a (str c.edge.target "\t" x) (if (> n 0) (* 2 n) -1)) a))
                         ((none) a)))
                     acc cases))
              (_ acc)))
          lists f.blocks))

fn knownClass facts: Facts label: String x: String -> Int64
  (match (mapGet facts.known (str label "\t" x))
    ((some c) c)
    ((none) (optionOr (mapGet facts.known (str "\t" x)) -2)))

fn recordClass? cls: Int64 -> Bool
  (and (= (mod cls 2) 1) (!= cls 3))

; (:m :ref PERCEUS :do "a dead cell whose class is known to differ from the construct's never resets into it; one known to match goes first, then one of the construct's kind")
fn cellFor facts: Facts label: String cls: Int64 dead: (List String) -> (Option String)
  (let [(cands (filter (fn [(x String)] -> Bool (and (mapHas? facts.cells x) (and (tracked? facts x) (let [(k (knownClass facts label x))] (or (= k -2) (= k cls)))))) dead))
        (want (not (recordClass? cls)))]
    (match (listHead (filter (fn [(x String)] -> Bool (= (knownClass facts label x) cls)) cands))
      ((some x) (some x))
      ((none) (match (listHead (filter (fn [(x String)] -> Bool (= (optionOr (mapGet facts.cells x) false) want)) cands))
                ((some x) (some x))
                ((none) (listHead cands))))))

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
                      (match (mapGet facts.parts f) ((some p) (and (= (pairFirst p) x) (< (pairSecond p) 62))) ((none) false)))))
          fields)

fn maskOf facts: Facts moved: (List String) -> Int64
  (fold (fn [(acc Int64) (f String)] -> Int64 (| acc (<< 1 (match (mapGet facts.parts f) ((some p) (pairSecond p)) ((none) 0))))) 0 moved)

fn constructFields ins: ty/SsaInstr -> (List String)
  (match ins.op ((ty/opConstruct _ _ fields) fields) ((ty/opEntry _ args) args) (_ (list)))

schema Reuse
  cell: String
  moved: (List String)
  callee: String

fn reusePlan facts: Facts label: String ins: ty/SsaInstr dead: (List String) -> (Option Reuse)
  (let [(cls (allocClass ins))]
    (if (or (< cls 0) (or (listEmpty? dead) (not (reusableDest? ins.dest))))
      (none)
      (match (cellFor facts label cls dead)
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

; (:m :ref RC-FBIP-CLOSURE :do "a closure call outside tail position with one or two arguments, all values (with the closure that keeps every parameter in a register, where a third argument would spill), goes through aslRcCallOwnedN, which hands the arguments over: an argument dying here moves to the callee without a drop after, any other is duplicated before, so a lambda sees a value its caller let go of as unique and its constructs can reuse the cell; the closure itself stays borrowed")
fn ownedArity -> Int64
  2

fn callOwnedName n: Int64 -> String
  (str "aslRcCallOwned" n)

fn ownedName name: String -> String
  (ssa/ownedEntryName (wrapperName name))

fn ownedCall? facts: Facts ins: ty/SsaInstr -> Bool
  (match ins.op
    ((ty/opCallClosure c args) (and (mapHas? facts.heap c) (and (> (listLength args) 0) (and (<= (listLength args) (ownedArity)) (and (not (listContains? args c)) (listAll? (fn [(a String)] -> Bool (mapHas? facts.heap a)) args))))))
    (_ false))

fn ownedUses facts: Facts ins: ty/SsaInstr -> (List Use)
  (match ins.op
    ((ty/opCallClosure c args) (listAppend (heapUses facts (list c) "borrow") (heapUses facts args "consume")))
    (_ (list)))

fn closureCall? ins: ty/SsaInstr -> Bool
  (match ins.op ((ty/opCallClosure _ _) true) (_ false))

fn closureUses facts: Facts ins: ty/SsaInstr -> (List Use)
  (match ins.op ((ty/opCallClosure c args) (heapUses facts (cons c args) "borrow")) (_ (list)))

fn ownedInstr ins: ty/SsaInstr -> ty/SsaInstr
  (match ins.op
    ((ty/opCallClosure c args) (ty/ssaInstr ins.dest ins.ty (ty/opCall (callOwnedName (listLength args)) (cons c args))))
    (_ ins))

fn rewriteInstr ctx: Ctx facts: Facts label: String tail: Bool w: Walk ins: ty/SsaInstr -> Walk
  (let [(after w.live)
        (owned (and (not tail) (ownedCall? facts ins)))
        (uses (cond (owned (ownedUses facts ins)) ((closureCall? ins) (closureUses facts ins)) (else (instrUses ctx facts ins))))
        (results (filter (fn [(c (Pair String String))] -> Bool (not (and (= (pairFirst c) (dupName)) (mapHas? w.moves (pairSecond c))))) (resultCalls facts ins after)))
        (dead0 (dropsAfter facts uses after))
        (plan0 (if tail (none) (reusePlan facts label ins dead0)))
        (extra (match plan0 ((some r) (restMoves facts (optionOr (mapGet w.quiet ins.dest) (mapEmpty)) r after uses)) ((none) (list))))
        (plan (match plan0 ((some r) (some (Reuse :cell r.cell :moved (listAppend r.moved extra) :callee (resetName (allocClass ins) (maskOf facts (listAppend r.moved extra)))))) ((none) (none))))
        (moved (match plan ((some r) r.moved) ((none) (list))))
        (before (takenDups facts uses w.raw (withoutDups (beforeCalls facts uses after) moved)))
        (late (match plan ((some _) (none)) ((none) (if tail (none) (latePlan facts label w.pend dead0)))))
        (gone (match plan ((some r) (some r.cell)) ((none) (match late ((some l) (some l.cell)) ((none) (none))))))
        (dead (match gone ((some c) (filter (fn [(n String)] -> Bool (!= n c)) dead0)) ((none) dead0)))
        (deferred (and tail (and (listEmpty? results) (not (listEmpty? dead)))))
        (pre (if deferred (listAppend before (deferCalls dead)) before))
        (quietHere (optionOr (mapGet w.quiet ins.dest) (mapEmpty)))
        (drops (if (or deferred (= (mapSize quietHere) 0)) (list) (dropMoves facts quietHere after uses dead)))
        (dropped (setOf (map (fn [(d DropMove)] -> String d.cell) drops)))
        (post (if deferred (list) (listAppend results (map (fn [(n String)] -> (Pair String String) (pair (dropName) n)) (filter (fn [(n String)] -> Bool (not (mapHas? dropped n))) dead)))))
        (n0 w.n)
        (shared (map (fn [(f String)] -> (Pair String String) (pair (dupSharedName) (str (tokenName ins.dest) "\t" f))) moved))
        (reuseIs (match plan ((some r) (cons (rcCall (tokenName ins.dest) r.callee r.cell) (rcInstrs label (+ n0 (listLength pre)) shared))) ((none) (list))))
        (nPre (+ (listLength pre) (listLength shared)))
        (beforeIs (listAppend (rcInstrs label n0 pre) reuseIs))
        (dropShared (fold (fn [(acc (List (Pair String String))) (d DropMove)] -> (List (Pair String String)) (listAppend acc (map (fn [(f String)] -> (Pair String String) (pair (dupSharedName) (str (tokenName (str "drop." label "." n0 "." d.cell)) "\t" f))) d.moved))) (list) drops))
        (dropIs (listAppend (map (fn [(d DropMove)] -> ty/SsaInstr (rcCall (tokenName (str "drop." label "." n0 "." d.cell)) (resetName (noCell) (maskOf facts d.moved)) d.cell)) drops)
                            (rcInstrs label (+ n0 (+ nPre (listLength post))) dropShared)))
        (dropMoved (fold (fn [(acc (List String)) (d DropMove)] -> (List String) (listAppend acc d.moved)) (list) drops))
        (lateMoved (match late ((some l) (if (= (mapSize quietHere) 0) (list) (restMoves facts quietHere (Reuse :cell l.cell :moved (list) :callee "") after uses))) ((none) (list))))
        (lateIs (match late
                  ((some l) (cons (rcCall (tokenName l.target) (resetName l.cls (maskOf facts lateMoved)) l.cell)
                                  (rcInstrs label (+ n0 (+ nPre (+ (listLength post) (listLength dropShared))))
                                            (map (fn [(f String)] -> (Pair String String) (pair (dupSharedName) (str (tokenName l.target) "\t" f))) lateMoved))))
                  ((none) (list))))
        (afterIs (listAppend (rcInstrs label (+ n0 nPre) post) (listAppend dropIs lateIs)))
        (pend (cond ((some? late) (optionOr (listTail w.pend) (list)))
                    ((and (none? plan) (and (not tail) (and (>= (allocClass ins) 0) (reusableDest? ins.dest)))) (cons (pair ins.dest (allocClass ins)) w.pend))
                    (else w.pend)))
        (live (union (mapRemove after ins.dest) (setOf (liveNames facts uses))))
        (raw (if (= (mapSize facts.rawSet) 0) w.raw (union (mapRemove w.raw ins.dest) (setOf (rawNamesOf facts uses)))))]
    (Walk :live live :out (listAppend beforeIs (cons (if owned (ownedInstr ins) ins) (listAppend afterIs w.out))) :n (+ n0 (+ nPre (+ (listLength post) (+ (listLength dropShared) (listLength lateMoved))))) :pend pend :raw raw
          :quiet w.quiet :moves (if (and (listEmpty? extra) (and (listEmpty? dropMoved) (listEmpty? lateMoved))) w.moves (union w.moves (setOf (listAppend extra (listAppend dropMoved lateMoved)))))))

schema DropMove
  cell: String
  moved: (List String)

; (:m :ref FREECHAINLOOP :do "a cell that dies here while a part read from it earlier in the block outlives it, duplicated at the read and untouched since, is released by a reset that keeps that slot (asking for a class no construct has, so it never hands its cell over): a unique cell is recycled with its other kids released and the part inherits the slot's count, a shared one is decremented and the part is duplicated then, so a list walk by head and tail costs no dup and release of each rest")
fn dropMoves facts: Facts quiet: (Map String Bool) after: (Map String Bool) uses: (List Use) dead: (List String) -> (List DropMove)
  (filter (fn [(d DropMove)] -> Bool (not (listEmpty? d.moved)))
          (map (fn [(x String)] -> DropMove (DropMove :cell x :moved (if (mapHas? facts.cells x) (restMoves facts quiet (Reuse :cell x :moved (list) :callee "") after uses) (list))))
               dead))

; (:m :ref FREECHAINLOOP :do "a part of the reset cell that was read earlier in the block, duplicated at its read because it outlives the cell, and untouched between that read and the construct moves with the reset like a moved field: the reset leaves its slot alone and it is duplicated only when the cell was shared, so a unique list cell walked by reverse costs no dup and release of its rest")
fn restMoves facts: Facts quiet: (Map String Bool) r: Reuse after: (Map String Bool) uses: (List Use) -> (List String)
  (let [(used (setOf (map (fn [(u Use)] -> String u.name) uses)))
        (taken (map (fn [(f String)] -> Int64 (partSlot facts "" f)) r.moved))
        (cands (filter (fn [(f String)] -> Bool (movableRest? facts after used taken (partSlot facts r.cell f) f)) (mapKeys quiet)))]
    (filter (fn [(f String)] -> Bool (= (listLength (filter (fn [(g String)] -> Bool (= (partSlot facts r.cell g) (partSlot facts r.cell f))) cands)) 1)) cands))

fn partSlot facts: Facts cell: String f: String -> Int64
  (match (mapGet facts.parts f)
    ((some p) (if (or (= cell "") (= (pairFirst p) cell)) (pairSecond p) -1))
    ((none) -1))

fn movableRest? facts: Facts after: (Map String Bool) used: (Map String Bool) taken: (List Int64) i: Int64 f: String -> Bool
  (and (>= i 0)
       (and (< i 62)
            (and (mapHas? after f)
                 (and (mapHas? facts.dupAfter f)
                      (and (not (mapHas? used f)) (not (listContains? taken i)))))))

; (:m :ref FREECHAINLOOP :do "for each instruction of a block, the parts read earlier in the block whose result is duplicated at the read and that no instruction uses between the read and the construct")
fn quietParts facts: Facts b: ty/SsaBlock -> (Map String (Map String Bool))
  (pairSecond (fold (fn [(acc (Pair (Map String Bool) (Map String (Map String Bool)))) (ins ty/SsaInstr)] -> (Pair (Map String Bool) (Map String (Map String Bool)))
                      (let [(clean0 (pairFirst acc))
                            (out (if (and (!= ins.dest "") (> (mapSize clean0) 0)) (mapSet (pairSecond acc) ins.dest clean0) (pairSecond acc)))
                            (clean1 (if (= (mapSize clean0) 0) clean0 (without clean0 (ty/opOperands ins.op))))
                            (clean (if (and (mapHas? facts.parts ins.dest) (mapHas? facts.dupAfter ins.dest)) (mapSet clean1 ins.dest true) clean1))]
                        (pair clean out)))
                    (pair (mapEmpty) (mapEmpty)) b.instrs))

fn rawNamesOf facts: Facts uses: (List Use) -> (List String)
  (filter (fn [(n String)] -> Bool (mapHas? facts.rawSet n)) (map (fn [(u Use)] -> String u.name) uses))

fn takeName i: Int64 -> String
  (str "aslRcTake_" i)

; (:m :ref RC-OWN-FOR-REUSE :do "the dup of a consumed part becomes a take from its cell when the part is used once here and neither it nor any name that could read the cell is live afterwards; raw is the set of those names live after the instruction")
fn takenDups facts: Facts uses: (List Use) raw: (Map String Bool) calls: (List (Pair String String)) -> (List (Pair String String))
  (if (= (mapSize facts.takes) 0)
    calls
    (map (fn [(c (Pair String String))] -> (Pair String String)
           (let [(v (pairSecond c))]
             (match (if (= (pairFirst c) (dupName)) (mapGet facts.takes v) (none))
               ((none) c)
               ((some p) (let [(x (pairFirst p))
                               (guard (optionOr (mapGet facts.guards x) (list x)))
                               (once (= (listLength (filter (fn [(u Use)] -> Bool (= u.name v)) uses)) 1))
                               (quiet (not (listAny? (fn [(u Use)] -> Bool (listContains? guard u.name)) uses)))
                               (dead (and (not (mapHas? raw v)) (not (listAny? (fn [(g String)] -> Bool (mapHas? raw g)) guard))))]
                           (if (and once (and quiet dead)) (pair (takeName (pairSecond p)) (str x "\t" v)) c))))))
         calls))

schema Late
  cell: String
  target: String
  callee: String
  cls: Int64

; (:m :ref RC-FBIP :do "an owned value read through its fields that dies before a later construct of the same block resets into the nearest such construct still without a cell; nothing it holds moves, so all its kids are released")
fn latePlan facts: Facts label: String pend: (List (Pair String Int64)) dead: (List String) -> (Option Late)
  (match (listHead pend)
    ((none) (none))
    ((some p) (match (cellFor facts label (pairSecond p) dead)
                ((none) (none))
                ((some x) (some (Late :cell x :target (pairFirst p) :callee (resetName (pairSecond p) 0) :cls (pairSecond p)))))))

fn trapBlock? blocks: (Map String ty/SsaBlock) target: String -> Bool
  (match (mapGet blocks target)
    ((some b) (and (listEmpty? b.instrs) (match b.term ((ty/termUnreachable) true) (_ false))))
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
    (match t
      ((ty/termJump _) (ty/termJump (at 0)))
      ((ty/termBranch c _ _) (ty/termBranch c (at 0) (at 1)))
      ((ty/termSwitch s typeName cases d)
        (ty/termSwitch s typeName
          (map (fn [(k Int64)] -> ty/SsaCase (let [(c (optionOr (listGet cases k) (ty/ssaCase "" (ty/ssaEdge "" (list)))))] (ty/ssaCase c.variant (at k)))) (range 0 (listLength cases)))
          (match d ((some _) (some (at (listLength cases)))) ((none) (none)))))
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
  (match t
    ((ty/termJump e) (edgeCalls facts liveIn (mapEmpty) e))
    ((ty/termReturn v) (if (and (mapHas? facts.borrowed v) (not (mapHas? facts.flow "$ret"))) (list (pair (dupName) v)) (list)))
    (_ (list)))

fn tailClosureDest b: ty/SsaBlock -> String
  (match b.term
    ((ty/termReturn v) (match (listHead (listReverse b.instrs))
                         ((some ins) (match ins.op ((ty/opCallClosure _ _) (if (= ins.dest v) v "")) (_ "")))
                         ((none) "")))
    (_ ""))

fn rewriteBlock ctx: Ctx facts: Facts liveIn: (Map String (Map String Bool)) rawIn: (Map String (Map String Bool)) byLabel: (Map String ty/SsaBlock) preds: (Map String Int64) entry: Bool fnParams: (List String) b: ty/SsaBlock prefix: (Map String (List ty/SsaInstr)) -> (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))
  (let [(liveOut (liveOutOf liveIn b))
        (termUsed (termUses facts b.term))
        (atTerm (union liveOut (setOf (liveNames facts termUsed))))
        (placed (placeEdges facts liveIn byLabel preds b atTerm prefix))
        (jumpCalls (jumpDups facts liveIn b.term))
        (start (Walk :live atTerm :out (rcInstrs (str b.label ".j") 0 jumpCalls) :n 0 :pend (list) :raw (rawAtTerm facts rawIn b) :quiet (quietParts facts b) :moves (mapEmpty)))
        (tailDest (tailClosureDest b))
        (walked (fold (fn [(w Walk) (ins ty/SsaInstr)] -> Walk (rewriteInstr ctx facts b.label (and (!= tailDest "") (and (= ins.dest tailDest) (listEmpty? w.out))) w ins)) start (listReverse b.instrs)))
        (defined (listAppend (blockParamNames facts b) (if entry fnParams (list))))
        (deadAtStart (filter (fn [(n String)] -> Bool (not (mapHas? walked.live n))) defined))
        (startDrops (rcInstrs (str b.label ".s") 0 (map (fn [(n String)] -> (Pair String String) (pair (dropName) n)) deadAtStart)))
        (main (ty/ssaBlock b.label b.params (listAppend startDrops walked.out) placed.term))]
    (pair (cons main placed.blocks) placed.prefix))

fn withPrefix b: ty/SsaBlock prefix: (Map String (List ty/SsaInstr)) -> ty/SsaBlock
  (match (mapGet prefix b.label)
    ((none) b)
    ((some xs) (ty/ssaBlock b.label b.params (listAppend xs b.instrs) b.term)))

fn closureCallee op: ty/SsaOp -> (Option String)
  (match op ((ty/opMakeClosure callee _) (some callee)) (_ (none)))

fn retarget targets: (Map String Bool) ins: ty/SsaInstr -> ty/SsaInstr
  (match ins.op
    ((ty/opMakeClosure callee caps) (if (mapHas? targets callee) (ty/ssaInstr ins.dest ins.ty (ty/opMakeClosure (wrapperName callee) caps)) ins))
    (_ ins))

fn retargetClosures targets: (Map String Bool) f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock (ty/ssaBlock b.label b.params (map (fn [(ins ty/SsaInstr)] -> ty/SsaInstr (retarget targets ins)) b.instrs) b.term)) f.blocks))

; (:m :ref RC-OWN-FOR-REUSE :do "liveness of the take names themselves, not of their anchors: a part or a cell name is live where a later instruction, terminator or edge still names it")
fn rawAtTerm facts: Facts rawIn: (Map String (Map String Bool)) b: ty/SsaBlock -> (Map String Bool)
  (if (= (mapSize facts.rawSet) 0)
    (mapEmpty)
    (union (liveOutOf rawIn b) (setOf (rawNamesOf facts (termUses facts b.term)))))

fn rawBack ctx: Ctx facts: Facts rawIn: (Map String (Map String Bool)) b: ty/SsaBlock -> (Map String Bool)
  (without (fold (fn [(live (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool)
                   (union (mapRemove live ins.dest) (setOf (rawNamesOf facts (instrUses ctx facts ins)))))
                 (rawAtTerm facts rawIn b) (listReverse b.instrs))
           (map (fn [(p ty/SsaParam)] -> String p.name) b.params))

fn rawLiveness ctx: Ctx facts: Facts f: ty/SsaFunction rawIn: (Map String (Map String Bool)) fuel: Int64 -> (Map String (Map String Bool))
  (let [(next (fold (fn [(acc (Map String (Map String Bool))) (b ty/SsaBlock)] -> (Map String (Map String Bool)) (mapSet acc b.label (rawBack ctx facts acc b)))
                    rawIn (listReverse f.blocks)))]
    (if (or (<= fuel 0) (= (liveSize next) (liveSize rawIn))) next (rawLiveness ctx facts f next (- fuel 1))))

fn rcFunction ctx: Ctx f: ty/SsaFunction -> ty/SsaFunction
  (let [(facts (cachedFacts ctx f))
        (liveIn (liveness ctx facts f (mapEmpty) 1000))
        (rawIn (if (= (mapSize facts.rawSet) 0) (mapEmpty) (rawLiveness ctx facts f (mapEmpty) 1000)))
        (byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))
        (preds (predCounts f.blocks))
        (fnParams (filter (fn [(n String)] -> Bool (tracked? facts n)) (map (fn [(p ty/SsaParam)] -> String p.name) (listAppend f.captures f.params))))
        (entryLabel (match (listHead f.blocks) ((some b) b.label) ((none) "")))
        (rewritten (fold (fn [(acc (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))) (b ty/SsaBlock)] -> (Pair (List ty/SsaBlock) (Map String (List ty/SsaInstr)))
                           (let [(r (rewriteBlock ctx facts liveIn rawIn byLabel preds (= b.label entryLabel) fnParams b (pairSecond acc)))]
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

; (:m :ref RC-FBIP-CLOSURE :do "the owned entry of a counted closure target: the closure keeps its captures, so they are duplicated, while the arguments arrive owned from aslRcCallOwnedN and pass straight on")
fn ownedFunction f: ty/SsaFunction -> ty/SsaFunction
  (let [(heapCaps (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (heapTy? p.ty)) f.captures)))
        (pre (map (fn [(i Int64)] -> ty/SsaInstr (rcCall (str "rc.o." i) (dupName) (optionOr (listGet heapCaps i) ""))) (range 0 (listLength heapCaps))))
        (call (ty/ssaInstr "rc.r" f.retTy (ty/opCall f.name (map (fn [(p ty/SsaParam)] -> String p.name) (listAppend f.captures f.params)))))]
    (ty/ssaFunction (ownedName f.name) f.captures f.params f.retTy
      (list (ty/ssaBlock "entry" (list) (listAppend pre (list call)) (ty/termReturn "rc.r")))))

fn ownedArities bodies: (List ty/SsaFunction) -> (List Int64)
  (distinctInts (fold (fn [(acc (List Int64)) (f ty/SsaFunction)] -> (List Int64)
                        (fold (fn [(a (List Int64)) (ins ty/SsaInstr)] -> (List Int64)
                                (match ins.op ((ty/opCall callee args) (if (stringStartsWith? callee "aslRcCallOwned") (cons (- (listLength args) 1) a) a)) (_ a)))
                              acc (functionInstrs f)))
                      (list) bodies))

fn ownedExterns bodies: (List ty/SsaFunction) -> (List ty/SsaExtern)
  (map (fn [(n Int64)] -> ty/SsaExtern (ty/ssaExternTyped (callOwnedName n) (map (fn [(i Int64)] -> ty/SsaTy (ty/tyVal)) (range 0 (+ n 1))) (ty/tyVal))) (ownedArities bodies))

fn slowName n: Int64 -> String
  (str "aslRcCallOwnedSlow" n)

; (:m :ref RC-FBIP-CLOSURE :do "the slow path of an owned call lives in SSA so its closure call pulls objrt.call into the module: it calls through the borrowing entry and then drops the owned arguments")
fn ownedSlowFunction n: Int64 -> ty/SsaFunction
  (let [(args (map (fn [(i Int64)] -> String (str "a" i)) (range 0 n)))
        (call (ty/ssaInstr "rc.r" (ty/tyVal) (ty/opCallClosure "f" args)))
        (drops (map (fn [(i Int64)] -> ty/SsaInstr (rcCall (str "rc.s." i) (dropName) (optionOr (listGet args i) ""))) (range 0 n)))]
    (ty/ssaFunction (slowName n) (list) (map (fn [(a String)] -> ty/SsaParam (ty/ssaParam a (ty/tyVal))) (cons "f" args)) (ty/tyVal)
      (list (ty/ssaBlock "entry" (list) (cons call drops) (ty/termReturn "rc.r")))))

fn uncaptured f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name (list) (listAppend f.captures f.params) f.retTy f.blocks)

fn distinctNames xs: (List String) -> (List String)
  (mapKeys (setOf xs))

fn rcModule m: ty/SsaModule user: (Map String Bool) -> ty/SsaModule
  (let [(builders (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) (filter ssa/listBuilder? m.functions))))
        (names (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) m.functions)))
        (singletons (setOf (filter opt/singleton? (mapKeys names))))
        (routed (setOf (filter (fn [(n String)] -> Bool (and (not (mapHas? user n)) (countedRoute? n))) (mapKeys names))))
        (ctx0 (Ctx :user (union (union user singletons) routed) :opaque builders :builders builders :borrows (mapEmpty) :scc (mapEmpty) :proj (mapEmpty) :cache (mapEmpty) :arity (variantArity m.types)))
        (targets (setOf (filter (fn [(n String)] -> Bool (mapHas? names n))
                                (distinctNames (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                                                       (listAppend acc (fold (fn [(a (List String)) (ins ty/SsaInstr)] -> (List String) (match (closureCallee ins.op) ((some c) (cons c a)) ((none) a))) (list) (functionInstrs f))))
                                                     (list) m.functions)))))
        (counted (fn [(f ty/SsaFunction)] -> Bool (not (opaqueFunction? ctx0 f.name))))
        (countedFns (filter counted m.functions))
        (ctxS (Ctx :user ctx0.user :opaque ctx0.opaque :builders ctx0.builders :borrows ctx0.borrows :scc (sccOf m.functions targets) :proj (mapEmpty) :cache (mapEmpty) :arity ctx0.arity))
        (borrows0 (initialBorrows countedFns targets))
        (ctxB (withBorrows ctxS borrows0))
        (ctx (settleProj (withProj ctxB (growProj ctxB (filter (fn [(f ty/SsaFunction)] -> Bool (borrowable? targets f)) countedFns) 50)) countedFns (flagReaders countedFns) (allPending countedFns) borrows0 50))
        (bodies (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction
                       (let [(g (retargetClosures targets (if (counted f) (rcFunction ctx f) f)))]
                         (if (mapHas? targets f.name) (uncaptured g) g)))
                     m.functions))
        (wrappers (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (wrapperFunction f (not (counted f))))
                       (filter (fn [(f ty/SsaFunction)] -> Bool (mapHas? targets f.name)) m.functions)))
        (owners (map ownedFunction (filter (fn [(f ty/SsaFunction)] -> Bool (and (mapHas? targets f.name) (counted f))) m.functions)))
        (have (setOf (map (fn [(e ty/SsaExtern)] -> String e.name) m.externs)))
        (externs (listAppend m.externs (filter (fn [(e ty/SsaExtern)] -> Bool (not (mapHas? have e.name))) (listAppend (rcExterns) (listAppend (reuseExterns bodies) (listAppend (takeExterns bodies) (ownedExterns bodies)))))))]
    (ty/ssaModule m.name m.strings m.types m.records externs m.globals (listAppend bodies (listAppend wrappers (listAppend owners (map ownedSlowFunction (ownedArities bodies)))))))

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
               (if notrace "  %arr = icmp eq i64 %ty8, 6\n  %hnd = icmp eq i64 %ty8, 7\n  %ext = or i1 %arr, %hnd\n  %ok = or i1 %small, %ext" "  %hnd = icmp eq i64 %ty8, 7\n  %pool = and i1 %small, %pooled\n  %ok = or i1 %pool, %hnd")
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


; (:m :ref RC-RELEASEKIDS :do "a freed object's dying kids never go through release: a kid without kids (string, bytes, box, array, a record or ctor whose +12 boxed-slot count is 0) is recycled on the spot, and of the kids that have kids one becomes the next turn of the loop while only the others are pushed, so a list spine, a tree path or a record chain frees with no pending-stack traffic")
fn kidText p: String k: String go: String -> (List String)
  (list (str p "Claim:")
        (str "  %" p "Free = call i1 @aslRc.claim(ptr %" k ")")
        (str "  br i1 %" p "Free, label %" p "Dies, label %" go)
        (str p "Dies:")
        (str "  %" p "H = load i64, ptr %" k)
        (str "  %" p "Ty = lshr i64 %" p "H, 32")
        (str "  %" p "Ty8 = and i64 %" p "Ty, 255")
        (str "  %" p "Ty1 = sub i64 %" p "Ty8, 1")
        (str "  %" p "Kinded = icmp ult i64 %" p "Ty1, 4")
        (str "  %" p "Ty2 = sub i64 %" p "Ty8, 2")
        (str "  %" p "Flat = icmp ult i64 %" p "Ty2, 2")
        (str "  %" p "Np = getelementptr inbounds i8, ptr %" k ", i64 12")
        (str "  %" p "N = load i32, ptr %" p "Np")
        (str "  %" p "None = icmp eq i32 %" p "N, 0")
        (str "  %" p "Bare = and i1 %" p "Flat, %" p "None")
        (str "  %" p "Boxed = xor i1 %" p "Bare, true")
        (str "  %" p "Nest = and i1 %" p "Kinded, %" p "Boxed")
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
                   "  br i1 %hk, label %headShallow, label %next"
                   "headShallow:"
                   "  call void @aslRc.freeShallow(ptr %hn)"
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

; (:m :ref FREECHAINLOOP :do "a nested head of a dying cons whose tail also dies is freed on the spot instead of being pushed: its count is already zero, each dying kid without kids is recycled, one dying kid with kids becomes the next turn of this loop and only further ones are pushed, then each cell is recycled; a list of records, nested records included, frees with no pending-stack traffic")
fn freeShallowText asan: Bool -> String
  (lines (listAppend
           (list "define internal void @aslRc.freeShallow(ptr %o) {"
                 "entry:"
                 "  br label %top"
                 "top:"
                 "  %p = phi ptr [ %o, %entry ], [ %nx, %again ]"
                 "  %h = load i64, ptr %p"
                 "  %ty = lshr i64 %h, 32"
                 "  %ty8 = and i64 %ty, 255"
                 "  switch i64 %ty8, label %leaf [ i64 1, label %cons i64 2, label %rec i64 3, label %ctor i64 4, label %clo ]"
                 "cons:"
                 "  %cb = getelementptr inbounds i8, ptr %p, i64 8"
                 "  br label %kids"
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
                 "  %base = phi ptr [ %cb, %cons ], [ %rb, %rec ], [ %fb, %ctor ], [ %ub, %clo ], [ %p, %leaf ]"
                 "  %n = phi i64 [ 2, %cons ], [ %rn, %rec ], [ %fn, %ctor ], [ %un, %clo ], [ 0, %leaf ]"
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
                   "  call void @aslRc.recycle(ptr %p, i64 %h)"
                   "  %go = icmp ne ptr %nx, null"
                   "  br i1 %go, label %again, label %done"
                   "again:"
                   "  br label %top"
                   "done:"
                   "  ret void"
                   "}"))))

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
  17

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
                           (str "  %pooled = icmp ult i64 %cls, " (classes))
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
                 (str "  %isLarge = icmp eq i64 %cls, 255\n  br i1 %isLarge, label %" (if notrace "largeFree" "largeFinalise") ", label %classed\nclassed:")
                 (if rooted (str "  %inFree = icmp ult i64 %cls, " (classes) "\n  br i1 %inFree, label %pooledClass, label %badClass\nbadClass:\n  call void @llvm.trap()\n  unreachable\npooledClass:\n  br i1 %big, label %node, label %smallNode") "  br label %small")
                 (if notrace (largeFreeText) (largeFinaliseText))
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

; (:m :ref FFI2 :do "under the traced runtime the only large object RC counts is a Handle (aslRc.obj admits type 7), and the sweep owns its memory: at count zero it runs fin(p) at once, clears both words so the sweep never runs it again, and sticks the header so later drops ignore it")
; (:m :ref RC-LARGE-RECYCLE-GUARD :do "the Handle type is checked here, not assumed from aslRc.obj: any other large type keeps its header untouched, since gcAsl largeSkip reads a nonzero byte 48 as permanent for every type but 7, so the sweep still frees it and widening aslRc.obj never runs a data word as fin; a pooled class past the free-list array traps in the slow path, and the inlined fast path admits only classes below it")
fn largeFinaliseText -> String
  (lines (list "largeFinalise:"
               "  %gty = lshr i64 %h, 32"
               "  %gty8 = and i64 %gty, 255"
               "  %gHnd = icmp eq i64 %gty8, 7"
               "  br i1 %gHnd, label %largeHandle, label %largeLeave"
               "largeLeave:"
               "  ret void"
               "largeHandle:"
               "  %gfp = getelementptr inbounds i8, ptr %o, i64 24"
               "  %gf = load ptr, ptr %gfp"
               "  %gnf = icmp eq ptr %gf, null"
               "  br i1 %gnf, label %largeStick, label %largeRun"
               "largeRun:"
               "  %gap = getelementptr inbounds i8, ptr %o, i64 16"
               "  %ga = load ptr, ptr %gap"
               "  store ptr null, ptr %gap"
               "  store ptr null, ptr %gfp"
               "  call void %gf(ptr %ga)"
               "  br label %largeStick"
               "largeStick:"
               (str "  %gs = or i64 %h, " (sticky))
               "  store i64 %gs, ptr %o"
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
               (if notrace "  %over = icmp ugt i64 %ty8, 7\n  %raw = icmp eq i64 %ty8, 5\n  %leafy = or i1 %over, %raw" "  %over = icmp ugt i64 %ty8, 4\n  %hndp = icmp eq i64 %ty8, 7\n  %nh = xor i1 %hndp, true\n  %leafy = and i1 %over, %nh")
               "  br i1 %leafy, label %done, label %kind"
               "kind:"
               "  %cls = lshr i64 %h, 56"
               "  %pooled = icmp ne i64 %cls, 255"
               (if notrace "  br label %counted" "  %cnt = or i1 %pooled, %hndp\n  br i1 %cnt, label %counted, label %walk")
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
  (match (stringIndexOf text "\ndeclare ")
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
  "(:rcStats :freed %llu :stuck %llu :reused %llu :pinned %llu :fresh %llu :large %llu :largeFreed %llu :pushed %llu :ops %llu :immediate %llu :fbip %llu :resets %llu :spare %llu :arenas %llu :arenaCells %llu :promoted %llu :retained %llu)\n"

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
               "  %r = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @aslRc.statsFmt, i64 %v0, i64 %v1, i64 %v2, i64 %v3, i64 %v4, i64 %v5, i64 %v6, i64 %v7, i64 %v8, i64 %v9, i64 %v10, i64 %v11, i64 %v12, i64 %v13, i64 %v14, i64 %v15, i64 %v16)"
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
  (runtimeTextIn text (declareSection text) asan notrace)

fn runtimeTextIn text: String section: String asan: Bool notrace: Bool -> String
  (let [(rooted (rootedRuntime? section))
        (uses (arenaCalled? text)) (active (and uses notrace))]
    (liveChecked asan (lines (listAppend
           (list (str "@aslRc.free = internal global [" (classes) " x %Val] zeroinitializer, align 16")
                 (str "@aslRc.rooted = internal global [" (classes) " x i8] zeroinitializer")
                 "@aslRc.stack = internal global ptr null"
                 "@aslRc.sp = internal global i64 0"
                 "@aslRc.cap = internal global i64 0"
                 (statsText)
                 (objText notrace) (liveCheckText) (dupText asan) (dropText asan) (pushText)
                 (childrenText "pinKids" "pinVal") (drainText) (recycleText asan rooted notrace) (if active (arenaPinned (pinValText notrace)) (pinValText notrace)) (pinText)
                 (if active (arenaDeferred (deferText rooted)) (deferText rooted))
                 (dupValText) (childrenText "dupKids" "dupVal") (dupKidsText) (dupSameText) (freeOneText) (claimText) (freeChainText asan) (freeShallowText asan)
                 (cond (active (arenaRuntimeText asan)) (uses (lines (list (arenaRunText false) (arenaRunFlatText false)))) (else "")))
           (listAppend (if rooted (listAppend (smallGlobals text) (list (smallSyncText) (smallPushText))) (list))
             (listAppend (runtimeDecls section asan rooted)
               (if active (listAppend (declIfAbsent section "@malloc" "declare ptr @malloc(i64)") (declIfAbsent section "@llvm.memcpy.p0.p0.i64" "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)")) (list))))))))

; (:m :ref MM-REGIONS :do "pinning a cell of an open arena retains the arena; a stuck value is never deferred, so no arena cell waits in the pending drops past its release")
fn arenaPinned def: String -> String
  (stringReplace def "  br i1 %stuck, label %done, label %stick"
    "  br i1 %stuck, label %stuckSeen, label %stick\nstuckSeen:\n  %pinArena = call i1 @aslRc.arenaAny(%Val %v)\n  br i1 %pinArena, label %pinRetain, label %done\npinRetain:\n  call void @aslRc.arenaRetain()\n  br label %done")

fn arenaDeferred def: String -> String
  (stringReplace def "counted:\n  %n = load i64, ptr @aslRc.pendN"
    "counted:\n  %dh = load i64, ptr %o\n  %dc = lshr i64 %dh, 48\n  %dc8 = and i64 %dc, 255\n  %dstuck = icmp eq i64 %dc8, 255\n  br i1 %dstuck, label %done, label %queue\nqueue:\n  %n = load i64, ptr @aslRc.pendN")

fn liveChecked asan: Bool text: String -> String
  (if asan
    text
    (fold (fn [(t String) (line String)] -> String (stringReplace t line ""))
          text
          (list "  call void @aslRc.live(ptr %o, i64 %h)\n" (str "  store i32 " (sentinel) ", ptr %idp\n") (str "  store i32 " (sentinel) ", ptr %sidp\n"))))

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
                                              (match ins.op ((ty/opCall callee _) (if (stringStartsWith? callee "aslRcReset_") (cons callee a) a)) (_ a)))
                                            acc (functionInstrs f)))
                                    (list) bodies)))]
    (if (listEmpty? names)
      (list)
      (cons (ty/ssaExternTyped (dupSharedName) (list (ty/tyI64) (ty/tyVal)) (ty/tyI64))
            (map (fn [(n String)] -> ty/SsaExtern (ty/ssaExternTyped n (list (ty/tyVal)) (ty/tyI64))) names))))

fn takeExterns bodies: (List ty/SsaFunction) -> (List ty/SsaExtern)
  (map (fn [(n String)] -> ty/SsaExtern (ty/ssaExternTyped n (list (ty/tyVal) (ty/tyVal)) (ty/tyI64)))
       (distinctNames (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String)
                              (fold (fn [(a (List String)) (ins ty/SsaInstr)] -> (List String)
                                      (match ins.op ((ty/opCall callee _) (if (stringStartsWith? callee "aslRcTake_") (cons callee a) a)) (_ a)))
                                    acc (functionInstrs f)))
                            (list) bodies)))

fn takeDecl i: Int64 -> String
  (str "declare tailcc i64 @" (takeName i) "(%Val, %Val)")

fn takeIndices section: String -> (List Int64)
  (filter (fn [(i Int64)] -> Bool (stringContains? section (takeDecl i))) (range 0 31))

; (:m :ref RC-OWN-FOR-REUSE :do "a take of slot i: when the cell is unique and slot i of its ctor fields or cons pair still holds the part, the slot is cleared to an immediate, so the cell no longer counts the part and its later reset or free leaves it alone; a shared, stuck, arena or other cell duplicates the part as before")
fn takeText i: Int64 -> String
  (lines (list (str "define internal tailcc i64 @" (takeName i) "(%Val %x, %Val %v) alwaysinline {")
               "entry:"
               "  %o = call ptr @aslRc.obj(%Val %x)"
               "  %z = icmp eq ptr %o, null"
               "  br i1 %z, label %shared, label %live"
               "live:"
               "  %h = load i64, ptr %o"
               "  call void @aslRc.live(ptr %o, i64 %h)"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %last = icmp eq i64 %c8, 0"
               "  br i1 %last, label %kind, label %shared"
               "kind:"
               "  %ty = lshr i64 %h, 32"
               "  %ty8 = and i64 %ty, 255"
               "  %isCons = icmp eq i64 %ty8, 1"
               (str "  br i1 %isCons, label %" (if (< i 2) "cons" "shared") ", label %ctorTest")
               "ctorTest:"
               "  %isCtor = icmp eq i64 %ty8, 3"
               "  br i1 %isCtor, label %ctor, label %shared"
               "cons:"
               (str "  %cb = getelementptr inbounds i8, ptr %o, i64 " (+ 8 (* 16 i)))
               "  br label %check"
               "ctor:"
               "  %fnp = getelementptr inbounds i8, ptr %o, i64 12"
               "  %fn = load i32, ptr %fnp"
               (str "  %inRange = icmp sgt i32 %fn, " i)
               "  br i1 %inRange, label %ctorAt, label %shared"
               "ctorAt:"
               (str "  %fb = getelementptr inbounds i8, ptr %o, i64 " (+ 16 (* 16 i)))
               "  br label %check"
               "check:"
               "  %at = phi ptr [ %cb, %cons ], [ %fb, %ctorAt ]"
               "  %kw = getelementptr inbounds i8, ptr %at, i64 8"
               "  %kid = load i64, ptr %kw"
               "  %vw = extractvalue %Val %v, 1"
               "  %same = icmp eq i64 %kid, %vw"
               "  br i1 %same, label %take, label %shared"
               "take:"
               "  store %Val zeroinitializer, ptr %at"
               "  ret i64 0"
               "shared:"
               (str "  %d = call tailcc i64 @" (dupName) "(%Val %v)")
               "  ret i64 0"
               "}"))

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

; (:m :ref RC-FBIP :do "a reset of a unique value releases its kids except the moved ones and hands its cell over when its size class is the construct's, else recycles it and answers 1 (moved, no cell); a shared value is decremented and answers 0, so the moved fields are then duplicated; the shared test is inlined and only a unique value that is no cons calls out")
; (:m :ref FREECHAINLOOP :do "a unique cons resets inline: the mask is a constant, so only the unmoved slots of the pair get a release and a cons whose two slots both moved costs a class test; any other kind takes the generic resetSlow")
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
                   "  %fty = lshr i64 %h, 32"
                   "  %fty8 = and i64 %fty, 255"
                   "  %isCons = icmp eq i64 %fty8, 1"
                   "  br i1 %isCons, label %consFast, label %slowPath"
                   "slowPath:"
                   (str "  %u = call i64 " slow "(ptr %o, i64 %h)")
                   "  ret i64 %u"
                   "consFast:")
             (listAppend (consReleaseText mask 0)
             (listAppend (consReleaseText mask 1)
             (listAppend (cons "  br label %kidsDone" (resetDoneText asan cls))
             (listAppend
               (list (str "define internal i64 " slow "(ptr %o, i64 %h) {")
                     "entry:"
                     (str "  %mask = add i64 0, " mask)
                     "  br label %unique")
               (listAppend (resetKidsText) (resetDoneText asan cls)))))))))

fn consReleaseText mask: Int64 i: Int64 -> (List String)
  (if (!= (& mask (<< 1 i)) 0)
    (list)
    (let [(k (str "%k" i))]
      (list (str "  " k "p = getelementptr inbounds i8, ptr %o, i64 " (+ 8 (* 16 i)))
            (str "  " k "v = load %Val, ptr " k "p")
            (str "  " k " = call ptr @aslRc.obj(%Val " k "v)")
            (str "  " k "z = icmp eq ptr " k ", null")
            (str "  br i1 " k "z, label %after" i ", label %claim" i)
            (str "claim" i ":")
            (str "  " k "d = call i1 @aslRc.claim(ptr " k ")")
            (str "  br i1 " k "d, label %free" i ", label %after" i)
            (str "free" i ":")
            (str "  call void @aslRc.freeOne(ptr " k ")")
            (str "  br label %after" i)
            (str "after" i ":"))))

fn resetDoneText asan: Bool cls: Int64 -> (List String)
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
        "}")

; (:m :ref PERCEUS :do "reuse keys: -3 is the cons allocator, any other key a pooled size class, so a one-field record of class 3 takes its fresh cell from allocFast.3, not from the cons pool")
fn reuseOrName key: Int64 -> String
  (if (= key -3) "@aslRc.reuseOrCons" (str "@aslRc.reuseOr." key))

fn reuseKey line: String -> Int64
  (if (and (stringContains? line "= call ") (stringContains? line "ptr @gcAsl.allocFastCons(")) -3 (allocClassOf line))

fn reuseOrText key: Int64 -> String
  (let [(cls (if (= key -3) 3 key))]
  (lines (list (str "define internal ptr " (reuseOrName key) "(i64 %tok, i32 %t, i64 %n) alwaysinline {")
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
               (str "  %r = call ptr " (if (= key -3) "@gcAsl.allocFastCons" (allocFastSym cls)) "(i32 %t, i64 %n)")
               "  ret ptr %r"
               "}")))

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
  (match (stringIndexOf line "@aslRcReset_")
    ((none) "")
    ((some at) (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ at 1) (stringLength line)) "") "(")) "")))

; (:m :ref MM-REGIONS :do "the collector cons call is spliced from its parts: routing rewrites whole module text, so a literal of it would rewrite this compiler's own constant when it compiles itself and an RC-built compiler would then never route cons; a line test uses the parts '= call ' and 'ptr @gcAsl.allocFastCons(', which that rewrite never matches")
fn gcConsCall -> String
  (str "call ptr @" (stringReplace "gcAsl+allocFastCons(" "+" "."))

fn allocClassOf line: String -> Int64
  (cond
    ((and (stringContains? line "= call ") (stringContains? line "ptr @gcAsl.allocFastCons(")) 3)
    (else (match (stringIndexOf line "= call ptr @gcAsl.allocFast.")
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
      (str "  %" x ".objp = call ptr " (reuseOrName (reuseKey line)) "(i64 %" (tokenName x) ", " (optionOr (listHead (listReverse (stringSplit line "("))) ""))))

fn unclaimed line: String consumed: (Map String Bool) -> String
  (let [(t (tokenOf line))]
    (if (or (= t "") (mapHas? consumed t))
      line
      (str (optionOr (listHead (stringSplit line "@aslRcReset_")) "") "@aslRcReset_" (noCell) "_" (optionOr (listGet (stringSplit (resetOf line) "_") 2) "0") "(" (optionOr (listHead (listReverse (stringSplit line "("))) ""))))

; (:m :ref PERCEUS :do "the reset of a claimed token asks for the class of the one alloc line that takes it, so the SSA class is only a reuse marker and a record of any layout gets its true size class")
fn reclassed line: String single: (Map String Int64) -> String
  (let [(t (tokenOf line))]
    (match (mapGet single t)
      ((none) line)
      ((some c) (let [(parts (stringSplit (resetOf line) "_"))]
                  (str (optionOr (listHead (stringSplit line "@aslRcReset_")) "") "@aslRcReset_" c "_" (optionOr (listGet parts 2) "0") "(" (optionOr (listHead (listReverse (stringSplit line "("))) ""))))))

fn noCell -> Int64
  99

; (:m :ref RC-FBIP :do "within one function the construct a reset precedes takes its cell through reuseOr, named by the token the reset defines; a reset whose construct allocates no pooled cell asks for a class no cell has, so it never hands one over; only functions that hold a reset are split into lines")
; (:m :ref PERCEUS :do "a token is claimed only by exactly one alloc line, and its reset is reclassed to that line's class, so a raw or reordered record layout never takes a cell of another size; a literal with two alloc paths (dynamic raw or boxed) or none leaves its reset a noCell drop")
fn routeChunk ls: (List String) -> (Pair (List String) (List Int64))
  (let [(toks (setOf (filter (fn [(t String)] -> Bool (!= t "")) (map tokenOf ls))))]
    (if (= (mapSize toks) 0)
      (pair ls (list))
      (let [(lines0 (fold (fn [(acc (Map String (List Int64))) (l String)] -> (Map String (List Int64))
                            (let [(x (allocTarget l))] (if (mapHas? toks x) (mapSet acc x (cons (allocClassOf l) (optionOr (mapGet acc x) (list)))) acc)))
                          (mapEmpty) ls))
            (single (fold (fn [(acc (Map String Int64)) (x String)] -> (Map String Int64)
                            (match (mapGet lines0 x) ((some cs) (if (= (listLength cs) 1) (mapSet acc x (optionOr (listHead cs) -1)) acc)) ((none) acc)))
                          (mapEmpty) (mapKeys lines0)))
            (consumed (setOf (mapKeys single)))]
        (pair (map (fn [(l String)] -> String (unclaimed (reclassed (reroute l consumed) single) consumed)) ls)
              (map reuseKey (filter (fn [(l String)] -> Bool (mapHas? consumed (allocTarget l))) ls))))))

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

fn distinctInts xs: (List Int64) -> (List Int64)
  (fold (fn [(acc (List Int64)) (x Int64)] -> (List Int64) (if (listContains? acc x) acc (cons x acc))) (list) xs)

fn resetFrom asan: Bool name: String -> String
  (let [(parts (stringSplit name "_"))]
    (resetText asan (optionOr (stringToInt64 (optionOr (listGet parts 1) "")) 0) (optionOr (stringToInt64 (optionOr (listGet parts 2) "")) 0)))

fn arenaEntry -> String
  "prelude.arenaRun"

; (:m :ref MM-REGIONS :do "built from arenaEntry, never a literal: the rename runs over whole module text, so a literal of the call would also rewrite this compiler's own string constant when it compiles itself")
fn arenaCallText -> String
  (str "call tailcc %Val @" (stringReplace (arenaEntry) "." "$2E") "(")

fn arenaRunCall -> String
  "call tailcc %Val @aslRc.arenaRun("

; (:m :ref SOAREGION :do "the flat region entry regionInfer calls for a thunk it proved allocates only arena cells and immediates; built from its entry like arenaCallText")
fn arenaFlatEntry -> String
  "prelude.arenaRunFlat"

; (:m :ref SOAREGION :do "both region entries consume their thunk and hand back a promoted value, never a projection")
fn arenaEntry? callee: String -> Bool
  (or (= callee (arenaEntry)) (= callee (arenaFlatEntry)))

fn arenaFlatCallText -> String
  (str "call tailcc %Val @" (stringReplace (arenaFlatEntry) "." "$2E") "(")

fn arenaFlatRunCall -> String
  "call tailcc %Val @aslRc.arenaRunFlat("

; (:m :ref RC-ARENA-MUSTTAIL :do "a module uses the region runtime only when it calls it: a call instruction assigns its result, so a string constant holding the call text, as in this compiler's own string table, does not count")
fn arenaCalled? text: String -> Bool
  (or (or (stringContains? text (str "= " (arenaRunCall))) (stringContains? text (str "= musttail " (arenaRunCall))))
      (or (stringContains? text (str "= " (arenaFlatRunCall))) (stringContains? text (str "= musttail " (arenaFlatRunCall)))))

; (:m :ref RC-LIST-RELINK :do "under untraced RC a listAppend call goes to aslRc.appendOwned, which owns both lists as listAppend does: it walks the unique leading cells of the left list and, when they reach its end, links the right list to the last cell in place with no copy; from the first shared cell on (count above zero, stuck or arena cells included) it hands that suffix to the copying listAppend and links the copy in; the callee and call texts are spliced at run time so an RC-built compiler still finds the calls in its own text; the entry is not internal, since musttail callers need its tailcc kept and LLVM turns internal functions to fastcc")
fn appendCallee -> String
  (str "@" (stringReplace "prelude+listAppend" "+" "$2E"))

fn appendCallText -> String
  (str "call tailcc %Val " (appendCallee) "(")

fn appendOwnedCall -> String
  "call tailcc %Val @aslRc.appendOwned("

fn appendOwnedText asan: Bool -> String
  (lines (list "define tailcc %Val @aslRc.appendOwned(%Val %a, %Val %b) {"
               "entry:"
               "  %aw = extractvalue %Val %a, 1"
               "  %ap = inttoptr i64 %aw to ptr"
               "  %empty = icmp eq ptr %ap, null"
               "  br i1 %empty, label %none, label %walk"
               "none:"
               "  ret %Val %b"
               "walk:"
               "  %c = phi ptr [ %ap, %entry ], [ %np, %step ]"
               "  %cv = phi %Val [ %a, %entry ], [ %t, %step ]"
               "  %prev = phi ptr [ null, %entry ], [ %tp, %step ]"
               "  %h = load i64, ptr %c"
               (if asan "  call void @aslRc.live(ptr %c, i64 %h)" "")
               "  %cn = lshr i64 %h, 48"
               "  %c8 = and i64 %cn, 255"
               "  %uniq = icmp eq i64 %c8, 0"
               "  br i1 %uniq, label %own, label %copy"
               "own:"
               "  %tp = getelementptr inbounds i8, ptr %c, i64 24"
               "  %t = load %Val, ptr %tp"
               "  %tw = extractvalue %Val %t, 1"
               "  %np = inttoptr i64 %tw to ptr"
               "  %last = icmp eq ptr %np, null"
               "  br i1 %last, label %link, label %step"
               "step:"
               "  br label %walk"
               "link:"
               "  store %Val %b, ptr %tp"
               "  ret %Val %a"
               "copy:"
               (str "  %r = " (appendCallText) "%Val %cv, %Val %b)")
               "  %first = icmp eq ptr %prev, null"
               "  br i1 %first, label %whole, label %splice"
               "whole:"
               "  ret %Val %r"
               "splice:"
               "  store %Val %r, ptr %prev"
               "  ret %Val %a"
               "}"))

; (:m :ref RINGSOA :do "under untraced RC a listReverse call goes to aslRc.reverseOwned, which owns its list as listReverse does: each unique leading cell has its tail turned to point at the cells already reversed, with no alloc, free or count traffic; from the first shared cell on (count above zero, stuck or arena cells included) it hands that suffix and the reversed prefix to the copying preludeReverseOnto; the call texts are spliced at run time like appendCallText")
fn reverseCallText -> String
  (str "call tailcc %Val @" (stringReplace "prelude+listReverse" "+" "$2E") "(")

fn reverseOntoCallText -> String
  (str "call tailcc %Val @" (stringReplace "prelude+preludeReverseOnto" "+" "$2E") "(")

fn reverseOwnedCall -> String
  "call tailcc %Val @aslRc.reverseOwned("

fn reverseOwnedText asan: Bool -> String
  (lines (list "define tailcc %Val @aslRc.reverseOwned(%Val %xs) {"
               "entry:"
               "  %tw = extractvalue %Val %xs, 0"
               "  %t32 = trunc i64 %tw to i32"
               "  %isList = icmp eq i32 %t32, 6"
               "  br i1 %isList, label %walk, label %copy"
               "walk:"
               "  %cv = phi %Val [ %xs, %entry ], [ %nv, %own ]"
               "  %acc = phi %Val [ { i64 6, i64 0 }, %entry ], [ %cv, %own ]"
               "  %cw = extractvalue %Val %cv, 1"
               "  %c = inttoptr i64 %cw to ptr"
               "  %empty = icmp eq ptr %c, null"
               "  br i1 %empty, label %done, label %cell"
               "cell:"
               "  %h = load i64, ptr %c"
               (if asan "  call void @aslRc.live(ptr %c, i64 %h)" "")
               "  %cn = lshr i64 %h, 48"
               "  %c8 = and i64 %cn, 255"
               "  %uniq = icmp eq i64 %c8, 0"
               "  br i1 %uniq, label %own, label %copy"
               "own:"
               "  %np = getelementptr inbounds i8, ptr %c, i64 24"
               "  %nv = load %Val, ptr %np"
               "  store %Val %acc, ptr %np"
               "  br label %walk"
               "done:"
               "  ret %Val %acc"
               "copy:"
               "  %rest = phi %Val [ %xs, %entry ], [ %cv, %cell ]"
               "  %onto = phi %Val [ { i64 6, i64 0 }, %entry ], [ %acc, %cell ]"
               (str "  %r = " (reverseOntoCallText) "%Val %rest, %Val %onto)")
               "  ret %Val %r"
               "}"))

fn arenaChunk -> Int64
  262144

fn arenaDeepest -> Int64
  125

fn retiredBits -> Int64
  -144115188075855872

fn forwardMask -> Int64
  -71776119061217281

fn forwardBits -> Int64
  71494644084506624

fn statArenas -> Int64
  13

fn statArenaCells -> Int64
  14

fn statPromoted -> Int64
  15

fn statRetained -> Int64
  16

fn heapTagText v: String p: String -> (List String)
  (list (str "  %" p "w0 = extractvalue %Val " v ", 0")
        (str "  %" p "tag = and i64 %" p "w0, 4294967295")
        (str "  %" p "ow = extractvalue %Val " v ", 1")
        (str "  %" p "lo = icmp sge i64 %" p "tag, 5")
        (str "  %" p "hi = icmp sle i64 %" p "tag, 15")
        (str "  %" p "nb = icmp ne i64 %" p "tag, 10")
        (str "  %" p "nz = icmp ne i64 %" p "ow, 0")
        (str "  %" p "a = and i1 %" p "lo, %" p "hi")
        (str "  %" p "b = and i1 %" p "nb, %" p "nz")
        (str "  %" p "has = and i1 %" p "a, %" p "b"))

; (:m :ref MM-REGIONS :do "an arena cell carries count 255, so dup, drop, claim and reset leave it alone, and class byte 128 plus its arena's depth, so a promotion copies only the cells of the arena that closes; 254 marks the cells of a retained arena, alive for good")
fn arenaTestText -> String
  (lines (listAppend
           (list "define internal i1 @aslRc.arenaIn(%Val %v, i64 %cls) alwaysinline {" "entry:")
           (listAppend (heapTagText "%v" "")
             (list "  br i1 %has, label %obj, label %no"
                   "obj:"
                   "  %o = inttoptr i64 %ow to ptr"
                   "  %h = load i64, ptr %o"
                   "  %c = lshr i64 %h, 56"
                   "  %in = icmp eq i64 %c, %cls"
                   "  ret i1 %in"
                   "no:"
                   "  ret i1 false"
                   "}"
                   "define internal i1 @aslRc.arenaAny(%Val %v) alwaysinline {"
                   "entry:"
                   (lines (heapTagText "%v" ""))
                   "  br i1 %has, label %obj, label %no"
                   "obj:"
                   "  %o = inttoptr i64 %ow to ptr"
                   "  %h = load i64, ptr %o"
                   "  %c = lshr i64 %h, 56"
                   "  %lo1 = icmp uge i64 %c, 128"
                   "  %hi1 = icmp ult i64 %c, 254"
                   "  %in = and i1 %lo1, %hi1"
                   "  ret i1 %in"
                   "no:"
                   "  ret i1 false"
                   "}"))))

fn arenaAllocText -> String
  (lines (list "define internal ptr @aslRc.arenaAlloc(ptr %a, i32 %t, i64 %n) {"
               "entry:"
               "  %small = icmp ult i64 %n, 16"
               "  %n16 = select i1 %small, i64 16, i64 %n"
               "  %r15 = add i64 %n16, 15"
               "  %s = and i64 %r15, -16"
               "  %bump = load ptr, ptr %a"
               "  %limp = getelementptr inbounds i8, ptr %a, i64 8"
               "  %lim = load ptr, ptr %limp"
               "  %nb = getelementptr i8, ptr %bump, i64 %s"
               "  %bi = ptrtoint ptr %nb to i64"
               "  %li = ptrtoint ptr %lim to i64"
               "  %fits = icmp ule i64 %bi, %li"
               "  %live = icmp ne ptr %bump, null"
               "  %ok = and i1 %fits, %live"
               "  br i1 %ok, label %take, label %grow"
               "take:"
               "  store ptr %nb, ptr %a"
               "  br label %init"
               "grow:"
               "  %g = call ptr @aslRc.arenaGrow(ptr %a, i64 %s)"
               "  br label %init"
               "init:"
               "  %o = phi ptr [ %bump, %take ], [ %g, %grow ]"
               "  %dp = getelementptr inbounds i8, ptr %a, i64 32"
               "  %d = load i64, ptr %dp"
               "  %cb = add i64 %d, 128"
               "  %ch = shl i64 %cb, 56"
               "  %t64 = zext i32 %t to i64"
               "  %ty = shl i64 %t64, 32"
               "  %h1 = or i64 %n, %ty"
               (str "  %h2 = or i64 %h1, " (sticky))
               "  %h = or i64 %h2, %ch"
               "  store i64 %h, ptr %o"
               "  %body = getelementptr inbounds i8, ptr %o, i64 8"
               "  %blen = sub i64 %s, 8"
               "  call void @llvm.memset.p0.i64(ptr %body, i8 0, i64 %blen, i1 false)"
               "  ret ptr %o"
               "}"))

; (:m :ref MM-REGIONS :do "an arena is a chain of fixed chunks cut by a bump pointer, a cell too big for a quarter chunk getting a chunk of its own; under ASan a chunk is returned to malloc at release so a stale reference faults, otherwise a few are kept for the next arena")
fn arenaGrowText asan: Bool -> String
  (lines (list "define internal ptr @aslRc.arenaGrow(ptr %a, i64 %s) noinline {"
               "entry:"
               "  %cp = getelementptr inbounds i8, ptr %a, i64 16"
               "  %c = load ptr, ptr %cp"
               (str "  %big = icmp ugt i64 %s, " (/ (arenaChunk) 4))
               "  br i1 %big, label %large, label %chunk"
               "large:"
               "  %lb = add i64 %s, 16"
               "  %m = call ptr @malloc(i64 %lb)"
               "  %mz = icmp eq ptr %m, null"
               "  br i1 %mz, label %oom, label %lgot"
               "lgot:"
               "  %bp = getelementptr inbounds i8, ptr %a, i64 48"
               "  %bh = load ptr, ptr %bp"
               "  store ptr %bh, ptr %m"
               "  %mend = getelementptr inbounds i8, ptr %m, i64 %lb"
               "  %mep = getelementptr inbounds i8, ptr %m, i64 8"
               "  store ptr %mend, ptr %mep"
               "  store ptr %m, ptr %bp"
               "  %lo = getelementptr inbounds i8, ptr %m, i64 16"
               "  ret ptr %lo"
               "chunk:"
               "  %hasC = icmp ne ptr %c, null"
               "  br i1 %hasC, label %close, label %fresh"
               "close:"
               "  %bump = load ptr, ptr %a"
               "  %uep = getelementptr inbounds i8, ptr %c, i64 8"
               "  store ptr %bump, ptr %uep"
               "  br label %fresh"
               "fresh:"
               "  %sp = load ptr, ptr @aslRc.arenaSpare"
               (if asan "  %hasS = icmp eq i1 false, true" "  %hasS = icmp ne ptr %sp, null")
               "  br i1 %hasS, label %reuse, label %new"
               "reuse:"
               "  %nx = load ptr, ptr %sp"
               "  store ptr %nx, ptr @aslRc.arenaSpare"
               "  %sn = load i64, ptr @aslRc.arenaSpareN"
               "  %sn1 = sub i64 %sn, 1"
               "  store i64 %sn1, ptr @aslRc.arenaSpareN"
               "  br label %got"
               "new:"
               (str "  %nm = call ptr @malloc(i64 " (arenaChunk) ")")
               "  %nmz = icmp eq ptr %nm, null"
               "  br i1 %nmz, label %oom, label %got"
               "got:"
               "  %k = phi ptr [ %sp, %reuse ], [ %nm, %new ]"
               "  store ptr %c, ptr %k"
               "  store ptr %k, ptr %cp"
               "  %o = getelementptr inbounds i8, ptr %k, i64 16"
               "  %nb = getelementptr inbounds i8, ptr %o, i64 %s"
               "  store ptr %nb, ptr %a"
               (str "  %lim = getelementptr inbounds i8, ptr %k, i64 " (arenaChunk))
               "  %lp = getelementptr inbounds i8, ptr %a, i64 8"
               "  store ptr %lim, ptr %lp"
               "  ret ptr %o"
               "oom:"
               "  call void @llvm.trap()"
               "  unreachable"
               "}"))

fn arenaChunkFreeText asan: Bool -> String
  (lines (if asan
           (list "define internal void @aslRc.arenaFreeChunk(ptr %k) {"
                 "entry:"
                 "  call void @free(ptr %k)"
                 "  ret void"
                 "}")
           (list "define internal void @aslRc.arenaFreeChunk(ptr %k) {"
                 "entry:"
                 "  %sn = load i64, ptr @aslRc.arenaSpareN"
                 "  %room = icmp ult i64 %sn, 64"
                 "  br i1 %room, label %keep, label %free"
                 "keep:"
                 "  %sp = load ptr, ptr @aslRc.arenaSpare"
                 "  store ptr %sp, ptr %k"
                 "  store ptr %k, ptr @aslRc.arenaSpare"
                 "  %sn1 = add i64 %sn, 1"
                 "  store i64 %sn1, ptr @aslRc.arenaSpareN"
                 "  ret void"
                 "free:"
                 "  call void @free(ptr %k)"
                 "  ret void"
                 "}")))

; (:m :ref MM-REGIONS :do "release walks the arena's cells once: a cell a promotion moved (count 254) is skipped, any other drops its kids outside every arena; chunks are freed only after the whole walk, since a list builder links an older cell to a newer one and the walk reads each kid's header; retirement instead stamps each cell 254, so a later arena at the same depth never takes it for its own")
fn arenaWalkText -> String
  (lines (list "define internal void @aslRc.arenaCell(ptr %p, i64 %h, i64 %retire) {"
               "entry:"
               (statBump "cells" (statArenaCells))
               "  %r = icmp ne i64 %retire, 0"
               "  br i1 %r, label %stamp, label %kids"
               "stamp:"
               (str "  %hk = and i64 %h, 72057594037927935")
               (str "  %hr = or i64 %hk, " (retiredBits))
               "  store i64 %hr, ptr %p"
               "  ret void"
               "kids:"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %moved = icmp eq i64 %c8, 254"
               "  br i1 %moved, label %done, label %drop"
               "drop:"
               "  call void @aslRc.arenaKids(ptr %p, i64 %h)"
               "  br label %done"
               "done:"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaDropKid(%Val %v) {"
               "entry:"
               "  %in = call i1 @aslRc.arenaAny(%Val %v)"
               "  br i1 %in, label %done, label %drop"
               "drop:"
               (str "  %d = call tailcc i64 @" (dropName) "(%Val %v)")
               "  br label %done"
               "done:"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaWalk(ptr %a, i64 %retire) noinline {"
               "entry:"
               "  %cp = getelementptr inbounds i8, ptr %a, i64 16"
               "  %c0 = load ptr, ptr %cp"
               "  %e0 = load ptr, ptr %a"
               "  br label %chunk"
               "chunk:"
               "  %c = phi ptr [ %c0, %entry ], [ %next, %nextEnd ], [ %next, %last ]"
               "  %e = phi ptr [ %e0, %entry ], [ %ne, %nextEnd ], [ null, %last ]"
               "  %more = icmp ne ptr %c, null"
               "  br i1 %more, label %walk, label %bigs"
               "walk:"
               "  %first = getelementptr inbounds i8, ptr %c, i64 16"
               "  br label %cell"
               "cell:"
               "  %p = phi ptr [ %first, %walk ], [ %pn, %visit ]"
               "  %pi = ptrtoint ptr %p to i64"
               "  %ei = ptrtoint ptr %e to i64"
               "  %in = icmp ult i64 %pi, %ei"
               "  br i1 %in, label %visit, label %chunkEnd"
               "visit:"
               "  %h = load i64, ptr %p"
               "  call void @aslRc.arenaCell(ptr %p, i64 %h, i64 %retire)"
               "  %n = and i64 %h, 4294967295"
               "  %small = icmp ult i64 %n, 16"
               "  %n16 = select i1 %small, i64 16, i64 %n"
               "  %r15 = add i64 %n16, 15"
               "  %s = and i64 %r15, -16"
               "  %pn = getelementptr inbounds i8, ptr %p, i64 %s"
               "  br label %cell"
               "chunkEnd:"
               "  %next = load ptr, ptr %c"
               "  %hasNext = icmp ne ptr %next, null"
               "  br i1 %hasNext, label %nextEnd, label %last"
               "nextEnd:"
               "  %nep = getelementptr inbounds i8, ptr %next, i64 8"
               "  %ne = load ptr, ptr %nep"
               "  br label %chunk"
               "last:"
               "  br label %chunk"
               "bigs:"
               "  %bp = getelementptr inbounds i8, ptr %a, i64 48"
               "  %b0 = load ptr, ptr %bp"
               "  br label %big"
               "big:"
               "  %b = phi ptr [ %b0, %bigs ], [ %bn, %bigCell ]"
               "  %bmore = icmp ne ptr %b, null"
               "  br i1 %bmore, label %bigCell, label %walked"
               "bigCell:"
               "  %bc = getelementptr inbounds i8, ptr %b, i64 16"
               "  %bh = load i64, ptr %bc"
               "  call void @aslRc.arenaCell(ptr %bc, i64 %bh, i64 %retire)"
               "  %bn = load ptr, ptr %b"
               "  br label %big"
               "walked:"
               "  %keep = icmp ne i64 %retire, 0"
               "  br i1 %keep, label %done, label %free"
               "free:"
               "  %f = phi ptr [ %c0, %walked ], [ %fn, %freeOne ]"
               "  %fmore = icmp ne ptr %f, null"
               "  br i1 %fmore, label %freeOne, label %bigFree"
               "freeOne:"
               "  %fn = load ptr, ptr %f"
               "  call void @aslRc.arenaFreeChunk(ptr %f)"
               "  br label %free"
               "bigFree:"
               "  %g = phi ptr [ %b0, %free ], [ %gn, %bigOne ]"
               "  %gmore = icmp ne ptr %g, null"
               "  br i1 %gmore, label %bigOne, label %done"
               "bigOne:"
               "  %gn = load ptr, ptr %g"
               "  call void @free(ptr %g)"
               "  br label %bigFree"
               "done:"
               "  ret void"
               "}"))

; (:m :ref SOAREGION :do "a flat release frees the chunks and the large cells as the walk does after it, without visiting a cell")
fn arenaReleaseText -> String
  (lines (list "define internal void @aslRc.arenaRelease(ptr %a) noinline {"
               "entry:"
               "  %cp = getelementptr inbounds i8, ptr %a, i64 16"
               "  %c0 = load ptr, ptr %cp"
               "  %bp = getelementptr inbounds i8, ptr %a, i64 48"
               "  %b0 = load ptr, ptr %bp"
               "  br label %free"
               "free:"
               "  %f = phi ptr [ %c0, %entry ], [ %fn, %freeOne ]"
               "  %fmore = icmp ne ptr %f, null"
               "  br i1 %fmore, label %freeOne, label %bigFree"
               "freeOne:"
               "  %fn = load ptr, ptr %f"
               "  call void @aslRc.arenaFreeChunk(ptr %f)"
               "  br label %free"
               "bigFree:"
               "  %g = phi ptr [ %b0, %free ], [ %gn, %bigOne ]"
               "  %gmore = icmp ne ptr %g, null"
               "  br i1 %gmore, label %bigOne, label %done"
               "bigOne:"
               "  %gn = load ptr, ptr %g"
               "  call void @free(ptr %g)"
               "  br label %bigFree"
               "done:"
               "  ret void"
               "}"))

; (:m :ref MM-REGIONS :do "promotion copies the closing arena's cells reachable from the result into the enclosing region through the ordinary allocator, depth-first over an explicit stack of slots; each copy takes over the cell's references, and the cell keeps a forward to it so shared structure is copied once")
fn arenaPromoteText -> String
  (lines (list "define internal %Val @aslRc.arenaPromote(%Val %r, i64 %cls) noinline {"
               "entry:"
               "  %root = alloca %Val"
               "  store %Val %r, ptr %root"
               "  %in = call i1 @aslRc.arenaIn(%Val %r, i64 %cls)"
               "  br i1 %in, label %start, label %plain"
               "plain:"
               "  ret %Val %r"
               "start:"
               "  %sp0 = load i64, ptr @aslRc.sp"
               "  call void @aslRc.push(ptr %root)"
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
               "  %slot = load ptr, ptr %at"
               "  call void @aslRc.arenaMove(ptr %slot, i64 %cls)"
               "  br label %loop"
               "done:"
               "  %out = load %Val, ptr %root"
               "  ret %Val %out"
               "}"
               "define internal void @aslRc.arenaMove(ptr %slot, i64 %cls) {"
               "entry:"
               "  %v = load %Val, ptr %slot"
               "  %ow = extractvalue %Val %v, 1"
               "  %o = inttoptr i64 %ow to ptr"
               "  %h = load i64, ptr %o"
               "  %c = lshr i64 %h, 48"
               "  %c8 = and i64 %c, 255"
               "  %fwd = icmp eq i64 %c8, 254"
               "  %fp = getelementptr inbounds i8, ptr %o, i64 8"
               "  br i1 %fwd, label %forwarded, label %copy"
               "forwarded:"
               "  %y0 = load i64, ptr %fp"
               "  %fv = insertvalue %Val %v, i64 %y0, 1"
               "  store %Val %fv, ptr %slot"
               (str "  %fd = call tailcc i64 @" (dupName) "(%Val %fv)")
               "  ret void"
               "copy:"
               "  %n = and i64 %h, 4294967295"
               "  %ty = lshr i64 %h, 32"
               "  %t16 = and i64 %ty, 65535"
               "  %t = trunc i64 %t16 to i32"
               "  %y = call ptr @aslRc.alloc(i32 %t, i64 %n)"
               "  %yb = getelementptr inbounds i8, ptr %y, i64 8"
               "  %len = sub i64 %n, 8"
               "  call void @llvm.memcpy.p0.p0.i64(ptr %yb, ptr %fp, i64 %len, i1 false)"
               (str "  %hm = and i64 %h, " (forwardMask))
               (str "  %hf = or i64 %hm, " (forwardBits))
               "  store i64 %hf, ptr %o"
               "  %yi = ptrtoint ptr %y to i64"
               "  store i64 %yi, ptr %fp"
               "  %nv = insertvalue %Val %v, i64 %yi, 1"
               "  store %Val %nv, ptr %slot"
               (statBump "promoted" (statPromoted))
               "  %yh = load i64, ptr %y"
               "  call void @aslRc.arenaPushKids(ptr %y, i64 %yh, i64 %cls)"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaPushKids(ptr %o, i64 %h, i64 %cls) {"
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
               "  %i = phi i64 [ 0, %kids ], [ %i1, %next ]"
               "  %more = icmp slt i64 %i, %n"
               "  br i1 %more, label %body, label %done"
               "body:"
               "  %off = mul i64 %i, 16"
               "  %at = getelementptr inbounds i8, ptr %base, i64 %off"
               "  %kid = load %Val, ptr %at"
               "  %inner = call i1 @aslRc.arenaIn(%Val %kid, i64 %cls)"
               "  br i1 %inner, label %push, label %next"
               "push:"
               "  call void @aslRc.push(ptr %at)"
               "  br label %next"
               "next:"
               "  %i1 = add i64 %i, 1"
               "  br label %loop"
               "done:"
               "  ret void"
               "}"))

; (:m :ref MM-REGIONS :do "a value of an open arena that escapes (pinned for opaque code, stored in a global) retains every open arena, which then is never freed and is retired at close; lazy global initialisers and parallel kernels run with the arena paused, so what they allocate is ordinary heap")
fn arenaEscapeText -> String
  (lines (list "define internal void @aslRc.arenaRetain() noinline {"
               "entry:"
               "  %a0 = load ptr, ptr @aslRc.arenaTop"
               "  br label %loop"
               "loop:"
               "  %a = phi ptr [ %a0, %entry ], [ %up, %mark ]"
               "  %more = icmp ne ptr %a, null"
               "  br i1 %more, label %mark, label %done"
               "mark:"
               "  %rp = getelementptr inbounds i8, ptr %a, i64 24"
               "  store i64 1, ptr %rp"
               "  %pp = getelementptr inbounds i8, ptr %a, i64 40"
               "  %up = load ptr, ptr %pp"
               "  br label %loop"
               "done:"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaEscape(%Val %v) {"
               "entry:"
               "  %top = load ptr, ptr @aslRc.arenaTop"
               "  %open = icmp ne ptr %top, null"
               "  br i1 %open, label %check, label %done"
               "check:"
               "  %in = call i1 @aslRc.arenaAny(%Val %v)"
               "  br i1 %in, label %retain, label %done"
               "retain:"
               "  call void @aslRc.arenaRetain()"
               "  br label %done"
               "done:"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaPause() {"
               "entry:"
               "  %n = load i64, ptr @aslRc.pausedN"
               "  %full = icmp uge i64 %n, 64"
               "  br i1 %full, label %oom, label %save"
               "oom:"
               "  call void @llvm.trap()"
               "  unreachable"
               "save:"
               "  %cur = load ptr, ptr @aslRc.arenaCur"
               "  %at = getelementptr [64 x ptr], ptr @aslRc.paused, i64 0, i64 %n"
               "  store ptr %cur, ptr %at"
               "  %n1 = add i64 %n, 1"
               "  store i64 %n1, ptr @aslRc.pausedN"
               "  store ptr null, ptr @aslRc.arenaCur"
               "  ret void"
               "}"
               "define internal void @aslRc.arenaResume() {"
               "entry:"
               "  %n = load i64, ptr @aslRc.pausedN"
               "  %n1 = sub i64 %n, 1"
               "  store i64 %n1, ptr @aslRc.pausedN"
               "  %at = getelementptr [64 x ptr], ptr @aslRc.paused, i64 0, i64 %n1"
               "  %cur = load ptr, ptr %at"
               "  store ptr %cur, ptr @aslRc.arenaCur"
               "  ret void"
               "}"
               "define internal %Val @aslRc.initPaused(ptr %init) noinline {"
               "entry:"
               "  call void @aslRc.arenaPause()"
               "  %v = call tailcc %Val %init()"
               "  call void @aslRc.arenaResume()"
               "  ret %Val %v"
               "}"))

; (:m :ref MM-REGIONS :do "arenaRun opens an arena one deeper than the innermost open one, runs the thunk with every allocation of this thread cut from it, then promotes the result into the enclosing region and releases the arena, or retires it when a value escaped; past the deepest depth it is a plain call")
fn arenaRunText active: Bool -> String
  (arenaRunTextFor active "arenaRun" "  call void @aslRc.arenaWalk(ptr %a, i64 0)")

; (:m :ref SOAREGION :do "arenaRunFlat is arenaRun whose release frees the chunks without walking the cells: regionInfer calls it only for a thunk whose cells hold nothing but immediates and cells of the same arena, so no cell has a kid outside to drop")
fn arenaRunFlatText active: Bool -> String
  (arenaRunTextFor active "arenaRunFlat" "  call void @aslRc.arenaRelease(ptr %a)")

fn arenaRunTextFor active: Bool name: String release: String -> String
  (lines (if active
           (list (str "define internal tailcc %Val @aslRc." name "(%Val %f) {")
                 "entry:"
                 "  %d = load i64, ptr @aslRc.arenaDepth"
                 (str "  %deep = icmp uge i64 %d, " (arenaDeepest))
                 "  br i1 %deep, label %plain, label %open"
                 "plain:"
                 "  %pr = call %Val @objrt.call(%Val %f, i64 0, ptr null)"
                 (str "  %pd = call tailcc i64 @" (dropName) "(%Val %f)")
                 "  ret %Val %pr"
                 "open:"
                 "  %a = call ptr @malloc(i64 64)"
                 "  %az = icmp eq ptr %a, null"
                 "  br i1 %az, label %oom, label %init"
                 "oom:"
                 "  call void @llvm.trap()"
                 "  unreachable"
                 "init:"
                 "  call void @llvm.memset.p0.i64(ptr %a, i8 0, i64 64, i1 false)"
                 "  %d1 = add i64 %d, 1"
                 "  %dp = getelementptr inbounds i8, ptr %a, i64 32"
                 "  store i64 %d1, ptr %dp"
                 "  %top = load ptr, ptr @aslRc.arenaTop"
                 "  %pp = getelementptr inbounds i8, ptr %a, i64 40"
                 "  store ptr %top, ptr %pp"
                 "  %cur = load ptr, ptr @aslRc.arenaCur"
                 "  store ptr %a, ptr @aslRc.arenaCur"
                 "  store ptr %a, ptr @aslRc.arenaTop"
                 "  store i64 %d1, ptr @aslRc.arenaDepth"
                 (statBump "arenas" (statArenas))
                 "  %r = call %Val @objrt.call(%Val %f, i64 0, ptr null)"
                 "  store ptr %cur, ptr @aslRc.arenaCur"
                 "  store ptr %top, ptr @aslRc.arenaTop"
                 "  store i64 %d, ptr @aslRc.arenaDepth"
                 "  %rp = getelementptr inbounds i8, ptr %a, i64 24"
                 "  %kept = load i64, ptr %rp"
                 "  %retained = icmp ne i64 %kept, 0"
                 "  br i1 %retained, label %retire, label %release"
                 "retire:"
                 (statBump "retained" (statRetained))
                 "  call void @aslRc.arenaWalk(ptr %a, i64 1)"
                 (str "  %rd = call tailcc i64 @" (dropName) "(%Val %f)")
                 "  ret %Val %r"
                 "release:"
                 "  %cls = add i64 %d1, 128"
                 "  %out = call %Val @aslRc.arenaPromote(%Val %r, i64 %cls)"
                 release
                 "  call void @free(ptr %a)"
                 (str "  %od = call tailcc i64 @" (dropName) "(%Val %f)")
                 "  ret %Val %out"
                 "}")
           (list (str "define internal tailcc %Val @aslRc." name "(%Val %f) {")
                 "entry:"
                 "  %r = call %Val @objrt.call(%Val %f, i64 0, ptr null)"
                 (str "  %d = call tailcc i64 @" (dropName) "(%Val %f)")
                 "  ret %Val %r"
                 "}")))

fn arenaGlobals -> (List String)
  (list "@aslRc.arenaCur = internal global ptr null"
        "@aslRc.arenaTop = internal global ptr null"
        "@aslRc.arenaDepth = internal global i64 0"
        "@aslRc.arenaSpare = internal global ptr null"
        "@aslRc.arenaSpareN = internal global i64 0"
        "@aslRc.paused = internal global [64 x ptr] zeroinitializer"
        "@aslRc.pausedN = internal global i64 0")

fn arenaRuntimeText asan: Bool -> String
  (lines (listAppend (arenaGlobals)
                     (list (arenaTestText) (arenaAllocText) (arenaGrowText asan) (arenaChunkFreeText asan) (childrenText "arenaKids" "arenaDropKid")
                           (arenaWalkText) (arenaPromoteText) (arenaEscapeText) (arenaRunText true) (arenaReleaseText) (arenaRunFlatText true))))

; (:m :ref MM-REGIONS :do "inside an open arena each allocation entry cuts its cell from the arena, except arrays and handles, which stay ordinary heap")
fn arenaGuarded def: String -> String
  (stringReplace def "(i32 %t, i64 %n) {\nentry:\n"
    (str "(i32 %t, i64 %n) {\nentry:\n"
         "  %arenaA = load ptr, ptr @aslRc.arenaCur\n"
         "  %arenaOn = icmp ne ptr %arenaA, null\n"
         "  br i1 %arenaOn, label %arenaKind, label %arenaPool\n"
         "arenaKind:\n"
         "  %arenaK = add i32 %t, -6\n"
         "  %arenaOut = icmp ult i32 %arenaK, 2\n"
         "  br i1 %arenaOut, label %arenaPool, label %arenaTake\n"
         "arenaTake:\n"
         "  %arenaO = tail call ptr @aslRc.arenaAlloc(ptr %arenaA, i32 %t, i64 %n)\n"
         "  ret ptr %arenaO\n"
         "arenaPool:\n"))

fn arenaReset def: String -> String
  (stringReplace def "  br i1 %fits, label %give, label %spare"
    "  %arenaA = load ptr, ptr @aslRc.arenaCur\n  %arenaOff = icmp eq ptr %arenaA, null\n  %fitsHere = and i1 %fits, %arenaOff\n  br i1 %fitsHere, label %give, label %spare")

fn parallelCallText -> String
  "@asl$2Dtarget$2Dllvm$2Fparallel$2E"

; (:m :ref MM-REGIONS :do "a store into a global outside a lazy initialiser checks its value for an open arena; a call into a parallel kernel runs paused, losing its tail position")
fn arenaLine l: String -> String
  (cond
    ((and (stringStartsWith? l "  store %Val %") (and (stringContains? l ", ptr @global.") (not (or (stringStartsWith? l "  store %Val %v, ptr @global.") (stringStartsWith? l "  store %Val %g.")))))
      (str "  call void @aslRc.arenaEscape(%Val " (optionOr (listHead (stringSplit (optionOr (stringSlice l 13 (stringLength l)) "") ",")) "") ")\n" l))
    ((and (stringContains? l (parallelCallText)) (and (stringStartsWith? l "  ") (stringContains? l " call ")))
      (str "  call void @aslRc.arenaPause()\n" (stringReplace l "musttail call " "call ") "\n  call void @aslRc.arenaResume()"))
    (else l))

; (:m :ref MM-REGIONS :do "lazy global caches (singleton getters, objrt.str constant cells) build outside any open arena, so a cached cell never points into a region that is later freed; a getter calls its initialiser through one shared paused entry, so it stays as small as before and still inlines")
fn arenaGetters text: String -> String
  (let [(pieces (stringSplit text "bb.init:\n  %v = call tailcc %Val "))
        (getters (stringJoin (cons (optionOr (listHead pieces) "") (map arenaInitPaused (listDrop pieces 1))) ""))
        (paused (stringReplace getters "build:\n  %size = add i64 %len, 17\n" "build:\n  call void @aslRc.arenaPause()\n  %size = add i64 %len, 17\n"))]
    (stringReplace paused "  call void @asl_rt_global_root(ptr %cell)\n  ret %Val %str\n" "  call void @asl_rt_global_root(ptr %cell)\n  call void @aslRc.arenaResume()\n  ret %Val %str\n"))

fn arenaInitPaused piece: String -> String
  (let [(at (optionOr (stringIndexOf piece "()\n") -1))
        (callee (if (< at 0) "" (optionOr (stringSlice piece 0 at) "")))]
    (if (or (< at 0) (or (not (stringStartsWith? callee "@")) (or (stringContains? callee " ") (stringContains? callee "\n"))))
      (str "bb.init:\n  call void @aslRc.arenaPause()\n  %v = call tailcc %Val " (stringReplace piece "\n  store %Val %v, ptr @global." "\n  call void @aslRc.arenaResume()\n  store %Val %v, ptr @global."))
      (str "bb.init:\n  %v = call %Val @aslRc.initPaused(ptr " (optionOr (stringSlice piece 0 at) "") ")\n" (optionOr (stringSlice piece (+ at 3) (stringLength piece)) ""))))

; (:m :ref RC-FBIP-CLOSURE :do "an owned closure call reads the fourth code pointer of a prototype ssa emits for a target with an owned entry, flagged by 1 in the i32 after the arity; prototypes without it (no owned entry, or modules built without RC such as the runtime archive) carry 0 there and take the slow path, objrt.call through the borrowing entry and then a drop of each argument")
fn ownCodeOffset -> Int64
  72

fn ownMarkOffset -> Int64
  20

fn callOwnedText n: Int64 -> String
  (lines (listAppend
           (list (str "define internal tailcc %Val @" (callOwnedName n) "(%Val %f" (stringJoin (map (fn [(i Int64)] -> String (str ", %Val %a" i)) (range 0 n)) "") ") {")
                 "entry:"
                 (str "  %argv = alloca [" n " x %Val]"))
           (listAppend
             (map (fn [(i Int64)] -> String (str "  %slot" i " = getelementptr [" n " x %Val], ptr %argv, i64 0, i64 " i "\n  store %Val %a" i ", ptr %slot" i)) (range 0 n))
             (list "  %tagw = extractvalue %Val %f, 0"
                   "  %tag = trunc i64 %tagw to i32"
                   "  %isFn = icmp eq i32 %tag, 9"
                   "  br i1 %isFn, label %closure, label %slow"
                   "closure:"
                   "  %objw = extractvalue %Val %f, 1"
                   "  %obj = inttoptr i64 %objw to ptr"
                   "  %protop = getelementptr inbounds i8, ptr %obj, i64 8"
                   "  %proto = load ptr, ptr %protop"
                   "  %np = getelementptr inbounds i8, ptr %proto, i64 16"
                   "  %n = load i32, ptr %np"
                   (str "  %fits = icmp eq i32 %n, " n)
                   "  br i1 %fits, label %arity, label %slow"
                   "arity:"
                   (str "  %markp = getelementptr inbounds i8, ptr %proto, i64 " (ownMarkOffset))
                   "  %mark = load i32, ptr %markp"
                   "  %isMarked = icmp eq i32 %mark, 1"
                   "  br i1 %isMarked, label %fast, label %slow"
                   "fast:"
                   (str "  %ownp = getelementptr inbounds i8, ptr %proto, i64 " (ownCodeOffset))
                   "  %own = load ptr, ptr %ownp"
                   (str "  %r = call %Val %own(%Val %f, i64 " n ", ptr %argv)")
                   "  ret %Val %r"
                   "slow:"
                   (str "  %s = call tailcc %Val @" (slowName n) "(%Val %f" (stringJoin (map (fn [(i Int64)] -> String (str ", %Val %a" i)) (range 0 n)) "") ")")
                   "  ret %Val %s"
                   "}"))))

fn ownedDecl n: Int64 -> String
  (str "declare tailcc %Val @" (callOwnedName n) "(" (stringJoin (map (fn [(i Int64)] -> String "%Val") (range 0 (+ n 1))) ", ") ")")

fn ownedArityIn text: String -> (List Int64)
  (filter (fn [(n Int64)] -> Bool (stringContains? text (str "call tailcc %Val @" (callOwnedName n) "("))) (range 1 (+ (ownedArity) 1)))

; (:m :ref RC-FBIP-COST :do "the module text ends in its declare block, found from a bounded tail window instead of a scan of the whole text: the block starts at the first declare of the window when the line before it closes a function (or is the blank line after one) and no define follows; otherwise the whole text is scanned, and with a define after the declares there is no block and the declares are removed in place")
fn declareWindow -> Int64
  65536

fn declareBlock? text: String cut: Int64 -> Bool
  (and (> cut 0)
       (and (or (= (optionOr (stringSlice text (- cut 1) cut) "") "}") (= (optionOr (stringSlice text (max 0 (- cut 2)) cut) "") "}\n"))
            (not (stringContains? (optionOr (stringSlice text cut (stringLength text)) "") "\ndefine "))))

fn declareCut text: String -> Int64
  (let [(n (stringLength text))
        (from (max 0 (- n (declareWindow))))
        (near (match (stringIndexOf (optionOr (stringSlice text from n) "") "\ndeclare ") ((some at) (+ from at)) ((none) -1)))]
    (if (declareBlock? text near)
      near
      (match (stringIndexOf text "\ndeclare ")
        ((some at) (if (declareBlock? text at) at n))
        ((none) n))))

fn removedDecls arities: (List Int64) -> (Map String Bool)
  (setOf (cons (str "declare tailcc i64 @" (dupSameName) "(%Val, %Val)")
               (listAppend (map (fn [(n String)] -> String (str "declare tailcc i64 @" n "(%Val)")) (rcNames))
                           (map ownedDecl arities))))

fn keptDecls section: String removed: (Map String Bool) -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (or (mapHas? removed l) (resetDecl? l)))) (stringSplit section "\n")) "\n")

fn undeclaredInPlace text: String removed: (Map String Bool) -> String
  (fold (fn [(t String) (d String)] -> String (stringReplace t (str d "\n") "")) text (mapKeys removed))

; (:m :ref RC-FBIP-COST :do "every pooled allocation call is routed in one split of the text on the common call prefix instead of one replace per size class: classes 2 up and cons cells always, classes 0 and 1 only with the rooted runtime; the definitions come out in the order the per-class passes produced them")
fn allocCallPrefix -> String
  "call ptr @gcAsl.allocFast"

fn routedCallPrefix -> String
  "call ptr @aslRc.allocFast"

fn allocKey piece: String -> Int64
  (cond
    ((stringStartsWith? piece "Cons(") -2)
    ((stringStartsWith? piece ".")
      (let [(head (optionOr (stringSlice piece 1 (min (stringLength piece) 5)) ""))
            (paren (optionOr (stringIndexOf head "(") -1))]
        (if (< paren 1) -1 (optionOr (stringToInt64 (optionOr (stringSlice head 0 paren) "")) -1))))
    (else -1))

fn routedKey? rooted: Bool k: Int64 -> Bool
  (or (= k -2) (and (< k (classes)) (or (>= k (smallClasses)) (and rooted (>= k 0)))))

; (:m :ref RCCOST2 :do "the module text is split into its function chunks once: the reset routing, the pooled allocation routing, the filter dup and the sized allocation lines each rewrite a chunk in place and the chunks are joined once, instead of one split and join of the whole text per pass; a chunk without a pass's trigger text is passed through untouched. The text after the last chunk boundary and the reuse definitions appended to it form chunks of their own, so every pass sees the same lines as before")
schema Finished
  text: String
  classes: (List Int64)
  cons: Bool
  sized: Bool

schema Piece
  text: String
  mask: Int64
  cons: Bool
  sized: Bool

fn allocBit k: Int64 -> Int64
  (if (and (>= k 0) (< k (classes))) (<< 1 k) 0)

fn routePieces c: String rooted: Bool -> Piece
  (let [(pieces (stringSplit c (allocCallPrefix)))
        (rest (optionOr (listTail pieces) (list)))]
    (if (listEmpty? rest)
      (Piece :text c :mask 0 :cons false :sized false)
      (let [(keyed (map (fn [(p String)] -> (Pair Int64 String) (pair (allocKey p) p)) rest))]
        (Piece :text (stringJoin (cons (optionOr (listHead pieces) "") (map (fn [(q (Pair Int64 String))] -> String (str (if (routedKey? rooted (pairFirst q)) (routedCallPrefix) (allocCallPrefix)) (pairSecond q))) keyed)) "")
               :mask (fold (fn [(acc Int64) (q (Pair Int64 String))] -> Int64 (| acc (allocBit (pairFirst q)))) 0 keyed)
               :cons (listAny? (fn [(q (Pair Int64 String))] -> Bool (= (pairFirst q) -2)) keyed)
               :sized false))))

fn dupPiece c: String last: Bool -> String
  (cond
    ((not (stringContains? c "  store %Val %x, ptr %ccar")) c)
    (last (filterDup c))
    (else (let [(r (filterDup (str c "\n")))] (optionOr (stringSlice r 0 (- (stringLength r) 1)) r))))

fn finishPiece c: String rooted: Bool active: Bool last: Bool -> Piece
  (let [(routed (routePieces c rooted))
        (t routed.text)
        (hasSized (stringContains? t (sizedCall)))
        (d (dupPiece t last))
        (touched (or hasSized (and active (or (stringContains? d ", ptr @global.") (stringContains? d (parallelCallText))))))]
    (Piece :text (if touched (routeSized active d) d) :mask routed.mask :cons routed.cons :sized hasSized))

fn finishChunks hashed: String stats: Bool rooted: Bool active: Bool -> Finished
  (let [(parts (stringSplit hashed "\ndefine "))
        (n (listLength parts))
        (hasReset (stringContains? hashed "= call tailcc i64 @aslRcReset_"))
        (done (if hasReset
                (listAppend (map (fn [(p String)] -> Routed (routeFunction false p)) (listTake parts (- n 1)))
                            (map (fn [(p String)] -> Routed (routeFunction true p)) (listDrop parts (- n 1))))
                (list)))
        (texts (if hasReset (map (fn [(r Routed)] -> String r.text) done) parts))
        (defs (if hasReset
                (cons (dupSharedText)
                      (listAppend (map reuseOrText (distinctInts (fold (fn [(acc (List Int64)) (r Routed)] -> (List Int64) (listAppend r.classes acc)) (list) done)))
                                  (map (fn [(r String)] -> String (resetFrom stats r)) (distinctNames (fold (fn [(acc (List String)) (r Routed)] -> (List String) (listAppend r.resets acc)) (list) done)))))
                (list)))
        (extra (if hasReset (stringSplit (str "\n" (lines (map (fn [(d String)] -> String (if active (arenaReset d) d)) defs)) "\n") "\ndefine ") (list)))
        (chunks (if hasReset
                  (listAppend (listTake texts (- n 1)) (cons (str (optionOr (listHead (listDrop texts (- n 1))) "") (optionOr (listHead extra) "")) (optionOr (listTail extra) (list))))
                  texts))
        (m (listLength chunks))
        (pieces (listAppend (map (fn [(c String)] -> Piece (finishPiece c rooted active false)) (listTake chunks (- m 1)))
                            (map (fn [(c String)] -> Piece (finishPiece c rooted active true)) (listDrop chunks (- m 1)))))
        (mask (fold (fn [(acc Int64) (p Piece)] -> Int64 (| acc p.mask)) 0 pieces))]
    (Finished :text (stringJoin (map (fn [(p Piece)] -> String p.text) pieces) "\ndefine ")
              :classes (filter (fn [(c Int64)] -> Bool (and (= (& (>> mask c) 1) 1) (routedKey? rooted c))) (range 0 (classes)))
              :cons (listAny? (fn [(p Piece)] -> Bool p.cons) pieces)
              :sized (listAny? (fn [(p Piece)] -> Bool p.sized) pieces)))

; (:m :ref QW-ALLOC :do "the one-byte string table: strrt.single, called where a slice has length 1, returns one of 256 static cells whose count is stuck (255) and class is unpooled (255), so dup, drop, claim and pin leave it alone and no allocation happens; under untraced RC the generic definition, which allocates a cell, is renamed and the table version takes its name. The replace is anchored to a line start, which a string constant never has (its newlines are escaped), so a user literal holding the define line is untouched. The head is built from two parts so this compiler's own constants never match the rename when it compiles itself")
fn oneCharHead -> String
  (str "define internal ptr @strrt." "single(ptr %src) {")

fn oneCharGenericHead -> String
  (str "define internal ptr @strrt." "singleGeneric(ptr %src) {")

fn hexDigit d: Int64 -> String
  (optionOr (stringSlice "0123456789ABCDEF" d (+ d 1)) "0")

fn hexByte b: Int64 -> String
  (str "\\" (hexDigit (/ b 16)) (hexDigit (mod b 16)))

; (:m :ref QW-ALLOC :do "the table is one byte-string constant of 256 cells of 24 bytes, little-endian: header word 0xFFFF000000000012 (class 255, count 255, type string, size 18), length 1, then the byte and a zero; one trailing token keeps irSplit's extern declaration of an internal global, which drops the last word of the initializer, valid")
fn oneCharCell b: Int64 -> String
  (str "\\12\\00\\00\\00\\00\\00\\FF\\FF\\01\\00\\00\\00\\00\\00\\00\\00" (hexByte b) "\\00\\00\\00\\00\\00\\00\\00")

fn oneCharText -> String
  (lines (list (str "@strrt.one = internal global [6144 x i8] c\"" (stringJoin (map oneCharCell (range 0 256)) "") "\", align 16")
               (oneCharHead)
               "entry:"
               "  %b = load i8, ptr %src"
               "  %i = zext i8 %b to i64"
               "  %off = mul i64 %i, 24"
               "  %p = getelementptr inbounds i8, ptr @strrt.one, i64 %off"
               "  ret ptr %p"
               "}"))

fn oneCharSplice text: String notrace: Bool -> String
  (if (and notrace (stringContains? text (str "\n" (oneCharHead))))
    (str (stringReplace text (str "\n" (oneCharHead)) (str "\n" (oneCharGenericHead))) "\n" (oneCharText) "\n")
    text)

fn rcFinishText text: String asan: Bool -> String
  (rcFinishTextWith text asan false)

fn rcFinishTextWith text: String asan: Bool notrace: Bool -> String
  (rcFinishTextCounted text asan notrace (or asan (not notrace)))

; (:m :ref FREECHAINLOOP :do "the per-cell counters (freed, reused, fresh) bump a global on every alloc and free; the untraced production build compiles them out unless counted is set (rc mode notraceStats), the counted, ASan and stats builds keep them, and the rarer counters stay in every build")
fn countedSlot? line: String -> Bool
  (and (stringContains? line ".sp = getelementptr [")
       (or (stringEndsWith? line (str "ptr @aslRc.stats, i64 0, i64 " (statFreed)))
           (or (stringEndsWith? line (str "ptr @aslRc.stats, i64 0, i64 " (statReused)))
               (stringEndsWith? line (str "ptr @aslRc.stats, i64 0, i64 " (statFresh))))))

fn uncounted counted: Bool text: String -> String
  (if counted
    text
    (lines (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
                                            (cond ((> (pairFirst acc) 0) (pair (- (pairFirst acc) 1) (pairSecond acc)))
                                                  ((countedSlot? l) (pair 3 (pairSecond acc)))
                                                  (else (pair 0 (cons l (pairSecond acc))))))
                                          (pair 0 (list)) (stringLines text))))))

fn rcFinishTextCounted text: String asan: Bool notrace: Bool counted: Bool -> String
  (let [(n (stringLength text))
        (cut (declareCut text))
        (arities (ownedArityIn text))
        (takes (takeIndices (if (< cut n) (optionOr (stringSlice text cut n) "") (declareSection text))))
        (removed (union (removedDecls arities) (setOf (map takeDecl takes))))
        (code (if (< cut n) (optionOr (stringSlice text 0 cut) "") (undeclaredInPlace text removed)))
        (section (if (< cut n) (keptDecls (optionOr (stringSlice text cut n) "") removed) ""))
        (rooted (rootedRuntime? (if (< cut n) section (declareSection code))))
        (uses (or (stringContains? code (arenaCallText)) (stringContains? code (arenaFlatCallText))))
        (active (and uses notrace))
        (guard (fn [(d String)] -> String (if active (arenaGuarded d) d)))
        (arenaed (if uses (stringReplace (stringReplace code (arenaCallText) (arenaRunCall)) (arenaFlatCallText) (arenaFlatRunCall)) code))
        (relink (and notrace (stringContains? arenaed (appendCallText))))
        (appended (if relink (stringReplace arenaed (appendCallText) (appendOwnedCall)) arenaed))
        (reversing (and notrace (and (stringContains? appended (reverseCallText)) (stringContains? appended (reverseOntoCallText)))))
        (undeclared (if reversing (stringReplace appended (reverseCallText) (reverseOwnedCall)) appended))
        (hashed (oneCharSplice (treapRt/treapSplice (hashRt/hashSplice undeclared notrace) (and notrace (not uses))) notrace))
        (fin (finishChunks hashed (or asan counted) rooted active))
        (large (filter (fn [(c Int64)] -> Bool (>= c (smallClasses))) fin.classes))
        (small (filter (fn [(c Int64)] -> Bool (< c (smallClasses))) fin.classes))
        (consDef (if fin.cons (list (allocText "@aslRc.allocFastCons" "@gcAsl.allocFastCons" 3 asan)) (list)))
        (sized (or active fin.sized))
        (body fin.text)
        (sizedDef (if sized (list (sizedAllocText asan rooted)) (list)))
        (final (if active (arenaGetters body) body))]
    (str final section "\n" (uncounted counted (runtimeTextIn final (if (< cut n) section (declareSection final)) asan notrace)) "\n"
         (uncounted counted (lines (map guard (listAppend (map (fn [(c Int64)] -> String (allocText (rcAllocSym c) (allocFastSym c) c asan)) large)
                                       (listAppend consDef (listAppend (map smallAllocText small) sizedDef))))))
         "\n" (lines (map callOwnedText arities)) "\n" (lines (map (fn [(i Int64)] -> String (liveChecked asan (takeText i))) takes)) "\n" (if relink (str (appendOwnedText asan) "\n") "") (if reversing (str (reverseOwnedText asan) "\n") "")))

fn routeSized active: Bool text: String -> String
  (stringJoin (map (fn [(l String)] -> String
                     (let [(r (if (and (stringContains? l (sizedCall)) (stringStartsWith? l "  ")) (stringReplace l (sizedCall) "call ptr @aslRc.alloc(") l))]
                       (if active (arenaLine r) r)))
                   (stringSplit text "\n"))
              "\n")

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
    (setOf (map (fn [(i Int64)] -> String (match (listGet f.params i) ((some p) p.name) ((none) "")))
                (filter (fn [(i Int64)] -> Bool (optionOr (listGet flags i) false)) (range 0 (listLength f.params))))))

fn borrowable? targets: (Map String Bool) f: ty/SsaFunction -> Bool
  (and (listEmpty? f.captures) (not (mapHas? targets f.name)))

; (:m :ref PERF-FREECHAIN :do "a parameter walked as a list starts owned, not borrowed, when one block both builds a cons and passes the parameter's rest to a call, as a reverse or a map onto an accumulator does: a unique cell of it then dies into a reset and becomes that cons, relinking the list in place instead of freeing the cell after the call while the cons takes a fresh one; a walk whose cons sits apart from its recursion keeps the borrow")
fn listReuseParams f: ty/SsaFunction -> (Map String Bool)
  (let [(instrs (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks))
        (rests (fold (fn [(acc (Map String String)) (i ty/SsaInstr)] -> (Map String String)
                       (match i.op
                         ((ty/opEntry name args) (if (= name "@listRest") (match (listHead args) ((some p) (mapSet acc i.dest p)) ((none) acc)) acc))
                         (_ acc)))
                     (mapEmpty) instrs))]
    (setOf (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
                   (if (listAny? (fn [(i ty/SsaInstr)] -> Bool (= (allocClass i) 3)) b.instrs)
                     (fold (fn [(found (List String)) (i ty/SsaInstr)] -> (List String)
                             (match i.op
                               ((ty/opCall _ args) (listAppend found (fold (fn [(ps (List String)) (a String)] -> (List String) (match (mapGet rests a) ((some p) (cons p ps)) ((none) ps))) (list) args)))
                               (_ found)))
                           acc b.instrs)
                     acc))
                 (list) f.blocks)))

; (:m :ref PERCEUS :do "a parameter starts owned when one block reads it as a cell (variant field or record field) and later builds a value of the same kind, as a map over a variant, a record update or an Option rebuild does: its unique cell then dies into a reset and becomes that value (Lean's borrow inference keeps a reset parameter owned); list walks keep listReuseParams, since a list is often walked while its owner keeps it (measured: preludeAppendBounded 1.17M shared resets when owned)")
fn cellRead param: (Map String Bool) op: ty/SsaOp -> String
  (match op
    ((ty/opVariantField b _) (if (mapHas? param b) "adt" ""))
    ((ty/opField b _) (if (mapHas? param b) "rec" ""))
    (_ ""))

fn allocKind ins: ty/SsaInstr -> String
  (if (< (allocClass ins) 0) "" (match ins.op ((ty/opRecord _ _ _) "rec") (_ "adt")))

fn reuseParams f: ty/SsaFunction -> (Map String Bool)
  (let [(params (setOf (map (fn [(q ty/SsaParam)] -> String q.name) f.params)))]
    (fold (fn [(acc (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
            (pairSecond (fold (fn [(st (Pair (Map String String) (Map String Bool))) (i ty/SsaInstr)] -> (Pair (Map String String) (Map String Bool))
                                (let [(read (cellRead params i.op))
                                      (seen (if (= read "") (pairFirst st) (mapSet (pairFirst st) (optionOr (listHead (ty/opOperands i.op)) "") read)))
                                      (kind (allocKind i))]
                                  (pair seen (if (= kind "") (pairSecond st)
                                               (fold (fn [(a (Map String Bool)) (x String)] -> (Map String Bool) (if (= (optionOr (mapGet (pairFirst st) x) "") kind) (mapSet a x true) a)) (pairSecond st) (mapKeys (pairFirst st)))))))
                              (pair (mapEmpty) acc) b.instrs)))
          (mapEmpty) f.blocks))

fn initialBorrows counted: (List ty/SsaFunction) targets: (Map String Bool) -> (Map String (List Bool))
  (fold (fn [(acc (Map String (List Bool))) (f ty/SsaFunction)] -> (Map String (List Bool))
          (if (borrowable? targets f)
            (let [(walked (union (listReuseParams f) (reuseParams f)))]
              (mapSet acc f.name (treapRt/ownedFlags f.name (hashRt/ownedFlags f.name (map (fn [(p ty/SsaParam)] -> Bool (and (heapTy? p.ty) (not (mapHas? walked p.name)))) f.params)))))
            acc))
        (mapEmpty) counted)

fn withBorrows ctx: Ctx borrows: (Map String (List Bool)) -> Ctx
  (Ctx :user ctx.user :opaque ctx.opaque :builders ctx.builders :borrows borrows :scc ctx.scc :proj ctx.proj :cache ctx.cache :arity ctx.arity)

fn withCache ctx: Ctx cache: (Map String Facts) -> Ctx
  (Ctx :user ctx.user :opaque ctx.opaque :builders ctx.builders :borrows ctx.borrows :scc ctx.scc :proj ctx.proj :cache cache :arity ctx.arity)

; (:m :ref RCCOST2 :do "the facts a function was last settled with are kept in the context: the worklist settles a function again whenever a flag it reads changes, so its last facts were computed from the flags and projections that are final, and rcFunction and the projection check reuse them instead of computing them again")
fn cachedFacts ctx: Ctx f: ty/SsaFunction -> Facts
  (match (mapGet ctx.cache f.name)
    ((some facts) facts)
    ((none) (functionFacts ctx f)))

fn ownParam borrows: (Map String (List Bool)) name: String i: Int64 -> (Map String (List Bool))
  (match (mapGet borrows name)
    ((none) borrows)
    ((some flags) (if (optionOr (listGet flags i) false)
                    (mapSet borrows name (map (fn [(k Int64)] -> Bool (if (= k i) false (optionOr (listGet flags k) false))) (range 0 (listLength flags))))
                    borrows)))

fn returnsVia byLabel: (Map String ty/SsaBlock) t: ty/SsaTerm v: String fuel: Int64 -> Bool
  (match t
    ((ty/termReturn r) (= r v))
    ((ty/termJump e) (and (> fuel 0)
                          (and (= e.args (list v))
                               (match (mapGet byLabel e.target)
                                 ((some j) (and (listEmpty? j.instrs) (and (= (listLength j.params) 1) (match (listHead j.params) ((some p) (returnsVia byLabel j.term p.name (- fuel 1))) ((none) false)))))
                                 ((none) false)))))
    (_ false))

fn tailCalls f: ty/SsaFunction -> (List (Pair String (List String)))
  (let [(byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))]
    (fold (fn [(acc (List (Pair String (List String)))) (b ty/SsaBlock)] -> (List (Pair String (List String)))
            (match (listHead (listReverse b.instrs))
              ((some ins) (match ins.op ((ty/opCall callee args) (if (returnsVia byLabel b.term ins.dest 16) (cons (pair callee args) acc) acc)) (_ acc)))
              ((none) acc)))
          (list) f.blocks))

; (:m :ref RC-PERF :do "a tail call keeps its musttail only when no drop follows it, so a callee whose parameter is borrowed forces the owned argument of a tail call to own it; that is needed only where the call can recur without growing the stack, a cycle of tail calls (a cycle through a plain call grows it anyway), so the force is limited to callers in the callee's strongly connected component of the tail-call graph and other tail calls become plain calls followed by the drop; closure calls in tail position go through one node that reaches every closure target")
fn callTargets f: ty/SsaFunction -> (List String)
  (let [(byLabel (fold (fn [(acc (Map String ty/SsaBlock)) (b ty/SsaBlock)] -> (Map String ty/SsaBlock) (mapSet acc b.label b)) (mapEmpty) f.blocks))
        (closures (listAny? (fn [(b ty/SsaBlock)] -> Bool
                              (match (listHead (listReverse b.instrs))
                                ((some ins) (match ins.op ((ty/opCallClosure _ _) (returnsVia byLabel b.term ins.dest 16)) (_ false)))
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
  (match (listHead stack)
    ((none) (pair seen order))
    ((some top) (let [(rest (optionOr (listTail stack) (list)))]
                  (match (listHead (pairSecond top))
                    ((none) (dfsOrder g rest seen (cons (pairFirst top) order)))
                    ((some c) (let [(top1 (pair (pairFirst top) (optionOr (listTail (pairSecond top)) (list))))]
                                (if (mapHas? seen c)
                                  (dfsOrder g (cons top1 rest) seen order)
                                  (dfsOrder g (cons (pair c (optionOr (mapGet g c) (list))) (cons top1 rest)) (mapSet seen c true) order))))))))

fn finishOrder g: (Map String (List String)) nodes: (List String) seen: (Map String Bool) order: (List String) -> (List String)
  (match (listHead nodes)
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
  (match (listHead stack)
    ((none) comp)
    ((some n) (let [(kids (filter (fn [(c String)] -> Bool (not (mapHas? comp c))) (optionOr (mapGet gT n) (list))))
                    (marked (fold (fn [(acc (Map String String)) (c String)] -> (Map String String) (mapSet acc c root)) comp kids))]
                (claim gT (listAppend kids (optionOr (listTail stack) (list))) root marked))))

fn components gT: (Map String (List String)) order: (List String) comp: (Map String String) -> (Map String String)
  (match (listHead order)
    ((none) comp)
    ((some n) (components gT (optionOr (listTail order) (list)) (if (mapHas? comp n) comp (claim gT (list n) n (mapSet comp n n))))))

fn sccOf fns: (List ty/SsaFunction) targets: (Map String Bool) -> (Map String String)
  (let [(g (callGraph fns targets))]
    (components (transposed g) (finishOrder g (mapKeys g) (mapEmpty) (list)) (mapEmpty)))

fn sameScc? ctx: Ctx a: String b: String -> Bool
  (match (mapGet ctx.scc a)
    ((none) true)
    ((some ca) (match (mapGet ctx.scc b) ((none) true) ((some cb) (= ca cb)))))

; (:m :ref RC-OWN-FOR-REUSE :do "Lean's projection rule: a part of a borrowed parameter that a counted call consumes makes the parameter owned, so a caller that lets go of a map hands mapSet a value whose tree it can take apart in place instead of a borrow that forces a copy of every node")
fn projOwners ctx: Ctx facts: Facts f: ty/SsaFunction -> (Map String Bool)
  (setOf (fold (fn [(acc (List String)) (ins ty/SsaInstr)] -> (List String)
                 (match ins.op
                   ((ty/opCall callee args)
                     (if (or (arenaEntry? callee) (or (builderFunction? ctx callee) (or (arrayFresh? callee) (or (borrowExtern? callee) (opaqueFunction? ctx callee)))))
                       acc
                       (fold (fn [(a (List String)) (u Use)] -> (List String)
                               (if (= u.kind "consume") (match (mapGet facts.anchors u.name) ((some p) (if (= p "") a (cons p a))) ((none) a)) a))
                             acc (callUses ctx facts callee args))))
                   (_ acc)))
               (list) (functionInstrs f)))

; (:m :ref RCCOST2 :do "settling only ever turns a borrowed flag of f or of a tail callee in f's SCC into owned, so a function with no borrowed parameter whose tail calls reach no callee with a borrowed parameter leaves the flags as they are and skips its facts")
fn settleIdle? ctx: Ctx f: ty/SsaFunction -> Bool
  (and (not (listAny? (fn [(b Bool)] -> Bool b) (borrowFlags ctx f.name)))
       (listAll? (fn [(c (Pair String (List String)))] -> Bool
                   (or (not (sameScc? ctx f.name (pairFirst c))) (not (listAny? (fn [(b Bool)] -> Bool b) (borrowFlags ctx (pairFirst c))))))
                 (tailCalls f)))

schema Visit
  borrows: (Map String (List Bool))
  facts: (Option Facts)

fn settleFunction ctx: Ctx borrows: (Map String (List Bool)) f: ty/SsaFunction -> Visit
  (if (settleIdle? ctx f) (Visit :borrows borrows :facts (none)) (settleFacts ctx borrows f))

fn settleFacts ctx: Ctx borrows: (Map String (List Bool)) f: ty/SsaFunction -> Visit
  (let [(facts (functionFacts ctx f))
        (consumeSet (consumedNames ctx facts f))
        (flags (borrowFlags ctx f.name))
        (owners (projOwners ctx facts f))
        (consumed (fold (fn [(acc (Map String (List Bool))) (i Int64)] -> (Map String (List Bool))
                          (let [(p (match (listGet f.params i) ((some q) q.name) ((none) "")))]
                            (if (and (optionOr (listGet flags i) false) (or (mapHas? consumeSet p) (mapHas? owners p))) (ownParam acc f.name i) acc)))
                        borrows (range 0 (listLength f.params))))]
    (Visit :borrows (fold (fn [(acc (Map String (List Bool))) (c (Pair String (List String)))] -> (Map String (List Bool))
                            (let [(args (pairSecond c))]
                              (fold (fn [(a (Map String (List Bool))) (i Int64)] -> (Map String (List Bool))
                                      (if (and (!= (liveName facts (optionOr (listGet args i) "")) "") (sameScc? ctx f.name (pairFirst c))) (ownParam a (pairFirst c) i) a))
                                    acc (range 0 (listLength args)))))
                          consumed (tailCalls f))
           :facts (some facts)))

fn borrowCount borrows: (Map String (List Bool)) -> Int64
  (fold (fn [(acc Int64) (flags (List Bool))] -> Int64 (+ acc (listLength (filter (fn [(b Bool)] -> Bool b) flags)))) 0 (mapValues borrows))

; (:m :ref RC-SETTLE-WORKLIST :do "the counted functions whose settling reads the borrow flags of a name: the function itself (its own flags make its borrowed parameters) and every function with a call to it (callUses reads the callee's flags at each opCall, tail calls included); closure calls read no flags")
fn flagReaders counted: (List ty/SsaFunction) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (f ty/SsaFunction)] -> (Map String (List String))
          (fold (fn [(a (Map String (List String))) (n String)] -> (Map String (List String)) (mapSet a n (cons f.name (optionOr (mapGet a n) (list)))))
                acc
                (distinctNames (cons f.name (fold (fn [(cs (List String)) (ins ty/SsaInstr)] -> (List String) (match ins.op ((ty/opCall callee _) (cons callee cs)) (_ cs))) (list) (functionInstrs f))))))
        (mapEmpty) counted)

; (:m :ref RC-SETTLE-WORKLIST :do "settleFunction writes only the flags of the function and of its tail callees, so a flag read goes stale only for the readers of those names")
fn settledNames f: ty/SsaFunction -> (List String)
  (cons f.name (map pairFirst (tailCalls f)))

fn flagsEqual? a: (Map String (List Bool)) b: (Map String (List Bool)) n: String -> Bool
  (= (optionOr (mapGet a n) (list)) (optionOr (mapGet b n) (list)))

; (:m :ref RC-SETTLE-WORKLIST :do "ownParam only turns a borrow into an own, so the settled flags are the one fixpoint whatever the visiting order; a function is settled again only when the flags it reads changed, instead of every function every round")
schema Settled
  borrows: (Map String (List Bool))
  queue: (Map String Bool)
  cache: (Map String Facts)

fn settleBorrows ctx: Ctx counted: (List ty/SsaFunction) readers: (Map String (List String)) pending: (Map String Bool) borrows: (Map String (List Bool)) fuel: Int64 -> Settled
  (let [(todo (filter (fn [(f ty/SsaFunction)] -> Bool (mapHas? pending f.name)) counted))
        (step (fold (fn [(st Settled) (f ty/SsaFunction)] -> Settled
                      (let [(cur st.borrows)
                            (v (settleFunction (withBorrows ctx cur) cur f))
                            (after v.borrows)
                            (changed (filter (fn [(n String)] -> Bool (not (flagsEqual? cur after n))) (settledNames f)))]
                        (Settled :borrows after
                                 :queue (fold (fn [(q (Map String Bool)) (n String)] -> (Map String Bool)
                                                (fold (fn [(q2 (Map String Bool)) (r String)] -> (Map String Bool) (mapSet q2 r true)) q (optionOr (mapGet readers n) (list))))
                                              st.queue changed)
                                 :cache (match v.facts ((some fc) (mapSet st.cache f.name fc)) ((none) (mapRemove st.cache f.name))))))
                    (Settled :borrows borrows :queue (mapEmpty) :cache ctx.cache) todo))]
    (cond
      ((= (mapSize step.queue) 0) step)
      ((<= fuel 0) (Settled :borrows step.borrows :queue step.queue :cache (fold (fn [(c (Map String Facts)) (n String)] -> (Map String Facts) (mapRemove c n)) step.cache (mapKeys step.queue))))
      (else (settleBorrows (withCache ctx step.cache) counted readers step.queue step.borrows (- fuel 1)))))

; (:m :ref RC-PERF :do "a projection returns a part of one borrowed parameter (the parameter, a field, a list cell's head or rest, a projection of those, or a join of them) without a dup; its callers treat the result as derived from that argument, so a read-only accessor or a list walk that returns a suffix costs no RC traffic in the loop and the caller dups once only if it keeps the result")
fn flowNone -> Flow
  (Flow :ok false :param -1 :keys (mapEmpty) :names (mapEmpty) :values (mapEmpty))

fn flowFail acc: Flow -> Flow
  (Flow :ok false :param acc.param :keys acc.keys :names acc.names :values acc.values)

fn flowWalk ctx: Ctx defs: (Map String ty/SsaInstr) owners: (Map String (Pair String Int64)) incoming: (Map String (List (List String))) params: (Map String Int64) todo: (List String) acc: Flow -> Flow
  (match (listHead todo)
    ((none) acc)
    ((some v) (let [(rest (optionOr (listTail todo) (list)))]
                (cond
                  ((not acc.ok) acc)
                  ((mapHas? acc.values v) (flowWalk ctx defs owners incoming params rest acc))
                  (else
                    (let [(seen (Flow :ok true :param acc.param :keys acc.keys :names acc.names :values (mapSet acc.values v true)))]
                      (match (mapGet params v)
                        ((some i) (if (or (= acc.param -1) (= acc.param i))
                                    (flowWalk ctx defs owners incoming params rest (Flow :ok true :param i :keys seen.keys :names seen.names :values seen.values))
                                    (flowFail seen)))
                        ((none) (match (mapGet defs v)
                                  ((some ins) (let [(b (sourceBase ctx ins.op))]
                                                (cond
                                                  ((!= b "") (flowWalk ctx defs owners incoming params (cons b rest) seen))
                                                  ((listContains? (list "immortal" "opaque") (resultKind ctx ins)) (flowWalk ctx defs owners incoming params rest seen))
                                                  (else (flowFail seen)))))
                                  ((none) (match (mapGet owners v)
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
                                  (match (listGet b.params j) ((some p) (mapSet a p.name (pair b.label j))) ((none) a)))
                                acc (range 0 (listLength b.params))))
                        (mapEmpty) f.blocks))
          (incoming (fold (fn [(acc (Map String (List (List String)))) (b ty/SsaBlock)] -> (Map String (List (List String)))
                            (fold (fn [(a (Map String (List (List String)))) (e ty/SsaEdge)] -> (Map String (List (List String))) (mapSet a e.target (cons e.args (optionOr (mapGet a e.target) (list)))))
                                  acc (ty/termEdges b.term)))
                          (mapEmpty) f.blocks))
          (params (fold (fn [(acc (Map String Int64)) (i Int64)] -> (Map String Int64)
                          (match (listGet f.params i) ((some p) (if (heapTy? p.ty) (mapSet acc p.name i) acc)) ((none) acc)))
                        (mapEmpty) (range 0 (listLength f.params))))
          (returns (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String) (match b.term ((ty/termReturn v) (cons v acc)) (_ acc))) (list) f.blocks))
          (walked (flowWalk ctx defs owners incoming params returns (Flow :ok true :param -1 :keys (mapSet (mapEmpty) "$ret" true) :names (mapEmpty) :values (mapEmpty))))]
      (if (and walked.ok (and (>= walked.param 0) (not (listEmpty? returns)))) walked (flowNone))))

fn withProj ctx: Ctx proj: (Map String Int64) -> Ctx
  (Ctx :user ctx.user :opaque ctx.opaque :builders ctx.builders :borrows ctx.borrows :scc ctx.scc :proj proj :cache ctx.cache :arity ctx.arity)

fn heapParamIndices f: ty/SsaFunction -> (List Int64)
  (filter (fn [(i Int64)] -> Bool (match (listGet f.params i) ((some p) (heapTy? p.ty)) ((none) false))) (range 0 (listLength f.params)))

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
        (facts (cachedFacts ctx f))
        (p (match (listGet f.params w.param) ((some q) q.name) ((none) "")))]
    (and w.ok (and (= (optionOr (mapGet ctx.proj f.name) -1) w.param)
                   (and (mapHas? facts.borrowed p) (listAll? (fn [(v String)] -> Bool (not (tracked? facts v))) (mapKeys w.values))))))

; (:m :ref RC-SETTLE-WORKLIST :do "after a round drops projections, only those functions and their callers see different facts (resultKind, sourceBase and the flow all look at the projection of a direct callee), so the next settling starts from them on the flags already settled")
fn settleProj ctx: Ctx counted: (List ty/SsaFunction) readers: (Map String (List String)) pending: (Map String Bool) borrows: (Map String (List Bool)) fuel: Int64 -> Ctx
  (let [(s (settleBorrows ctx counted readers pending borrows 50))
        (b s.borrows)
        (c (withCache (withBorrows ctx b) s.cache))
        (kept (fold (fn [(acc (Map String Int64)) (f ty/SsaFunction)] -> (Map String Int64)
                      (if (and (mapHas? ctx.proj f.name) (projOk? c f)) (mapSet acc f.name (optionOr (mapGet ctx.proj f.name) -1)) acc))
                    (mapEmpty) counted))
        (dropped (filter (fn [(n String)] -> Bool (not (mapHas? kept n))) (mapKeys ctx.proj)))
        (affected (setOf (fold (fn [(acc (List String)) (n String)] -> (List String) (listAppend acc (optionOr (mapGet readers n) (list)))) (list) dropped)))]
    (cond
      ((= (mapSize kept) (mapSize ctx.proj)) c)
      ((<= fuel 0) (let [(none0 (withProj c (mapEmpty)))
                         (again (settleBorrows none0 counted readers (allPending counted) b 50))]
                     (withCache (withBorrows none0 again.borrows) again.cache)))
      (else (settleProj (withProj c kept) counted readers affected b (- fuel 1)))))

fn allPending counted: (List ty/SsaFunction) -> (Map String Bool)
  (setOf (map (fn [(f ty/SsaFunction)] -> String f.name) counted))
