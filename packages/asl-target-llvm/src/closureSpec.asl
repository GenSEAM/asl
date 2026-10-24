(module asl-target-llvm/closureSpec
  :x [specializeClosures cloneName directName]
  :i [(asl-ir/types :a ty)])

; (:m :ref CLOSPEC :do "call-site specialisation on a known closure: a call that passes a closure built in the caller (opMakeClosure of a module lambda) to a module function whose parameter is only called or passed on to module functions that do the same gets a clone of the callee per (callee, position, lambda), with the closure parameter replaced by the closure's captures; inside a clone the call of the closure goes straight to the lambda (captures as leading parameters), so the loop makes no objrt.call and the lambda body inlines")
schema Spec
  fns: (Map String ty/SsaFunction)
  added: (List String)
  fresh: (List String)
  count: Int64
  lambdas: (Map String Bool)

fn cloneLimit -> Int64
  4096

fn cloneName callee: String k: Int64 lambda: String -> String
  (str callee "$cs" (stringFromInt64 k) "$" lambda)

fn directName lambda: String -> String
  (str lambda "$cd")

; (:m :do "array kernels stay opaque to the RC pass, so a clone of one may only take captures that are immediates; parallel workers are never cloned")
fn opaque? name: String -> Bool
  (stringStartsWith? name "asl-target-llvm/arrays.")

fn barred? name: String -> Bool
  (stringStartsWith? name "asl-target-llvm/parallel.")

; (:m :do "prelude.map and prelude.filter have hand-written bodies that build the list forward (ssa listBuilderNames); a clone would run the SSA body, which builds it reversed and reverses it, allocating twice, so they keep the closure call")
fn builder? name: String -> Bool
  (listContains? (list "prelude.map" "prelude.filter") name)

fn allVal? ps: (List ty/SsaParam) -> Bool
  (listAll? (fn [(p ty/SsaParam)] -> Bool (= (ty/ssaTyName p.ty) "val")) ps)

fn valTy? t: ty/SsaTy -> Bool
  (= (ty/ssaTyName t) "val")

fn defsOf f: ty/SsaFunction -> (Map String ty/SsaOp)
  (fold (fn [(acc (Map String ty/SsaOp)) (b ty/SsaBlock)] -> (Map String ty/SsaOp)
          (fold (fn [(a (Map String ty/SsaOp)) (ins ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet a ins.dest ins.op)) acc b.instrs))
        (mapEmpty) f.blocks)

fn termOperands t: ty/SsaTerm -> (List String)
  (listAppend
    (match t ((ty/termReturn v) (list v)) ((ty/termBranch c _ _) (list c)) ((ty/termSwitch s _ _ _) (list s)) (_ (list)))
    (listFlatMap (fn [(e ty/SsaEdge)] -> (List String) e.args) (ty/termEdges t)))

fn splice xs: (List T) k: Int64 ys: (List T) -> (List T)
  (listAppend (listTake xs k) (listAppend ys (listDrop xs (+ k 1))))

; (:m :do "the lambda and captures of v when the caller itself builds v as a closure over a module function whose code is all Val")
fn closureOf st: Spec defs: (Map String ty/SsaOp) v: String -> (Option (Pair ty/SsaFunction (List String)))
  (match (mapGet defs v)
    ((none) (none))
    ((some op) (match op
                 ((ty/opMakeClosure callee caps)
                   (match (mapGet st.fns callee)
                     ((none) (none))
                     ((some l) (if (and (= (listLength l.captures) (listLength caps))
                                        (and (allVal? l.captures) (and (allVal? l.params) (and (valTy? l.retTy) (not (barred? l.name))))))
                                 (some (pair l caps))
                                 (none)))))
                 (_ (none)))))

; (:m :do "a value the RC pass never counts: a boxed raw number or a constant other than a string, symbol or keyword")
fn immediate? defs: (Map String ty/SsaOp) v: String -> Bool
  (match (mapGet defs v)
    ((none) false)
    ((some op) (match op
                 ((ty/opBox _) true)
                 ((ty/opConst c) (match c ((ty/constStr _) false) ((ty/constSymbol _) false) ((ty/constKeyword _) false) (_ true)))
                 (_ false))))

; (:m :do "a capture that is also another argument of the call, or twice a capture, is not split out: the RC pass would see one name both borrowed and consumed by one call and pass it without a dup")
fn clash? caps: (List String) others: (List String) -> Bool
  (or (listAny? (fn [(c String)] -> Bool (listContains? others c)) caps)
      (listAny? (fn [(e (Pair Int64 String))] -> Bool (listContains? (listDrop caps (+ (pairFirst e) 1)) (pairSecond e))) (enumerate caps)))

fn arityOk? st: Spec name: String args: (List String) -> Bool
  (match (mapGet st.fns name)
    ((none) false)
    ((some f) (and (listEmpty? f.captures) (= (listLength args) (listLength f.params)))))

fn siteKey name: String k: Int64 lambda: String -> String
  (str name "\t" (stringFromInt64 k) "\t" lambda)

; (:m :do "parameter k of the named function only ever is the callee of a closure call of the lambda's arity, or an argument of a module function call whose parameter there accepts the same; a cycle through the same position is accepted")
fn accepts? st: Spec seen: (List String) name: String k: Int64 l: ty/SsaFunction -> Bool
  (if (listContains? seen (siteKey name k l.name))
    true
    (match (mapGet st.fns name)
      ((none) false)
      ((some f) (and (listEmpty? f.captures)
                     (and (not (or (barred? f.name) (builder? f.name)))
                          (match (listGet f.params k)
                            ((none) false)
                            ((some p) (and (valTy? p.ty) (usesAccepted? st (cons (siteKey name k l.name) seen) f p.name l)))))))))

; (:m :do "only loops are worth a clone: parameter k of the named function goes back into its own self call at k, or on to a function that loops on it, or the function is an array kernel; a function that only calls its closure once keeps the closure call, and with it its tail-call shape")
fn loops? st: Spec seen: (List String) name: String k: Int64 -> Bool
  (cond
    ((opaque? name) true)
    ((listContains? seen name) false)
    (else (match (mapGet st.fns name)
            ((none) false)
            ((some f) (match (listGet f.params k)
                        ((none) false)
                        ((some p) (listAny? (fn [(b ty/SsaBlock)] -> Bool
                                              (listAny? (fn [(ins ty/SsaInstr)] -> Bool
                                                          (match ins.op
                                                            ((ty/opCall h args) (listAny? (fn [(e (Pair Int64 String))] -> Bool
                                                                                            (and (= (pairSecond e) p.name)
                                                                                                 (if (= h name) (= (pairFirst e) k) (loops? st (cons name seen) h (pairFirst e)))))
                                                                                          (enumerate args)))
                                                            (_ false)))
                                                        b.instrs))
                                            f.blocks)))))))

fn useOk? st: Spec seen: (List String) p: String l: ty/SsaFunction ins: ty/SsaInstr -> Bool
  (if (not (listContains? (ty/opOperands ins.op) p))
    true
    (match ins.op
      ((ty/opCallClosure c args) (and (= c p) (and (not (listContains? args p)) (and (valTy? ins.ty) (= (listLength args) (listLength l.params))))))
      ((ty/opCall h args) (and (or (not (opaque? h)) (listEmpty? l.captures))
                               (listAll? (fn [(e (Pair Int64 String))] -> Bool
                                           (or (!= (pairSecond e) p) (and (arityOk? st h args) (accepts? st seen h (pairFirst e) l))))
                                         (enumerate args))))
      (_ false)))

fn usesAccepted? st: Spec seen: (List String) f: ty/SsaFunction p: String l: ty/SsaFunction -> Bool
  (listAll? (fn [(b ty/SsaBlock)] -> Bool
              (and (not (listContains? (termOperands b.term) p))
                   (listAll? (fn [(ins ty/SsaInstr)] -> Bool (useOk? st seen p l ins)) b.instrs)))
            f.blocks)

fn withFn st: Spec name: String f: ty/SsaFunction -> Spec
  (Spec :fns (mapSet st.fns name f) :added st.added :fresh st.fresh :count st.count :lambdas st.lambdas)

fn withNew st: Spec name: String f: ty/SsaFunction lambda: String -> Spec
  (Spec :fns (mapSet st.fns name f) :added (cons name st.added) :fresh (cons name st.fresh) :count (+ st.count 1)
        :lambdas (if (stringEmpty? lambda) st.lambdas (mapSet st.lambdas lambda true)))

fn directCallee l: ty/SsaFunction -> String
  (if (listEmpty? l.captures) l.name (directName l.name))

; (:m :do "the lambda as a plain function: its captures become its leading parameters, its body is unchanged; a lambda without captures is called as it is")
fn ensureDirect st: Spec l: ty/SsaFunction -> Spec
  (let [(n (directName l.name))]
    (if (or (listEmpty? l.captures) (mapHas? st.fns n))
      st
      (withNew st n (ty/ssaFunction n (list) (listAppend l.captures l.params) l.retTy l.blocks) l.name)))

; (:m :do "the clone takes the captures where the closure was and rebuilds the closure from them on entry, so the scan of the clone turns its closure calls into direct calls and drops the closure once nothing reads it")
fn ensureClone st: Spec f: ty/SsaFunction k: Int64 l: ty/SsaFunction -> Spec
  (let [(n (cloneName f.name k l.name))]
    (if (mapHas? st.fns n)
      st
      (let [(pname (match (listGet f.params k) ((some p) p.name) ((none) "")))
            (tag (str "cs" (stringFromInt64 st.count) "$"))
            (capParams (map (fn [(i Int64)] -> ty/SsaParam (ty/ssaParam (str tag (stringFromInt64 i)) (ty/tyVal))) (range 0 (listLength l.captures))))
            (def (ty/ssaInstr pname (ty/tyVal) (ty/opMakeClosure l.name (map (fn [(p ty/SsaParam)] -> String p.name) capParams))))
            (blocks (match (listHead f.blocks)
                      ((none) f.blocks)
                      ((some b0) (cons (ty/ssaBlock b0.label b0.params (cons def b0.instrs) b0.term) (optionOr (listTail f.blocks) (list))))))]
        (withNew st n (ty/ssaFunction n (list) (splice f.params k capParams) f.retTy blocks) ""))))

fn siteAt st: Spec defs: (Map String ty/SsaOp) f: ty/SsaFunction args: (List String) k: Int64 a: String -> (Option (Pair Int64 (Pair ty/SsaFunction (List String))))
  (match (closureOf st defs a)
    ((none) (none))
    ((some lc) (if (and (not (clash? (pairSecond lc) (splice args k (list))))
                        (and (or (not (opaque? f.name)) (listAll? (fn [(c String)] -> Bool (immediate? defs c)) (pairSecond lc))) (and (loops? st (list) f.name k) (accepts? st (list) f.name k (pairFirst lc)))))
                 (some (pair k lc))
                 (none))))

fn firstSite st: Spec defs: (Map String ty/SsaOp) f: ty/SsaFunction args: (List String) -> (Option (Pair Int64 (Pair ty/SsaFunction (List String))))
  (fold (fn [(acc (Option (Pair Int64 (Pair ty/SsaFunction (List String))))) (e (Pair Int64 String))] -> (Option (Pair Int64 (Pair ty/SsaFunction (List String))))
          (match acc ((some _) acc) ((none) (siteAt st defs f args (pairFirst e) (pairSecond e)))))
        (none) (enumerate args))

; (:m :do "a closure call on a closure the function builds becomes a direct call only inside a clone, where the clone rebuilt its closure parameter; elsewhere a local closure call keeps its trampoline")
fn rewriteOnce st: Spec defs: (Map String ty/SsaOp) local: Bool ins: ty/SsaInstr -> (Option (Pair Spec ty/SsaInstr))
  (match ins.op
    ((ty/opCallClosure c args)
      (match (if local (closureOf st defs c) (none))
        ((none) (none))
        ((some lc) (let [(l (pairFirst lc))]
                     (if (and (valTy? ins.ty) (and (= (listLength args) (listLength l.params)) (not (clash? (pairSecond lc) args))))
                       (some (pair (ensureDirect st l) (ty/ssaInstr ins.dest ins.ty (ty/opCall (directCallee l) (listAppend (pairSecond lc) args)))))
                       (none))))))
    ((ty/opCall callee args)
      (match (mapGet st.fns callee)
        ((none) (none))
        ((some f) (if (or (not (arityOk? st callee args)) (>= st.count (cloneLimit)))
                    (none)
                    (match (firstSite st defs f args)
                      ((none) (none))
                      ((some site) (let [(k (pairFirst site)) (l (pairFirst (pairSecond site))) (caps (pairSecond (pairSecond site)))]
                                     (some (pair (ensureClone st f k l) (ty/ssaInstr ins.dest ins.ty (ty/opCall (cloneName f.name k l.name) (splice args k caps))))))))))))
    (_ (none)))

fn rewriteInstr st: Spec defs: (Map String ty/SsaOp) local: Bool ins: ty/SsaInstr fuel: Int64 -> (Pair Spec ty/SsaInstr)
  (if (<= fuel 0)
    (pair st ins)
    (match (rewriteOnce st defs local ins)
      ((none) (pair st ins))
      ((some r) (rewriteInstr (pairFirst r) defs local (pairSecond r) (- fuel 1)))))

fn useSet blocks: (List ty/SsaBlock) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
          (fold (fn [(a (Map String Bool)) (x String)] -> (Map String Bool) (mapSet a x true))
                (fold (fn [(a (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool)
                        (fold (fn [(a2 (Map String Bool)) (x String)] -> (Map String Bool) (mapSet a2 x true)) a (ty/opOperands ins.op)))
                      acc b.instrs)
                (termOperands b.term)))
        (mapEmpty) blocks)

fn closure? op: ty/SsaOp -> Bool
  (match op ((ty/opMakeClosure _ _) true) (_ false))

; (:m :do "a closure nothing reads any more is not built: building one has no effect beyond its allocation")
fn dropDeadClosures blocks: (List ty/SsaBlock) rounds: Int64 -> (List ty/SsaBlock)
  (let [(uses (useSet blocks))
        (next (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
                     (ty/ssaBlock b.label b.params (filter (fn [(ins ty/SsaInstr)] -> Bool (or (not (closure? ins.op)) (mapHas? uses ins.dest))) b.instrs) b.term))
                   blocks))]
    (if (or (<= rounds 0) (= next blocks)) next (dropDeadClosures next (- rounds 1))))

fn scanBlock st: Spec defs: (Map String ty/SsaOp) local: Bool b: ty/SsaBlock -> (Pair Spec ty/SsaBlock)
  (let [(r (fold (fn [(acc (Pair Spec (List ty/SsaInstr))) (ins ty/SsaInstr)] -> (Pair Spec (List ty/SsaInstr))
                   (let [(x (rewriteInstr (pairFirst acc) defs local ins 8))]
                     (pair (pairFirst x) (cons (pairSecond x) (pairSecond acc)))))
                 (pair st (list)) b.instrs))]
    (pair (pairFirst r) (ty/ssaBlock b.label b.params (listReverse (pairSecond r)) b.term)))

fn clone? name: String -> Bool
  (stringContains? name "$cs")

; (:m :do "every rewrite needs a closure the function builds itself, so a function that builds none is passed over")
fn buildsClosure? f: ty/SsaFunction -> Bool
  (listAny? (fn [(b ty/SsaBlock)] -> Bool (listAny? (fn [(ins ty/SsaInstr)] -> Bool (closure? ins.op)) b.instrs)) f.blocks)

fn scanFunction st: Spec name: String -> Spec
  (match (mapGet st.fns name)
    ((none) st)
    ((some f) (if (not (buildsClosure? f)) st (let [(defs (defsOf f))
                    (r (fold (fn [(acc (Pair Spec (List ty/SsaBlock))) (b ty/SsaBlock)] -> (Pair Spec (List ty/SsaBlock))
                               (let [(x (scanBlock (pairFirst acc) defs (clone? name) b))]
                                 (pair (pairFirst x) (cons (pairSecond x) (pairSecond acc)))))
                             (pair st (list)) f.blocks))
                    (blocks (dropDeadClosures (listReverse (pairSecond r)) 8))]
                (if (= blocks f.blocks)
                  (pairFirst r)
                  (withFn (pairFirst r) name (ty/ssaFunction f.name f.captures f.params f.retTy blocks)))))))

fn drain st: Spec names: (List String) rounds: Int64 -> Spec
  (if (or (<= rounds 0) (listEmpty? names))
    st
    (let [(st1 (fold scanFunction (Spec :fns st.fns :added st.added :fresh (list) :count st.count :lambdas st.lambdas) names))]
      (drain st1 (listReverse st1.fresh) (- rounds 1))))

fn referenced fs: (List ty/SsaFunction) globals: (List ty/SsaGlobal) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (f ty/SsaFunction)] -> (Map String Bool)
          (fold (fn [(a (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
                  (fold (fn [(a2 (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool)
                          (match ins.op
                            ((ty/opCall c _) (mapSet a2 c true))
                            ((ty/opMakeClosure c _) (mapSet a2 c true))
                            (_ a2)))
                        a b.instrs))
                acc f.blocks))
        (fold (fn [(acc (Map String Bool)) (g ty/SsaGlobal)] -> (Map String Bool) (mapSet acc g.init true)) (mapEmpty) globals)
        fs)

; (:m :do "the module with every specialisable call rewritten and the clones and direct lambdas appended; a lambda whose every closure was replaced by direct calls is dropped")
fn specializeClosures m: ty/SsaModule -> ty/SsaModule
  (let [(names (map (fn [(f ty/SsaFunction)] -> String f.name) m.functions))
        (st0 (Spec :fns (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (mapSet acc f.name f)) (mapEmpty) m.functions)
                   :added (list) :fresh (list) :count 0 :lambdas (mapEmpty)))
        (st (drain st0 names 32))
        (all (listFlatMap (fn [(n String)] -> (List ty/SsaFunction) (match (mapGet st.fns n) ((some f) (list f)) ((none) (list))))
                          (listAppend names (listReverse st.added))))
        (used (referenced all m.globals))]
    (with m :functions (filter (fn [(f ty/SsaFunction)] -> Bool (or (not (mapHas? st.lambdas f.name)) (mapHas? used f.name))) all)))
