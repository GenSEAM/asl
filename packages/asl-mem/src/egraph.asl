(module aslMem/egraph :x [ENode EClass EGraph egraphNew egraphFind egraphAddNode addEnode egraphUnion mergeEclasses egraphRebuild egraphExtract egraphSaturate] :i [(tokenRegex :a tr)])

(schema ENode (:f op Str) (:f children (List I64)))

(schema EClass (:f id I64) (:f nodes (List ENode)) (:f parents (List I64)))

(schema EGraph (:f classes (Map I64 EClass)) (:f unionFind (Map I64 I64)) (:f memo (Map Str I64)) (:f nextId I64))

(schema Pattern (:f op Str) (:f isVar Bool) (:f children (List Pattern)))

(schema RuleMatch (:f classId I64) (:f subst (Map Str I64)))

fn isVarToken? token: Str -> Bool
  (or (stringStartsWith? token "?") (or (= token "x") (or (= token "y") (or (= token "a") (= token "b")))))

fn enodeEqual? a: ENode b: ENode -> Bool
  (and (= a.op b.op) (= a.children b.children))

fn listDedupI64 items: (List I64) -> (List I64)
  (fold (fn [(acc (List I64)) (item I64)] -> (List I64) (if (listContains? acc item) acc (listAppend acc (list item)))) (list) items)

fn listDedupEnodes nodes: (List ENode) -> (List ENode)
  (fold (fn [(acc (List ENode)) (n ENode)] -> (List ENode) (let [(exists (fold (fn [(found Bool) (existing ENode)] -> Bool (if found true (enodeEqual? n existing))) false acc))] (if exists acc (listAppend acc (list n))))) (list) nodes)

fn insertSortedI64 sorted: (List I64) val: I64 -> (List I64)
  (let [(len (listLength sorted))] (if (= len 0) (list val) (let [(inserted (fold (fn [(acc (pair (List I64) Bool)) (elem I64)] -> (Pair (List I64) Bool) (if (pairSecond acc) (pair (listAppend (pairFirst acc) (list elem)) true) (if (<= val elem) (pair (listAppend (listAppend (pairFirst acc) (list val)) (list elem)) true) (pair (listAppend (pairFirst acc) (list elem)) false)))) (pair (list) false) sorted))] (if (pairSecond inserted) (pairFirst inserted) (listAppend (pairFirst inserted) (list val))))))

fn sortI64 items: (List I64) -> (List I64)
  (fold (fn [(acc (List I64)) (x I64)] -> (List I64) (insertSortedI64 acc x)) (list) items)

fn formatNodeKey op: Str children: (List I64) -> Str
  (let [(childrenStr (fold (fn [(acc Str) (c I64)] -> Str (if (= acc "") (stringFromInt64 c) (str acc "," (stringFromInt64 c)))) "" children))] (str op "(" childrenStr ")"))

fn canonicalizeNode eg: EGraph node: ENode -> ENode
  (let [(canonChildren (map (fn [(c I64)] -> I64 (egraphFind eg c)) node.children))] (with node :children canonChildren))

fn addParentToClass classes: (Map I64 EClass) childId: I64 parentId: I64 -> (Map I64 EClass)
  (mt (mapGet classes childId) ((none) classes) ((some cls) (if (listContains? cls.parents parentId) classes (let [(updated (EClass :id cls.id :nodes cls.nodes :parents (listAppend cls.parents (list parentId))))] (mapSet classes childId updated)))))

fn egraphNew -> EGraph
  (EGraph :classes (mapEmpty) :unionFind (mapEmpty) :memo (mapEmpty) :nextId 1)

fn egraphFind eg: EGraph id: I64 -> I64
  (mt (mapGet eg.unionFind id) ((none) id) ((some parent) (if (= parent id) id (egraphFind eg parent))))

fn egraphAddNode eg: EGraph op: Str children: (List I64) -> (Pair EGraph I64)
  (let [(canonChildren (map (fn [(c I64)] -> I64 (egraphFind eg c)) children)) (node (ENode :op op :children canonChildren)) (key (formatNodeKey op canonChildren))] (mt (mapGet eg.memo key) ((some existingId) (pair eg (egraphFind eg existingId))) ((none) (let [(newId eg.nextId) (newCls (EClass :id newId :nodes (list node) :parents (list))) (updatedClasses (mapSet eg.classes newId newCls)) (linkedClasses (fold (fn [(acc (Map I64 EClass)) (cid I64)] -> (Map I64 EClass) (addParentToClass acc cid newId)) updatedClasses canonChildren)) (newUf (mapSet eg.unionFind newId newId)) (newMemo (mapSet eg.memo key newId)) (newEg (EGraph :classes linkedClasses :unionFind newUf :memo newMemo :nextId (+ newId 1)))] (pair newEg newId)))))

fn addEnode eg: EGraph op: Str children: (List I64) -> (Pair EGraph I64)
  (egraphAddNode eg op children)

fn egraphUnion eg: EGraph id1: I64 id2: I64 -> EGraph
  (let [(root1 (egraphFind eg id1)) (root2 (egraphFind eg id2))] (if (= root1 root2) eg (let [(leader (if (< root1 root2) root1 root2)) (subordinate (if (< root1 root2) root2 root1)) (clsLeader (optionOr (mapGet eg.classes leader) (EClass :id leader :nodes (list) :parents (list)))) (clsSub (optionOr (mapGet eg.classes subordinate) (EClass :id subordinate :nodes (list) :parents (list)))) (mergedNodes (listDedupEnodes (listAppend clsLeader.nodes clsSub.nodes))) (mergedParents (listDedupI64 (listAppend clsLeader.parents clsSub.parents))) (mergedCls (EClass :id leader :nodes mergedNodes :parents mergedParents)) (newUf (mapSet eg.unionFind subordinate leader)) (classesWithLeader (mapSet eg.classes leader mergedCls)) (newClasses (mapRemove classesWithLeader subordinate))] (with eg :classes newClasses :unionFind newUf))))

fn mergeEclasses eg: EGraph id1: I64 id2: I64 -> EGraph
  (egraphUnion eg id1 id2)

fn rebuildStep eg: EGraph -> (Pair EGraph Bool)
  (let [(sortedIds (sortI64 (mapKeys eg.classes))) (canonPass (fold (fn [(acc EGraph) (cid I64)] -> EGraph (mt (mapGet acc.classes cid) ((none) acc) ((some cls) (let [(canonNodes (listDedupEnodes (map (fn [(n ENode)] -> ENode (canonicalizeNode acc n)) cls.nodes))) (canonParents (listDedupI64 (map (fn [(p I64)] -> I64 (egraphFind acc p)) cls.parents))) (updatedCls (EClass :id cid :nodes canonNodes :parents canonParents))] (EGraph :classes (mapSet acc.classes cid updatedCls) :unionFind acc.unionFind :memo acc.memo :nextId acc.nextId))))) eg sortedIds))] (rebuildMemoAndCongruence canonPass))

fn rebuildMemoAndCongruence eg: EGraph -> (Pair EGraph Bool)
  (let [(sortedIds (sortI64 (mapKeys eg.classes)))] (fold (fn [(acc (pair EGraph Bool)) (cid I64)] -> (Pair EGraph Bool) (let [(curEg (pairFirst acc)) (anyMerged (pairSecond acc))] (mt (mapGet curEg.classes cid) ((none) acc) ((some cls) (fold (fn [(inner (pair EGraph Bool)) (node ENode)] -> (Pair EGraph Bool) (let [(inEg (pairFirst inner)) (inMerged (pairSecond inner)) (key (formatNodeKey node.op node.children))] (mt (mapGet inEg.memo key) ((none) (let [(upMemo (mapSet inEg.memo key (egraphFind inEg cid))) (upEg (EGraph :classes inEg.classes :unionFind inEg.unionFind :memo upMemo :nextId inEg.nextId))] (pair upEg inMerged))) ((some existingId) (let [(root1 (egraphFind inEg existingId)) (root2 (egraphFind inEg cid))] (if (!= root1 root2) (let [(united (egraphUnion inEg root1 root2))] (pair united true)) (pair inEg inMerged))))))) acc cls.nodes))))) (pair (with eg :memo (mapEmpty)) false) sortedIds))

fn egraphRebuildLoop eg: EGraph fuel: I64 -> EGraph
  (if (<= fuel 0) eg (let [(step (rebuildStep eg))] (if (pairSecond step) (egraphRebuildLoop (pairFirst step) (- fuel 1)) (pairFirst step))))

fn egraphRebuild eg: EGraph -> EGraph
  (egraphRebuildLoop eg 20)

fn extractNode eg: EGraph node: ENode visited: (List I64) -> (Pair I64 Str)
  (if (listEmpty? node.children) (pair 1 node.op) (let [(children node.children) (extracted (fold (fn [(acc (pair I64 (List Str))) (cid I64)] -> (Pair I64 (List Str)) (let [(sub (extractClass eg cid visited)) (cost (+ (pairFirst acc) (pairFirst sub))) (exprs (listAppend (pairSecond acc) (list (pairSecond sub))))] (pair cost exprs))) (pair 1 (list)) children)) (totalCost (pairFirst extracted)) (childExprs (pairSecond extracted)) (joined (fold (fn [(acc Str) (s Str)] -> Str (if (= acc "") s (str acc " " s))) "" childExprs)) (expr (str "(" node.op " " joined ")"))] (pair totalCost expr)))

fn extractClass eg: EGraph classId: I64 visited: (List I64) -> (Pair I64 Str)
  (let [(root (egraphFind eg classId))] (if (listContains? visited root) (pair 999999 "") (mt (mapGet eg.classes root) ((none) (pair 999999 "")) ((some cls) (let [(nodes cls.nodes)] (if (listEmpty? nodes) (pair 999999 "") (let [(nextVisited (listAppend visited (list root)))] (fold (fn [(best (pair I64 Str)) (n ENode)] -> (Pair I64 Str) (let [(cur (extractNode eg n nextVisited))] (if (< (pairFirst cur) (pairFirst best)) cur (if (and (= (pairFirst cur) (pairFirst best)) (< (stringLength (pairSecond cur)) (stringLength (pairSecond best)))) cur best)))) (pair 999999 "") nodes))))))))

fn egraphExtract eg: EGraph classId: I64 -> Str
  (let [(res (extractClass eg classId (list)))] (pairSecond res))

fn parsePatternTokens tokens: (List Str) -> (Pair (Option Pattern) (List Str))
  (if (listEmpty? tokens) (pair (none) (list)) (let [(head (optionOr (listHead tokens) "")) (tail (optionOr (listTail tokens) (list)))] (if (= head "(") (if (listEmpty? tail) (pair (none) (list)) (let [(op (optionOr (listHead tail) "")) (afterOp (optionOr (listTail tail) (list))) (res (parsePatternList afterOp (list)))] (pair (some (Pattern :op op :isVar false :children (pairFirst res))) (pairSecond res)))) (pair (some (Pattern :op head :isVar (isVarToken? head) :children (list))) tail))))

fn parsePatternList tokens: (List Str) acc: (List Pattern) -> (Pair (List Pattern) (List Str))
  (if (listEmpty? tokens) (pair acc (list)) (let [(head (optionOr (listHead tokens) ""))] (if (= head ")") (pair acc (optionOr (listTail tokens) (list))) (let [(parsed (parsePatternTokens tokens))] (mt (pairFirst parsed) ((none) (pair acc (pairSecond parsed))) ((some pat) (parsePatternList (pairSecond parsed) (listAppend acc (list pat)))))))))

fn parsePattern s: Str -> (Option Pattern)
  (let [(tokens (tr/tokenizePattern (stringTrim s))) (res (parsePatternTokens tokens))] (pairFirst res))

fn matchChildPatterns eg: EGraph pats: (List Pattern) children: (List I64) subst: (Map Str I64) -> (Option (Map Str I64))
  (if (listEmpty? pats) (some subst) (let [(pHead (optionOr (listHead pats) (Pattern :op "" :isVar false :children (list)))) (cHead (optionOr (listHead children) 0)) (pTail (optionOr (listTail pats) (list))) (cTail (optionOr (listTail children) (list))) (matched (matchPatternNode eg pHead cHead subst))] (mt matched ((none) (none)) ((some nextSubst) (matchChildPatterns eg pTail cTail nextSubst)))))

fn matchPatternNode eg: EGraph pat: Pattern classId: I64 subst: (Map Str I64) -> (Option (Map Str I64))
  (if pat.isVar (let [(varName pat.op)] (mt (mapGet subst varName) ((some boundId) (if (= (egraphFind eg boundId) (egraphFind eg classId)) (some subst) (none))) ((none) (some (mapSet subst varName (egraphFind eg classId)))))) (let [(root (egraphFind eg classId))] (mt (mapGet eg.classes root) ((none) (none)) ((some cls) (if (listEmpty? pat.children) (let [(hasLeaf (fold (fn [(acc Bool) (n ENode)] -> Bool (if acc true (and (= n.op pat.op) (listEmpty? n.children)))) false cls.nodes))] (if hasLeaf (some subst) (none))) (fold (fn [(acc (Option (Map Str I64))) (n ENode)] -> (Option (Map Str I64)) (mt acc ((some s) (some s)) ((none) (if (and (= n.op pat.op) (= (listLength n.children) (listLength pat.children))) (matchChildPatterns eg pat.children n.children subst) (none))))) (none) cls.nodes))))))

fn findRuleMatches eg: EGraph lhs: Pattern -> (List RuleMatch)
  (let [(sortedIds (sortI64 (mapKeys eg.classes)))] (fold (fn [(acc (List RuleMatch)) (cid I64)] -> (List RuleMatch) (let [(matched (matchPatternNode eg lhs cid (mapEmpty)))] (mt matched ((none) acc) ((some subst) (listAppend acc (list (RuleMatch :classId cid :subst subst))))))) (list) sortedIds))

fn instantiatePattern eg: EGraph pat: Pattern subst: (Map Str I64) -> (Pair EGraph I64)
  (if pat.isVar (let [(varName pat.op)] (mt (mapGet subst varName) ((some cid) (pair eg (egraphFind eg cid))) ((none) (egraphAddNode eg varName (list))))) (if (listEmpty? pat.children) (egraphAddNode eg pat.op (list)) (let [(childStep (fold (fn [(acc (pair EGraph (List I64))) (cp Pattern)] -> (Pair EGraph (List I64)) (let [(curEg (pairFirst acc)) (curIds (pairSecond acc)) (sub (instantiatePattern curEg cp subst))] (pair (pairFirst sub) (listAppend curIds (list (pairSecond sub)))))) (pair eg (list)) pat.children))] (egraphAddNode (pairFirst childStep) pat.op (pairSecond childStep)))))

fn applyRulesPass eg: EGraph rules: (List (Pair Str Str)) -> (Pair EGraph Bool)
  (let [(parsedRules (fold (fn [(acc (List (pair Pattern Pattern))) (r (pair Str Str))] -> (List (Pair Pattern Pattern)) (let [(lhsOpt (parsePattern (pairFirst r))) (rhsOpt (parsePattern (pairSecond r)))] (mt lhsOpt ((none) acc) ((some lhs) (mt rhsOpt ((none) acc) ((some rhs) (listAppend acc (list (pair lhs rhs))))))))) (list) rules))] (fold (fn [(acc (pair EGraph Bool)) (rule (pair Pattern Pattern))] -> (Pair EGraph Bool) (let [(curEg (pairFirst acc)) (curChanged (pairSecond acc)) (lhs (pairFirst rule)) (rhs (pairSecond rule)) (matches (findRuleMatches curEg lhs))] (fold (fn [(mAcc (pair EGraph Bool)) (m RuleMatch)] -> (Pair EGraph Bool) (let [(mEg (pairFirst mAcc)) (mChanged (pairSecond mAcc)) (inst (instantiatePattern mEg rhs m.subst)) (instEg (pairFirst inst)) (rhsId (pairSecond inst)) (matchedId m.classId) (rootLhs (egraphFind instEg matchedId)) (rootRhs (egraphFind instEg rhsId))] (if (!= rootLhs rootRhs) (let [(united (egraphUnion instEg rootLhs rootRhs))] (pair united true)) (pair instEg mChanged)))) (pair curEg curChanged) matches))) (pair eg false) parsedRules))

fn egraphSaturateLoop eg: EGraph rules: (List (Pair Str Str)) fuel: I64 -> EGraph
  (if (<= fuel 0) eg (let [(pass (applyRulesPass eg rules)) (newEg (pairFirst pass)) (changed (pairSecond pass))] (if changed (let [(rebuilt (egraphRebuild newEg))] (egraphSaturateLoop rebuilt rules (- fuel 1))) newEg)))

fn egraphSaturate eg: EGraph rules: (List (Pair Str Str)) -> EGraph
  (egraphSaturateLoop eg rules 15)
