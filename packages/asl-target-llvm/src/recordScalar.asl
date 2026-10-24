(module asl-target-llvm/recordScalar
  :x [scalarizeRecords scalarizeFunction workerName]
  :i [(asl-ir/types :a ty)])

; (:m :ref RECSROA :do "scalar replacement of a record parameter threaded through self calls: when its only uses are field reads, the same position of self calls, returns and edges into a block that only returns it, and some self call passes a fresh record of its schema, the function becomes a wrapper that reads the fields once and a worker that takes one parameter per field, raw when every producer boxes the same raw type, so the loop allocates no record; a return of the record rebuilds it once on exit")
schema Plan
  index: Int64
  param: String
  schema: String
  recTy: ty/SsaTy
  fields: (List String)
  kinds: (List ty/SsaTy)
  names: (List String)
  tag: String
  worker: String

fn workerName name: String -> String
  (str name "$sr")

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)

fn defsOf f: ty/SsaFunction -> (Map String ty/SsaOp)
  (fold (fn [(acc (Map String ty/SsaOp)) (ins ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet acc ins.dest ins.op)) (mapEmpty) (instrsOf f))

fn noteParams acc: (Map String ty/SsaTy) ps: (List ty/SsaParam) -> (Map String ty/SsaTy)
  (fold (fn [(a (Map String ty/SsaTy)) (p ty/SsaParam)] -> (Map String ty/SsaTy) (mapSet a p.name p.ty)) acc ps)

fn typesOf f: ty/SsaFunction -> (Map String ty/SsaTy)
  (let [(params (noteParams (noteParams (mapEmpty) f.captures) f.params))
        (blocks (fold (fn [(acc (Map String ty/SsaTy)) (b ty/SsaBlock)] -> (Map String ty/SsaTy) (noteParams acc b.params)) params f.blocks))]
    (fold (fn [(acc (Map String ty/SsaTy)) (ins ty/SsaInstr)] -> (Map String ty/SsaTy) (mapSet acc ins.dest ins.ty)) blocks (instrsOf f)))

fn edgeArgs t: ty/SsaTerm -> (List String)
  (listFlatMap (fn [(e ty/SsaEdge)] -> (List String) e.args) (ty/termEdges t))

; (:m :do "operands a terminator reads other than through an edge; a returned value is listed apart because a return is an exit use")
fn termScalars t: ty/SsaTerm -> (List String)
  (match t
    ((ty/termBranch c _ _) (list c))
    ((ty/termSwitch s _ _ _) (list s))
    (_ (list)))

fn termOperands t: ty/SsaTerm -> (List String)
  (listAppend (match t ((ty/termReturn v) (list v)) (_ (termScalars t))) (edgeArgs t))

fn namesOf f: ty/SsaFunction -> (Map String Bool)
  (let [(params (fold (fn [(acc (Map String Bool)) (p ty/SsaParam)] -> (Map String Bool) (mapSet acc p.name true)) (mapEmpty) (listAppend f.captures f.params)))]
    (fold (fn [(acc (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
            (fold (fn [(a (Map String Bool)) (ins ty/SsaInstr)] -> (Map String Bool) (mapSet a ins.dest true))
                  (fold (fn [(a (Map String Bool)) (p ty/SsaParam)] -> (Map String Bool) (mapSet a p.name true)) acc b.params)
                  b.instrs))
          params f.blocks))

fn blockNamed f: ty/SsaFunction label: String -> (Option ty/SsaBlock)
  (listFind (fn [(b ty/SsaBlock)] -> Bool (= b.label label)) f.blocks)

; (:m :do "a block parameter that its block only returns, so a record passed into it leaves the function there")
fn returnOnly? f: ty/SsaFunction label: String i: Int64 -> Bool
  (match (blockNamed f label)
    ((none) false)
    ((some b) (match (listGet b.params i)
                ((none) false)
                ((some q) (and (match b.term ((ty/termReturn v) (= v q.name)) (_ false))
                               (not (listAny? (fn [(ins ty/SsaInstr)] -> Bool (listContains? (ty/opOperands ins.op) q.name)) b.instrs)))))))

fn edgeOk? f: ty/SsaFunction p: String e: ty/SsaEdge -> Bool
  (listAll? (fn [(a (Pair Int64 String))] -> Bool (or (!= (pairSecond a) p) (returnOnly? f e.target (pairFirst a)))) (enumerate e.args))

fn termOk? f: ty/SsaFunction p: String t: ty/SsaTerm -> Bool
  (and (not (listContains? (termScalars t) p))
       (listAll? (fn [(e ty/SsaEdge)] -> Bool (edgeOk? f p e)) (ty/termEdges t)))

fn allSome xs: (List (Option String)) -> (Option (List String))
  (match (fold (fn [(acc (Option (List String))) (x (Option String))] -> (Option (List String))
                 (match acc ((none) (none)) ((some ys) (match x ((none) (none)) ((some y) (some (cons y ys)))))))
               (some (list)) xs)
    ((none) (none))
    ((some ys) (some (listReverse ys))))

; (:m :do "the field values, in declared order, of a fresh record of the schema that defines v")
fn producerValues defs: (Map String ty/SsaOp) schema: String fields: (List String) v: String -> (Option (List String))
  (match (mapGet defs v)
    ((none) (none))
    ((some op) (match op
                 ((ty/opRecord s fs vals)
                   (if (and (= s schema) (= (listLength fs) (listLength fields)))
                     (allSome (map (fn [(j String)] -> (Option String) (match (listIndexOf fs j) ((some i) (listGet vals i)) ((none) (none)))) fields))
                     (none)))
                 (_ (none)))))

fn selfArgs f: ty/SsaFunction ins: ty/SsaInstr -> (Option (List String))
  (match ins.op
    ((ty/opCall callee args) (if (and (= callee f.name) (= (listLength args) (listLength f.params))) (some args) (none)))
    (_ (none)))

; (:m :do "every read of p is a declared field read, the same position of a self call that passes p itself or a fresh record of the schema, or an exit use; anything else (stored, captured, passed elsewhere, compared) keeps the record")
fn instrOk? f: ty/SsaFunction k: Int64 p: String fields: (List String) defs: (Map String ty/SsaOp) schema: String ins: ty/SsaInstr -> Bool
  (match ins.op
    ((ty/opField base j) (or (!= base p) (listContains? fields j)))
    (_ (match (selfArgs f ins)
         ((some args) (listAll? (fn [(a (Pair Int64 String))] -> Bool
                                  (if (= (pairFirst a) k)
                                    (or (= (pairSecond a) p) (some? (producerValues defs schema fields (pairSecond a))))
                                    (!= (pairSecond a) p)))
                                (enumerate args)))
         ((none) (not (listContains? (ty/opOperands ins.op) p))))))

fn producers f: ty/SsaFunction k: Int64 p: String defs: (Map String ty/SsaOp) schema: String fields: (List String) -> (List (List String))
  (listFlatMap (fn [(ins ty/SsaInstr)] -> (List (List String))
                 (match (selfArgs f ins)
                   ((none) (list))
                   ((some args) (match (listGet args k)
                                  ((none) (list))
                                  ((some a) (if (= a p) (list)
                                              (match (producerValues defs schema fields a) ((some vs) (list vs)) ((none) (list)))))))))
               (instrsOf f))

fn classicRaw? t: ty/SsaTy -> Bool
  (listContains? (list "i64" "f64" "i1") (ty/ssaTyName t))

; (:m :do "none: the producer passes field j of p back unchanged; some raw: it boxes a raw value of that type; some val: anything else")
fn valueKind defs: (Map String ty/SsaOp) types: (Map String ty/SsaTy) p: String j: String x: String -> (Option ty/SsaTy)
  (match (mapGet defs x)
    ((none) (some (ty/tyVal)))
    ((some op) (match op
                 ((ty/opField b j2) (if (and (= b p) (= j2 j)) (none) (some (ty/tyVal))))
                 ((ty/opBox y) (match (mapGet types y)
                                 ((some t) (if (classicRaw? t) (some t) (some (ty/tyVal))))
                                 ((none) (some (ty/tyVal)))))
                 (_ (some (ty/tyVal))))))

fn combineKind a: (Option ty/SsaTy) b: (Option ty/SsaTy) -> (Option ty/SsaTy)
  (match a
    ((none) b)
    ((some ta) (match b
                 ((none) a)
                 ((some tb) (if (= (ty/ssaTyName ta) (ty/ssaTyName tb)) a (some (ty/tyVal)))))))

fn fieldKind defs: (Map String ty/SsaOp) types: (Map String ty/SsaTy) p: String prods: (List (List String)) i: Int64 j: String -> ty/SsaTy
  (optionOr (fold (fn [(acc (Option ty/SsaTy)) (vs (List String))] -> (Option ty/SsaTy)
                    (combineKind acc (valueKind defs types p j (optionOr (listGet vs i) ""))))
                  (none) prods)
            (ty/tyVal))

fn recordFields records: (List ty/SsaRecordDecl) schema: String -> (Option (List String))
  (match (listFind (fn [(r ty/SsaRecordDecl)] -> Bool (= r.name schema)) records)
    ((none) (none))
    ((some r) (some r.fields)))

fn planAt records: (List ty/SsaRecordDecl) taken: (Map String Bool) depth: Int64 f: ty/SsaFunction k: Int64 -> (Option Plan)
  (match (listGet f.params k)
    ((none) (none))
    ((some p) (match p.ty
                ((ty/tyRec schema) (match (recordFields records schema)
                                     ((none) (none))
                                     ((some fields) (planChecked f k p.name p.ty schema fields depth taken))))
                (_ (none)))))

fn planChecked f: ty/SsaFunction k: Int64 p: String recTy: ty/SsaTy schema: String fields: (List String) depth: Int64 taken: (Map String Bool) -> (Option Plan)
  (let [(defs (defsOf f))
        (tag (str "sr" (stringFromInt64 depth)))
        (names (map (fn [(j String)] -> String (str tag "." j)) fields))
        (worker (workerName f.name))
        (used (namesOf f))]
    (if (not (and (listAll? (fn [(b ty/SsaBlock)] -> Bool (and (listAll? (fn [(ins ty/SsaInstr)] -> Bool (instrOk? f k p fields defs schema ins)) b.instrs) (termOk? f p b.term))) f.blocks)
                  (and (not (mapHas? taken worker))
                       (not (listAny? (fn [(n String)] -> Bool (stringStartsWith? n tag)) (mapKeys used))))))
      (none)
      (let [(prods (producers f k p defs schema fields))
            (types (typesOf f))]
        (if (listEmpty? prods)
          (none)
          (some (Plan :index k :param p :schema schema :recTy recTy :fields fields
                      :kinds (map (fn [(e (Pair Int64 String))] -> ty/SsaTy (fieldKind defs types p prods (pairFirst e) (pairSecond e))) (enumerate fields))
                      :names names :tag tag :worker worker))))))

fn firstPlan records: (List ty/SsaRecordDecl) taken: (Map String Bool) depth: Int64 f: ty/SsaFunction -> (Option Plan)
  (if (not (listEmpty? f.captures))
    (none)
    (fold (fn [(acc (Option Plan)) (k Int64)] -> (Option Plan)
            (match acc ((some _) acc) ((none) (planAt records taken depth f k))))
          (none) (range 0 (listLength f.params))))

fn renamed ren: (Map String String) x: String -> String
  (optionOr (mapGet ren x) x)

fn renameOp ren: (Map String String) op: ty/SsaOp -> ty/SsaOp
  (let [(r (fn [(x String)] -> String (renamed ren x)))
        (rs (fn [(xs (List String))] -> (List String) (map (fn [(x String)] -> String (renamed ren x)) xs)))]
    (match op
      ((ty/opCall c args) (ty/opCall c (rs args)))
      ((ty/opBuiltin n args) (ty/opBuiltin n (rs args)))
      ((ty/opEntry n args) (ty/opEntry n (rs args)))
      ((ty/opCallClosure c args) (ty/opCallClosure (r c) (rs args)))
      ((ty/opMakeClosure c caps) (ty/opMakeClosure c (rs caps)))
      ((ty/opConstruct t v fs) (ty/opConstruct t v (rs fs)))
      ((ty/opRecord s fs vals) (ty/opRecord s fs (rs vals)))
      ((ty/opField b j) (ty/opField (r b) j))
      ((ty/opVariantField b i) (ty/opVariantField (r b) i))
      ((ty/opList items) (ty/opList (rs items)))
      ((ty/opBox v) (ty/opBox (r v)))
      ((ty/opUnbox v) (ty/opUnbox (r v)))
      ((ty/opPrim n args) (ty/opPrim n (rs args)))
      (_ op)))

fn renameEdge ren: (Map String String) e: ty/SsaEdge -> ty/SsaEdge
  (ty/ssaEdge e.target (map (fn [(x String)] -> String (renamed ren x)) e.args))

fn renameTerm ren: (Map String String) t: ty/SsaTerm -> ty/SsaTerm
  (match t
    ((ty/termReturn v) (ty/termReturn (renamed ren v)))
    ((ty/termJump e) (ty/termJump (renameEdge ren e)))
    ((ty/termBranch c a b) (ty/termBranch (renamed ren c) (renameEdge ren a) (renameEdge ren b)))
    ((ty/termSwitch s n cases d) (ty/termSwitch (renamed ren s) n
                                   (map (fn [(c ty/SsaCase)] -> ty/SsaCase (ty/ssaCase c.variant (renameEdge ren c.edge))) cases)
                                   (match d ((some e) (some (renameEdge ren e))) ((none) (none)))))
    (_ t))

fn fieldIndex plan: Plan j: String -> Int64
  (optionOr (listIndexOf plan.fields j) -1)

fn kindAt plan: Plan i: Int64 -> ty/SsaTy
  (optionOr (listGet plan.kinds i) (ty/tyVal))

fn nameAt plan: Plan i: Int64 -> String
  (optionOr (listGet plan.names i) "")

fn rawAt? plan: Plan i: Int64 -> Bool
  (classicRaw? (kindAt plan i))

; (:m :do "the worker field parameter an unbox of a raw field read of p yields directly")
fn unboxedField plan: Plan defs: (Map String ty/SsaOp) ins: ty/SsaInstr -> (Option String)
  (match ins.op
    ((ty/opUnbox d) (match (mapGet defs d)
                      ((some op) (match op
                                   ((ty/opField b j) (let [(i (fieldIndex plan j))]
                                                       (if (and (= b plan.param) (and (rawAt? plan i) (= (ty/ssaTyName (kindAt plan i)) (ty/ssaTyName ins.ty)))) (some (nameAt plan i)) (none))))
                                   (_ (none))))
                      ((none) (none))))
    (_ (none)))

; (:m :do "field reads of p that stay Val alias the worker parameter; raw ones rebox it, which clang folds into the unbox that follows")
fn fieldRenames plan: Plan f: ty/SsaFunction -> (Map String String)
  (let [(defs (defsOf f))]
    (fold (fn [(acc (Map String String)) (ins ty/SsaInstr)] -> (Map String String)
            (match (unboxedField plan defs ins)
              ((some n) (mapSet acc ins.dest n))
              ((none) (match ins.op
                        ((ty/opField b j) (if (and (= b plan.param) (not (rawAt? plan (fieldIndex plan j)))) (mapSet acc ins.dest (nameAt plan (fieldIndex plan j))) acc))
                        (_ acc)))))
          (mapEmpty) (instrsOf f)))

fn producerArg plan: Plan defs: (Map String ty/SsaOp) i: Int64 x: String -> String
  (match (mapGet defs x)
    ((none) x)
    ((some op) (match op
                 ((ty/opField b j) (if (and (= b plan.param) (= (fieldIndex plan j) i)) (nameAt plan i) x))
                 ((ty/opBox y) (if (rawAt? plan i) y x))
                 (_ x))))

fn fieldArgs plan: Plan defs: (Map String ty/SsaOp) a: String -> (List String)
  (if (= a plan.param)
    plan.names
    (map (fn [(e (Pair Int64 String))] -> String (producerArg plan defs (pairFirst e) (pairSecond e)))
         (enumerate (optionOr (producerValues defs plan.schema plan.fields a) (list)))))

fn spliceArgs plan: Plan args: (List String) fieldVals: (List String) -> (List String)
  (listAppend (listTake args plan.index) (listAppend fieldVals (listDrop args (+ plan.index 1))))

fn rewriteInstr plan: Plan f: ty/SsaFunction defs: (Map String ty/SsaOp) ins: ty/SsaInstr -> (List ty/SsaInstr)
  (match ins.op
    ((ty/opField b j) (if (!= b plan.param)
                        (list ins)
                        (if (rawAt? plan (fieldIndex plan j))
                          (list (ty/ssaInstr ins.dest ins.ty (ty/opBox (nameAt plan (fieldIndex plan j)))))
                          (list))))
    (_ (match (selfArgs f ins)
         ((none) (if (some? (unboxedField plan defs ins)) (list) (list ins)))
         ((some args) (list (ty/ssaInstr ins.dest ins.ty
                              (ty/opCall plan.worker (spliceArgs plan args (fieldArgs plan defs (optionOr (listGet args plan.index) ""))))))))))

; (:m :do "a block that returns p or passes it to a return-only parameter rebuilds the record once, on the exit path")
fn rebuild plan: Plan label: String -> (Pair (List ty/SsaInstr) String)
  (let [(prefix (str plan.tag ".exit." label "."))
        (boxes (listFlatMap (fn [(i Int64)] -> (List ty/SsaInstr)
                              (if (rawAt? plan i) (list (ty/ssaInstr (str prefix (nameAt plan i)) (ty/tyVal) (ty/opBox (nameAt plan i)))) (list)))
                            (range 0 (listLength plan.fields))))
        (vals (map (fn [(i Int64)] -> String (if (rawAt? plan i) (str prefix (nameAt plan i)) (nameAt plan i))) (range 0 (listLength plan.fields))))
        (dest (str prefix "rec"))]
    (pair (listAppend boxes (list (ty/ssaInstr dest plan.recTy (ty/opRecord plan.schema plan.fields vals)))) dest))

fn rewriteBlock plan: Plan f: ty/SsaFunction defs: (Map String ty/SsaOp) b: ty/SsaBlock -> ty/SsaBlock
  (let [(instrs (listFlatMap (fn [(ins ty/SsaInstr)] -> (List ty/SsaInstr) (rewriteInstr plan f defs ins)) b.instrs))]
    (if (listContains? (termOperands b.term) plan.param)
      (let [(made (rebuild plan b.label))]
        (ty/ssaBlock b.label b.params (listAppend instrs (pairFirst made)) (renameTerm (mapSet (mapEmpty) plan.param (pairSecond made)) b.term)))
      (ty/ssaBlock b.label b.params instrs b.term)))

fn useCounts blocks: (List ty/SsaBlock) -> (Map String Int64)
  (let [(bump (fn [(acc (Map String Int64)) (x String)] -> (Map String Int64) (mapSet acc x (+ (optionOr (mapGet acc x) 0) 1))))]
    (fold (fn [(acc (Map String Int64)) (b ty/SsaBlock)] -> (Map String Int64)
            (fold bump (fold (fn [(a (Map String Int64)) (ins ty/SsaInstr)] -> (Map String Int64) (fold bump a (ty/opOperands ins.op))) acc b.instrs) (termOperands b.term)))
          (mapEmpty) blocks))

fn pureAlloc? op: ty/SsaOp -> Bool
  (match op ((ty/opRecord _ _ _) true) ((ty/opBox _) true) (_ false))

; (:m :do "drop records and boxes the rewrite left unread, so the record the self call used to receive is no longer allocated")
fn dropDead blocks: (List ty/SsaBlock) rounds: Int64 -> (List ty/SsaBlock)
  (let [(uses (useCounts blocks))
        (live? (fn [(ins ty/SsaInstr)] -> Bool (or (not (pureAlloc? ins.op)) (mapHas? uses ins.dest))))
        (next (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock (ty/ssaBlock b.label b.params (filter live? b.instrs) b.term)) blocks))]
    (if (or (<= rounds 0) (= next blocks)) next (dropDead next (- rounds 1))))

fn workerOf plan: Plan f: ty/SsaFunction -> ty/SsaFunction
  (let [(defs (defsOf f))
        (ren (fieldRenames plan f))
        (fieldParams (map (fn [(i Int64)] -> ty/SsaParam (ty/ssaParam (nameAt plan i) (kindAt plan i))) (range 0 (listLength plan.fields))))
        (blocks (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
                       (let [(nb (rewriteBlock plan f defs b))]
                         (ty/ssaBlock nb.label nb.params (map (fn [(ins ty/SsaInstr)] -> ty/SsaInstr (ty/ssaInstr ins.dest ins.ty (renameOp ren ins.op))) nb.instrs) (renameTerm ren nb.term))))
                     f.blocks))]
    (ty/ssaFunction plan.worker f.captures
      (listAppend (listTake f.params plan.index) (listAppend fieldParams (listDrop f.params (+ plan.index 1))))
      f.retTy (dropDead blocks 4)))

fn wrapperOf plan: Plan f: ty/SsaFunction -> ty/SsaFunction
  (let [(prefix (str plan.tag ".in."))
        (reads (listFlatMap (fn [(i Int64)] -> (List ty/SsaInstr)
                              (let [(j (optionOr (listGet plan.fields i) ""))
                                    (v (ty/ssaInstr (str prefix j) (ty/tyVal) (ty/opField plan.param j)))]
                                (if (rawAt? plan i) (list v (ty/ssaInstr (str prefix j ".raw") (kindAt plan i) (ty/opUnbox (str prefix j)))) (list v))))
                            (range 0 (listLength plan.fields))))
        (vals (map (fn [(i Int64)] -> String (let [(j (optionOr (listGet plan.fields i) ""))] (if (rawAt? plan i) (str prefix j ".raw") (str prefix j)))) (range 0 (listLength plan.fields))))
        (args (spliceArgs plan (map (fn [(p ty/SsaParam)] -> String p.name) f.params) vals))
        (dest (str prefix "call"))]
    (ty/ssaFunction f.name f.captures f.params f.retTy
      (list (ty/ssaBlock "entry" (list) (listAppend reads (list (ty/ssaInstr dest f.retTy (ty/opCall plan.worker args)))) (ty/termReturn dest)))))

fn scalarizeFunction records: (List ty/SsaRecordDecl) taken: (Map String Bool) depth: Int64 f: ty/SsaFunction -> (List ty/SsaFunction)
  (if (> depth 7)
    (list f)
    (match (firstPlan records taken depth f)
      ((none) (list f))
      ((some plan) (cons (wrapperOf plan f) (scalarizeFunction records (mapSet taken plan.worker true) (+ depth 1) (workerOf plan f))))))

fn scalarizeRecords m: ty/SsaModule -> ty/SsaModule
  (if (listEmpty? m.records)
    m
    (let [(taken (fold (fn [(acc (Map String Bool)) (f ty/SsaFunction)] -> (Map String Bool) (mapSet acc f.name true)) (mapEmpty) m.functions))]
      (with m :functions (listFlatMap (fn [(f ty/SsaFunction)] -> (List ty/SsaFunction) (scalarizeFunction m.records taken 0 f)) m.functions))))
