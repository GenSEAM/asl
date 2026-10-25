(module asl-target-llvm/listFusion
  :x [fuseLists fusedName fused?]
  :i [(asl-ir/types :a ty)])

; (:m :ref FUSION :do "producer/consumer fusion of (C (listReverse (P .. (list) ..)) ..): P is a self tail loop that builds its result list in an accumulator parameter (each step conses one element onto it or passes it on, the base case returns it), so listReverse of it is the elements in the order P made them; C is a self tail left fold over a list parameter (empty case, else head, tail and a self call on the tail). The site becomes one call of a new loop P$fuse that runs P's steps and, where P consed, runs C's step on the element and calls itself, with C on the empty list where P returned its accumulator: the list, its reverse and their cells are never built. The guard: the built list and its reverse each have one use (no escape, consumed once), P and C contain only pure operations, any trap they can raise is of one kind on both sides (so moving C's steps before P's later steps cannot change which error fires), C never stops before the end of its list, and the code between the calls is pure and trap-free")
schema Site
  label: String
  call: String
  cons: String
  elem: String
  args: (List String)

schema Step
  ok: Bool
  site: (Option Site)

schema Producer
  f: ty/SsaFunction
  index: Int64
  sites: (List Site)
  traps: (List String)

schema Consumer
  f: ty/SsaFunction
  index: Int64
  empty: String
  arm: String
  head: String
  tail: String
  nilList: String
  region: (List String)
  traps: (List String)

fn fusedName producer: String index: Int64 consumer: String at: Int64 -> String
  (str producer "$fuse" index "$" consumer "$" at)

fn fused? name: String -> Bool
  (stringContains? name "$fuse")

fn quietPrim? name: String -> Bool
  (listContains? (list "eqBool" "neBool" "eqInt" "neInt" "ltInt" "leInt" "gtInt" "geInt" "negFloat" "addFloat" "subFloat" "mulFloat" "divFloat"
                       "eqFloat" "neFloat" "ltFloat" "leFloat" "gtFloat" "geFloat" "andBool" "orBool" "notBool" "intToFloat"
                       "rawAddI64" "rawSubI64" "rawMulI64" "rawAndI64" "rawOrI64" "rawXorI64" "rawShlI64" "rawLshrI64" "rawAshrI64"
                       "rawAddI32" "rawSubI32" "rawMulI32" "rawAndI32" "rawOrI32" "rawXorI32" "rawShlI32" "rawLshrI32" "rawAshrI32"
                       "rawEqI32" "rawNeI32" "rawLtI32" "rawLeI32" "rawGtI32" "rawGeI32" "rawWidenI32")
                 name)

fn trapPrim? name: String -> Bool
  (listContains? (list "addInt" "subInt" "mulInt" "quotInt" "remInt" "floatToInt" "addIntHost" "subIntHost" "mulIntHost" "divIntHost" "modIntHost" "negIntHost" "rawNarrowI32") name)

; (:m :ref FUSION :do "the errors a trapping primitive can raise, as ssa.asl lowers it: the rterr.int kind of each host check (add 0, sub and neg 1, mul 2, div 3 on INT64_MIN by -1 or 5 on a zero divisor, mod 6, floatToInt 8, narrow 7) and one bare signal for the IR-internal ones")
fn trapCodes name: String -> (List String)
  (cond
    ((= name "addIntHost") (list "0"))
    ((or (= name "subIntHost") (= name "negIntHost")) (list "1"))
    ((= name "mulIntHost") (list "2"))
    ((= name "divIntHost") (list "3" "5"))
    ((= name "modIntHost") (list "6"))
    ((= name "floatToInt") (list "8"))
    ((= name "rawNarrowI32") (list "7"))
    (else (list "signal")))

; (:m :do "the trap kinds an operation can raise, or none when it is not known to be pure: a call, builtin, runtime entry, global read or memory access may have an effect")
fn opTraps op: ty/SsaOp -> (Option (List String))
  (match op
    ((ty/opConst _) (some (list)))
    ((ty/opBox _) (some (list)))
    ((ty/opUnbox _) (some (list)))
    ((ty/opList _) (some (list)))
    ((ty/opConstruct _ _ _) (some (list)))
    ((ty/opRecord _ _ _) (some (list)))
    ((ty/opField _ _) (some (list)))
    ((ty/opVariantField _ _) (some (list)))
    ((ty/opMakeClosure _ _) (some (list)))
    ((ty/opPrim name _) (cond ((quietPrim? name) (some (list))) ((trapPrim? name) (some (trapCodes name))) (else (none))))
    (_ (none)))

fn termOperands t: ty/SsaTerm -> (List String)
  (listAppend
    (match t ((ty/termReturn v) (list v)) ((ty/termBranch c _ _) (list c)) ((ty/termSwitch s _ _ _) (list s)) (_ (list)))
    (listFlatMap (fn [(e ty/SsaEdge)] -> (List String) e.args) (ty/termEdges t)))

fn blockUses b: ty/SsaBlock -> (List String)
  (listAppend (listFlatMap (fn [(ins ty/SsaInstr)] -> (List String) (ty/opOperands ins.op)) b.instrs) (termOperands b.term))

fn usesIn blocks: (List ty/SsaBlock) name: String -> Int64
  (fold (fn [(n Int64) (b ty/SsaBlock)] -> Int64 (+ n (listCount (fn [(x String)] -> Bool (= x name)) (blockUses b)))) 0 blocks)

fn defsOf f: ty/SsaFunction -> (Map String ty/SsaOp)
  (fold (fn [(acc (Map String ty/SsaOp)) (b ty/SsaBlock)] -> (Map String ty/SsaOp)
          (fold (fn [(a (Map String ty/SsaOp)) (ins ty/SsaInstr)] -> (Map String ty/SsaOp) (mapSet a ins.dest ins.op)) acc b.instrs))
        (mapEmpty) f.blocks)

fn blockOf f: ty/SsaFunction label: String -> (Option ty/SsaBlock)
  (listHead (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label label)) f.blocks))

fn lastInstr b: ty/SsaBlock -> (Option ty/SsaInstr)
  (listLast b.instrs)

fn argAt xs: (List String) k: Int64 -> String
  (optionOr (listGet xs k) "")

fn without xs: (List T) k: Int64 -> (List T)
  (listAppend (listTake xs k) (listDrop xs (+ k 1)))

fn inserted xs: (List T) k: Int64 x: T -> (List T)
  (listAppend (listTake xs k) (cons x (listDrop xs k)))

fn paramNames ps: (List ty/SsaParam) -> (List String)
  (map (fn [(p ty/SsaParam)] -> String p.name) ps)

fn nilOp? op: ty/SsaOp -> Bool
  (match op ((ty/opList items) (listEmpty? items)) (_ false))

fn unionAll xs: (List String) ys: (List String) -> (List String)
  (fold (fn [(acc (List String)) (y String)] -> (List String) (if (listContains? acc y) acc (cons y acc))) xs ys)

fn trapsOf instrs: (List ty/SsaInstr) -> (Option (List String))
  (fold (fn [(acc (Option (List String))) (ins ty/SsaInstr)] -> (Option (List String))
          (match acc
            ((none) (none))
            ((some ts) (match (opTraps ins.op) ((none) (none)) ((some more) (some (unionAll ts more)))))))
        (some (list)) instrs)

; (:m :do "a join is a block that only returns its one parameter or passes it on to a join; a function's exits are the values its other blocks return or pass to a join")
fn joinStep b: ty/SsaBlock joins: (List String) -> Bool
  (and (listEmpty? b.instrs)
       (and (= (listLength b.params) 1)
            (let [(p (optionOr (listHead (paramNames b.params)) ""))]
              (match b.term
                ((ty/termReturn v) (= v p))
                ((ty/termJump e) (and (= e.args (list p)) (listContains? joins e.target)))
                (_ false)))))

fn joinsFrom f: ty/SsaFunction joins: (List String) fuel: Int64 -> (List String)
  (let [(next (map (fn [(b ty/SsaBlock)] -> String b.label) (filter (fn [(b ty/SsaBlock)] -> Bool (joinStep b joins)) f.blocks)))]
    (if (or (<= fuel 0) (= (listLength next) (listLength joins))) next (joinsFrom f next (- fuel 1))))

fn joinLabels f: ty/SsaFunction -> (List String)
  (joinsFrom f (list) (listLength f.blocks))

fn exitsOf b: ty/SsaBlock joins: (List String) -> (List String)
  (if (listContains? joins b.label)
    (list)
    (match b.term
      ((ty/termReturn v) (list v))
      (_ (listFlatMap (fn [(e ty/SsaEdge)] -> (List String) (if (listContains? joins e.target) e.args (list))) (ty/termEdges b.term)))))

fn unreachable? b: ty/SsaBlock -> Bool
  (match b.term ((ty/termUnreachable) true) (_ false))

fn selfCall? f: ty/SsaFunction op: ty/SsaOp -> Bool
  (match op ((ty/opCall callee _) (= callee f.name)) (_ false))

fn callArgs op: ty/SsaOp -> (List String)
  (match op ((ty/opCall _ args) args) (_ (list)))

; (:m :do "a producer step: the block ends in a self call whose result is the block's only exit, and the accumulator argument is the parameter itself (a skip) or a cons of one element onto it made in the block and used only there")
fn siteOf f: ty/SsaFunction acc: String a: Int64 joins: (List String) b: ty/SsaBlock -> Step
  (match (lastInstr b)
    ((none) (Step :ok true :site (none)))
    ((some last)
      (if (not (selfCall? f last.op))
        (Step :ok true :site (none))
        (let [(args (callArgs last.op)) (x (argAt args a))
              (defs (defsOf (with f :blocks (list b))))
              (others (without args a))]
          (cond
            ((listContains? others acc) (Step :ok false :site (none)))
            ((!= (exitsOf b joins) (list last.dest)) (Step :ok false :site (none)))
            ((not (match b.term ((ty/termReturn _) true) ((ty/termJump _) true) (_ false))) (Step :ok false :site (none)))
            ((!= (usesIn f.blocks last.dest) 1) (Step :ok false :site (none)))
            ((= x acc) (Step :ok true :site (some (Site :label b.label :call last.dest :cons "" :elem "" :args args))))
            (else (let [(cargs (match (mapGet defs x) ((some op) (entryNamed op "cons")) ((none) (list))))]
                    (if (and (= (argAt cargs 1) acc) (and (= (listLength cargs) 2) (= (usesIn f.blocks x) 1)))
                      (Step :ok true :site (some (Site :label b.label :call last.dest :cons x :elem (argAt cargs 0) :args args)))
                      (Step :ok false :site (none))))))))))

fn collectSites f: ty/SsaFunction acc: String a: Int64 joins: (List String) -> (Option (List Site))
  (fold (fn [(r (Option (List Site))) (b ty/SsaBlock)] -> (Option (List Site))
          (match r
            ((none) (none))
            ((some xs) (let [(st (siteOf f acc a joins b))]
                         (if (not st.ok)
                           (none)
                           (match st.site ((none) (some xs)) ((some s) (some (cons s xs)))))))))
        (some (list)) f.blocks)

fn producerOf f: ty/SsaFunction a: Int64 -> (Option Producer)
  (match (listGet f.params a)
    ((none) (none))
    ((some p)
      (let [(acc p.name) (joins (joinLabels f))]
        (cond
          ((or (not (listEmpty? f.captures)) (or (!= (ty/ssaTyName p.ty) "val") (!= (ty/ssaTyName f.retTy) "val"))) (none))
          ((listAny? unreachable? f.blocks) (none))
          (else
            (match (collectSites f acc a joins)
              ((none) (none))
              ((some sites)
                (let [(calls (map (fn [(s Site)] -> String s.call) sites))
                      (conses (filter (fn [(c String)] -> Bool (not (stringEmpty? c))) (map (fn [(s Site)] -> String s.cons) sites)))
                      (exits (listFlatMap (fn [(b ty/SsaBlock)] -> (List String) (exitsOf b joins)) f.blocks))
                      (accExits (listCount (fn [(v String)] -> Bool (= v acc)) exits))
                      (rest (filter (fn [(ins ty/SsaInstr)] -> Bool (not (or (listContains? calls ins.dest) (listContains? conses ins.dest))))
                                    (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)))]
                  (cond
                    ((listEmpty? conses) (none))
                    ((not (listAll? (fn [(v String)] -> Bool (or (= v acc) (listContains? calls v))) exits)) (none))
                    ((< accExits 1) (none))
                    ((listAny? (fn [(b ty/SsaBlock)] -> Bool (and (> (usesIn (list (ty/ssaBlock b.label (list) (list) b.term)) acc) 0)
                                                                  (not (match b.term ((ty/termReturn _) true) ((ty/termJump _) true) (_ false)))))
                               f.blocks)
                      (none))
                    ((!= (usesIn f.blocks acc) (+ accExits (listLength sites))) (none))
                    (else (match (trapsOf rest)
                            ((none) (none))
                            ((some ts) (some (Producer :f f :index a :sites sites :traps ts))))))))))))))

fn reach f: ty/SsaFunction todo: (List String) seen: (List String) fuel: Int64 -> (List String)
  (match (listHead todo)
    ((none) seen)
    ((some l) (if (or (listContains? seen l) (<= fuel 0))
                (reach f (listDrop todo 1) seen (- fuel 1))
                (match (blockOf f l)
                  ((none) (reach f (listDrop todo 1) seen (- fuel 1)))
                  ((some b) (reach f (listAppend (map (fn [(e ty/SsaEdge)] -> String e.target) (ty/termEdges b.term)) (listDrop todo 1)) (cons l seen) (- fuel 1)))))))

fn findEntry instrs: (List ty/SsaInstr) name: String -> (Option ty/SsaInstr)
  (listHead (filter (fn [(ins ty/SsaInstr)] -> Bool (match ins.op ((ty/opEntry n _) (= n name)) (_ false))) instrs))

fn entryArgs op: ty/SsaOp -> (List String)
  (match op ((ty/opEntry _ args) args) (_ (list)))

fn entryNamed op: ty/SsaOp name: String -> (List String)
  (match op ((ty/opEntry n args) (if (= n name) args (list))) (_ (list)))

; (:m :do "a consumer: the entry block only tests its list for empty; the other arm reads the head and the tail and every exit of that arm is a self call on the tail, so C walks to the end of the list and the list parameter is read nowhere else in the arm")
fn consumerOf f: ty/SsaFunction l: Int64 -> (Option Consumer)
  (match (listGet f.params l)
    ((none) (none))
    ((some p)
      (match (listHead f.blocks)
        ((none) (none))
        ((some entry)
          (match (if (= (listLength entry.instrs) 1) (listHead entry.instrs) (none))
            ((none) (none))
            ((some test)
              (match entry.term
                ((ty/termBranch c thenE elseE)
                  (if (or (!= (entryNamed test.op "@listHeadEmpty?") (list p.name)) (or (!= c test.dest) (or (not (listEmpty? thenE.args)) (not (listEmpty? elseE.args)))))
                    (none)
                    (consumerArm f l p.name thenE.target elseE.target)))
                (_ (none)))))))))

fn consumerArm f: ty/SsaFunction l: Int64 items: String empty: String arm: String -> (Option Consumer)
  (let [(region (reach f (list arm) (list) 10000))
        (blocks (filter (fn [(b ty/SsaBlock)] -> Bool (listContains? region b.label)) f.blocks))
        (joins (joinLabels f))]
    (match (blockOf f arm)
      ((none) (none))
      ((some a)
        (match (findEntry a.instrs "@listFirst")
         ((none) (none))
         ((some h)
         (match (findEntry a.instrs "@listTailOr")
          ((none) (none))
          ((some t)
            (let [(ta (entryArgs t.op)) (nilList (argAt ta 1)) (defs (defsOf (with f :blocks (list a))))
                  (calls (filter (fn [(ins ty/SsaInstr)] -> Bool (selfCall? f ins.op)) (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) blocks)))
                  (callDests (map (fn [(ins ty/SsaInstr)] -> String ins.dest) calls))
                  (exits (listFlatMap (fn [(b ty/SsaBlock)] -> (List String) (exitsOf b joins)) blocks))
                  (rest (filter (fn [(ins ty/SsaInstr)] -> Bool (not (or (listContains? callDests ins.dest) (listContains? (list h.dest t.dest nilList) ins.dest))))
                                (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) blocks)))]
              (cond
                ((or (listContains? region (optionOr (optionMap (fn [(b ty/SsaBlock)] -> String b.label) (listHead f.blocks)) "")) (not (listEmpty? a.params))) (none))
                ((or (!= (entryArgs h.op) (list items)) (or (!= (listLength ta) 2) (!= (argAt ta 0) items))) (none))
                ((not (match (mapGet defs nilList) ((some op) (nilOp? op)) ((none) false))) (none))
                ((or (!= (usesIn blocks nilList) 1) (!= (usesIn blocks items) 2)) (none))
                ((listAny? unreachable? blocks) (none))
                ((listAny? (fn [(b ty/SsaBlock)] -> Bool (listAny? (fn [(e ty/SsaEdge)] -> Bool (= e.target arm)) (ty/termEdges b.term))) blocks) (none))
                ((listEmpty? calls) (none))
                ((not (listAll? (fn [(ins ty/SsaInstr)] -> Bool (let [(args (callArgs ins.op))] (and (= (argAt args l) t.dest) (not (listContains? (without args l) t.dest))))) calls)) (none))
                ((!= (usesIn blocks t.dest) (listLength calls)) (none))
                ((not (listAll? (fn [(v String)] -> Bool (listContains? callDests v)) exits)) (none))
                ((not (listAll? (fn [(d String)] -> Bool (= (usesIn blocks d) 1)) callDests)) (none))
                ((not (listAll? (fn [(b ty/SsaBlock)] -> Bool (match (lastInstr b) ((some ins) (if (selfCall? f ins.op) (= (exitsOf b joins) (list ins.dest)) true)) ((none) true))) blocks)) (none))
                ((listAny? (fn [(ins ty/SsaInstr)] -> Bool (and (selfCall? f ins.op) (not (listAny? (fn [(b ty/SsaBlock)] -> Bool (= (optionMap (fn [(x ty/SsaInstr)] -> String x.dest) (lastInstr b)) (some ins.dest))) blocks)))) calls) (none))
                (else (match (trapsOf rest)
                        ((none) (none))
                        ((some ts) (some (Consumer :f f :index l :empty empty :arm arm :head h.dest :tail t.dest :nilList nilList :region region :traps ts))))))))))))))

; (:m :do "running C's step for element j before P's step j+1 instead of after all of P is unobservable when neither side has an effect and they cannot raise two different errors: one side raises none, or the errors both sides can raise together are one kind (a primitive with two, like div, counts both). A P that skips may loop forever after its last cons without allocating, so a C that can trap needs a P that conses at every step")
; (:m :ref FUSION :do "accepted divergence (lead decision 2026-10-25): a P that conses at every step and never ends exhausts memory in the original, while the fused loop allocates nothing and raises C's error at the first element that traps, or runs forever; memory exhaustion is not a specified outcome, and listFusionTest keeps an endless producer whose fused run traps at once")
fn reorderSafe? p: Producer c: Consumer -> Bool
  (cond
    ((listEmpty? c.traps) true)
    ((listAny? (fn [(s Site)] -> Bool (stringEmpty? s.cons)) p.sites) false)
    ((listEmpty? p.traps) true)
    (else (<= (listLength (unionAll p.traps c.traps)) 1)))

fn renameIn rn: (fn [String] -> String) op: ty/SsaOp -> ty/SsaOp
  (match op
    ((ty/opConst v) op)
    ((ty/opCall callee args) (ty/opCall callee (map rn args)))
    ((ty/opBuiltin n args) (ty/opBuiltin n (map rn args)))
    ((ty/opEntry n args) (ty/opEntry n (map rn args)))
    ((ty/opCallClosure c args) (ty/opCallClosure (rn c) (map rn args)))
    ((ty/opMakeClosure callee caps) (ty/opMakeClosure callee (map rn caps)))
    ((ty/opConstruct t v fields) (ty/opConstruct t v (map rn fields)))
    ((ty/opRecord s fields values) (ty/opRecord s fields (map rn values)))
    ((ty/opField b fl) (ty/opField (rn b) fl))
    ((ty/opVariantField b i) (ty/opVariantField (rn b) i))
    ((ty/opList items) (ty/opList (map rn items)))
    ((ty/opGlobal _) op)
    ((ty/opLoadGlobal _) op)
    ((ty/opBox v) (ty/opBox (rn v)))
    ((ty/opUnbox v) (ty/opUnbox (rn v)))
    ((ty/opPrim n args) (ty/opPrim n (map rn args))))

fn renameEdge rn: (fn [String] -> String) rl: (fn [String] -> String) e: ty/SsaEdge -> ty/SsaEdge
  (ty/ssaEdge (rl e.target) (map rn e.args))

fn renameTerm rn: (fn [String] -> String) rl: (fn [String] -> String) t: ty/SsaTerm -> ty/SsaTerm
  (match t
    ((ty/termReturn v) (ty/termReturn (rn v)))
    ((ty/termJump e) (ty/termJump (renameEdge rn rl e)))
    ((ty/termBranch c a b) (ty/termBranch (rn c) (renameEdge rn rl a) (renameEdge rn rl b)))
    ((ty/termSwitch s tn cases d) (ty/termSwitch (rn s) tn (map (fn [(k ty/SsaCase)] -> ty/SsaCase (ty/ssaCase k.variant (renameEdge rn rl k.edge))) cases)
                                    (match d ((some e) (some (renameEdge rn rl e))) ((none) (none)))))
    ((ty/termUnreachable) t))

fn consumerParam name: String -> String
  (str "fc." name)

; (:m :do "C's arm copied for one producer step: values and labels get the step's prefix, C's other parameters become the fused loop's, the head is P's element, the head, tail and nil reads go, and each self call on the tail calls the fused loop with P's next arguments")
fn armCopy p: Producer c: Consumer fname: String s: Site -> (List ty/SsaBlock)
  (let [(pre (str "fz." s.label "."))
        (cparams (paramNames c.f.params))
        (rn (fn [(n String)] -> String (cond ((= n c.head) s.elem) ((listContains? cparams n) (consumerParam n)) (else (str pre n)))))
        (rl (fn [(l String)] -> String (if (= l c.arm) s.label (str pre l))))
        (dropped (list c.head c.tail c.nilList))
        (next (without s.args p.index))
        (instr (fn [(ins ty/SsaInstr)] -> ty/SsaInstr
                 (if (selfCall? c.f ins.op)
                   (ty/ssaInstr (rn ins.dest) ins.ty (ty/opCall fname (listAppend next (map rn (without (callArgs ins.op) c.index)))))
                   (ty/ssaInstr (rn ins.dest) ins.ty (renameIn rn ins.op)))))]
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock (rl b.label) (map (fn [(q ty/SsaParam)] -> ty/SsaParam (ty/ssaParam (rn q.name) q.ty)) b.params)
                        (map instr (filter (fn [(ins ty/SsaInstr)] -> Bool (not (listContains? dropped ins.dest))) b.instrs))
                        (renameTerm rn rl b.term)))
         (filter (fn [(b ty/SsaBlock)] -> Bool (listContains? c.region b.label)) c.f.blocks)))

fn fusedBlock p: Producer c: Consumer fname: String b: ty/SsaBlock -> (List ty/SsaBlock)
  (let [(acc (optionOr (optionMap (fn [(q ty/SsaParam)] -> String q.name) (listGet p.f.params p.index)) ""))
        (cps (map consumerParam (paramNames (without c.f.params c.index))))
        (site (listHead (filter (fn [(s Site)] -> Bool (= s.label b.label)) p.sites)))]
    (cond
      ((listContains? (joinLabels p.f) b.label) (list (ty/ssaBlock b.label (map (fn [(q ty/SsaParam)] -> ty/SsaParam (ty/ssaParam q.name c.f.retTy)) b.params) b.instrs b.term)))
      (else
        (match site
          ((some s)
            (if (stringEmpty? s.cons)
              (list (ty/ssaBlock b.label b.params
                      (map (fn [(ins ty/SsaInstr)] -> ty/SsaInstr (if (= ins.dest s.call) (ty/ssaInstr ins.dest c.f.retTy (ty/opCall fname (listAppend (without s.args p.index) cps))) ins)) b.instrs)
                      b.term))
              (let [(copied (armCopy p c fname s))
                    (head (listHead (filter (fn [(x ty/SsaBlock)] -> Bool (= x.label b.label)) copied)))
                    (keep (filter (fn [(ins ty/SsaInstr)] -> Bool (not (or (= ins.dest s.call) (= ins.dest s.cons)))) b.instrs))]
                (match head
                  ((none) (list b))
                  ((some h) (cons (ty/ssaBlock b.label b.params (listAppend keep h.instrs) h.term)
                                  (filter (fn [(x ty/SsaBlock)] -> Bool (!= x.label b.label)) copied)))))))
          ((none)
            (if (= (usesIn (list (ty/ssaBlock b.label (list) (list) b.term)) acc) 0)
              (list b)
              (let [(e (str "fz.nil." b.label)) (r (str "fz.end." b.label))
                    (rn (fn [(n String)] -> String (if (= n acc) r n)))]
                (list (ty/ssaBlock b.label b.params
                        (listAppend b.instrs (list (ty/ssaInstr e (ty/tyVal) (ty/opList (list)))
                                                   (ty/ssaInstr r c.f.retTy (ty/opCall c.f.name (inserted cps c.index e)))))
                        (renameTerm rn (fn [(l String)] -> String l) b.term))))))))))

fn fusedFunction p: Producer c: Consumer fname: String -> ty/SsaFunction
  (ty/ssaFunction fname (list)
    (listAppend (without p.f.params p.index) (map (fn [(q ty/SsaParam)] -> ty/SsaParam (ty/ssaParam (consumerParam q.name) q.ty)) (without c.f.params c.index)))
    c.f.retTy
    (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaBlock) (fusedBlock p c fname b)) p.f.blocks))

schema Match
  producer: Producer
  consumer: Consumer
  made: String
  reversed: String
  call: String

fn opaqueName? name: String -> Bool
  (or (stringStartsWith? name "asl-target-llvm/arrays.") (stringStartsWith? name "asl-target-llvm/parallel."))

fn reverseOf op: ty/SsaOp -> (Option String)
  (let [(one (fn [(ok Bool) (args (List String))] -> (Option String) (if (and ok (= (listLength args) 1)) (listHead args) (none))))]
    (match op
      ((ty/opCall n args) (one (= n "prelude.listReverse") args))
      ((ty/opBuiltin n args) (one (= n "listReverse") args))
      ((ty/opEntry n args) (one (= n "listReverse") args))
      (_ (none))))

fn findIndex xs: (List ty/SsaInstr) dest: String -> Int64
  (optionOr (listIndexOf (map (fn [(i ty/SsaInstr)] -> String i.dest) xs) dest) -1)

; (:m :do "a fusable site in block b of g: the C call's list argument is a listReverse of a P call made earlier in b, each used once, P's accumulator argument is the empty list, and every instruction between the P call and the C call is pure and cannot trap")
fn siteIn fns: (Map String ty/SsaFunction) g: ty/SsaFunction b: ty/SsaBlock defs: (Map String ty/SsaOp) ins: ty/SsaInstr -> (Option Match)
  (match ins.op
    ((ty/opCall cname cargs)
      (match (mapGet fns cname)
        ((none) (none))
        ((some cf)
          (listHead (listFlatMap (fn [(l Int64)] -> (List Match) (optionToList (siteAt fns g b defs ins cf cargs l))) (range 0 (listLength cargs)))))))
    (_ (none)))

fn optionToList o: (Option T) -> (List T)
  (match o ((some x) (list x)) ((none) (list)))

fn siteAt fns: (Map String ty/SsaFunction) g: ty/SsaFunction b: ty/SsaBlock defs: (Map String ty/SsaOp) ins: ty/SsaInstr cf: ty/SsaFunction cargs: (List String) l: Int64 -> (Option Match)
  (let [(cname cf.name) (r (argAt cargs l))]
    (match (match (mapGet defs r) ((some op) (reverseOf op)) ((none) (none)))
      ((none) (none))
      ((some made)
        (match (match (mapGet defs made) ((some op) (match op ((ty/opCall n xs) (some (pair n xs))) (_ (none)))) ((none) (none)))
          ((some called)
            (let [(pname (pairFirst called)) (pargs (pairSecond called))]
            (match (mapGet fns pname)
              ((none) (none))
              ((some pf)
                (let [(i (findIndex b.instrs made)) (k (findIndex b.instrs ins.dest)) (j (findIndex b.instrs r))
                      (between (filter (fn [(x ty/SsaInstr)] -> Bool (!= x.dest r)) (listTake (listDrop b.instrs (+ i 1)) (- (- k i) 1))))]
                  (cond
                    ((or (= pname cname) (or (= pname g.name) (= cname g.name))) (none))
                    ((or (opaqueName? pname) (opaqueName? cname)) (none))
                    ((or (< i 0) (or (< j i) (< k j))) (none))
                    ((or (!= (usesIn g.blocks made) 1) (!= (usesIn g.blocks r) 1)) (none))
                    ((!= (trapsOf between) (some (list))) (none))
                    (else
                      (match (consumerOf cf l)
                        ((none) (none))
                        ((some c)
                          (let [(all (defsOf g))]
                          (listHead (listFlatMap (fn [(a Int64)] -> (List Match)
                                                   (if (not (match (mapGet all (argAt pargs a)) ((some op) (nilOp? op)) ((none) false)))
                                                     (list)
                                                     (match (producerOf pf a)
                                                       ((none) (list))
                                                       ((some p) (if (reorderSafe? p c) (list (Match :producer p :consumer c :made made :reversed r :call ins.dest)) (list))))))
                                                 (range 0 (listLength pargs))))))))))))))
          ((none) (none))))))

fn rewriteCaller g: ty/SsaFunction b: ty/SsaBlock m: Match fname: String -> ty/SsaFunction
  (let [(pargs (match (mapGet (defsOf (with g :blocks (list b))) m.made) ((some op) (callArgs op)) ((none) (list))))
        (nilList (argAt pargs m.producer.index))
        (newArgs (listAppend (without pargs m.producer.index) (without (match (mapGet (defsOf (with g :blocks (list b))) m.call) ((some op) (callArgs op)) ((none) (list))) m.consumer.index)))
        (instrs (listFlatMap (fn [(ins ty/SsaInstr)] -> (List ty/SsaInstr)
                               (cond
                                 ((or (= ins.dest m.made) (= ins.dest m.reversed)) (list))
                                 ((= ins.dest m.call) (list (ty/ssaInstr ins.dest ins.ty (ty/opCall fname newArgs))))
                                 (else (list ins))))
                             b.instrs))
        (blocks (map (fn [(x ty/SsaBlock)] -> ty/SsaBlock (if (= x.label b.label) (ty/ssaBlock x.label x.params instrs x.term) x)) g.blocks))
        (dead (= (usesIn blocks nilList) 0))]
    (with g :blocks (if dead
                      (map (fn [(x ty/SsaBlock)] -> ty/SsaBlock (ty/ssaBlock x.label x.params (filter (fn [(ins ty/SsaInstr)] -> Bool (or (!= ins.dest nilList) (not (nilOp? ins.op)))) x.instrs) x.term)) blocks)
                      blocks)))

schema Fusion
  fns: (Map String ty/SsaFunction)
  added: (List ty/SsaFunction)

fn firstMatch fns: (Map String ty/SsaFunction) g: ty/SsaFunction -> (Option (Pair ty/SsaBlock Match))
  (listHead (listFlatMap (fn [(b ty/SsaBlock)] -> (List (Pair ty/SsaBlock Match))
                           (let [(defs (defsOf (with g :blocks (list b))))]
                             (listFlatMap (fn [(ins ty/SsaInstr)] -> (List (Pair ty/SsaBlock Match)) (match (siteIn fns g b defs ins) ((some m) (list (pair b m))) ((none) (list)))) b.instrs)))
                         g.blocks))

; (:m :do "most functions reverse no list; they are passed over on one scan, before any per-block table is built")
fn reverses? g: ty/SsaFunction -> Bool
  (listAny? (fn [(b ty/SsaBlock)] -> Bool (listAny? (fn [(ins ty/SsaInstr)] -> Bool (some? (reverseOf ins.op))) b.instrs)) g.blocks)

fn fuseIn st: Fusion g: ty/SsaFunction fuel: Int64 -> (Pair Fusion ty/SsaFunction)
  (if (or (<= fuel 0) (or (fused? g.name) (not (reverses? g))))
    (pair st g)
    (match (firstMatch st.fns g)
      ((none) (pair st g))
      ((some found)
        (let [(m (pairSecond found)) (p m.producer) (c m.consumer)
              (fname (fusedName p.f.name p.index c.f.name c.index))
              (known (mapHas? st.fns fname))
              (f (fusedFunction p c fname))
              (st2 (if known st (Fusion :fns (mapSet st.fns fname f) :added (cons f st.added))))]
          (fuseIn st2 (rewriteCaller g (pairFirst found) m fname) (- fuel 1))))))

fn fuseLists m: ty/SsaModule -> ty/SsaModule
  (let [(fns (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (mapSet acc f.name f)) (mapEmpty) m.functions))
        (r (fold (fn [(acc (Pair Fusion (List ty/SsaFunction))) (f ty/SsaFunction)] -> (Pair Fusion (List ty/SsaFunction))
                   (let [(done (fuseIn (pairFirst acc) f 16))] (pair (pairFirst done) (cons (pairSecond done) (pairSecond acc)))))
                 (pair (Fusion :fns fns :added (list)) (list)) m.functions))]
    (let [(st (pairFirst r))]
      (if (listEmpty? st.added)
        m
        (with m :functions (listAppend (listReverse (pairSecond r)) (listReverse st.added))))))
