(module ws/asl/tools/observe/pyQuery
  :x [targets stubWhy testDefs skipped patches reach directCallees commentsOf wordAt? todoIn? allDefs]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)
      (ws/asl/tools/observe/pyDump :a d)
      (ws/asl/tools/observe/pyIndex :a p)])

fn allDefs pi: p/PyIndex -> (List p/PyDef)
  (h/omValues pi.ix.defs)

fn keep? module: String dd: p/PyDef -> Bool
  (or (stringEmpty? module) (= module dd.rel) (= module dd.modName))

fn targets pi: p/PyIndex name: String module: String -> (List p/PyDef)
  (let [(ds (allDefs pi))]
    (if (stringContains? name ".")
      (filter (fn [(dd p/PyDef)] -> Bool (and (or (= dd.qual name) (stringEndsWith? dd.qual (str "." name))) (keep? module dd))) ds)
      (let [(top (filter (fn [(dd p/PyDef)] -> Bool (and (= dd.name name) (listContains? (list "function" "class" "lambda") dd.kind) (keep? module dd))) ds))]
        (if (not (listEmpty? top)) top (filter (fn [(dd p/PyDef)] -> Bool (and (= dd.name name) (keep? module dd))) ds)))))

fn commentsOf m: p/PyMod -> (List (Pair Int64 String))
  m.comments

fn wordCode? k: Int64 -> Bool
  (cond
    ((< k 0) false)
    ((< k 128) (or (and (>= k 48) (<= k 57)) (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)) (= k 95)))
    ((c/pyIsSpaceCode k) false)
    ((and (>= k 161) (<= k 191)) (listContains? (list 170 178 179 181 185 186 188 189 190) k))
    ((or (= k 215) (= k 247)) false)
    ((and (>= k 8208) (<= k 8231)) false)
    ((and (>= k 8240) (<= k 8286)) false)
    ((and (>= k 12288) (<= k 12291)) false)
    ((and (>= k 12296) (<= k 12305)) false)
    (else true))

fn codeBefore s: String i: Int64 -> Int64
  (if (<= i 0) -1 (let [(cs (c/charCodes (optionOr (stringSlice s (max 0 (- i 4)) i) "")))] (mt (listLast cs) ((some p) (pairFirst p)) ((none) -1))))

fn codeAfter s: String i: Int64 -> Int64
  (if (>= i (stringLength s)) -1 (mt (listHead (c/charCodes (optionOr (stringSlice s i (min (stringLength s) (+ i 4))) ""))) ((some p) (pairFirst p)) ((none) -1)))

fn wordAt? s: String i: Int64 j: Int64 -> Bool
  (let [(first (codeAfter s i)) (last (codeBefore s j))]
    (and (!= (wordCode? (codeBefore s i)) (wordCode? first))
         (!= (wordCode? last) (wordCode? (codeAfter s j)))))

fn occurrences s: String w: String from: Int64 acc: (List Int64) -> (List Int64)
  (let [(bs (stringToBytes s)) (i (c/findFrom bs (bytesLength bs) (stringToBytes w) from))]
    (if (< i 0) (listReverse acc) (occurrences s w (+ i 1) (cons i acc))))

fn anyWord? s: String w: String -> Bool
  (listAny? (fn [(i Int64)] -> Bool (wordAt? s i (+ i (stringLength w)))) (occurrences s w 0 (list)))

fn todoIn? text: String -> Bool
  (or (anyWord? text "TODO") (anyWord? text "FIXME") (anyWord? text "XXX"))

fn skipRx? s: String -> Bool
  (let [(starts (occurrences s "skip" 0 (list)))
        (lead? (fn [(i Int64)] -> Bool (not (wordCode? (codeBefore s i)))))
        (tail? (fn [(j Int64)] -> Bool (not (wordCode? (codeAfter s j)))))
        (sub (fn [(i Int64) (w String)] -> Bool (= (optionOr (stringSlice s i (+ i (stringLength w))) "") w)))]
    (or (listAny? (fn [(i Int64)] -> Bool
                    (and (lead? i)
                         (or (and (sub (+ i 4) "If") (tail? (+ i 6)))
                             (and (sub (+ i 4) "Unless") (tail? (+ i 10)))
                             (tail? (+ i 4)))))
                  starts)
        (listAny? (fn [(i Int64)] -> Bool
                    (and (>= i 5) (sub (- i 5) "mark.") (lead? (- i 5))
                         (or (and (sub (+ i 4) "if") (tail? (+ i 6))) (tail? (+ i 4)))))
                  starts)))

fn bodyNoDoc n: d/PyNode -> (List d/PyNode)
  (let [(body (d/kids n "body"))]
    (mt (listHead body)
      ((some b0) (if (and (d/isType? b0 "Expr") (mt (d/kid b0 "value") ((some v) (some? (d/constStr v))) ((none) false))) (optionOr (listTail body) (list)) body))
      ((none) body)))

fn exprConst? s: d/PyNode kind: String -> Bool
  (and (d/isType? s "Expr") (mt (d/kid s "value") ((some v) (= (d/constKind v) (some kind))) ((none) false)))

fn singleWhy s: d/PyNode -> (Option String)
  (cond
    ((and (d/isType? s "Raise") (some? (d/kid s "exc")))
      (let [(ex (optionOr (d/kid s "exc") s))
            (e (if (d/isType? ex "Call") (optionOr (d/kid ex "func") ex) ex))
            (nm (optionOr (d/sfield e "id") ""))]
        (if (and (d/isType? e "Name") (or (= nm "NotImplementedError") (= nm "NotImplemented"))) (some (str "raises " nm)) (none))))
    ((d/isType? s "Return")
      (mt (d/kid s "value")
        ((none) (some "returns None"))
        ((some v)
          (cond
            ((= (d/constKind v) (some "NoneType")) (some "returns None"))
            ((and (d/isType? v "Name") (= (d/sfield v "id") (some "NotImplemented"))) (some "returns NotImplemented"))
            (else (none))))))
    (else (none)))

fn stubWhy pi: p/PyIndex dd: p/PyDef -> (Option String)
  (if (or (= dd.kind "class") (= dd.kind "lambda"))
    (none)
    (let [(body (bodyNoDoc dd.node))]
      (cond
        ((listEmpty? body) (some "docstring only"))
        ((listAll? (fn [(s d/PyNode)] -> Bool (d/isType? s "Pass")) body) (some "body is pass"))
        ((listAll? (fn [(s d/PyNode)] -> Bool (exprConst? s "ellipsis")) body) (some "body is ..."))
        (else
          (let [(single (if (= (listLength body) 1) (singleWhy (optionOr (listHead body) dd.node)) (none)))]
            (mt single
              ((some w) (some w))
              ((none)
                (mt (p/modOf pi.ix dd.modName)
                  ((none) (none))
                  ((some m)
                    (mt (listHead (filter (fn [(cm (Pair Int64 String))] -> Bool (and (<= dd.line (pairFirst cm)) (<= (pairFirst cm) dd.end) (todoIn? (pairSecond cm)))) (commentsOf m)))
                      ((some cm) (some (str "TODO at line " (stringFromInt64 (pairFirst cm)))))
                      ((none) (none))))))))))))

fn isTestMod? pi: p/PyIndex dd: p/PyDef -> Bool
  (mt (p/modOf pi.ix dd.modName) ((some m) m.isTest) ((none) false))

fn padLine n: Int64 -> String
  (let [(s (stringFromInt64 n))] (str (stringRepeat "0" (max 0 (- 12 (stringLength s)))) s))

fn testDefs pi: p/PyIndex -> (List p/PyDef)
  (listSortBy (fn [(dd p/PyDef)] -> String (str dd.rel "\x00" (padLine dd.line)))
              (filter (fn [(dd p/PyDef)] -> Bool
                        (and (isTestMod? pi dd) (stringStartsWith? dd.name "test")
                             (or (= dd.kind "function")
                                 (and (= dd.kind "method") (= (p/defKind pi.ix (p/defKey dd.modName (optionOr dd.cls ""))) "class")))))
                      (allDefs pi)))

fn classDecos pi: p/PyIndex t: p/PyDef -> (List d/PyNode)
  (mt t.cls
    ((some cq) (mt (p/defOf pi.ix (p/defKey t.modName cq)) ((some cd) (d/kids cd.node "decorator_list")) ((none) (list))))
    ((none) (list)))

fn skipped pi: p/PyIndex t: p/PyDef -> Bool
  (let [(decos (listAppend (d/kids t.node "decorator_list") (classDecos pi t)))]
    (or (listAny? (fn [(x d/PyNode)] -> Bool (skipRx? (optionOr x.u ""))) decos)
        (listAny? (fn [(n d/PyNode)] -> Bool
                    (and (d/isType? n "Call")
                         (mt (d/kid n "func")
                           ((some f) (let [(s (optionOr f.u ""))] (or (stringEndsWith? s "skipTest") (= s "pytest.skip") (= s "skip"))))
                           ((none) false))))
                  (d/walkBfs t.node))))

fn dottedStep ix: p/Ix cur: (Option p/Res) part: String -> (Option p/Res)
  (mt cur
    ((none) (none))
    ((some r)
      (cond
        ((= r.tag "mod") (p/resolveSym ix r.val part 0))
        ((and (= r.tag "def") (= (p/defKind ix r.val) "class"))
          (optionMap (fn [(k String)] -> p/Res (p/Res :tag "def" :val k :how "" :hops 0)) (p/methodOf ix r.val part 0)))
        (else (none)))))

fn dottedFrom ix: p/Ix parts: (List String) i: Int64 -> (Option String)
  (if (< i 1)
    (none)
    (let [(m (c/joinWith (listTake parts i) "."))]
      (if (not (or (h/omHas? ix.mods m) (h/hmHas? ix.pkgs m)))
        (dottedFrom ix parts (- i 1))
        (mt (fold (fn [(cur (Option p/Res)) (part String)] -> (Option p/Res) (dottedStep ix cur part))
                  (some (p/Res :tag "mod" :val m :how "" :hops 0)) (listDrop parts i))
          ((some r) (if (= r.tag "def") (some r.val) (none)))
          ((none) (none))))))

fn resolveDotted ix: p/Ix s: String -> (Option String)
  (let [(parts (stringSplit s "."))] (dottedFrom ix parts (- (listLength parts) 1)))

fn patchKey pi: p/PyIndex tmod: p/PyMod n: d/PyNode -> (Option String)
  (let [(ix pi.ix)
        (fname (mt (d/kid n "func") ((some f) (optionOr f.u "")) ((none) "")))
        (args (d/kids n "args"))
        (arg0 (listGet args 0))
        (str0 (mt arg0 ((some a) (d/constStr a)) ((none) (none))))
        (str1 (mt (listGet args 1) ((some a) (d/constStr a)) ((none) (none))))
        (monkey (and (stringEndsWith? fname ".setattr") (stringContains? fname "monkeypatch")))]
    (cond
      ((and (or (= fname "patch") (stringEndsWith? fname ".patch")) (some? str0)) (resolveDotted ix (optionOr str0 "")))
      ((and (or (stringEndsWith? fname "patch.object") monkey) (>= (listLength args) 2) (some? str1))
        (let [(attr (optionOr str1 ""))]
          (mt (p/resolveExpr ix tmod (optionOr arg0 n) (list))
            ((some base)
              (cond
                ((= base.tag "mod")
                  (mt (p/resolveSym ix base.val attr 0) ((some r) (if (= r.tag "def") (some r.val) (none))) ((none) (none))))
                ((or (= base.tag "def") (= base.tag "inst"))
                  (if (= (p/defKind ix base.val) "class") (p/methodOf ix base.val attr 0) (none)))
                (else (none))))
            ((none) (none)))))
      ((and monkey (some? str0)) (resolveDotted ix (optionOr str0 "")))
      (else (none))))

fn patches pi: p/PyIndex t: p/PyDef -> (h/HMap Bool)
  (mt (p/modOf pi.ix t.modName)
    ((none) (h/hmEmpty))
    ((some tmod)
      (let [(roots (listAppend (listAppend (d/kids t.node "decorator_list") (list t.node)) (classDecos pi t)))]
        (fold (fn [(acc (h/HMap Bool)) (root d/PyNode)] -> (h/HMap Bool)
                (fold (fn [(a2 (h/HMap Bool)) (n d/PyNode)] -> (h/HMap Bool)
                        (if (d/isType? n "Call") (mt (patchKey pi tmod n) ((some k) (h/hmPut a2 k true)) ((none) a2)) a2))
                      acc (d/walkBfs root)))
              (h/hmEmpty) roots))))

fn edgesOf pi: p/PyIndex k: String -> (List String)
  (map (fn [(q (Pair String Bool))] -> String (pairFirst q)) (h/hmPairs (optionOr (h/hmGet pi.w.edges k) (h/hmEmpty))))

fn reachLoop pi: p/PyIndex todo: (List String) cut: (h/HMap Bool) seen: (h/HMap Bool) -> (h/HMap Bool)
  (mt (listHead todo)
    ((none) seen)
    ((some k)
      (let [(st (fold (fn [(acc (Pair (h/HMap Bool) (List String))) (cc String)] -> (Pair (h/HMap Bool) (List String))
                        (if (or (h/hmHas? (pairFirst acc) cc) (h/hmHas? cut cc)) acc (pair (h/hmPut (pairFirst acc) cc true) (cons cc (pairSecond acc)))))
                      (pair seen (optionOr (listTail todo) (list))) (edgesOf pi k)))]
        (reachLoop pi (pairSecond st) cut (pairFirst st)))))

fn reach pi: p/PyIndex t: p/PyDef cut: (h/HMap Bool) -> (h/HMap Bool)
  (let [(setUp (mt t.cls ((some cq) (p/methodOf pi.ix (p/defKey t.modName cq) "setUp" 0)) ((none) (none))))
        (start (mt setUp ((some s) (list t.key s)) ((none) (list t.key))))]
    (reachLoop pi start cut (h/hmEmpty)))

fn directCallees pi: p/PyIndex t: p/PyDef -> (h/HMap Bool)
  (optionOr (h/hmGet pi.w.edges t.key) (h/hmEmpty))
