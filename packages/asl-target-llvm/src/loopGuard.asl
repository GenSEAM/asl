(module asl-target-llvm/loopGuard
  :x [guardLoops checkedName kernelName fastName slowName]
  :i [(asl-ir/types :a ty)])

; (:m :ref LOOPGUARD :do "loop versioning of counted sum loops: a self tail loop f(.. i .. n .. buf .. acc ..) that returns acc at (= i n) and otherwise calls itself with i+1 and acc plus bytesGet buf i (or i64ArrayGet buf i over the whole array) gets one entry check that proves every read in [i, n) inside buf and no partial sum outside int64; then a loop with neither check runs, which clang vectorizes; otherwise the original loop runs unchanged as f$lgChecked, so every trap fires at the same element with the same error (D154: checks are moved, never removed)")
schema Shape
  kind: String
  index: String
  bound: String
  buf: String
  acc: String

fn checkedName name: String -> String
  (str name "$lgChecked")

; (:m :do "the i64 kernel is named under the arrays prefix so the RC pass keeps it opaque, as it keeps the array kernels it reads like")
fn kernelName name: String -> String
  (str "asl-target-llvm/arrays.i64SumGuard$lg$" name)

fn defsOf instrs: (List ty/SsaInstr) -> (Map String ty/SsaOp)
  (fold (fn [(acc (Map String ty/SsaOp)) (ins ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet acc ins.dest ins.op)) (mapEmpty) instrs)

fn paramNames f: ty/SsaFunction -> (List String)
  (map (fn [(p ty/SsaParam)] -> String p.name) f.params)

fn paramTy f: ty/SsaFunction name: String -> String
  (fold (fn [(acc String) (p ty/SsaParam)] -> String (if (= p.name name) (ty/ssaTyName p.ty) acc)) "" f.params)

fn blockOf f: ty/SsaFunction label: String -> (Option ty/SsaBlock)
  (listHead (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label label)) f.blocks))

fn plainEdge? e: ty/SsaEdge -> Bool
  (listEmpty? e.args)

fn constOne? defs: (Map String ty/SsaOp) v: String -> Bool
  (match (mapGet defs v)
    ((some op) (match op ((ty/opConst c) (match c ((ty/constInt n) (= n 1)) (_ false))) (_ false)))
    ((none) false))

fn constUnit? defs: (Map String ty/SsaOp) v: String -> Bool
  (match (mapGet defs v)
    ((some op) (match op ((ty/opConst c) (match c ((ty/constUnit) true) (_ false))) (_ false)))
    ((none) false))

fn checkedAdd? name: String -> Bool
  (or (= name "addIntHost") (= name "addInt"))

; (:m :do "the other operand when v is a checked Int add of x and something")
fn addend defs: (Map String ty/SsaOp) v: String x: String -> (Option String)
  (match (mapGet defs v)
    ((some op) (match op
                 ((ty/opPrim name args) (if (and (checkedAdd? name) (= (listLength args) 2))
                                          (let [(a (optionOr (listGet args 0) "")) (b (optionOr (listGet args 1) ""))]
                                            (cond ((= a x) (some b)) ((= b x) (some a)) (else (none))))
                                          (none)))
                 (_ (none))))
    ((none) (none)))

fn callOf defs: (Map String ty/SsaOp) v: String -> (Option (Pair String (List String)))
  (match (mapGet defs v)
    ((some op) (match op ((ty/opCall callee args) (some (pair callee args))) (_ (none))))
    ((none) (none)))

fn boxOf? defs: (Map String ty/SsaOp) v: String i: String -> Bool
  (match (mapGet defs v)
    ((some op) (match op ((ty/opBox x) (= x i)) (_ false)))
    ((none) false))

fn arg xs: (List String) k: Int64 -> String
  (optionOr (listGet xs k) "")

fn dedup xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

; (:m :do "the whole-array i64ArrayGet buf (box i) unit unit that g is, with the dests it uses")
fn wholeGet defs: (Map String ty/SsaOp) g: String buf: String i: String -> (Option (List String))
  (match (callOf defs g)
    ((none) (none))
    ((some c) (let [(args (pairSecond c))]
                (if (and (= (pairFirst c) "asl-target-llvm/arrays.i64ArrayGet")
                         (and (= (listLength args) 4)
                              (and (= (arg args 0) buf) (and (boxOf? defs (arg args 1) i) (and (constUnit? defs (arg args 2)) (constUnit? defs (arg args 3)))))))
                  (some (dedup (list g (arg args 1) (arg args 2) (arg args 3))))
                  (none)))))

; (:m :do "the kind of the element read x of buf at i and the dests it uses: bytesGet buf i, or the unboxed whole-array i64ArrayGet buf (box i) unit unit")
fn elementRead defs: (Map String ty/SsaOp) x: String buf: String i: String -> (Option (Pair String (List String)))
  (match (mapGet defs x)
    ((none) (none))
    ((some op)
      (match op
        ((ty/opEntry name args) (if (and (= name "bytesGet") (= args (list buf i))) (some (pair "bytes" (list x))) (none)))
        ((ty/opUnbox g) (match (wholeGet defs g buf i) ((some used) (some (pair "i64" (cons x used)))) ((none) (none))))
        (_ (none)))))

fn firstBlock f: ty/SsaFunction -> ty/SsaBlock
  (optionOr (listHead f.blocks) (ty/ssaBlock "" (list) (list) (ty/termUnreachable)))

fn emptyBlock -> ty/SsaBlock
  (ty/ssaBlock "" (list) (list) (ty/termUnreachable))

fn jumpOf t: ty/SsaTerm -> (Option ty/SsaEdge)
  (match t ((ty/termJump e) (some e)) (_ (none)))

; (:m :do "the shape of f when it is exactly the counted sum loop: entry (= i n) or (= n i) branching to a block that passes acc to the join and one computing only i+1, the element, acc plus the element and the self call, every other argument of which is its own parameter; the join returns its one parameter")
fn loopShape f: ty/SsaFunction -> (Option Shape)
  (if (or (!= (listLength f.blocks) 4) (or (not (listEmpty? f.captures)) (or (!= (ty/ssaTyName f.retTy) "i64") (or (stringEndsWith? f.name "$lgChecked") (stringContains? f.name "$av")))))
    (none)
    (let [(entry (firstBlock f))]
      (match entry.term
        ((ty/termBranch c thenE elseE)
          (let [(thenB (optionOr (blockOf f thenE.target) (emptyBlock)))
                (elseB (optionOr (blockOf f elseE.target) (emptyBlock)))]
            (if (and (plainEdge? thenE) (and (plainEdge? elseE) (and (!= thenB.label "") (and (!= elseB.label "") (and (listEmpty? thenB.params) (listEmpty? elseB.params))))))
              (shapeOf f entry thenB elseB c)
              (none))))
        (_ (none)))))

fn shapeOf f: ty/SsaFunction entry: ty/SsaBlock thenB: ty/SsaBlock elseB: ty/SsaBlock c: String -> (Option Shape)
  (match (jumpOf thenB.term)
         ((none) (none))
         ((some accE) (match (jumpOf elseB.term)
                        ((none) (none))
                        ((some resE)
                          (let [(joinB (optionOr (blockOf f accE.target) (emptyBlock)))]
                            (if (and (= (listLength entry.instrs) 1) (and (listEmpty? thenB.instrs) (and (= accE.target resE.target)
                                     (and (joinReturns? joinB) (and (= (listLength accE.args) 1) (= (listLength resE.args) 1))))))
                              (let [(cmpI (optionOr (listHead entry.instrs) (ty/ssaInstr "" (ty/tyI1) (ty/opConst (ty/constBool false)))))]
                                (match cmpI.op
                                  ((ty/opPrim name args)
                                    (if (and (= name "eqInt") (and (= cmpI.dest c) (= (listLength args) 2)))
                                      (bodyShape f elseB (arg args 0) (arg args 1) (arg accE.args 0) (arg resE.args 0))
                                      (none)))
                                  (_ (none))))
                              (none)))))))

fn joinReturns? b: ty/SsaBlock -> Bool
  (and (= (listLength b.params) 1)
       (and (listEmpty? b.instrs)
            (match b.term
              ((ty/termReturn v) (match (listHead b.params) ((some p) (= p.name v)) ((none) false)))
              (_ false))))

fn bodyShape f: ty/SsaFunction elseB: ty/SsaBlock x: String y: String acc: String r: String -> (Option Shape)
  (let [(defs (defsOf elseB.instrs))
        (names (paramNames f))]
    (match (callOf defs r)
      ((none) (none))
      ((some c)
        (if (or (!= (pairFirst c) f.name) (!= (listLength (pairSecond c)) (listLength names)))
          (none)
          (let [(moved (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) (pairSecond p))) (zip names (pairSecond c))))]
            (if (!= (listLength moved) 2)
              (none)
              (let [(m1 (optionOr (listGet moved 0) (pair "" ""))) (m2 (optionOr (listGet moved 1) (pair "" "")))]
                (orShape (movedShape f defs elseB x y acc r m1 m2) (movedShape f defs elseB x y acc r m2 m1)))))))))

fn orShape a: (Option Shape) b: (Option Shape) -> (Option Shape)
  (match a ((some s) (some s)) ((none) b))

; (:m :do "mi moves the index parameter to i+1 and ma the acc parameter to acc plus an element read of an unmoved Val parameter at the index; the bound is the other operand of the entry compare, an unmoved Int parameter")
fn movedShape f: ty/SsaFunction defs: (Map String ty/SsaOp) elseB: ty/SsaBlock x: String y: String acc: String r: String mi: (Pair String String) ma: (Pair String String) -> (Option Shape)
  (let [(i (pairFirst mi)) (a (pairFirst ma))
        (n (cond ((= x i) y) ((= y i) x) (else "")))]
    (if (or (!= a acc) (or (= n "") (or (= n i) (or (= n a) (or (not (listContains? (paramNames f) n))
            (or (!= (paramTy f i) "i64") (or (!= (paramTy f n) "i64") (!= (paramTy f a) "i64"))))))))
      (none)
      (match (addend defs (pairSecond mi) i)
        ((none) (none))
        ((some one)
          (match (addend defs (pairSecond ma) a)
            ((none) (none))
            ((some el)
              (if (not (constOne? defs one))
                (none)
                (let [(bufs (filter (fn [(p ty/SsaParam)] -> Bool (and (= (ty/ssaTyName p.ty) "val") (not (listContains? (list i n a) p.name)))) f.params))
                      (found (fold (fn [(acc0 (Option (Pair String (Pair String (List String))))) (p ty/SsaParam)] -> (Option (Pair String (Pair String (List String))))
                                     (match acc0
                                       ((some s) (some s))
                                       ((none) (match (elementRead defs el p.name i) ((some k) (some (pair p.name k))) ((none) (none))))))
                                   (none) bufs))]
                  (match found
                    ((none) (none))
                    ((some hit)
                      (let [(used (dedup (listAppend (list one (pairSecond mi) (pairSecond ma) r) (pairSecond (pairSecond hit)))))]
                        (if (= (listLength used) (listLength elseB.instrs))
                          (some (Shape :kind (pairFirst (pairSecond hit)) :index i :bound n :buf (pairFirst hit) :acc a))
                          (none)))))))))))))


fn ins d: String t: ty/SsaTy op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr d t op)

fn kInt d: String v: Int64 -> ty/SsaInstr
  (ins d (ty/tyI64) (ty/opConst (ty/constInt v)))

fn prim d: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ins d t (ty/opPrim name args))

fn edge target: String args: (List String) -> ty/SsaEdge
  (ty/ssaEdge target args)

fn jumpTo target: String args: (List String) -> ty/SsaTerm
  (ty/termJump (edge target args))

fn branchTo c: String yes: String yesArgs: (List String) no: String noArgs: (List String) -> ty/SsaTerm
  (ty/termBranch c (edge yes yesArgs) (edge no noArgs))

fn blk label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn pblk label: String params: (List ty/SsaParam) instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label params instrs term)

fn pI name: String -> ty/SsaParam
  (ty/ssaParam name (ty/tyI64))

fn i64Max -> Int64
  9223372036854775807

fn i64Min -> Int64
  (- (- 0 (i64Max)) 1)

; (:m :do "the original loop under its checked name, calling itself")
fn checkedCopy f: ty/SsaFunction -> ty/SsaFunction
  (let [(cn (checkedName f.name))]
    (ty/ssaFunction cn f.captures f.params f.retTy
      (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
             (ty/ssaBlock b.label b.params
               (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr
                      (match i.op ((ty/opCall callee args) (if (= callee f.name) (ins i.dest i.ty (ty/opCall cn args)) i)) (_ i)))
                    b.instrs)
               b.term))
           f.blocks)))

; (:m :do "blocks every version shares: the empty loop returns acc; an index below 0 or above the bound runs the checked loop, which fails or walks as before")
fn commonBlocks f: ty/SsaFunction s: Shape next: String -> (List ty/SsaBlock)
  (list (blk "entry" (list (prim "lg.empty" (ty/tyI1) "eqInt" (list s.index s.bound))) (branchTo "lg.empty" "lg.ret" (list s.acc) "lg.range" (list)))
        (pblk "lg.ret" (list (pI "lg.result")) (list) (ty/termReturn "lg.result"))
        (blk "lg.range" (list (kInt "lg.zero" 0) (prim "lg.neg" (ty/tyI1) "ltInt" (list s.index "lg.zero")) (prim "lg.behind" (ty/tyI1) "gtInt" (list s.index s.bound))
                              (prim "lg.out" (ty/tyI1) "orBool" (list "lg.neg" "lg.behind")))
          (branchTo "lg.out" "lg.slow" (list) next (list)))
        (blk "lg.slow" (list (ins "lg.checked" (ty/tyI64) (ty/opCall (checkedName f.name) (paramNames f)))) (ty/termReturn "lg.checked")))

; (:m :do "Bytes: the first read runs checked, so a wrong value or an index past the end fails as the loop's first step does; with n <= length every read is inside, and as each byte is at most 255, acc + 255 (n - i) inside int64 means no partial sum leaves it")
fn bytesBlocks f: ty/SsaFunction s: Shape -> (List ty/SsaBlock)
  (listAppend (commonBlocks f s "lg.probe")
    (list (blk "lg.probe" (list (ins "lg.first" (ty/tyI64) (ty/opEntry "bytesGet" (list s.buf s.index))) (ins "lg.len" (ty/tyI64) (ty/opEntry "bytesLength" (list s.buf)))
                                (prim "lg.past" (ty/tyI1) "gtInt" (list s.bound "lg.len")))
            (branchTo "lg.past" "lg.slow" (list) "lg.room" (list)))
          (blk "lg.room" (list (prim "lg.rem" (ty/tyI64) "rawSubI64" (list s.bound s.index)) (kInt "lg.zero2" 0) (prim "lg.pos" (ty/tyI1) "geInt" (list s.acc "lg.zero2")))
            (branchTo "lg.pos" "lg.headPos" (list) "lg.headNeg" (list)))
          (blk "lg.headPos" (list (kInt "lg.max" (i64Max)) (prim "lg.head" (ty/tyI64) "rawSubI64" (list "lg.max" s.acc))) (jumpTo "lg.cap" (list "lg.head")))
          (blk "lg.headNeg" (list (kInt "lg.max2" (i64Max))) (jumpTo "lg.cap" (list "lg.max2")))
          (pblk "lg.cap" (list (pI "lg.room")) (list (kInt "lg.k255" 255) (prim "lg.lim" (ty/tyI64) "quotInt" (list "lg.room" "lg.k255")) (prim "lg.fits" (ty/tyI1) "leInt" (list "lg.rem" "lg.lim")))
            (branchTo "lg.fits" "lg.loop" (list s.index s.acc) "lg.slow" (list)))
          (pblk "lg.loop" (list (pI "lg.i") (pI "lg.a")) (list (prim "lg.done" (ty/tyI1) "eqInt" (list "lg.i" s.bound)))
            (branchTo "lg.done" "lg.ret" (list "lg.a") "lg.body" (list)))
          (blk "lg.body" (list (ins "lg.x" (ty/tyI64) (ty/opEntry "bytesGet" (list s.buf "lg.i"))) (prim "lg.a2" (ty/tyI64) "rawAddI64" (list "lg.a" "lg.x"))
                               (kInt "lg.one" 1) (prim "lg.i2" (ty/tyI64) "rawAddI64" (list "lg.i" "lg.one")))
            (jumpTo "lg.loop" (list "lg.i2" "lg.a2")))))

; (:m :do "I64Array: the first read runs checked as the loop's first step does; the kernel then proves n <= length, sums wrapping while it ORs each element's magnitude, and returns acc plus the sum when |acc| < 2^61, n - i < 2^61 and (n - i) times the magnitude bound < 2^61, so no partial sum leaves int64 and the result lies inside (-2^62, 2^62); otherwise INT64_MIN, which no accepted result can be, and the checked loop runs")
fn i64Blocks f: ty/SsaFunction s: Shape -> (List ty/SsaBlock)
  (listAppend (commonBlocks f s "lg.probe")
    (list (blk "lg.probe" (list (ins "lg.bi" (ty/tyVal) (ty/opBox s.index)) (ins "lg.unit" (ty/tyVal) (ty/opConst (ty/constUnit)))
                                (ins "lg.first" (ty/tyVal) (ty/opCall "asl-target-llvm/arrays.i64ArrayGet" (list s.buf "lg.bi" "lg.unit" "lg.unit")))
                                (ins "lg.fast" (ty/tyI64) (ty/opCall (kernelName f.name) (list s.index s.bound s.buf s.acc)))
                                (kInt "lg.min" (i64Min)) (prim "lg.refused" (ty/tyI1) "eqInt" (list "lg.fast" "lg.min")))
            (branchTo "lg.refused" "lg.slow" (list) "lg.ret" (list "lg.fast")))))

fn word1 d: String v: String -> (List ty/SsaInstr)
  (list (ins (str d ".p") (ty/tyPtr) (ty/opCall "aslArrWord1" (list v))) (prim d (ty/tyI64) "rawPtrToInt" (list (str d ".p"))))

fn load d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (list (prim (str d ".p") (ty/tyPtr) "rawIntToPtr" (list addr)) (kInt (str d ".o") off) (prim d (ty/tyI64) "rawLoadI64" (list (str d ".p") (str d ".o"))))

; (:m :do "the kernel the I64Array version calls after its checked first read: i in [0, n) and buf an I64Array are known there")
fn kernel f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction (kernelName f.name) (list) (list (pI "i") (pI "n") (ty/ssaParam "a" (ty/tyVal)) (pI "acc")) (ty/tyI64)
    (list (blk "entry" (listAppend (word1 "obj" "a") (listAppend (load "len" "obj" 8) (list (prim "past" (ty/tyI1) "gtInt" (list "n" "len")))))
            (branchTo "past" "no" (list) "data" (list)))
          (blk "no" (list (kInt "refused" (i64Min))) (ty/termReturn "refused"))
          (blk "data" (listAppend (load "dw" "obj" 24) (list (prim "d" (ty/tyPtr) "rawIntToPtr" (list "dw")) (kInt "z" 0))) (jumpTo "loop" (list "i" "z" "z")))
          (pblk "loop" (list (pI "fi") (pI "fs") (pI "fm")) (list (prim "end" (ty/tyI1) "geInt" (list "fi" "n"))) (branchTo "end" "fin" (list) "body" (list)))
          (blk "body" (list (kInt "k8" 8) (prim "off" (ty/tyI64) "rawMulI64" (list "fi" "k8")) (prim "v" (ty/tyI64) "rawLoadI64" (list "d" "off"))
                            (prim "fs2" (ty/tyI64) "rawAddI64" (list "fs" "v")) (kInt "k63" 63) (prim "sg" (ty/tyI64) "rawAshrI64" (list "v" "k63"))
                            (prim "mag" (ty/tyI64) "rawXorI64" (list "v" "sg")) (prim "fm2" (ty/tyI64) "rawOrI64" (list "fm" "mag"))
                            (kInt "k1" 1) (prim "fi2" (ty/tyI64) "rawAddI64" (list "fi" "k1")))
            (jumpTo "loop" (list "fi2" "fs2" "fm2")))
          (blk "fin" (list (prim "rem" (ty/tyI64) "rawSubI64" (list "n" "i")) (kInt "lim" 2305843009213693952) (kInt "f63" 63)
                           (prim "asg" (ty/tyI64) "rawAshrI64" (list "acc" "f63")) (prim "amag" (ty/tyI64) "rawXorI64" (list "acc" "asg"))
                           (prim "accOk" (ty/tyI1) "ltInt" (list "amag" "lim")) (prim "remOk" (ty/tyI1) "ltInt" (list "rem" "lim"))
                           (prim "per" (ty/tyI64) "quotInt" (list "lim" "rem")) (prim "magOk" (ty/tyI1) "ltInt" (list "fm" "per"))
                           (prim "ok0" (ty/tyI1) "andBool" (list "accOk" "remOk")) (prim "ok" (ty/tyI1) "andBool" (list "ok0" "magOk")))
            (branchTo "ok" "yes" (list) "no" (list)))
          (blk "yes" (list (prim "t" (ty/tyI64) "rawAddI64" (list "acc" "fs"))) (ty/termReturn "t"))))

fn hasExtern? m: ty/SsaModule name: String -> Bool
  (listAny? (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs)

fn hasFunction? m: ty/SsaModule name: String -> Bool
  (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name name)) m.functions)

; (:m :do "the functions that replace f: the guarded entry, the checked loop, and for I64Array the kernel; none when f is not the loop, its names are taken, or the I64Array kernel would lack the arrays helpers")
fn versions m: ty/SsaModule f: ty/SsaFunction -> (Option (List ty/SsaFunction))
  (match (loopShape f)
    ((none) (none))
    ((some s)
      (cond
        ((hasFunction? m (checkedName f.name)) (none))
        ((= s.kind "bytes") (some (list (ty/ssaFunction f.name f.captures f.params f.retTy (bytesBlocks f s)) (checkedCopy f))))
        ((and (hasExtern? m "aslArrWord1") (not (hasFunction? m (kernelName f.name))))
          (some (list (ty/ssaFunction f.name f.captures f.params f.retTy (i64Blocks f s)) (checkedCopy f) (kernel f))))
        (else (none)))))

fn guardLoops m: ty/SsaModule -> ty/SsaModule
  (let [(guarded (listFlatMap (fn [(f ty/SsaFunction)] -> (List ty/SsaFunction) (optionOr (versions m f) (list f))) m.functions))
        (m2 (with m :functions guarded))]
    (with m2 :functions (listFlatMap (fn [(f ty/SsaFunction)] -> (List ty/SsaFunction) (optionOr (arithVersions m2 f) (list f))) guarded)))

; (:m :ref ARITHVER :do "bench note: the fused ring rounds versioned raw are closed-formed by clang (about 0.035 instructions per element at 4M and 40M), so the bench/native ring instruction ratio after FUSION + ARITHVER (0.77) is closedForm, startup-dominated: startup against startup, not a loop speedup")
; (:m :ref ARITHVER :do "range versioning of checked Int arithmetic in self loops: f(.. i .. n ..) whose entry tests (= i n), whose self calls (none reachable from the equal branch) all pass i+1 and n unchanged. Under H, every Int parameter of f other than accumulators within +-2^40 and i <= n, each value in f gets a compile-time interval; a checked add, sub or mul whose interval stays within +-2^61 cannot overflow. A moved parameter stays under H when every self call passes it a value inside +-2^40 (by induction over the calls); an accumulator, passed itself or itself plus a value e of known bound M, stays inside +-2^62 when |acc| <= 2^61 and n - i <= 2^61 / M at entry, since the call depth is at most n - i. f becomes an entry check of H and those bounds: when it holds f$avFast runs, the loop with those operations raw; otherwise f$avChecked, the loop as it was, so every trap fires at the same step with the same error. A loop is versioned only when every checked operation in it runs raw: with some left checked the raw ones save about one instruction per step and cost a second copy of the body, which on bench/native/array cost the clang inlining of i64ArrayGet (2.06x -> 3.19x)")
schema Iv
  known: Bool
  lo: Int64
  hi: Int64

schema ArithPlan
  index: String
  bound: String
  held: (List String)
  accs: (List (Pair String Int64))
  raw: (List String)

fn ivCap -> Int64
  2305843009213693952

fn ivHeld -> Int64
  1099511627776

fn ivTop -> Iv
  (Iv :known false :lo 0 :hi 0)

fn ivOf lo: Int64 hi: Int64 -> Iv
  (if (and (>= lo (- 0 (ivCap))) (<= hi (ivCap))) (Iv :known true :lo lo :hi hi) (ivTop))

fn ivMag a: Iv -> Int64
  (max (if (< a.lo 0) (- 0 a.lo) a.lo) (if (< a.hi 0) (- 0 a.hi) a.hi))

fn ivAdd a: Iv b: Iv -> Iv
  (if (and a.known b.known) (ivOf (+ a.lo b.lo) (+ a.hi b.hi)) (ivTop))

fn ivSub a: Iv b: Iv -> Iv
  (if (and a.known b.known) (ivOf (- a.lo b.hi) (- a.hi b.lo)) (ivTop))

fn ivMul a: Iv b: Iv -> Iv
  (cond
    ((not (and a.known b.known)) (ivTop))
    ((and (> (ivMag a) 0) (> (ivMag b) (/ (ivCap) (ivMag a)))) (ivTop))
    (else (let [(ps (list (* a.lo b.lo) (* a.lo b.hi) (* a.hi b.lo) (* a.hi b.hi)))]
            (ivOf (fold (fn [(x Int64) (y Int64)] -> Int64 (min x y)) (* a.lo b.lo) ps) (fold (fn [(x Int64) (y Int64)] -> Int64 (max x y)) (* a.lo b.lo) ps)))))

; (:m :do "a floored mod by a positive divisor is in [0, hi-1]; by any other nonzero divisor its magnitude is below the divisor's")
fn ivMod a: Iv b: Iv -> Iv
  (cond
    ((not b.known) (ivTop))
    ((> b.lo 0) (ivOf 0 (- b.hi 1)))
    ((= (ivMag b) 0) (ivTop))
    (else (ivOf (- 1 (ivMag b)) (- (ivMag b) 1))))

fn ivHull a: Iv b: Iv -> Iv
  (if (and a.known b.known) (ivOf (min a.lo b.lo) (max a.hi b.hi)) (ivTop))

fn ivWithin? a: Iv lim: Int64 -> Bool
  (and a.known (and (>= a.lo (- 0 lim)) (<= a.hi lim)))

fn ivGet env: (Map String Iv) v: String -> Iv
  (optionOr (mapGet env v) (ivTop))

fn arg2 args: (List String) env: (Map String Iv) k: Int64 -> Iv
  (ivGet env (arg args k))

fn rawOf name: String -> String
  (cond ((= name "addIntHost") "rawAddI64") ((= name "subIntHost") "rawSubI64") ((= name "mulIntHost") "rawMulI64") (else ""))

fn ivOp env: (Map String Iv) defs: (Map String ty/SsaOp) op: ty/SsaOp -> Iv
  (match op
    ((ty/opConst c) (match c ((ty/constInt k) (ivOf k k)) (_ (ivTop))))
    ((ty/opPrim name args)
      (cond
        ((= name "addIntHost") (ivAdd (arg2 args env 0) (arg2 args env 1)))
        ((= name "subIntHost") (ivSub (arg2 args env 0) (arg2 args env 1)))
        ((= name "mulIntHost") (ivMul (arg2 args env 0) (arg2 args env 1)))
        ((= name "modIntHost") (ivMod (arg2 args env 0) (arg2 args env 1)))
        (else (ivTop))))
    ((ty/opUnbox v) (match (mapGet defs v) ((some d) (match d ((ty/opBox x) (ivGet env x)) (_ (ivTop)))) ((none) (ivTop))))
    (_ (ivTop)))

fn allDefs f: ty/SsaFunction -> (Map String ty/SsaOp)
  (fold (fn [(acc (Map String ty/SsaOp)) (b ty/SsaBlock)] -> (Map String ty/SsaOp) (fold (fn [(a (Map String ty/SsaOp)) (i ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet a i.dest i.op)) acc b.instrs))
        (mapEmpty) f.blocks)

; (:m :do "the interval of every Int value of f given its parameters' intervals: instructions in block order, a block parameter the hull of what every edge into it passes (top while an edge's value is not yet known), two passes")
fn ivBlocks f: ty/SsaFunction defs: (Map String ty/SsaOp) env: (Map String Iv) -> (Map String Iv)
  (fold (fn [(e (Map String Iv)) (b ty/SsaBlock)] -> (Map String Iv)
          (let [(withParams (fold (fn [(e2 (Map String Iv)) (k Int64)] -> (Map String Iv)
                                    (let [(p (optionOr (listGet b.params k) (ty/ssaParam "" (ty/tyVal))))
                                          (ins (listFlatMap (fn [(c ty/SsaBlock)] -> (List String)
                                                              (listFlatMap (fn [(ed ty/SsaEdge)] -> (List String) (if (= ed.target b.label) (list (arg ed.args k)) (list))) (ty/termEdges c.term)))
                                                            f.blocks))]
                                      (if (or (listEmpty? ins) (!= (ty/ssaTyName p.ty) "i64"))
                                        e2
                                        (mapSet e2 p.name (fold (fn [(acc Iv) (v String)] -> Iv (ivHull acc (ivGet e2 v))) (ivGet e2 (arg ins 0)) ins)))))
                                  e (range 0 (listLength b.params))))]
            (fold (fn [(e3 (Map String Iv)) (i ty/SsaInstr)] -> (Map String Iv) (if (= (ty/ssaTyName i.ty) "i64") (mapSet e3 i.dest (ivOp e3 defs i.op)) e3)) withParams b.instrs)))
        env f.blocks)

fn selfCalls f: ty/SsaFunction -> (List (List String))
  (listFlatMap (fn [(b ty/SsaBlock)] -> (List (List String))
                 (listFlatMap (fn [(i ty/SsaInstr)] -> (List (List String)) (match i.op ((ty/opCall c args) (if (= c f.name) (list args) (list))) (_ (list)))) b.instrs))
               f.blocks)

fn reachFrom f: ty/SsaFunction todo: (List String) seen: (List String) fuel: Int64 -> (List String)
  (match (listHead todo)
    ((none) seen)
    ((some l) (if (or (<= fuel 0) (listContains? seen l))
                (reachFrom f (listDrop todo 1) seen (- fuel 1))
                (match (blockOf f l)
                  ((none) (reachFrom f (listDrop todo 1) seen (- fuel 1)))
                  ((some b) (reachFrom f (listAppend (map (fn [(e ty/SsaEdge)] -> String e.target) (ty/termEdges b.term)) (listDrop todo 1)) (cons l seen) (- fuel 1)))))))

fn callsSelf? f: ty/SsaFunction b: ty/SsaBlock -> Bool
  (listAny? (fn [(i ty/SsaInstr)] -> Bool (match i.op ((ty/opCall c _) (= c f.name)) (_ false))) b.instrs)

fn indexOf names: (List String) x: String -> Int64
  (optionOr (listIndexOf names x) -1)

fn stepsByOne? defs: (Map String ty/SsaOp) v: String i: String -> Bool
  (match (addend defs v i) ((some one) (constOne? defs one)) ((none) false))

; (:m :do "the induction pair (i, n) of f: the entry block's compare, n passed unchanged and i as i+1 by every self call, and no self call reachable from the equal branch or in the entry block")
fn inductionOf f: ty/SsaFunction defs: (Map String ty/SsaOp) -> (Option (Pair String String))
  (let [(entry (firstBlock f)) (names (paramNames f)) (calls (selfCalls f))]
    (match entry.term
      ((ty/termBranch c thenE _)
        (match (mapGet (defsOf entry.instrs) c)
          ((some op)
            (match op
              ((ty/opPrim name args)
                (let [(x (arg args 0)) (y (arg args 1))
                      (fits (fn [(i String) (n String)] -> Bool
                              (let [(ki (indexOf names i)) (kn (indexOf names n))]
                                (and (>= ki 0) (and (>= kn 0) (and (!= i n) (and (= (paramTy f i) "i64") (and (= (paramTy f n) "i64")
                                     (listAll? (fn [(a (List String))] -> Bool (and (= (arg a kn) n) (stepsByOne? defs (arg a ki) i))) calls)))))))))
                      (equal (reachFrom f (list thenE.target) (list) 10000))]
                  (cond
                    ((or (!= name "eqInt") (listEmpty? calls)) (none))
                    ((callsSelf? f entry) (none))
                    ((listAny? (fn [(b ty/SsaBlock)] -> Bool (and (listContains? equal b.label) (callsSelf? f b))) f.blocks) (none))
                    ((fits x y) (some (pair x y)))
                    ((fits y x) (some (pair y x)))
                    (else (none)))))
              (_ (none))))
          ((none) (none))))
      (_ (none))))

fn heldEnv names: (List String) -> (Map String Iv)
  (fold (fn [(e (Map String Iv)) (p String)] -> (Map String Iv) (mapSet e p (ivOf (- 0 (ivHeld)) (ivHeld)))) (mapEmpty) names)

fn argsAt calls: (List (List String)) k: Int64 -> (List String)
  (map (fn [(a (List String))] -> String (arg a k)) calls)

; (:m :do "the parameters that stay under H: start from every Int parameter and drop each one some self call may pass a value outside +-2^40, until none is dropped; i stays, as i <= n and every call that passes i+1 has i != n")
fn heldParams f: ty/SsaFunction defs: (Map String ty/SsaOp) i: String held: (List String) fuel: Int64 -> (List String)
  (let [(env (ivBlocks f defs (ivBlocks f defs (heldEnv held))))
        (calls (selfCalls f)) (names (paramNames f))
        (kept (filter (fn [(p String)] -> Bool (or (= p i) (listAll? (fn [(v String)] -> Bool (or (= v p) (ivWithin? (ivGet env v) (ivHeld)))) (argsAt calls (indexOf names p))))) held))]
    (if (or (<= fuel 0) (= (listLength kept) (listLength held))) kept (heldParams f defs i kept (- fuel 1))))

; (:m :do "an accumulator p: every self call passes p itself or a checked add of p and a value of known interval, whose magnitude bound it returns (at least 1)")
fn accBound f: ty/SsaFunction defs: (Map String ty/SsaOp) env: (Map String Iv) p: String -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (v String)] -> (Option Int64)
          (match acc
            ((none) (none))
            ((some m) (if (= v p) (some m)
                        (match (addend defs v p)
                          ((none) (none))
                          ((some e) (let [(r (ivGet env e))] (if (and r.known (!= e p)) (some (max m (ivMag r))) (none)))))))))
        (some 1) (argsAt (selfCalls f) (indexOf (paramNames f) p)))

fn accAdds f: ty/SsaFunction p: String -> (List String)
  (filter (fn [(v String)] -> Bool (!= v p)) (argsAt (selfCalls f) (indexOf (paramNames f) p)))

fn arithPlan f: ty/SsaFunction -> (Option ArithPlan)
  (if (or (not (listEmpty? f.captures)) (or (stringContains? f.name "$av") (stringStartsWith? f.name "asl-target-llvm/arrays.")))
    (none)
    (let [(defs (allDefs f))]
      (match (inductionOf f defs)
        ((none) (none))
        ((some ind)
          (let [(ints (map (fn [(p ty/SsaParam)] -> String p.name) (filter (fn [(p ty/SsaParam)] -> Bool (= (ty/ssaTyName p.ty) "i64")) f.params)))
                (held (heldParams f defs (pairFirst ind) ints (listLength ints)))
                (env0 (ivBlocks f defs (ivBlocks f defs (heldEnv held))))
                (accs (listFlatMap (fn [(p String)] -> (List (Pair String Int64)) (if (listContains? held p) (list) (match (accBound f defs env0 p) ((some m) (list (pair p m))) ((none) (list))))) ints))
                (accOps (listFlatMap (fn [(a (Pair String Int64))] -> (List String) (accAdds f (pairFirst a))) accs))
                (checked (filter (fn [(i ty/SsaInstr)] -> Bool (match i.op ((ty/opPrim n _) (!= (rawOf n) "")) (_ false))) (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)))
                (raw (map (fn [(i ty/SsaInstr)] -> String i.dest) (filter (fn [(i ty/SsaInstr)] -> Bool (or (listContains? accOps i.dest) (ivWithin? (ivGet env0 i.dest) (ivCap)))) checked)))]
            (if (or (or (listEmpty? raw) (!= (listLength raw) (listLength checked))) (not (and (listContains? held (pairFirst ind)) (listContains? held (pairSecond ind)))))
              (none)
              (some (ArithPlan :index (pairFirst ind) :bound (pairSecond ind) :held held :accs accs :raw raw))))))))

fn fastName name: String -> String
  (str name "$avFast")

fn slowName name: String -> String
  (str name "$avChecked")

fn renamedLoop f: ty/SsaFunction name: String raw: (List String) -> ty/SsaFunction
  (ty/ssaFunction name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params
             (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr
                    (match i.op
                      ((ty/opCall c args) (if (= c f.name) (ins i.dest i.ty (ty/opCall name args)) i))
                      ((ty/opPrim n args) (if (listContains? raw i.dest) (ins i.dest i.ty (ty/opPrim (rawOf n) args)) i))
                      (_ i)))
                  b.instrs)
             b.term))
         f.blocks))

fn rangeChecks v: String lim: Int64 k: Int64 -> (List ty/SsaInstr)
  (let [(p (str "av." k "."))]
    (list (kInt (str p "lo") (- 0 lim)) (kInt (str p "hi") lim)
          (prim (str p "ge") (ty/tyI1) "geInt" (list v (str p "lo"))) (prim (str p "le") (ty/tyI1) "leInt" (list v (str p "hi")))
          (prim (str p "in") (ty/tyI1) "andBool" (list (str p "ge") (str p "le")))))

; (:m :do "the entry check: each held parameter within +-2^40, each accumulator within +-2^61, i <= n, and n - i within 2^61 over the largest accumulator step; all quiet compares on values the checks bound")
fn arithEntry f: ty/SsaFunction s: ArithPlan -> (List ty/SsaBlock)
  (let [(held (map (fn [(k Int64)] -> (List ty/SsaInstr) (rangeChecks (arg s.held k) (ivHeld) k)) (range 0 (listLength s.held))))
        (accs (map (fn [(k Int64)] -> (List ty/SsaInstr) (rangeChecks (pairFirst (optionOr (listGet s.accs k) (pair "" 0))) (ivCap) (+ k (listLength s.held)))) (range 0 (listLength s.accs))))
        (m (fold (fn [(a Int64) (p (Pair String Int64))] -> Int64 (max a (pairSecond p))) 1 s.accs))
        (oks (map (fn [(k Int64)] -> String (str "av." k ".in")) (range 0 (+ (listLength s.held) (listLength s.accs)))))
        (trip (list (prim "av.order" (ty/tyI1) "leInt" (list s.index s.bound)) (prim "av.trip" (ty/tyI64) "rawSubI64" (list s.bound s.index))
                    (kInt "av.limit" (/ (ivCap) m)) (prim "av.short" (ty/tyI1) "leInt" (list "av.trip" "av.limit"))
                    (prim "av.t0" (ty/tyI1) "andBool" (list "av.order" "av.short"))))
        (folded (pairSecond (fold (fn [(acc (Pair String (List ty/SsaInstr))) (k Int64)] -> (Pair String (List ty/SsaInstr))
                                    (let [(d (str "av.all" k))] (pair d (listAppend (pairSecond acc) (list (prim d (ty/tyI1) "andBool" (list (pairFirst acc) (arg oks k))))))))
                                  (pair "av.t0" (list)) (range 0 (listLength oks)))))
        (last (if (listEmpty? oks) "av.t0" (str "av.all" (- (listLength oks) 1))))]
    (list (blk "entry" (listAppend (listFlatMap (fn [(x (List ty/SsaInstr))] -> (List ty/SsaInstr) x) (listAppend held accs)) (listAppend trip folded))
            (branchTo last "av.fast" (list) "av.slow" (list)))
          (blk "av.fast" (list (ins "av.r1" f.retTy (ty/opCall (fastName f.name) (paramNames f)))) (ty/termReturn "av.r1"))
          (blk "av.slow" (list (ins "av.r2" f.retTy (ty/opCall (slowName f.name) (paramNames f)))) (ty/termReturn "av.r2"))))

fn arithVersions m: ty/SsaModule f: ty/SsaFunction -> (Option (List ty/SsaFunction))
  (match (arithPlan f)
    ((none) (none))
    ((some s) (if (or (hasFunction? m (fastName f.name)) (hasFunction? m (slowName f.name)))
                (none)
                (some (list (ty/ssaFunction f.name f.captures f.params f.retTy (arithEntry f s))
                            (renamedLoop f (fastName f.name) s.raw)
                            (renamedLoop f (slowName f.name) (list)))))))
