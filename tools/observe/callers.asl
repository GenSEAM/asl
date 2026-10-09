(module ws/asl/tools/observe/callers
  :x [observeCallers! textMentions! absentLine setOf padLine]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/hmap :a h)
      (ws/asl/tools/observe/aslIndex :a ai)
      (ws/asl/tools/observe/pyDump :a d)
      (ws/asl/tools/observe/pyIndex :a p)
      (ws/asl/tools/observe/pyQuery :a q)])

fn callersLimits -> String
  (str "python: static ast resolution over this workspace; a call through an untyped receiver, a stored "
       "function value or a dynamic getattr name is :possible; asl: (alias/name ...) through the module "
       ":i/:import aliases and same-module (name ...) heads; asl graph answers the asex graph, not this workspace")

fn textExt -> (List String)
  (list ".md" ".txt" ".rst" ".asn" ".toml" ".cfg" ".ini" ".yaml" ".yml" ".json")

fn textMaxBytes -> Int64
  1048576

fn rankOf why: String -> Int64
  (cond ((= why "otherDefinition") 0) ((= why "importOnly") 1) ((= why "docstring") 2) ((= why "string") 3) ((= why "comment") 4) ((= why "similarName") 5) (else 6))

fn keyOf rel: String line: Int64 -> String
  (str rel "\x00" (stringFromInt64 line))

fn putFound found: (h/HMap ai/Mention) accounted: (h/HMap Bool) m: ai/Mention -> (h/HMap ai/Mention)
  (let [(k (keyOf m.rel m.line))]
    (if (h/hmHas? accounted k)
      found
      (mt (h/hmGet found k)
        ((none) (h/hmPut found k m))
        ((some cur) (if (< (rankOf m.why) (rankOf cur.why)) (h/hmPut found k m) found)))))

fn proseLines rel: String text: String sym: String -> (List ai/Mention)
  (let [(ls (c/keepEndsLines (c/universalNewlines text)))]
    (fold (fn [(acc (List ai/Mention)) (p (Pair Int64 String))] -> (List ai/Mention)
            (if (stringContains? (pairSecond p) sym) (cons (ai/Mention :rel rel :line (+ (pairFirst p) 1) :why "prose") acc) acc))
          (list) (enumerate ls)))

fn textMentions! root: String files: (List String) sym: String accounted: (h/HMap Bool) found: (h/HMap ai/Mention) -> (h/HMap ai/Mention)
  (fold (fn [(acc (h/HMap ai/Mention)) (rel String)] -> (h/HMap ai/Mention)
          (if (not (listContains? (textExt) (stringLower (pairSecond (c/splitExt rel)))))
            acc
            (let [(full (c/joinPath root rel))]
              (mt (fileStat full)
                ((err _) acc)
                ((ok st)
                  (if (> st.size (textMaxBytes))
                    acc
                    (mt (fileReadString full)
                      ((err _) acc)
                      ((ok text)
                        (if (or (not (stringContains? text sym)) (not (c/utf8Valid? text)))
                          acc
                          (fold (fn [(a2 (h/HMap ai/Mention)) (m ai/Mention)] -> (h/HMap ai/Mention) (putFound a2 accounted m))
                                acc (listReverse (proseLines rel text sym))))))))))))
        found files)

fn padLine n: Int64 -> String
  (let [(s (stringFromInt64 n))] (str (stringRepeat "0" (max 0 (- 12 (stringLength s)))) s))

fn mentionKey m: ai/Mention -> String
  (str m.rel "\x00" (padLine m.line) "\x00" m.why)

fn sortMentions ms: (List ai/Mention) -> (List ai/Mention)
  (listSortBy mentionKey ms)

fn dedupeMentions ms: (List ai/Mention) acc: (List ai/Mention) -> (List ai/Mention)
  (mt (listHead ms)
    ((none) (listReverse acc))
    ((some m) (dedupeMentions (optionOr (listTail ms) (list))
                              (if (mt (listHead acc) ((some h) (= (mentionKey h) (mentionKey m))) ((none) false)) acc (cons m acc)))))

fn sortedSet ms: (List ai/Mention) -> (List ai/Mention)
  (dedupeMentions (sortMentions ms) (list))

fn firstPerLine ms: (List ai/Mention) seen: (h/HMap Bool) acc: (List ai/Mention) -> (List ai/Mention)
  (mt (listHead ms)
    ((none) (listReverse acc))
    ((some m) (let [(k (keyOf m.rel m.line))]
                (if (h/hmHas? seen k)
                  (firstPerLine (optionOr (listTail ms) (list)) seen acc)
                  (firstPerLine (optionOr (listTail ms) (list)) (h/hmPut seen k true) (cons m acc))))))

fn callKey r: ai/CallRow -> String
  (str r.rel "\x00" (padLine r.line) "\x00" r.kind "\x00" (optionOr r.via "") "\x00" (optionOr r.through "") "\x00" r.of)

fn callForm ambiguous: Bool r: ai/CallRow -> String
  (str "(:at " (c/atStr r.rel r.line) " :kind " r.kind
       (mt r.via ((some v) (if (stringEmpty? v) "" (str " :via " (c/quoted v)))) ((none) ""))
       (mt r.through ((some t) (str " :through " t)) ((none) ""))
       (if (and ambiguous (not (stringEmpty? r.of))) (str " :of " (c/quoted r.of)) "")
       ")")

fn splitSymbol symbol: String module: String -> (Pair String String)
  (if (and (stringContains? symbol "/") (stringEmpty? module))
    (let [(parts (stringSplit symbol "/"))]
      (pair (optionOr (listLast parts) symbol) (stringJoin (listTake parts (- (listLength parts) 1)) "/")))
    (pair symbol module))

fn absentLine dim: String why: String -> String
  (str "(:observe :status :absent :dim " dim " :absent (python3) :message \"python3 could not be run (" (c/esc why) "); the python subject checker is absent, so " dim " is not answered\")")

fn setOf keys: (List String) -> (h/HMap Bool)
  (fold (fn [(acc (h/HMap Bool)) (k String)] -> (h/HMap Bool) (h/hmPut acc k true)) (h/hmEmpty) keys)

fn nonOverlapping text: String sym: String from: Int64 acc: (List Int64) -> (List Int64)
  (let [(bs (stringToBytes text)) (i (c/findFrom bs (bytesLength bs) (stringToBytes sym) from))]
    (if (< i 0) (listReverse acc) (nonOverlapping text sym (+ i (max 1 (stringLength sym))) (cons i acc))))

fn newlines s: String -> Int64
  (- (listLength (c/splitByte s 10)) 1)

(schema MS (:f found (h/HMap ai/Mention)) (:f possible (List ai/Mention)))

fn pyMentions pi: p/PyIndex sym: String keys: (h/HMap Bool) accounted: (h/HMap Bool) -> MS
  (let [(ix pi.ix)
        (other0 (fold (fn [(acc (h/HMap Bool)) (dd p/PyDef)] -> (h/HMap Bool) (if (and (= dd.name sym) (not (h/hmHas? keys dd.key))) (h/hmPut acc (keyOf dd.rel dd.line) true) acc))
                      (h/hmEmpty) (q/allDefs pi)))
        (other1 (fold (fn [(acc (h/HMap Bool)) (cs p/CallSite)] -> (h/HMap Bool) (if (and (= (p/lastSeg (p/keyQual cs.callee)) sym) (not (h/hmHas? keys cs.callee))) (h/hmPut acc (keyOf cs.rel cs.line) true) acc))
                      other0 pi.w.calls))
        (other (fold (fn [(acc (h/HMap Bool)) (lk (Pair String Bool))] -> (h/HMap Bool)
                       (let [(parts (stringSplit (pairFirst lk) "\x01"))]
                         (if (= (optionOr (listGet parts 2) "") sym) (h/hmPut acc (keyOf (optionOr (listGet parts 0) "") (optionOr (stringToInt64 (optionOr (listGet parts 1) "")) 0)) true) acc)))
                     other1 (h/hmPairs pi.w.localsAt)))
        (mods (listSortBy (fn [(m p/PyMod)] -> String m.rel) (h/omValues ix.mods)))]
    (fold (fn [(st MS) (m p/PyMod)] -> MS
            (if (not (stringContains? m.src sym))
              st
              (fold (fn [(s2 MS) (t d/PyTok)] -> MS
                      (let [(rel m.rel) (line t.line) (text t.text)]
                        (cond
                          ((not (stringContains? text sym)) s2)
                          ((= t.kind "COMMENT") (MS :found (putFound s2.found accounted (ai/Mention :rel rel :line line :why "comment")) :possible s2.possible))
                          ((or (= t.kind "STRING") (= t.kind "FSTRING_MIDDLE"))
                            (let [(why (if (h/hmHas? m.docstrings (stringFromInt64 line)) "docstring" "string"))]
                              (fold (fn [(s3 MS) (i Int64)] -> MS
                                      (MS :found (putFound s3.found accounted (ai/Mention :rel rel :line (+ line (newlines (optionOr (stringSlice text 0 i) ""))) :why why)) :possible s3.possible))
                                    s2 (nonOverlapping text sym 0 (list)))))
                          ((= t.kind "NAME")
                            (cond
                              ((!= text sym) (MS :found (putFound s2.found accounted (ai/Mention :rel rel :line line :why "similarName")) :possible s2.possible))
                              ((h/hmHas? other (keyOf rel line)) (MS :found (putFound s2.found accounted (ai/Mention :rel rel :line line :why "otherDefinition")) :possible s2.possible))
                              ((h/hmHas? m.importLines (stringFromInt64 line)) (MS :found (putFound s2.found accounted (ai/Mention :rel rel :line line :why "importOnly")) :possible s2.possible))
                              ((h/hmHas? accounted (keyOf rel line)) s2)
                              (else (MS :found s2.found :possible (cons (ai/Mention :rel rel :line line :why "unresolved name") s2.possible)))))
                          (else s2))))
                    st m.toks)))
          (MS :found (h/hmEmpty) :possible (list)) mods))

fn pyCallKey cs: p/CallSite -> String
  (str cs.rel "\x00" (padLine cs.line) "\x00" cs.kind)

fn pyCallForm ambiguous: Bool pi: p/PyIndex cs: p/CallSite -> String
  (str "(:at " (c/atStr cs.rel cs.line) " :kind " cs.kind
       (mt cs.via ((some v) (if (stringEmpty? v) "" (str " :via " (c/quoted v)))) ((none) ""))
       (mt cs.through ((some t) (if (stringEmpty? t) "" (str " :through " t))) ((none) ""))
       (if (and ambiguous (not (stringEmpty? (p/keyMod cs.callee)))) (str " :of " (c/quoted (p/keyMod cs.callee))) "")
       ")")

fn dynHit? targets: (List p/PyDef) dy: p/Dyn -> Bool
  (listAny? (fn [(dd p/PyDef)] -> Bool
              (or (and (= dy.tag "mod") (= dd.modName dy.base) (listContains? (list "function" "class" "lambda") dd.kind))
                  (and (= dy.tag "inst") (mt dd.cls ((some cq) (= (p/defKey dd.modName cq) dy.base)) ((none) false)))))
            targets)

fn defLineKey dd: p/PyDef -> String
  (str dd.rel "\x00" (padLine dd.line))

fn ! callersOver! root: String files: (List String) pi: p/PyIndex symbol: String module: String limit: Int64 ctx: c/Ctx -> (Result String String)
  (let [(index (ai/buildAslIndex! root files (if (stringContains? symbol ".") "" symbol)))
        (targets (q/targets pi symbol module))
        (keys (setOf (map (fn [(dd p/PyDef)] -> String dd.key) targets)))
        (leaf (p/lastSeg symbol))
        (res (if (stringContains? symbol ".")
               (ai/AslCallers :defs (list) :calls (list) :possible (list) :excluded (list))
               (ai/aslCallers index symbol module)))]
    (if (and (listEmpty? targets) (listEmpty? res.defs))
      (let [(names (c/sortUnique (listAppend (map (fn [(dd p/PyDef)] -> String dd.name) (q/allDefs pi)) (ai/defNames index))))
            (near (c/closeMatches symbol names 3 0.6))]
        (err (c/rejectLine "ERR_SYMBOL_NOT_FOUND" (str "no definition of " symbol (if (stringEmpty? module) "" (str " in " module)) " in this workspace")
                           (str " :symbol " (c/quoted symbol) " :nearest (" (c/joinWith (map c/quoted near) " ") ")"))))
      (let [(calls (listSortBy pyCallKey (filter (fn [(cs p/CallSite)] -> Bool (h/hmHas? keys cs.callee)) pi.w.calls)))
            (acc0 (setOf (listAppend (map (fn [(cs p/CallSite)] -> String (keyOf cs.rel cs.line)) calls) (map (fn [(dd p/PyDef)] -> String (keyOf dd.rel dd.line)) targets))))
            (poss0 (fold (fn [(acc (List ai/Mention)) (r p/Ref)] -> (List ai/Mention)
                           (if (and (h/hmHas? keys r.key) (not (h/hmHas? acc0 (keyOf r.rel r.line)))) (cons (ai/Mention :rel r.rel :line r.line :why "value reference") acc) acc))
                         (list) pi.w.refs))
            (poss1 (fold (fn [(acc (List ai/Mention)) (dy p/Dyn)] -> (List ai/Mention)
                           (if (and (dynHit? targets dy) (not (h/hmHas? acc0 (keyOf dy.rel dy.line)))) (cons (ai/Mention :rel dy.rel :line dy.line :why "getattr with a dynamic name") acc) acc))
                         poss0 pi.w.dynamic))
            (poss2 (fold (fn [(acc (List ai/Mention)) (u p/Untyped)] -> (List ai/Mention)
                           (if (and (= u.attr leaf) (not (h/hmHas? acc0 (keyOf u.rel u.line)))) (cons (ai/Mention :rel u.rel :line u.line :why "attribute call on an untyped receiver") acc) acc))
                         poss1 pi.w.untyped))
            (accounted (fold (fn [(acc (h/HMap Bool)) (m ai/Mention)] -> (h/HMap Bool) (h/hmPut acc (keyOf m.rel m.line) true)) acc0 poss2))
            (ms (pyMentions pi leaf keys accounted))
            (found (textMentions! root files leaf (h/hmEmpty) ms.found))
            (excludedAll (sortMentions (h/hmValues found)))
            (excluded (listAppend excludedAll (sortedSet res.excluded)))
            (possible (listAppend (firstPerLine (sortedSet (listAppend poss2 ms.possible)) (h/hmEmpty) (list)) (sortedSet res.possible)))
            (aslDefMods (map (fn [(d0 (Pair String Int64))] -> String (optionOr (mt (listHead (filter (fn [(m ai/AslMod)] -> Bool (= m.rel (pairFirst d0))) index.mods)) ((some m) (some m.name)) ((none) (none))) "")) res.defs))
            (defMods (c/sortUnique (listAppend (map (fn [(dd p/PyDef)] -> String dd.modName) targets) aslDefMods)))
            (ambiguous (> (listLength defMods) 1))
            (callItems (listAppend (map (fn [(cs p/CallSite)] -> String (pyCallForm ambiguous pi cs)) calls)
                                   (map (fn [(r ai/CallRow)] -> String (callForm ambiguous r)) (listSortBy callKey res.calls))))
            (defItems (listAppend
                        (map (fn [(dd p/PyDef)] -> String (str "(:at " (c/atStr dd.rel dd.line) " :kind " dd.kind " :module " (c/quoted dd.modName) ")"))
                             (listSortBy defLineKey targets))
                        (map (fn [(d0 (Pair String Int64))] -> String
                               (str "(:at " (c/atStr (pairFirst d0) (pairSecond d0)) " :kind fn :module "
                                    (c/quoted (optionOr (mt (listHead (filter (fn [(m ai/AslMod)] -> Bool (= m.rel (pairFirst d0))) index.mods)) ((some m) (some m.name)) ((none) (none))) "")) ")"))
                             res.defs)))
            (possItems (map (fn [(m ai/Mention)] -> String (str "(:at " (c/atStr m.rel m.line) " :why " (c/quoted m.why) ")")) possible))
            (exclItems (map (fn [(m ai/Mention)] -> String (str "(:at " (c/atStr m.rel m.line) " :why " m.why ")")) excluded))
            (langs (c/joinWith (listAppend (if (listEmpty? (h/omValues pi.ix.mods)) (list) (list "python")) (if (listEmpty? index.mods) (list) (list "asl"))) " "))]
        (mt (c/shortRev! root ctx)
          ((err e) (err e))
          ((ok rev)
            (let [(head (str "(:observe :dim callers :v 1 :symbol " (c/quoted symbol) (if (stringEmpty? module) "" (str " :module " (c/quoted module)))
                             " :rev " rev " :languages (" langs ") :count (:defs " (stringFromInt64 (listLength defItems))
                             " :calls " (stringFromInt64 (listLength callItems)) " :possible " (stringFromInt64 (listLength possItems))
                             " :excluded " (stringFromInt64 (listLength exclItems)) ")"
                             (if ambiguous
                               (str " :ambiguous (" (c/joinWith (map c/quoted defMods) " ") ") :hint \"" (stringFromInt64 (listLength defMods))
                                    " modules define " (c/esc symbol) "; each call names its definition in :of; :module m or m/" (c/esc symbol) " narrows to one\"")
                               "")))
                  (tail (str (if (listEmpty? pi.unparsed) "" (str " :unparsed (" (c/joinWith (map c/quoted (listTake pi.unparsed 5)) " ") ")"))
                             " :limits " (c/quoted (callersLimits))))]
              (c/fitReceipt head (list (c/Section :key "defs" :items defItems :limit limit) (c/Section :key "calls" :items callItems :limit limit)
                                       (c/Section :key "possible" :items possItems :limit limit) (c/Section :key "excluded" :items exclItems :limit limit))
                            tail "callers")))))))

fn ! observeCallers! root: String symbolArg: String moduleArg: String limit: Int64 ctx: c/Ctx -> (Pair String (Result String String))
  (let [(sm (splitSymbol symbolArg moduleArg)) (symbol (pairFirst sm)) (module (pairSecond sm))]
    (mt (c/workspaceFiles! root ctx)
      ((err e) (pair "" (err e)))
      ((ok files)
        (mt (p/buildPyIndex root (str "=" (p/lastSeg symbol)) files ctx)
          ((err e) (pair "" (err e)))
          ((ok b)
            (mt b
              ((p/pyAbsent why) (pair "" (err (absentLine "callers" why))))
              ((p/built pi) (pair pi.warnings (callersOver! root files pi symbol module limit ctx)))))))))
