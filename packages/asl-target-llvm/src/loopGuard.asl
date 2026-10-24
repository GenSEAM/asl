(module asl-target-llvm/loopGuard
  :x [guardLoops checkedName kernelName]
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
  (if (or (!= (listLength f.blocks) 4) (or (not (listEmpty? f.captures)) (or (!= (ty/ssaTyName f.retTy) "i64") (stringEndsWith? f.name "$lgChecked"))))
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
  (with m :functions (listFlatMap (fn [(f ty/SsaFunction)] -> (List ty/SsaFunction) (optionOr (versions m f) (list f))) m.functions))
