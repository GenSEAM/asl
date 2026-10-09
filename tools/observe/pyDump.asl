(module ws/asl/tools/observe/pyDump
  :x [PyF PyNode PyTok PyFile Dump dumpScript runDump! fld kid kids optKids sfield ifield children walkBfs isType? constStr constKind]
  :i [(ws/asl/tools/observe/common :a c)])

(enum PyF
  (:c fNode [(n PyNode)])
  (:c fNone [])
  (:c fStr [(s String)])
  (:c fInt [(i Int64)])
  (:c fConst [(kind String) (s (Option String))])
  (:c fList [(xs (List PyF))]))

(schema PyNode
  (:f id Int64) (:f type String) (:f line Int64) (:f endLine Int64) (:f col Int64) (:f endCol Int64) (:f hasEnd Bool)
  (:f fields (List (Pair String PyF))) (:f u (Option String)))

(schema PyTok (:f kind String) (:f text String) (:f line Int64))

(schema PyFile (:f rel String) (:f ok Bool) (:f tree (Option PyNode)) (:f toks (List PyTok)))

(enum Dump
  (:c dumped [(files (List PyFile)) (warnings String)])
  (:c absent [(why String)]))

fn dumpScript -> String
  (c/joinWith
    (list
      "import ast,io,sys,tokenize"
      "o=sys.stdout.buffer"
      "root=sys.argv[1]"
      "W=sys.argv[2]"
      "OPS=(ast.expr_context,ast.operator,ast.unaryop,ast.boolop,ast.cmpop)"
      "TK={tokenize.COMMENT:'COMMENT',tokenize.STRING:'STRING',tokenize.NAME:'NAME'}"
      "if hasattr(tokenize,'FSTRING_MIDDLE'):TK[tokenize.FSTRING_MIDDLE]='FSTRING_MIDDLE'"
      "def S(s):"
      " b=s.encode('utf-8','surrogatepass');return b'S%d:'%len(b)+b"
      "def V(v):"
      " if v is None:return b'-'"
      " if isinstance(v,int):return b'I%d'%v"
      " if isinstance(v,str):return S(v)"
      " return S(type(v).__name__)"
      "def E(n,f,v):"
      " if f=='value' and isinstance(n,(ast.Constant,ast.MatchSingleton)):return b'K'+S(type(v).__name__)+b' '+(S(v) if isinstance(v,str) else b'-')"
      " if isinstance(v,OPS):return S(type(v).__name__)"
      " if isinstance(v,ast.AST):return b'C'"
      " if isinstance(v,list):return b'L%d'%len(v)+b''.join(b' '+(b'C' if isinstance(x,ast.AST) and not isinstance(x,OPS) else V(x)) for x in v)"
      " return V(v)"
      "def keep(n,f,v):"
      " return (v is not None and v!=[]) or (f=='value' and isinstance(n,(ast.Constant,ast.MatchSingleton)))"
      "for rel in sys.argv[3:]:"
      " try:"
      "  with open(root+'/'+rel,encoding='utf-8') as fh:src=fh.read()"
      "  tree=ast.parse(src,filename=rel)"
      " except (OSError,UnicodeDecodeError,SyntaxError,ValueError):"
      "  o.write(b'F '+S(rel)+b' I0\\n');continue"
      " o.write(b'F '+S(rel)+b' I1\\n')"
      " U=set()"
      " for n in ast.walk(tree):"
      "  if isinstance(n,ast.Call):U.add(id(n.func))"
      "  for x in getattr(n,'decorator_list',None) or ():U.add(id(x))"
      " todo=[(tree,0)]"
      " while todo:"
      "  n,done=todo.pop()"
      "  if not done:"
      "   todo.append((n,1))"
      "   kids=[]"
      "   for f,v in ast.iter_fields(n):"
      "    if isinstance(v,ast.AST) and not isinstance(v,OPS):kids.append(v)"
      "    elif isinstance(v,list):kids.extend(x for x in v if isinstance(x,ast.AST) and not isinstance(x,OPS))"
      "   todo.extend((k,0) for k in reversed(kids))"
      "   continue"
      "  g=lambda a:V(getattr(n,a,None))"
      "  fs=[(f,v) for f,v in ast.iter_fields(n) if keep(n,f,v)]"
      "  o.write(b'N '+S(type(n).__name__)+b' '+g('lineno')+b' '+g('end_lineno')+b' '+g('col_offset')+b' '+g('end_col_offset')+b' '+(S(ast.unparse(n)) if id(n) in U else b'-')+b' I%d'%len(fs)+b''.join(b' '+S(f)+b' '+E(n,f,v) for f,v in fs)+b'\\n')"
      " try:"
      "  for t in tokenize.generate_tokens(io.StringIO(src).readline):"
      "   if t.type in TK and (t.type==tokenize.COMMENT or (W and W[1:] in t.string)):o.write(b'T '+S(TK[t.type])+b' I%d '%t.start[0]+S(t.string)+b'\\n')"
      " except (tokenize.TokenError,SyntaxError):pass"
      "o.write(b'E\\n')")
    "\n")

fn fld n: PyNode name: String -> PyF
  (mt (listHead (filter (fn [(p (Pair String PyF))] -> Bool (= (pairFirst p) name)) n.fields))
    ((some p) (pairSecond p))
    ((none) (fNone)))

fn kid n: PyNode name: String -> (Option PyNode)
  (mt (fld n name) ((fNode k) (some k)) (_ (none)))

fn fNodeOpt f: PyF -> (Option PyNode)
  (mt f ((fNode k) (some k)) (_ (none)))

fn kids n: PyNode name: String -> (List PyNode)
  (mt (fld n name)
    ((fList xs) (fold (fn [(acc (List PyNode)) (f PyF)] -> (List PyNode) (mt f ((fNode k) (cons k acc)) (_ acc))) (list) (listReverse xs)))
    (_ (list)))

fn optKids n: PyNode name: String -> (List (Option PyNode))
  (mt (fld n name) ((fList xs) (map fNodeOpt xs)) (_ (list)))

fn sfield n: PyNode name: String -> (Option String)
  (mt (fld n name) ((fStr s) (some s)) (_ (none)))

fn ifield n: PyNode name: String -> Int64
  (mt (fld n name) ((fInt i) i) (_ 0))

fn isType? n: PyNode t: String -> Bool
  (= n.type t)

fn constKind n: PyNode -> (Option String)
  (if (isType? n "Constant") (mt (fld n "value") ((fConst k s) (some k)) (_ (none))) (none))

fn constStr n: PyNode -> (Option String)
  (if (isType? n "Constant") (mt (fld n "value") ((fConst k s) (if (= k "str") s (none))) (_ (none))) (none))

fn children n: PyNode -> (List PyNode)
  (listReverse
    (fold (fn [(acc (List PyNode)) (p (Pair String PyF))] -> (List PyNode)
            (mt (pairSecond p)
              ((fNode k) (cons k acc))
              ((fList xs) (fold (fn [(a2 (List PyNode)) (f PyF)] -> (List PyNode) (mt f ((fNode k) (cons k a2)) (_ a2))) acc xs))
              (_ acc)))
          (list) n.fields))

fn bfsLoop front: (List PyNode) next: (List PyNode) acc: (List PyNode) -> (List PyNode)
  (mt (listHead front)
    ((some n) (bfsLoop (optionOr (listTail front) (list)) (listAppend (listReverse (children n)) next) (cons n acc)))
    ((none) (if (listEmpty? next) (listReverse acc) (bfsLoop (listReverse next) (list) acc))))

fn walkBfs n: PyNode -> (List PyNode)
  (bfsLoop (list n) (list) (list))

(schema Build (:f stack (List PyNode)) (:f size Int64) (:f next Int64) (:f files (List PyFile)) (:f cur (Option PyFile)))

(enum RawF
  (:c rChild [])
  (:c rVal [(v PyF)])
  (:c rList [(xs (List RawF))]))

(schema Got (:f v PyF) (:f at Int64))

fn digitsAt bs: Bytes i: Int64 n: Int64 acc: Int64 -> (Pair Int64 Int64)
  (if (and (< i n) (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57)) (digitsAt bs (+ i 1) n (+ (* acc 10) (- (bytesGet bs i) 48))) (pair acc i))

fn intAt bs: Bytes i: Int64 n: Int64 -> (Pair Int64 Int64)
  (if (and (< i n) (= (bytesGet bs i) 45))
    (let [(p (digitsAt bs (+ i 1) n 0))] (pair (- 0 (pairFirst p)) (pairSecond p)))
    (digitsAt bs i n 0))

fn valAt s: String bs: Bytes i: Int64 n: Int64 -> (Result Got String)
  (let [(b (if (< i n) (bytesGet bs i) -1))]
    (cond
      ((= b 45) (ok (Got :v (fNone) :at (+ i 1))))
      ((= b 73) (let [(p (intAt bs (+ i 1) n))] (ok (Got :v (fInt (pairFirst p)) :at (pairSecond p)))))
      ((= b 83)
        (let [(p (digitsAt bs (+ i 1) n 0)) (start (+ (pairSecond p) 1)) (end (+ (+ (pairSecond p) 1) (pairFirst p)))]
          (if (or (> end n) (>= (pairSecond p) n) (!= (bytesGet bs (pairSecond p)) 58))
            (err (str "python3 ast dump: bad string at byte " (stringFromInt64 i)))
            (ok (Got :v (fStr (optionOr (stringSlice s start end) "")) :at end)))))
      (else (err (str "python3 ast dump: bad value at byte " (stringFromInt64 i))))))

fn strOf v: PyF -> String
  (mt v ((fStr x) x) (_ ""))

fn intOf v: PyF -> Int64
  (mt v ((fInt x) x) (_ 0))

(schema RawGot (:f r RawF) (:f at Int64))

fn listElems s: String bs: Bytes i: Int64 n: Int64 k: Int64 acc: (List RawF) -> (Result RawGot String)
  (if (<= k 0)
    (ok (RawGot :r (rList (listReverse acc)) :at i))
    (let [(j (+ i 1))]
      (if (and (< j n) (= (bytesGet bs j) 67))
        (listElems s bs (+ j 1) n (- k 1) (cons (rChild) acc))
        (mt (valAt s bs j n)
          ((err e) (err e))
          ((ok g) (listElems s bs g.at n (- k 1) (cons (rVal g.v) acc)))))))

fn specAt s: String bs: Bytes i: Int64 n: Int64 -> (Result RawGot String)
  (let [(b (if (< i n) (bytesGet bs i) -1))]
    (cond
      ((= b 67) (ok (RawGot :r (rChild) :at (+ i 1))))
      ((= b 75)
        (mt (valAt s bs (+ i 1) n)
          ((err e) (err e))
          ((ok k) (mt (valAt s bs (+ k.at 1) n)
                    ((err e) (err e))
                    ((ok v) (ok (RawGot :r (rVal (fConst (strOf k.v) (mt v.v ((fStr x) (some x)) (_ (none))))) :at v.at)))))))
      ((= b 76) (let [(p (digitsAt bs (+ i 1) n 0))] (listElems s bs (pairSecond p) n (pairFirst p) (list))))
      (else (mt (valAt s bs i n) ((err e) (err e)) ((ok g) (ok (RawGot :r (rVal g.v) :at g.at)))))))

(schema RawField (:f name String) (:f r RawF))

fn fieldsAt s: String bs: Bytes i: Int64 n: Int64 k: Int64 acc: (List RawField) -> (Result (Pair (List RawField) Int64) String)
  (if (<= k 0)
    (ok (pair (listReverse acc) i))
    (mt (valAt s bs (+ i 1) n)
      ((err e) (err e))
      ((ok nm) (mt (specAt s bs (+ nm.at 1) n)
                 ((err e) (err e))
                 ((ok sp) (fieldsAt s bs sp.at n (- k 1) (cons (RawField :name (strOf nm.v) :r sp.r) acc)))))))

fn childCount r: RawF -> Int64
  (mt r ((rChild) 1) ((rList xs) (fold (fn [(acc Int64) (x RawF)] -> Int64 (+ acc (childCount x))) 0 xs)) (_ 0))

fn fill r: RawF kidsLeft: (List PyNode) -> (Pair PyF (List PyNode))
  (mt r
    ((rChild) (mt (listHead kidsLeft) ((some k) (pair (fNode k) (optionOr (listTail kidsLeft) (list)))) ((none) (pair (fNone) kidsLeft))))
    ((rVal v) (pair v kidsLeft))
    ((rList xs)
      (let [(t (fold (fn [(acc (Pair (List PyF) (List PyNode))) (x RawF)] -> (Pair (List PyF) (List PyNode))
                       (let [(q (fill x (pairSecond acc)))] (pair (cons (pairFirst q) (pairFirst acc)) (pairSecond q))))
                     (pair (list) kidsLeft) xs))]
        (pair (fList (listReverse (pairFirst t))) (pairSecond t)))))

(schema Head (:f vals (List PyF)) (:f at Int64))

fn headVals s: String bs: Bytes i: Int64 n: Int64 k: Int64 acc: (List PyF) -> (Result Head String)
  (if (<= k 0)
    (ok (Head :vals (listReverse acc) :at i))
    (mt (valAt s bs (+ i 1) n)
      ((err e) (err e))
      ((ok g) (headVals s bs g.at n (- k 1) (cons g.v acc)))))

fn nodeAt s: String bs: Bytes i: Int64 n: Int64 b: Build -> (Result (Pair Build Int64) String)
  (mt (headVals s bs i n 7 (list))
    ((err e) (err e))
    ((ok h)
      (let [(at (fn [(k Int64)] -> PyF (optionOr (listGet h.vals k) (fNone))))]
        (mt (fieldsAt s bs h.at n (intOf (at 6)) (list))
          ((err e) (err e))
          ((ok fp)
            (let [(raw (pairFirst fp))
                  (need (fold (fn [(acc Int64) (f RawField)] -> Int64 (+ acc (childCount f.r))) 0 raw))]
              (if (< b.size need)
                (err (str "python3 ast dump: node " (strOf (at 0)) " needs " (stringFromInt64 need) " children"))
                (let [(built (fold (fn [(acc (Pair (List (Pair String PyF)) (List PyNode))) (f RawField)] -> (Pair (List (Pair String PyF)) (List PyNode))
                                     (let [(q (fill f.r (pairSecond acc)))] (pair (cons (pair f.name (pairFirst q)) (pairFirst acc)) (pairSecond q))))
                                   (pair (list) (listReverse (listTake b.stack need))) raw))
                      (endLine (at 2)) (endCol (at 4))
                      (node (PyNode :id b.next :type (strOf (at 0)) :line (intOf (at 1)) :endLine (intOf endLine) :col (intOf (at 3)) :endCol (intOf endCol)
                                    :hasEnd (and (mt endLine ((fInt x) true) (_ false)) (mt endCol ((fInt x) true) (_ false)))
                                    :fields (listReverse (pairFirst built)) :u (mt (at 5) ((fStr x) (some x)) (_ (none)))))]
                  (ok (pair (with b :stack (cons node (listDrop b.stack need)) :size (+ (- b.size need) 1) :next (+ b.next 1))
                            (+ (pairSecond fp) 1)))))))))))

fn closeFile b: Build -> Build
  (mt b.cur
    ((none) b)
    ((some f)
      (let [(tree (if f.ok (listHead b.stack) (none)))]
        (with b :stack (list) :size 0 :files (cons (PyFile :rel f.rel :ok f.ok :tree tree :toks (listReverse f.toks)) b.files) :cur (none)))))

fn recordsAt s: String bs: Bytes i: Int64 n: Int64 b: Build -> (Result Build String)
  (let [(tag (if (< i n) (bytesGet bs i) -1))]
    (cond
      ((= tag 69) (ok (closeFile b)))
      ((= tag 78) (mt (nodeAt s bs (+ i 1) n b) ((err e) (err e)) ((ok r) (recordsAt s bs (pairSecond r) n (pairFirst r)))))
      ((= tag 84)
        (mt (headVals s bs (+ i 1) n 3 (list))
          ((err e) (err e))
          ((ok h)
            (mt b.cur
              ((none) (err "python3 ast dump: token before a file"))
              ((some f)
                (let [(v (fn [(k Int64)] -> PyF (optionOr (listGet h.vals k) (fNone))))
                      (tok (PyTok :kind (strOf (v 0)) :line (intOf (v 1)) :text (strOf (v 2))))]
                  (recordsAt s bs (+ h.at 1) n
                             (with b :cur (some (PyFile :rel f.rel :ok f.ok :tree (none) :toks (cons tok f.toks)))))))))))
      ((= tag 70)
        (mt (headVals s bs (+ i 1) n 2 (list))
          ((err e) (err e))
          ((ok h)
            (let [(b2 (closeFile b)) (v (fn [(k Int64)] -> PyF (optionOr (listGet h.vals k) (fNone))))]
              (recordsAt s bs (+ h.at 1) n
                         (Build :stack (list) :size 0 :next b2.next :files b2.files
                                :cur (some (PyFile :rel (strOf (v 0)) :ok (= (intOf (v 1)) 1) :tree (none) :toks (list)))))))))
      ((< tag 0) (err "python3 ast dump ended early"))
      (else (err (str "python3 ast dump: unknown record at byte " (stringFromInt64 i))))))

fn parseDump out: String -> (Result (List PyFile) String)
  (let [(bs (stringToBytes out))]
    (mt (recordsAt out bs 0 (bytesLength bs) (Build :stack (list) :size 0 :next 1 :files (list) :cur (none)))
      ((err e) (err e))
      ((ok b) (ok (listReverse b.files)))))

fn ! runDump! root: String want: String rels: (List String) ctx: c/Ctx -> (Result Dump String)
  (if (listEmpty? rels)
    (ok (dumped (list) ""))
    (mt (c/runArgv! (listAppend (list "python3" "-I" "-c" (dumpScript) root want) rels) ctx.cwd ctx)
      ((err e) (ok (absent e)))
      ((ok p)
        (if (!= p.code 0)
          (err (str "python3 ast dump exited " (stringFromInt64 p.code) ": " p.errText))
          (mt (parseDump p.out)
            ((err e) (err e))
            ((ok files) (ok (dumped files p.errText))))))))
