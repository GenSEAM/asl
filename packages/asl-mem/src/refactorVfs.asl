(module aslMem/refactorVfs :x [RefactorPlan stageRefactorDiff previewTokenSavings commitStagedRefactor rollbackStagedRefactor] :i [(vfs :a v) (asl-compiler/compactRewrite :a cr)])

(schema RefactorPlan (:f path Str) (:f baseHash Str) (:f stagedHash Str) (:f baseContent Str) (:f stagedContent Str) (:f diff Str) (:f tokensSaved I64) (:f status Str))

(schema CountState (:f cur Str) (:f inStr Bool) (:f esc Bool) (:f inCmt Bool) (:f count I64))

fn countAtom cnt: I64 atom: Str target: Str -> I64
  (if (= atom target) (+ cnt 1) cnt)

fn countStep st: CountState ch: Str target: Str -> CountState
  (if st.inCmt (if (= ch "\n") (with st :cur "" :inStr false :esc false :inCmt false) (with st :cur "" :inStr false :esc false :inCmt true)) (if st.inStr (if st.esc (with st :cur "" :inStr true :esc false :inCmt false) (if (= ch "\\") (with st :cur "" :inStr true :esc true :inCmt false) (if (= ch "\"") (with st :cur "" :inStr false :esc false :inCmt false) (with st :cur "" :inStr true :esc false :inCmt false)))) (if (= ch "\"") (let [(c (countAtom st.count st.cur target))] (CountState :cur "" :inStr true :esc false :inCmt false :count c)) (if (= ch ";") (let [(c (countAtom st.count st.cur target))] (CountState :cur "" :inStr false :esc false :inCmt true :count c)) (if (or (stringContains? "()[]{}" ch) (stringContains? " \t\n\r" ch)) (let [(c (countAtom st.count st.cur target))] (CountState :cur "" :inStr false :esc false :inCmt false :count c)) (with st :cur (str st.cur ch) :inStr false :esc false :inCmt false))))))

fn countAstTokens content: Str target: Str -> I64
  (let [(chars (stringChars content)) (initSt (CountState :cur "" :inStr false :esc false :inCmt false :count 0)) (finalSt (fold (fn [(st CountState) (ch Str)] -> CountState (countStep st ch target)) initSt chars))] (countAtom finalSt.count finalSt.cur target))

fn previewTokenSavings content: Str rules: (List cr/CompactionRule) -> I64
  (fold (fn [(acc I64) (r cr/CompactionRule)] -> I64 (let [(cnt (countAstTokens content r.verbose))] (+ acc (* cnt r.savings)))) 0 rules)

fn stageRefactorDiff reg: v/VFSRegistry path: Str rules: (List cr/CompactionRule) -> (Option RefactorPlan)
  (mt (v/vfsRead reg path) ((none) (none)) ((some buf) (let [(origC buf.content) (stagedC (cr/rewriteAstTokens origC rules)) (baseH buf.casHash) (stagedH (v/vfsCasHash stagedC)) (tempBuf (v/VFSBuffer :path buf.path :content stagedC :baseContent origC :casHash stagedH :baseHash baseH :revision (+ buf.revision 1) :dirty (!= stagedH baseH) :loadedAt buf.loadedAt)) (diffLines (v/vfsDiff tempBuf)) (diffStr (stringJoin diffLines "\n")) (savings (previewTokenSavings origC rules))] (some (RefactorPlan :path buf.path :baseHash baseH :stagedHash stagedH :baseContent origC :stagedContent stagedC :diff diffStr :tokensSaved savings :status "staged")))))

fn commitStagedRefactor reg: v/VFSRegistry plan: RefactorPlan -> (Option v/VFSRegistry)
  (mt (v/vfsRead reg plan.path) ((none) (none)) ((some curBuf) (if (!= curBuf.casHash plan.baseHash) (none) (some (v/vfsWrite reg plan.path plan.stagedContent)))))

fn rollbackStagedRefactor reg: v/VFSRegistry plan: RefactorPlan -> v/VFSRegistry
  (v/vfsWrite reg plan.path plan.baseContent)
