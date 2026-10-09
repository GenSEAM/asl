(module ws/asl/tools/observe/status
  :x [observeStatus! constName?]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)
      (ws/asl/tools/observe/pyDump :a d)
      (ws/asl/tools/observe/pyIndex :a p)
      (ws/asl/tools/observe/pyQuery :a q)
      (ws/asl/tools/observe/callers :a cal)])

fn statusLimits -> String
  (str "python only; tests reach a symbol through resolved calls (setUp included), not stored function values; "
       "a patch cuts its target everywhere, not only in the patched namespace")

fn testsPerDef -> Int64
  8

fn constName? n: String -> Bool
  (let [(bs (stringToBytes n)) (len (bytesLength bs))]
    (and (> len 0) (>= (bytesGet bs 0) 65) (<= (bytesGet bs 0) 90)
         (listAll? (fn [(i Int64)] -> Bool (let [(b (bytesGet bs i))] (or (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57)) (= b 95)))) (range 1 len))))

fn boolText b: Bool -> String
  (if b "true" "false")

(schema TInfo (:f t p/PyDef) (:f cut (h/HMap Bool)) (:f reached (h/HMap Bool)))

fn count m: (h/HMap Int64) k: String -> Int64
  (optionOr (h/hmGet m k) 0)

fn bump m: (h/HMap Int64) k: String -> (h/HMap Int64)
  (h/hmPut m k (+ (count m k) 1))

fn statusForm pi: p/PyIndex dd: p/PyDef callsBy: (h/HMap Int64) refsBy: (h/HMap Int64) infos: (List TInfo) -> String
  (let [(why (q/stubWhy pi dd))
        (tforms (fold (fn [(acc (List String)) (ti TInfo)] -> (List String)
                        (let [(t ti.t)
                              (mocked (h/hmHas? ti.cut dd.key))
                              (executes (and (not mocked) (or (h/hmHas? ti.reached dd.key) (= dd.key t.key))))]
                          (if (not (or mocked executes))
                            acc
                            (cons (str "(:at " (c/atStr t.rel t.line) " :test " (c/quoted t.qual) " :executes " (boolText executes)
                                       " :mocked " (boolText mocked) " :skipped " (boolText (q/skipped pi t)) ")")
                                  acc))))
                      (list) infos))
        (all (listReverse tforms))
        (shown (listTake all (testsPerDef)))
        (decos (map (fn [(x d/PyNode)] -> String (optionOr x.u "")) (d/kids dd.node "decorator_list")))]
    (str "(:symbol " (c/quoted dd.qual) " :at " (c/atStr dd.rel dd.line) " :kind " dd.kind " :stub "
         (mt why ((some w) (str "true :stubWhy " (c/quoted w))) ((none) "false"))
         " :callers " (stringFromInt64 (count callsBy dd.key)) " :refs " (stringFromInt64 (count refsBy dd.key))
         (if (listEmpty? decos) "" (str " :decorators (" (c/joinWith (map (fn [(x String)] -> String (c/quoted (p/pyPrefix x 40))) decos) " ") ")"))
         " :tests (" (c/joinWith shown " ") ")"
         (if (> (listLength all) (listLength shown)) (str " :moreTests " (stringFromInt64 (- (listLength all) (listLength shown)))) "")
         ")"))

fn padLine n: Int64 -> String
  (cal/padLine n)

(schema Const (:f mod p/PyMod) (:f name String) (:f line Int64))

fn constOf m: p/PyMod n: String -> Const
  (Const :mod m :name n :line (mt (h/omGet m.vars n) ((some pr) (pairFirst pr)) ((none) 0)))

fn flagForm pi: p/PyIndex k: Const -> String
  (let [(reads (optionOr (h/hmGet pi.w.varReads (p/defKey k.mod.name k.name)) (list)))
        (readers (c/sortUnique (map (fn [(r (Pair String Int64))] -> String (pairFirst r)) reads)))]
    (str "(:name " k.name " :at " (c/atStr k.mod.rel k.line) " :reads " (stringFromInt64 (listLength reads))
         " :readers (" (c/joinWith (map c/quoted (listTake readers 4)) " ") ")"
         " :flagUnread " (boolText (listEmpty? reads)) ")"))

(schema Sel (:f defs (List p/PyDef)) (:f consts (List Const)))

fn ! selectPath pi: p/PyIndex path: String -> (Result Sel String)
  (mt (listHead (filter (fn [(m p/PyMod)] -> Bool (= m.rel path)) (h/omValues pi.ix.mods)))
    ((none)
      (if (listContains? pi.unparsed path)
        (err (c/rejectLine "ERR_PARSE" (str path " does not parse as Python") ""))
        (err (c/rejectLine "ERR_BAD_ARG" (str "status reads Python files; not a Python file of this workspace: " path) ""))))
    ((some m)
      (ok (Sel :defs (listSortBy (fn [(dd p/PyDef)] -> String (padLine dd.line))
                                 (filter (fn [(dd p/PyDef)] -> Bool (and (= dd.modName m.name) (listContains? (list "function" "method" "nested") dd.kind))) (q/allDefs pi)))
               :consts (map (fn [(pr (Pair String (Pair Int64 d/PyNode)))] -> Const (constOf m (pairFirst pr)))
                            (filter (fn [(pr (Pair String (Pair Int64 d/PyNode)))] -> Bool (constName? (pairFirst pr))) (h/omPairs m.vars)))))))

fn ! selectSymbol pi: p/PyIndex symbol: String -> (Result Sel String)
  (let [(defs (listSortBy (fn [(dd p/PyDef)] -> String (str dd.rel "\x00" (padLine dd.line)))
                          (filter (fn [(dd p/PyDef)] -> Bool (and (!= dd.kind "class") (or (= dd.name symbol) (= dd.qual symbol) (stringEndsWith? dd.qual (str "." symbol)))))
                                  (q/allDefs pi))))
        (mods (h/omValues pi.ix.mods))
        (consts (if (constName? symbol) (map (fn [(m p/PyMod)] -> Const (constOf m symbol)) (filter (fn [(m p/PyMod)] -> Bool (h/omHas? m.vars symbol)) mods)) (list)))]
    (if (and (listEmpty? defs) (listEmpty? consts))
      (let [(names (c/sortUnique (listAppend (map (fn [(dd p/PyDef)] -> String dd.name) (q/allDefs pi))
                                             (fold (fn [(acc (List String)) (m p/PyMod)] -> (List String) (listAppend acc (map (fn [(pr (Pair String (Pair Int64 d/PyNode)))] -> String (pairFirst pr)) (h/omPairs m.vars)))) (list) mods))))
            (near (c/closeMatches symbol names 3 0.6))]
        (err (c/rejectLine "ERR_SYMBOL_NOT_FOUND" (str "no Python definition or module constant " symbol " in this workspace")
                           (str " :symbol " (c/quoted symbol) " :nearest (" (c/joinWith (map c/quoted near) " ") ")"))))
      (ok (Sel :defs defs :consts consts))))

fn ! statusOver! root: String pi: p/PyIndex symbol: String path: String limit: Int64 ctx: c/Ctx -> (Result String String)
  (mt (if (stringEmpty? path) (selectSymbol pi symbol) (selectPath pi path))
    ((err e) (err e))
    ((ok sel)
      (let [(callsBy (fold (fn [(acc (h/HMap Int64)) (cs p/CallSite)] -> (h/HMap Int64) (bump acc cs.callee)) (h/hmEmpty) pi.w.calls))
            (refsBy (fold (fn [(acc (h/HMap Int64)) (r p/Ref)] -> (h/HMap Int64) (bump acc r.key)) (h/hmEmpty) pi.w.refs))
            (infos (map (fn [(t p/PyDef)] -> TInfo (let [(cut (q/patches pi t))] (TInfo :t t :cut cut :reached (q/reach pi t cut)))) (q/testDefs pi)))
            (defItems (map (fn [(dd p/PyDef)] -> String (statusForm pi dd callsBy refsBy infos)) sel.defs))
            (consts (listSortBy (fn [(k Const)] -> String (str k.mod.rel "\x00" (padLine k.line))) sel.consts))
            (flagItems (map (fn [(k Const)] -> String (flagForm pi k)) consts))
            (stubs (listLength (filter (fn [(dd p/PyDef)] -> Bool (some? (q/stubWhy pi dd))) sel.defs)))
            (unread (listLength (filter (fn [(f String)] -> Bool (stringContains? f ":flagUnread true")) flagItems)))]
        (mt (c/shortRev! root ctx)
          ((err e) (err e))
          ((ok rev)
            (let [(head (str "(:observe :dim status :v 1" (if (stringEmpty? symbol) (str " :path " (c/quoted path)) (str " :symbol " (c/quoted symbol)))
                             " :rev " rev " :count (:defs " (stringFromInt64 (listLength defItems)) " :stubs " (stringFromInt64 stubs)
                             " :flags " (stringFromInt64 (listLength flagItems)) " :flagUnread " (stringFromInt64 unread) ")"))]
              (c/fitReceipt head (list (c/Section :key "defs" :items defItems :limit limit) (c/Section :key "flags" :items flagItems :limit limit))
                            (str " :limits " (c/quoted (statusLimits))) "status")))))))

fn ! observeStatus! root: String symbol: String path: String limit: Int64 ctx: c/Ctx -> (Pair String (Result String String))
  (mt (c/workspaceFiles! root ctx)
    ((err e) (pair "" (err e)))
    ((ok files)
      (mt (p/buildPyIndex root "" files ctx)
        ((err e) (pair "" (err e)))
        ((ok b)
          (mt b
            ((p/pyAbsent why) (pair "" (err (cal/absentLine "status" why))))
            ((p/built pi) (pair pi.warnings (statusOver! root pi symbol path limit ctx))))))))
