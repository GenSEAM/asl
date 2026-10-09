(module ws/asl/tools/observe/pyIndex
  :x [Binding PyMod PyDef Res Scope CallSite Ref Dyn Untyped W Ix PyIndex Built
      defKey keyMod keyQual lastSeg modOf defOf defKind buildPyIndex resolveSym resolveExpr resolveName methodOf importBindings pyPrefix]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)
      (ws/asl/tools/observe/pyDump :a d)])

(enum Binding
  (:c bMod [(name String) (how String)])
  (:c bSym [(base String) (name String) (how String)])
  (:c bStar [(base String)]))

(schema PyMod
  (:f rel String) (:f name String) (:f isPkg Bool) (:f pkg String) (:f src String) (:f tree d/PyNode) (:f isTest Bool) (:f toks (List d/PyTok))
  (:f top (h/HMap String)) (:f bindings (h/HMap Binding)) (:f vars (h/OMap (Pair Int64 d/PyNode))) (:f varTypes (h/HMap String))
  (:f stars (List String)) (:f docstrings (h/HMap Bool)) (:f importLines (h/HMap Bool)) (:f comments (List (Pair Int64 String))))

(schema PyDef
  (:f key String) (:f modName String) (:f rel String) (:f qual String) (:f name String) (:f kind String) (:f node d/PyNode)
  (:f cls (Option String)) (:f line Int64) (:f end Int64))

(schema Res (:f tag String) (:f val String) (:f how String) (:f hops Int64))

(schema Scope
  (:f kind String) (:f key (Option String)) (:f names (h/HMap Bool)) (:f bindings (h/HMap Binding)) (:f defs (h/HMap String))
  (:f types (h/HMap String)) (:f selfName (Option String)) (:f cls (Option String)) (:f nested Bool))

(schema CallSite (:f rel String) (:f line Int64) (:f caller String) (:f callee String) (:f kind String) (:f via (Option String)) (:f through (Option String)))

(schema Ref (:f rel String) (:f line Int64) (:f key String))

(schema Dyn (:f rel String) (:f line Int64) (:f tag String) (:f base String))

(schema Untyped (:f rel String) (:f line Int64) (:f attr String))

(schema W
  (:f calls (List CallSite)) (:f refs (List Ref)) (:f dynamic (List Dyn)) (:f untyped (List Untyped))
  (:f varReads (h/HMap (List (Pair String Int64)))) (:f edges (h/HMap (h/HMap Bool))) (:f localsAt (h/HMap Bool)))

(schema Ix
  (:f mods (h/OMap PyMod)) (:f pkgs (h/HMap Bool)) (:f defs (h/OMap PyDef)) (:f attrTypes (h/HMap String))
  (:f children (h/HMap (List String))) (:f lambdaKeys (h/HMap String)))

(schema PyIndex (:f root String) (:f ix Ix) (:f w W) (:f unparsed (List String)) (:f warnings String))

(enum Built
  (:c built [(pi PyIndex)])
  (:c pyAbsent [(why String)]))

fn defKey m: String q: String -> String
  (str m "\x01" q)

fn keyMod k: String -> String
  (mt (stringIndexOf k "\x01") ((some i) (optionOr (stringSlice k 0 i) "")) ((none) k))

fn keyQual k: String -> String
  (mt (stringIndexOf k "\x01") ((some i) (optionOr (stringSlice k (+ i 1) (stringLength k)) "")) ((none) ""))

fn lastDotIn s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (optionOr (stringSlice s i (+ i 1)) "") ".") i) (else (lastDotIn s (- i 1))))

fn lastSeg q: String -> String
  (let [(i (lastDotIn q (- (stringLength q) 1)))] (if (< i 0) q (optionOr (stringSlice q (+ i 1) (stringLength q)) "")))

fn attrKey clsKey: String attr: String -> String
  (str clsKey "\x02" attr)

fn lineKey rel: String line: Int64 -> String
  (str rel "\x01" (stringFromInt64 line))

fn modOf ix: Ix name: String -> (Option PyMod)
  (h/omGet ix.mods name)

fn defOf ix: Ix key: String -> (Option PyDef)
  (h/omGet ix.defs key)

fn defKind ix: Ix key: String -> String
  (mt (defOf ix key) ((some dd) dd.kind) ((none) ""))

fn nameOf n: d/PyNode -> String
  (optionOr (d/sfield n "name") "")

fn idOf n: d/PyNode -> String
  (optionOr (d/sfield n "id") "")

fn endOf n: d/PyNode -> Int64
  (if (> n.endLine 0) n.endLine n.line)

fn defLike? t: String -> Bool
  (or (= t "FunctionDef") (= t "AsyncFunctionDef") (= t "ClassDef"))

fn stmtTypes -> (List String)
  (list "FunctionDef" "AsyncFunctionDef" "ClassDef" "Return" "Delete" "Assign" "TypeAlias" "AugAssign" "AnnAssign" "For" "AsyncFor"
        "While" "If" "With" "AsyncWith" "Match" "Raise" "Try" "TryStar" "Assert" "Import" "ImportFrom" "Global" "Nonlocal" "Expr" "Pass"
        "Break" "Continue")

fn pyPrefix s: String n: Int64 -> String
  (let [(cs (c/charCodes s))]
    (if (<= (listLength cs) n) s (mt (listGet cs n) ((some p) (optionOr (stringSlice s 0 (pairSecond p)) s)) ((none) s))))

fn pyLen s: String -> Int64
  (listLength (c/charCodes s))

fn moduleName rel: String -> (Pair String Bool)
  (let [(parts (stringSplit (optionOr (stringSlice rel 0 (- (stringLength rel) 3)) "") "/"))
        (isPkg (= (optionOr (listLast parts) "") "__init__"))
        (parts2 (if isPkg (listTake parts (- (listLength parts) 1)) parts))]
    (pair (c/joinWith parts2 ".") isPkg))

fn rpartDot s: String -> String
  (let [(i (lastDotIn s (- (stringLength s) 1)))] (if (< i 0) "" (optionOr (stringSlice s 0 i) "")))

fn testFileName? rel: String -> Bool
  (let [(base (c/baseName rel))]
    (and (stringEndsWith? base ".py")
         (or (stringStartsWith? base "test_") (stringEndsWith? base "_test.py"))))

fn testRel? rel: String -> Bool
  (let [(parts (stringSplit rel "/"))]
    (or (testFileName? rel) (listAny? (fn [(p String)] -> Bool (or (= p "tests") (= p "test"))) (listTake parts (- (listLength parts) 1)))))

fn aliasName al: d/PyNode -> String
  (optionOr (d/sfield al "name") "")

fn importBindings pkg: String st: d/PyNode -> (List (Pair String Binding))
  (cond
    ((d/isType? st "Import")
      (map (fn [(al d/PyNode)] -> (Pair String Binding)
             (mt (d/sfield al "asname")
               ((some a) (pair a (bMod (aliasName al) "alias")))
               ((none) (let [(head (optionOr (listHead (stringSplit (aliasName al) ".")) ""))] (pair head (bMod head "direct"))))))
           (d/kids st "names")))
    ((d/isType? st "ImportFrom")
      (let [(module (d/sfield st "module"))
            (level (d/ifield st "level"))
            (parts (if (stringEmpty? pkg) (list) (stringSplit pkg ".")))
            (up (- level 1))]
        (if (and (> level 0) (> up (listLength parts)))
          (list)
          (let [(base (if (> level 0)
                        (c/joinWith (listAppend (listTake parts (- (listLength parts) up)) (mt module ((some m) (list m)) ((none) (list)))) ".")
                        (optionOr module "")))]
            (map (fn [(al d/PyNode)] -> (Pair String Binding)
                   (let [(nm (aliasName al)) (asn (d/sfield al "asname"))]
                     (if (= nm "*")
                       (pair "*" (bStar base))
                       (pair (optionOr asn nm) (bSym base nm (mt asn ((some a) (if (!= a nm) "alias" "direct")) ((none) "direct")))))))
                 (d/kids st "names"))))))
    (else (list)))

(schema Base (:f rel String) (:f name String) (:f pkg String))

(schema MC
  (:f top (h/HMap String)) (:f bindings (h/HMap Binding)) (:f vars (h/OMap (Pair Int64 d/PyNode))) (:f stars (List String))
  (:f importLines (h/HMap Bool)) (:f defs (h/OMap PyDef)) (:f own (h/HMap (Option d/PyNode))))

fn mcDefs st: MC defs: (h/OMap PyDef) top: (h/HMap String) own: (h/HMap (Option d/PyNode)) -> MC
  (with st :top top :defs defs :own own)

fn addDef st: MC b: Base qual: String node: d/PyNode kind: String cls: (Option String) topName: (Option String) -> MC
  (let [(dd (PyDef :key (defKey b.name qual) :modName b.name :rel b.rel :qual qual :name (lastSeg qual) :kind kind :node node
                   :cls cls :line node.line :end (endOf node)))]
    (mcDefs st (h/omPut st.defs dd.key dd) (mt topName ((some t) (h/hmPut st.top t qual)) ((none) st.top))
            (h/hmPut st.own dd.key (if (= kind "lambda") (none) (some node)))))

fn lineRange a: Int64 b: Int64 acc: (h/HMap Bool) -> (h/HMap Bool)
  (if (> a b) acc (lineRange (+ a 1) b (h/hmPut acc (stringFromInt64 a) true)))

fn importInto st: MC b: Base node: d/PyNode topLevel: Bool -> MC
  (let [(lines (lineRange node.line (endOf node) st.importLines))
        (pairs (if topLevel (importBindings b.pkg node) (list)))
        (binds (fold (fn [(acc (h/HMap Binding)) (p (Pair String Binding))] -> (h/HMap Binding) (if (= (pairFirst p) "*") acc (h/hmPut acc (pairFirst p) (pairSecond p)))) st.bindings pairs))
        (stars (fold (fn [(acc (List String)) (p (Pair String Binding))] -> (List String) (mt (pairSecond p) ((bStar base) (cons base acc)) (_ acc))) st.stars pairs))]
    (with st :bindings binds :stars stars :importLines lines))

fn assignInto st: MC b: Base node: d/PyNode -> MC
  (let [(targets (if (d/isType? node "Assign") (d/kids node "targets") (mt (d/kid node "target") ((some t) (list t)) ((none) (list)))))
        (value (d/kid node "value"))]
    (fold (fn [(acc MC) (t d/PyNode)] -> MC
            (mt value
              ((none) acc)
              ((some v)
                (if (not (d/isType? t "Name"))
                  acc
                  (if (and (d/isType? v "Lambda") (= (listLength targets) 1))
                    (addDef acc b (idOf t) v "lambda" (none) (some (idOf t)))
                    (MC :top acc.top :bindings acc.bindings :vars (h/omPut acc.vars (idOf t) (pair node.line v)) :stars acc.stars
                        :importLines acc.importLines :defs acc.defs :own acc.own))))))
          st targets))

fn stmtList? xs: (List d/PyNode) -> Bool
  (mt (listHead xs) ((some x) (listContains? (stmtTypes) x.type)) ((none) false))

fn collect b: Base body: (List d/PyNode) prefix: String cls: (Option String) inFunc: Bool st: MC -> MC
  (fold (fn [(acc MC) (node d/PyNode)] -> MC (collectStmt b node prefix cls inFunc acc)) st body)

fn collectStmt b: Base node: d/PyNode prefix: String cls: (Option String) inFunc: Bool st: MC -> MC
  (let [(t node.type) (topLevel (stringEmpty? prefix))]
    (cond
      ((or (= t "FunctionDef") (= t "AsyncFunctionDef"))
        (let [(qual (str prefix (nameOf node)))
              (kind (if inFunc "nested" (if (some? cls) "method" "function")))
              (st1 (addDef st b qual node kind cls (if topLevel (some (nameOf node)) (none))))]
          (collect b (d/kids node "body") (str qual ".") (none) true st1)))
      ((= t "ClassDef")
        (let [(qual (str prefix (nameOf node)))
              (st1 (addDef st b qual node "class" (none) (if topLevel (some (nameOf node)) (none))))]
          (collect b (d/kids node "body") (str qual ".") (some qual) inFunc st1)))
      (else
        (let [(st1 (cond
                     ((or (= t "Import") (= t "ImportFrom")) (importInto st b node topLevel))
                     ((and topLevel (or (= t "Assign") (= t "AnnAssign"))) (assignInto st b node))
                     (else st)))
              (st2 (fold (fn [(acc MC) (field String)] -> MC
                           (let [(sub (d/kids node field))] (if (stmtList? sub) (collect b sub prefix cls inFunc acc) acc)))
                         st1 (list "body" "orelse" "finalbody")))]
          (fold (fn [(acc MC) (hd d/PyNode)] -> MC (collect b (d/kids hd "body") prefix cls inFunc acc)) st2 (d/kids node "handlers"))))))

fn docLine n: d/PyNode -> (Option Int64)
  (mt (listHead (d/kids n "body"))
    ((some b0) (if (and (d/isType? b0 "Expr") (mt (d/kid b0 "value") ((some v) (some? (d/constStr v))) ((none) false))) (some b0.line) (none)))
    ((none) (none)))

fn commentToks toks: (List d/PyTok) -> (List (Pair Int64 String))
  (listReverse (fold (fn [(acc (List (Pair Int64 String))) (t d/PyTok)] -> (List (Pair Int64 String)) (if (= t.kind "COMMENT") (cons (pair t.line t.text) acc) acc)) (list) toks))

fn docstringsOf tree: d/PyNode nodes: (List d/PyNode) -> (h/HMap Bool)
  (fold (fn [(acc (h/HMap Bool)) (n d/PyNode)] -> (h/HMap Bool) (mt (docLine n) ((some l) (h/hmPut acc (stringFromInt64 l) true)) ((none) acc)))
        (h/hmEmpty) (cons tree nodes))

fn resolveBinding ix: Ix b: Binding depth: Int64 -> (Option Res)
  (mt b
    ((bMod name how) (some (Res :tag "mod" :val name :how "" :hops 0)))
    ((bSym base name how) (resolveSym ix base name depth))
    ((bStar base) (none)))

fn bindingHow b: Binding -> String
  (mt b ((bMod name how) how) ((bSym base name how) how) ((bStar base) ""))

fn bumped r: Res -> Res
  (with r :hops (+ r.hops 1))

fn symInMod ix: Ix mod: PyMod m: String n: String depth: Int64 -> (Option Res)
  (mt (h/hmGet mod.top n)
    ((some q) (some (Res :tag "def" :val (defKey m q) :how "" :hops 0)))
    ((none)
      (let [(viaBinding (mt (h/hmGet mod.bindings n) ((some b) (optionMap bumped (resolveBinding ix b (+ depth 1)))) ((none) (none))))]
        (mt viaBinding
          ((some r) (some r))
          ((none) (if (h/omHas? mod.vars n) (some (Res :tag "var" :val (defKey m n) :how "" :hops 0)) (none)))))))

fn starDef ix: Ix stars: (List String) n: String depth: Int64 -> (Option Res)
  (mt (listHead stars)
    ((none) (none))
    ((some base)
      (mt (resolveSym ix base n (+ depth 1))
        ((some r) (if (= r.tag "def") (some (bumped r)) (starDef ix (optionOr (listTail stars) (list)) n depth)))
        ((none) (starDef ix (optionOr (listTail stars) (list)) n depth)))))

fn resolveSym ix: Ix m: String n: String depth: Int64 -> (Option Res)
  (if (> depth 16)
    (none)
    (let [(modO (modOf ix m))
          (fromMod (mt modO ((some mod) (symInMod ix mod m n depth)) ((none) (none))))]
      (mt fromMod
        ((some r) (some r))
        ((none)
          (let [(sub (if (stringEmpty? m) n (str m "." n)))]
            (if (or (h/omHas? ix.mods sub) (h/hmHas? ix.pkgs sub))
              (some (Res :tag "mod" :val sub :how "" :hops 0))
              (mt modO ((some mod) (starDef ix mod.stars n depth)) ((none) (none)))))))))

fn baseMethod ix: Ix bases: (List d/PyNode) mod: PyMod name: String depth: Int64 -> (Option String)
  (mt (listHead bases)
    ((none) (none))
    ((some base)
      (let [(found (mt (resolveExpr ix mod base (list))
                     ((some r) (if (and (= r.tag "def") (= (defKind ix r.val) "class")) (methodOf ix r.val name (+ depth 1)) (none)))
                     ((none) (none))))]
        (mt found ((some k) (some k)) ((none) (baseMethod ix (optionOr (listTail bases) (list)) mod name depth))))))

fn methodOf ix: Ix clsKey: String name: String depth: Int64 -> (Option String)
  (let [(key (str clsKey "." name))]
    (if (h/omHas? ix.defs key)
      (some key)
      (mt (defOf ix clsKey)
        ((none) (none))
        ((some dd)
          (if (> depth 8)
            (none)
            (mt (modOf ix dd.modName)
              ((some mod) (baseMethod ix (d/kids dd.node "bases") mod name depth))
              ((none) (none))))))))

fn fromBinding ix: Ix b: Binding -> (Option Res)
  (optionMap (fn [(r Res)] -> Res (Res :tag r.tag :val r.val :how (bindingHow b) :hops r.hops)) (resolveBinding ix b 0))

fn inScopes ix: Ix name: String stack: (List Scope) first: Bool -> (Option (Option Res))
  (mt (listHead stack)
    ((none) (none))
    ((some sc)
      (let [(rest (optionOr (listTail stack) (list)))]
        (if (and (= sc.kind "class") (not first))
          (inScopes ix name rest false)
          (mt (h/hmGet sc.bindings name)
            ((some b) (some (fromBinding ix b)))
            ((none)
              (mt (h/hmGet sc.defs name)
                ((some k) (some (some (Res :tag "def" :val k :how "direct" :hops 0))))
                ((none)
                  (mt (h/hmGet sc.types name)
                    ((some t) (some (some (Res :tag "inst" :val t :how "local" :hops 0))))
                    ((none)
                      (if (= sc.selfName (some name))
                        (some (optionMap (fn [(k String)] -> Res (Res :tag "inst" :val k :how "self" :hops 0)) sc.cls))
                        (if (h/hmHas? sc.names name) (some (none)) (inScopes ix name rest false)))))))))))))

fn starAny ix: Ix stars: (List String) name: String -> (Option Res)
  (mt (listHead stars)
    ((none) (none))
    ((some base)
      (mt (resolveSym ix base name 0)
        ((some r) (some (Res :tag r.tag :val r.val :how "direct" :hops (+ r.hops 1))))
        ((none) (starAny ix (optionOr (listTail stars) (list)) name)))))

fn resolveName ix: Ix mod: PyMod name: String stack: (List Scope) -> (Option Res)
  (mt (inScopes ix name stack true)
    ((some decided) decided)
    ((none)
      (mt (h/hmGet mod.top name)
        ((some q) (some (Res :tag "def" :val (defKey mod.name q) :how "direct" :hops 0)))
        ((none)
          (mt (h/hmGet mod.bindings name)
            ((some b) (fromBinding ix b))
            ((none)
              (mt (h/hmGet mod.varTypes name)
                ((some t) (some (Res :tag "inst" :val t :how "var" :hops 0)))
                ((none)
                  (if (h/omHas? mod.vars name)
                    (some (Res :tag "var" :val (defKey mod.name name) :how "direct" :hops 0))
                    (starAny ix mod.stars name))))))))))

fn attrOf ix: Ix mod: PyMod expr: d/PyNode stack: (List Scope) -> (Option Res)
  (let [(attr (optionOr (d/sfield expr "attr") ""))]
    (mt (d/kid expr "value")
      ((none) (none))
      ((some v)
        (mt (resolveExpr ix mod v stack)
          ((none) (none))
          ((some base)
            (cond
              ((= base.tag "mod")
                (optionMap (fn [(r Res)] -> Res (Res :tag r.tag :val r.val :how "attribute" :hops r.hops)) (resolveSym ix base.val attr 0)))
              ((= base.tag "inst")
                (mt (methodOf ix base.val attr 0)
                  ((some k) (some (Res :tag "def" :val k :how "method" :hops 0)))
                  ((none) (optionMap (fn [(t String)] -> Res (Res :tag "inst" :val t :how "attr" :hops 0)) (h/hmGet ix.attrTypes (attrKey base.val attr))))))
              ((and (= base.tag "def") (= (defKind ix base.val) "class"))
                (optionMap (fn [(k String)] -> Res (Res :tag "def" :val k :how "method" :hops 0)) (methodOf ix base.val attr 0)))
              (else (none))))))))

fn resolveExpr ix: Ix mod: PyMod expr: d/PyNode stack: (List Scope) -> (Option Res)
  (cond
    ((d/isType? expr "Name") (resolveName ix mod (idOf expr) stack))
    ((d/isType? expr "Attribute") (attrOf ix mod expr stack))
    ((d/isType? expr "Call")
      (mt (d/kid expr "func")
        ((none) (none))
        ((some f)
          (mt (resolveExpr ix mod f stack)
            ((some r) (if (and (= r.tag "def") (= (defKind ix r.val) "class")) (some (Res :tag "inst" :val r.val :how "new" :hops 0)) (none)))
            ((none) (none))))))
    (else (none)))

fn withVarTypes m: PyMod vt: (h/HMap String) -> PyMod
  (with m :varTypes vt)

fn withMods ix: Ix mods: (h/OMap PyMod) -> Ix
  (with ix :mods mods)

fn withAttrTypes ix: Ix at: (h/HMap String) -> Ix
  (with ix :attrTypes at)

fn firstArg fnNode: d/PyNode -> (Option String)
  (mt (d/kid fnNode "args")
    ((some a) (mt (listHead (d/kids a "args")) ((some p) (d/sfield p "arg")) ((none) (none))))
    ((none) (none)))

fn selfAttrTypes ix: Ix mod: PyMod dd: PyDef -> Ix
  (mt (firstArg dd.node)
    ((none) ix)
    ((some selfName)
      (fold (fn [(acc Ix) (n d/PyNode)] -> Ix
              (if (not (and (d/isType? n "Assign") (mt (d/kid n "value") ((some v) (d/isType? v "Call")) ((none) false))))
                acc
                (fold (fn [(a2 Ix) (t d/PyNode)] -> Ix
                        (if (and (d/isType? t "Attribute") (mt (d/kid t "value") ((some tv) (and (d/isType? tv "Name") (= (idOf tv) selfName))) ((none) false)))
                          (mt (resolveExpr a2 mod (optionOr (d/kid n "value") n) (list))
                            ((some r) (if (= r.tag "inst")
                                        (withAttrTypes a2 (h/hmPut a2.attrTypes (attrKey (defKey mod.name (optionOr dd.cls "")) (optionOr (d/sfield t "attr") "")) r.val))
                                        a2))
                            ((none) a2))
                          a2))
                      acc (d/kids n "targets"))))
            ix (d/walkBfs dd.node))))

fn typesOf methods: (h/HMap (List PyDef)) ix: Ix name: String -> Ix
  (mt (modOf ix name)
    ((none) ix)
    ((some mod0)
      (let [(ix1 (fold (fn [(acc Ix) (p (Pair String (Pair Int64 d/PyNode)))] -> Ix
                         (let [(value (pairSecond (pairSecond p)))]
                           (if (not (d/isType? value "Call"))
                             acc
                             (mt (modOf acc name)
                               ((none) acc)
                               ((some cur)
                                 (mt (resolveExpr acc cur value (list))
                                   ((some r) (if (= r.tag "inst")
                                               (withMods acc (h/omPut acc.mods name (withVarTypes cur (h/hmPut cur.varTypes (pairFirst p) r.val))))
                                               acc))
                                   ((none) acc)))))))
                       ix (h/omPairs mod0.vars)))
            (mod1 (optionOr (modOf ix1 name) mod0))]
        (fold (fn [(acc Ix) (dd PyDef)] -> Ix (selfAttrTypes acc mod1 dd))
              ix1 (optionOr (h/hmGet methods name) (list))))))

fn paramNodes fnNode: d/PyNode -> (List d/PyNode)
  (mt (d/kid fnNode "args")
    ((none) (list))
    ((some a)
      (listAppend (listAppend (listAppend (d/kids a "posonlyargs") (d/kids a "args")) (d/kids a "kwonlyargs"))
                  (listAppend (mt (d/kid a "vararg") ((some v) (list v)) ((none) (list))) (mt (d/kid a "kwarg") ((some v) (list v)) ((none) (list)))))))

fn localWalk n: d/PyNode acc: (h/HMap Bool) -> (h/HMap Bool)
  (let [(t n.type)]
    (cond
      ((defLike? t) (h/hmPut acc (nameOf n) true))
      ((= t "Lambda") acc)
      (else
        (let [(acc1 (cond
                      ((and (= t "Name") (let [(cx (optionOr (d/sfield n "ctx") ""))] (or (= cx "Store") (= cx "Del")))) (h/hmPut acc (idOf n) true))
                      ((or (= t "Import") (= t "ImportFrom"))
                        (fold (fn [(a2 (h/HMap Bool)) (al d/PyNode)] -> (h/HMap Bool)
                                (h/hmPut a2 (optionOr (listHead (stringSplit (optionOr (d/sfield al "asname") (aliasName al)) ".")) "") true))
                              acc (d/kids n "names")))
                      (else acc)))]
          (fold (fn [(a2 (h/HMap Bool)) (k d/PyNode)] -> (h/HMap Bool) (localWalk k a2)) acc1 (d/children n))))))

fn localNames fnNode: d/PyNode -> (h/HMap Bool)
  (let [(params (fold (fn [(acc (h/HMap Bool)) (p d/PyNode)] -> (h/HMap Bool) (h/hmPut acc (optionOr (d/sfield p "arg") "") true)) (h/hmEmpty) (paramNodes fnNode)))
        (body (if (d/isType? fnNode "Lambda") (mt (d/kid fnNode "body") ((some b) (list b)) ((none) (list))) (d/kids fnNode "body")))]
    (fold (fn [(acc (h/HMap Bool)) (n d/PyNode)] -> (h/HMap Bool) (localWalk n acc)) params body))

fn emptyScope kind: String key: (Option String) names: (h/HMap Bool) -> Scope
  (Scope :kind kind :key key :names names :bindings (h/hmEmpty) :defs (h/hmEmpty) :types (h/hmEmpty) :selfName (none) :cls (none) :nested false)

fn wLocal w: W key: String -> W
  (with w :localsAt (h/hmPut w.localsAt key true))

fn localKey rel: String line: Int64 name: String -> String
  (str rel "\x01" (stringFromInt64 line) "\x01" name)

fn scopeFor ix: Ix mod: PyMod dd: PyDef w: W -> (Pair Scope W)
  (let [(node dd.node)
        (w1 (fold (fn [(acc W) (p d/PyNode)] -> W (wLocal acc (localKey mod.rel p.line (optionOr (d/sfield p "arg") "")))) w (paramNodes node)))
        (binds (fold (fn [(acc (h/HMap Binding)) (n d/PyNode)] -> (h/HMap Binding)
                       (if (and (or (d/isType? n "Import") (d/isType? n "ImportFrom")) (!= n.id node.id))
                         (fold (fn [(a2 (h/HMap Binding)) (p (Pair String Binding))] -> (h/HMap Binding) (if (= (pairFirst p) "*") a2 (h/hmPut a2 (pairFirst p) (pairSecond p))))
                               acc (importBindings mod.pkg n))
                         acc))
                     (h/hmEmpty) (d/walkBfs node)))
        (defs0 (fold (fn [(acc (h/HMap String)) (k String)] -> (h/HMap String) (h/hmPut acc (lastSeg (keyQual k)) k))
                     (h/hmEmpty) (optionOr (h/hmGet ix.children dd.key) (list))))
        (decos (map (fn [(x d/PyNode)] -> String (optionOr x.u "")) (d/kids node "decorator_list")))
        (clsKey (defKey mod.name (optionOr dd.cls "")))
        (method (and (= dd.kind "method") (some? (firstArg node)) (not (listContains? decos "staticmethod"))))
        (classM (and method (listContains? decos "classmethod")))
        (sc (Scope :kind "function" :key (some dd.key) :names (localNames node) :bindings binds
                   :defs (if classM (h/hmPut defs0 (optionOr (firstArg node) "") clsKey) defs0)
                   :types (h/hmEmpty)
                   :selfName (if (and method (not classM)) (firstArg node) (none))
                   :cls (if (and method (not classM)) (some clsKey) (none))
                   :nested (= dd.kind "nested")))]
    (pair sc w1))

(schema WS (:f w W) (:f stack (List Scope)))

fn wCall w: W cs: CallSite -> W
  (with w :calls (cons cs w.calls))

fn wEdge w: W caller: String callee: String -> W
  (let [(cur (optionOr (h/hmGet w.edges caller) (h/hmEmpty)))]
    (with w :edges (h/hmPut w.edges caller (h/hmPut cur callee true))))

fn wRef w: W r: Ref -> W
  (with w :refs (cons r w.refs))

fn wDyn w: W r: Dyn -> W
  (with w :dynamic (cons r w.dynamic))

fn wUntyped w: W r: Untyped -> W
  (with w :untyped (cons r w.untyped))

fn wRead w: W key: String rel: String line: Int64 -> W
  (with w :varReads (h/hmPut w.varReads key (cons (pair rel line) (optionOr (h/hmGet w.varReads key) (list)))))

fn callerOf mod: PyMod stack: (List Scope) -> String
  (mt (listHead (filter (fn [(sc Scope)] -> Bool (and (some? sc.key) (!= sc.kind "class"))) stack))
    ((some sc) (optionOr sc.key ""))
    ((none) (defKey mod.name "<module>")))

fn contextOf stack: (List Scope) -> (Option String)
  (mt (listHead stack)
    ((none) (none))
    ((some sc)
      (cond
        ((= sc.kind "lambda") (some "lambda"))
        ((= sc.kind "function") (if sc.nested (some "nested") (none)))
        (else (contextOf (optionOr (listTail stack) (list)))))))

fn record ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) key: String how: String hops: Int64 via: (Option String) w: W -> W
  (let [(caller (callerOf mod stack))
        (kind0 (cond ((> hops 0) "reexport") ((listContains? (list "alias" "attribute" "method" "stringKey") how) how) (else "direct")))
        (cx (contextOf stack))
        (through (mt cx ((some x) (if (!= kind0 "direct") (some kind0) (none))) ((none) (none))))
        (kind (optionOr cx kind0))
        (w1 (wEdge (wCall w (CallSite :rel mod.rel :line node.line :caller caller :callee key :kind kind :via via :through through)) caller key))]
    (if (= (defKind ix key) "class")
      (mt (methodOf ix key "__init__" 0) ((some init) (wEdge w1 caller init)) ((none) w1))
      w1))

fn bindingOf mod: PyMod name: String stack: (List Scope) -> (Option Binding)
  (mt (listHead stack)
    ((none) (h/hmGet mod.bindings name))
    ((some sc)
      (mt (h/hmGet sc.bindings name)
        ((some b) (some b))
        ((none) (if (or (h/hmHas? sc.names name) (h/hmHas? sc.defs name)) (none) (bindingOf mod name (optionOr (listTail stack) (list))))))))

fn strsOf values: (List d/PyNode) -> (Option (List String))
  (let [(vals (fold (fn [(acc (List String)) (v d/PyNode)] -> (List String) (mt (d/constStr v) ((some s) (cons s acc)) ((none) acc))) (list) values))]
    (if (and (= (listLength vals) (listLength values)) (not (listEmpty? vals))) (some (listReverse vals)) (none)))

fn tableOf node0: d/PyNode mod: PyMod -> (Option (List String))
  (let [(node (if (d/isType? node0 "Name") (mt (h/omGet mod.vars (idOf node0)) ((some p) (pairSecond p)) ((none) node0)) node0))]
    (cond
      ((d/isType? node "Dict") (strsOf (d/kids node "values")))
      ((or (d/isType? node "Tuple") (d/isType? node "List") (d/isType? node "Set")) (strsOf (d/kids node "elts")))
      (else (none))))

fn literalNames expr: d/PyNode mod: PyMod -> (Option (List String))
  (mt (d/constStr expr)
    ((some s) (some (list s)))
    ((none) (if (d/isType? expr "Subscript") (mt (d/kid expr "value") ((some v) (tableOf v mod)) ((none) (none))) (none))))

fn argAt n: d/PyNode i: Int64 -> (Option d/PyNode)
  (listGet (d/kids n "args") i)

fn getattrName? ix: Ix mod: PyMod f: d/PyNode stack: (List Scope) -> Bool
  (and (d/isType? f "Name") (= (idOf f) "getattr") (not (some? (resolveName ix mod "getattr" stack))))

(schema OC (:f w W) (:f marks (List Int64)))

fn stringKeyCalls ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) base: Res names: (List String) w: W -> W
  (fold (fn [(acc W) (n String)] -> W
          (if (= base.tag "mod")
            (mt (resolveSym ix base.val n 0)
              ((some r)
                (cond
                  ((= r.tag "def") (record ix mod node stack r.val "stringKey" 0 (some (str "getattr " n)) acc))
                  ((= r.tag "var") (wRead acc r.val mod.rel node.line))
                  (else acc)))
              ((none) acc))
            (mt (methodOf ix base.val n 0)
              ((some k) (record ix mod node stack k "stringKey" 0 (some (str "getattr " n)) acc))
              ((none) acc))))
        w names)

fn viaOf ix: Ix mod: PyMod f: d/PyNode stack: (List Scope) r: Res -> (Option String)
  (let [(b (if (d/isType? f "Name") (bindingOf mod (idOf f) stack) (none)))
        (symVia (mt b ((some bb) (mt bb ((bSym base name how) (some (str base "." name))) (_ (none)))) ((none) (none))))]
    (if (and (> r.hops 0) (some? symVia))
      symVia
      (if (or (!= r.how "direct") (> r.hops 0))
        (let [(u (optionOr f.u ""))] (some (if (<= (pyLen u) 40) u (str (pyPrefix u 37) "..."))))
        (none))))

fn onCall ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) w: W -> OC
  (mt (d/kid node "func")
    ((none) (OC :w w :marks (list)))
    ((some f)
      (let [(inner (if (d/isType? f "Call") (d/kid f "func") (none)))]
        (cond
          ((and (some? inner) (getattrName? ix mod (optionOr inner f) stack) (>= (listLength (d/kids f "args")) 2))
            (let [(marks (list f.id (optionOr inner f).id))]
              (mt (resolveExpr ix mod (optionOr (argAt f 0) f) stack)
                ((none) (OC :w w :marks marks))
                ((some base)
                  (if (not (or (= base.tag "mod") (= base.tag "inst")))
                    (OC :w w :marks marks)
                    (mt (literalNames (optionOr (argAt f 1) f) mod)
                      ((none) (OC :w (wDyn w (Dyn :rel mod.rel :line node.line :tag base.tag :base base.val)) :marks marks))
                      ((some names) (OC :w (stringKeyCalls ix mod node stack base names w) :marks marks))))))))
          ((and (getattrName? ix mod f stack) (>= (listLength (d/kids node "args")) 2))
            (let [(base (resolveExpr ix mod (optionOr (argAt node 0) f) stack))
                  (names (literalNames (optionOr (argAt node 1) f) mod))]
              (mt base
                ((some bs)
                  (if (and (= bs.tag "mod") (some? names))
                    (OC :w (fold (fn [(acc W) (n String)] -> W
                                   (mt (resolveSym ix bs.val n 0) ((some r) (if (= r.tag "var") (wRead acc r.val mod.rel node.line) acc)) ((none) acc)))
                                 w (optionOr names (list)))
                        :marks (list f.id))
                    (OC :w w :marks (list f.id))))
                ((none) (OC :w w :marks (list f.id))))))
          (else
            (let [(r (resolveExpr ix mod f stack))
                  (w1 (mt r
                        ((some rr) (if (= rr.tag "def") (record ix mod node stack rr.val rr.how rr.hops (viaOf ix mod f stack rr) w) (untypedOr ix mod node f stack w)))
                        ((none) (untypedOr ix mod node f stack w))))]
              (OC :w w1
                  :marks (if (and (d/isType? f "Attribute") (some? r))
                           (list f.id (optionOr (d/kid f "value") f).id)
                           (list f.id)))))))))

fn untypedOr ix: Ix mod: PyMod node: d/PyNode f: d/PyNode stack: (List Scope) w: W -> W
  (if (and (d/isType? f "Attribute") (mt (d/kid f "value") ((some v) (not (some? (resolveExpr ix mod v stack)))) ((none) false)))
    (wUntyped w (Untyped :rel mod.rel :line node.line :attr (optionOr (d/sfield f "attr") "")))
    w)

fn defKeyAt mod: PyMod node: d/PyNode stack: (List Scope) -> String
  (let [(q (mt (listHead (filter (fn [(sc Scope)] -> Bool (and (mt sc.key ((some k) (= (keyMod k) mod.name)) ((none) false)) (!= sc.kind "lambda"))) stack))
             ((some sc) (str (keyQual (optionOr sc.key "")) "."))
             ((none) "")))]
    (defKey mod.name (str q (nameOf node))))

fn walkAll ix: Ix mod: PyMod nodes: (List d/PyNode) stack: (List Scope) called: (List Int64) w: W -> WS
  (fold (fn [(acc WS) (n d/PyNode)] -> WS (walk ix mod n acc.stack called acc.w)) (WS :w w :stack stack) nodes)

fn walkDef ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) called: (List Int64) w: W -> WS
  (let [(pre (listAppend (d/kids node "decorator_list")
                         (if (d/isType? node "ClassDef")
                           (listAppend (d/kids node "bases") (fold (fn [(acc (List d/PyNode)) (k d/PyNode)] -> (List d/PyNode) (mt (d/kid k "value") ((some v) (cons v acc)) ((none) acc))) (list) (listReverse (d/kids node "keywords"))))
                           (mt (d/kid node "args")
                             ((some a) (listAppend (d/kids a "defaults") (d/kids a "kw_defaults")))
                             ((none) (list))))))
        (ws1 (walkAll ix mod pre stack called w))
        (key (defKeyAt mod node ws1.stack))]
    (mt (defOf ix key)
      ((none) ws1)
      ((some dd)
        (let [(scw (if (= dd.kind "class")
                     (pair (emptyScope "class" (some key) (h/hmEmpty)) ws1.w)
                     (scopeFor ix mod dd ws1.w)))
              (inner (walkAll ix mod (d/kids node "body") (cons (pairFirst scw) ws1.stack) called (pairSecond scw)))]
          (WS :w inner.w :stack ws1.stack)))))

fn withTypes sc: Scope types: (h/HMap String) -> Scope
  (with sc :types types)

fn assignTypes ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) -> (List Scope)
  (mt (listHead stack)
    ((none) stack)
    ((some top)
      (if (not (and (d/isType? node "Assign") (= top.kind "function") (mt (d/kid node "value") ((some v) (d/isType? v "Call")) ((none) false))))
        stack
        (mt (resolveExpr ix mod (optionOr (d/kid node "value") node) stack)
          ((some r)
            (if (= r.tag "inst")
              (cons (withTypes top (fold (fn [(acc (h/HMap String)) (t d/PyNode)] -> (h/HMap String) (if (d/isType? t "Name") (h/hmPut acc (idOf t) r.val) acc))
                                         top.types (d/kids node "targets")))
                    (optionOr (listTail stack) (list)))
              stack))
          ((none) stack)))))

fn walk ix: Ix mod: PyMod node: d/PyNode stack: (List Scope) called: (List Int64) w: W -> WS
  (let [(t node.type)]
    (cond
      ((defLike? t) (walkDef ix mod node stack called w))
      ((= t "Lambda")
        (let [(sc (emptyScope "lambda" (h/hmGet ix.lambdaKeys (stringFromInt64 node.id)) (localNames node)))
              (inner (walkAll ix mod (mt (d/kid node "body") ((some b) (list b)) ((none) (list))) (cons sc stack) called w))]
          (WS :w inner.w :stack stack)))
      (else
        (let [(stack1 (assignTypes ix mod node stack))
              (w1 (if (and (= t "Name")
                           (listAny? (fn [(sc Scope)] -> Bool (and (!= sc.kind "class") (h/hmHas? sc.names (idOf node)))) stack1)
                           (not (some? (resolveName ix mod (idOf node) stack1))))
                    (wLocal w (localKey mod.rel node.line (idOf node)))
                    w))
              (oc (if (= t "Call")
                    (let [(o (onCall ix mod node stack1 w1))] (OC :w o.w :marks (listAppend o.marks called)))
                    (if (and (or (= t "Name") (= t "Attribute")) (= (d/sfield node "ctx") (some "Load")) (not (listContains? called node.id)))
                      (let [(r (resolveExpr ix mod node stack1))
                            (w2 (mt r
                                  ((some rr) (cond
                                               ((= rr.tag "def") (wRef w1 (Ref :rel mod.rel :line node.line :key rr.val)))
                                               ((= rr.tag "var") (wRead w1 rr.val mod.rel node.line))
                                               (else w1)))
                                  ((none) w1)))
                            (more (mt r
                                    ((some rr) (if (and (= t "Attribute") (or (= rr.tag "def") (= rr.tag "var"))) (mt (d/kid node "value") ((some v) (list v.id)) ((none) (list))) (list)))
                                    ((none) (list))))]
                        (OC :w w2 :marks (listAppend more called)))
                      (OC :w w1 :marks called))))]
          (walkAll ix mod (d/children node) stack1 oc.marks oc.w)))))

fn emptyW -> W
  (W :calls (list) :refs (list) :dynamic (list) :untyped (list) :varReads (h/hmEmpty) :edges (h/hmEmpty) :localsAt (h/hmEmpty))

fn pkgsOf names: (List String) -> (h/HMap Bool)
  (fold (fn [(acc (h/HMap Bool)) (n String)] -> (h/HMap Bool)
          (let [(parts (stringSplit n "."))]
            (fold (fn [(a2 (h/HMap Bool)) (i Int64)] -> (h/HMap Bool) (h/hmPut a2 (c/joinWith (listTake parts i) ".") true)) acc (range 1 (listLength parts)))))
        (h/hmEmpty) names)

fn childrenOf defs: (List PyDef) -> (h/HMap (List String))
  (let [(rev (fold (fn [(acc (h/HMap (List String))) (dd PyDef)] -> (h/HMap (List String))
                     (let [(parent (rpartDot dd.qual))]
                       (if (stringEmpty? parent) acc
                         (let [(pk (defKey dd.modName parent))] (h/hmPut acc pk (cons dd.key (optionOr (h/hmGet acc pk) (list))))))))
                   (h/hmEmpty) defs))]
    (fold (fn [(acc (h/HMap (List String))) (p (Pair String (List String)))] -> (h/HMap (List String)) (h/hmPut acc (pairFirst p) (listReverse (pairSecond p))))
          (h/hmEmpty) (h/hmPairs rev)))

fn ! loadMods! root: String files: (List d/PyFile) -> (Result (Pair (h/OMap PyMod) (List String)) String)
  (fold (fn [(acc (Result (Pair (h/OMap PyMod) (List String)) String)) (f d/PyFile)] -> (Result (Pair (h/OMap PyMod) (List String)) String)
          (mt acc
            ((err e) (err e))
            ((ok st)
              (mt f.tree
                ((none) (ok (pair (pairFirst st) (cons f.rel (pairSecond st)))))
                ((some tree)
                  (mt (fileReadString (c/joinPath root f.rel))
                    ((err e) (err (str "cannot read " f.rel ": " e)))
                    ((ok raw)
                      (let [(mn (moduleName f.rel)) (name (pairFirst mn)) (isPkg (pairSecond mn))
                            (m (PyMod :rel f.rel :name name :isPkg isPkg :pkg (if isPkg name (rpartDot name)) :src (c/universalNewlines raw) :tree tree
                                      :isTest (testRel? f.rel) :toks f.toks :top (h/hmEmpty) :bindings (h/hmEmpty) :vars (h/omEmpty)
                                      :varTypes (h/hmEmpty) :stars (list) :docstrings (h/hmEmpty) :importLines (h/hmEmpty) :comments (commentToks f.toks)))]
                        (ok (pair (h/omPut (pairFirst st) name m) (pairSecond st)))))))))))
        (ok (pair (h/omEmpty) (list))) files)

fn collectMod st: (Pair (h/OMap PyMod) (h/OMap PyDef)) m: PyMod -> (Pair (h/OMap PyMod) (h/OMap PyDef))
  (let [(b (Base :rel m.rel :name m.name :pkg m.pkg))
        (mc (collect b (d/kids m.tree "body") "" (none) false
                     (MC :top (h/hmEmpty) :bindings (h/hmEmpty) :vars (h/omEmpty) :stars (list) :importLines (h/hmEmpty) :defs (pairSecond st) :own (h/hmEmpty))))
        (m2 (PyMod :rel m.rel :name m.name :isPkg m.isPkg :pkg m.pkg :src m.src :tree m.tree :isTest m.isTest :toks m.toks
                   :top mc.top :bindings mc.bindings :vars mc.vars :varTypes (h/hmEmpty) :stars (listReverse mc.stars)
                   :docstrings (docstringsOf m.tree (fold (fn [(acc (List d/PyNode)) (o (Option d/PyNode))] -> (List d/PyNode) (mt o ((some n) (cons n acc)) ((none) acc))) (list) (h/hmValues mc.own))) :importLines mc.importLines :comments m.comments))]
    (pair (h/omPut (pairFirst st) m.name m2) mc.defs))

fn ! buildPyIndex root: String want: String files: (List String) ctx: c/Ctx -> (Result Built String)
  (let [(rels (filter (fn [(f String)] -> Bool (stringEndsWith? f ".py")) files))]
    (mt (d/runDump! root want rels ctx)
      ((err e) (err e))
      ((ok dump)
        (mt dump
          ((d/absent why) (ok (pyAbsent why)))
          ((d/dumped pfiles warnings)
            (mt (loadMods! root pfiles)
              ((err e) (err e))
              ((ok lm)
                (let [(mods0 (pairFirst lm))
                      (collected (fold collectMod (pair mods0 (h/omEmpty)) (h/omValues mods0)))
                      (defs (pairSecond collected))
                      (defList (h/omValues defs))
                      (ix0 (Ix :mods (pairFirst collected) :pkgs (pkgsOf (map (fn [(p (Pair String PyMod))] -> String (pairFirst p)) (h/omPairs (pairFirst collected))))
                               :defs defs :attrTypes (h/hmEmpty) :children (childrenOf defList)
                               :lambdaKeys (fold (fn [(acc (h/HMap String)) (dd PyDef)] -> (h/HMap String) (if (= dd.kind "lambda") (h/hmPut acc (stringFromInt64 dd.node.id) dd.key) acc))
                                                 (h/hmEmpty) defList)))
                      (names (map (fn [(p (Pair String PyMod))] -> String (pairFirst p)) (h/omPairs ix0.mods)))
                      (methods (fold (fn [(acc (h/HMap (List PyDef))) (dd PyDef)] -> (h/HMap (List PyDef)) (if (= dd.kind "method") (h/hmPut acc dd.modName (cons dd (optionOr (h/hmGet acc dd.modName) (list)))) acc))
                                     (h/hmEmpty) (listReverse defList)))
                      (ix (fold (fn [(acc Ix) (nm String)] -> Ix (typesOf methods acc nm)) ix0 names))
                      (w (fold (fn [(acc W) (m PyMod)] -> W
                                 (fold (fn [(a2 W) (st d/PyNode)] -> W (walk ix m st (list) (list) a2).w) acc (d/kids m.tree "body")))
                               (emptyW) (h/omValues ix.mods)))
                      (wOut (W :calls (listReverse w.calls) :refs (listReverse w.refs) :dynamic (listReverse w.dynamic) :untyped (listReverse w.untyped)
                               :varReads w.varReads :edges w.edges :localsAt w.localsAt))]
                  (ok (built (PyIndex :root root :ix ix :w wOut :unparsed (listReverse (pairSecond lm)) :warnings warnings)))))))))))
