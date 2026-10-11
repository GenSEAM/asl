(module aslIntel/preload
  :x [PreloadTier
      tierMicroAst
      tierMesoSymbol
      tierMacroTopology
      SymbolStub
      PreloadedHorizon
      preloadTierToString
      estimateStubTokens
      stubCreate
      horizonCreate
      horizonAddStub
      extractShortName
      makeNodeFromSymbol
      makeEdgeFromRef
      hydrateGraphInto
      hydrateGraphFromFileSymbols
      hydrateGraphFromSources
      hydrateGraphFromFiles!
      defaultWorkspaceFiles!
      intelPreloadFiles!
      intelPreloadGraph
      intelPreload!
      formatPreloadContext
      findTargetNode
      scoreStubBm25
      Bm25Stats
      makeBm25Stats
      updateStubBm25Incremental
      scoreStubBm25Enhanced
      computeStubSimHash
      areStubsNearDuplicates?
      dedupStubs
      rankStubsByRelevance
      ContextBanditArm
      armShallowSignature
      armDeepCallGraph
      armToString
      ContextBanditModel
      makeContextBanditModel
      updateBanditArmReward
      determineContextRoutingBanditAdaptive
      determineContextRoutingBandit
      decayBanditEpsilon]
  :i [(symbolGraph :a g)
      (extractor :a ex)
      (asl-text/text :a txt)])

(enum ContextBanditArm
  (:c armShallowSignature [] "Shallow symbol signature slice")
  (:c armDeepCallGraph [] "Deep transitive call-graph blast radius"))

fn armToString arm: ContextBanditArm -> Str
  (mt arm
    ((armShallowSignature) "shallow-signature")
    ((armDeepCallGraph) "deep-callgraph"))

(schema ContextBanditModel
  (:f shallowWeight F64)
  (:f deepWeight F64)
  (:f pullCount I64)
  (:f temperature F64)
  (:f epsilon F64))

fn makeContextBanditModel -> ContextBanditModel
  (ContextBanditModel :shallowWeight 1.0 :deepWeight 1.0 :pullCount 0 :temperature 0.1 :epsilon 0.2)

fn updateBanditArmReward model: ContextBanditModel arm: ContextBanditArm reward: F64 alpha: F64 -> ContextBanditModel
  (let [(cnt (+ model.pullCount 1))]
    (mt arm
      ((armShallowSignature)
        (let [(oldW model.shallowWeight)
              (newW (+ oldW (* alpha (- reward oldW))))]
          (with model :shallowWeight newW :pullCount cnt)))
      ((armDeepCallGraph)
        (let [(oldW model.deepWeight)
              (newW (+ oldW (* alpha (- reward oldW))))]
          (with model :deepWeight newW :pullCount cnt)))))

fn decayBanditEpsilon model: ContextBanditModel decayRate: F64 minEpsilon: F64 -> ContextBanditModel
  (let [(raw (* model.epsilon decayRate))
        (clamped (if (< raw minEpsilon) minEpsilon raw))]
    (with model :epsilon clamped))

fn determineContextRoutingBanditAdaptive model: ContextBanditModel entropy: F64 isRefactoring: Bool -> ContextBanditArm
  (if isRefactoring
    (armDeepCallGraph)
    (let [(shallowPrior (if (< entropy 2.5) 1.5 0.8))
          (deepPrior (if (> entropy 2.5) 1.5 0.8))
          (shallowScore (* model.shallowWeight shallowPrior))
          (deepScore (* model.deepWeight deepPrior))]
      (if (> deepScore shallowScore)
        (armDeepCallGraph)
        (armShallowSignature))))

fn determineContextRoutingBandit entropy: F64 isRefactoring: Bool -> ContextBanditArm
  (determineContextRoutingBanditAdaptive (makeContextBanditModel) entropy isRefactoring)

(enum PreloadTier
  (:c tierMicroAst [] "Target symbol at depth 0: hydrated with full AST / source body")
  (:c tierMesoSymbol [] "Direct caller/callee at depth 1: interface skeletons and signatures, zero bodies")
  (:c tierMacroTopology [] "Transitive boundary at depth 2: symbol name and 1-line docstring"))

(schema SymbolStub
  (:f symbol Str)
  (:f tier PreloadTier)
  (:f path Str)
  (:f signature Str)
  (:f docstring Str)
  (:f tokens I64))

(schema PreloadedHorizon
  (:f targetSymbol Str)
  (:f maxDepth I64)
  (:f tokenBudget I64)
  (:f totalTokens I64)
  (:f stubs (List SymbolStub))
  (:f truncated Bool))

fn preloadTierToString tier: PreloadTier -> Str
  (mt tier ((tierMicroAst) "micro-ast") ((tierMesoSymbol) "meso-symbol") ((tierMacroTopology) "macro-topology"))

fn estimateStubTokens stub: SymbolStub -> I64
  (if (> stub.tokens 0) stub.tokens (let [(text (str stub.symbol " " stub.path " " stub.signature " " stub.docstring)) (toks (txt/estimateTokens text))] (if (<= toks 0) 1 toks)))

fn stubCreate symbol: Str tier: PreloadTier path: Str signature: Str docstring: Str tokens: I64 -> SymbolStub
  (let [(tok (if (> tokens 0) tokens (let [(text (str symbol " " path " " signature " " docstring)) (est (txt/estimateTokens text))] (if (<= est 0) 1 est))))] (SymbolStub :symbol symbol :tier tier :path path :signature signature :docstring docstring :tokens tok))

fn horizonCreate target: Str maxDepth: I64 budget: I64 -> PreloadedHorizon
  (PreloadedHorizon :targetSymbol target :maxDepth maxDepth :tokenBudget budget :totalTokens 0 :stubs (list) :truncated false)

fn horizonAddStub h: PreloadedHorizon stub: SymbolStub -> PreloadedHorizon
  (if h.truncated h (let [(cost (estimateStubTokens stub)) (newTotal (+ h.totalTokens cost))] (if (> newTotal h.tokenBudget) (with h :truncated true) (with h :totalTokens newTotal :stubs (listAppend h.stubs (list stub)) :truncated false))))

fn normalizeSymbolName s: Str -> Str
  (stringReplace (stringReplace (stringReplace (stringReplace (stringLower (stringTrim s)) "-" "") "_" "") "!" "") "?" "")

fn matchesIdOrName? candidate: Str target: Str -> Bool
  (let [(c (normalizeSymbolName candidate)) (t (normalizeSymbolName target))] (or (= candidate target) (or (= c t) (or (stringEndsWith? target (str "/" candidate)) (or (stringEndsWith? candidate (str "/" target)) (or (stringEndsWith? t (str "/" c)) (stringEndsWith? c (str "/" t))))))))

fn findTargetNode nodes: (List g/GraphNode) target: Str -> (Option g/GraphNode)
  (let [(tNorm (normalizeSymbolName target)) (matches (filter (fn [(n g/GraphNode)] -> Bool (let [(id n.id) (name n.name) (file n.file) (idNorm (normalizeSymbolName id)) (nameNorm (normalizeSymbolName name))] (or (= id target) (or (= name target) (or (= file target) (or (= idNorm tNorm) (or (= nameNorm tNorm) (or (stringEndsWith? id (str "/" target)) (or (stringEndsWith? target (str "/" name)) (or (stringEndsWith? idNorm (str "/" tNorm)) (stringEndsWith? tNorm (str "/" nameNorm)))))))))))) nodes))] (listHead matches))

fn findDepth1Ids rootId: Str edges: (List g/GraphEdge) -> (List Str)
  (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(neighbor (if (matchesIdOrName? e.src rootId) e.dst (if (matchesIdOrName? e.dst rootId) e.src "")))] (if (and (not (stringEmpty? neighbor)) (not (matchesIdOrName? neighbor rootId)) (not (listContains? acc neighbor))) (listAppend acc (list neighbor)) acc))) (list) edges)

fn idInList? id: Str lst: (List Str) -> Bool
  (fold (fn [(found Bool) (item Str)] -> Bool (if found true (matchesIdOrName? id item))) false lst)

fn findDepth2Ids rootId: Str d1Ids: (List Str) edges: (List g/GraphEdge) -> (List Str)
  (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(src e.src) (dst e.dst) (acc1 (if (and (idInList? src d1Ids) (not (matchesIdOrName? dst rootId)) (not (idInList? dst d1Ids)) (not (listContains? acc dst))) (listAppend acc (list dst)) acc))] (if (and (idInList? dst d1Ids) (not (matchesIdOrName? src rootId)) (not (idInList? src d1Ids)) (not (listContains? acc1 src))) (listAppend acc1 (list src)) acc1))) (list) edges)

fn findNodesByIds ids: (List Str) allNodes: (List g/GraphNode) -> (List g/GraphNode)
  (fold (fn [(acc (List g/GraphNode)) (id Str)] -> (List g/GraphNode) (let [(matched (findTargetNode allNodes id))] (mt matched ((some n) (listAppend acc (list n))) ((none) acc)))) (list) ids)

fn scoreStubBm25 stub: SymbolStub target: Str -> I64
  (let [(sym stub.symbol)
        (sig stub.signature)
        (doc stub.docstring)
        (symMatch (if (stringContains? sym target) 100 0))
        (sigMatch (if (stringContains? sig target) 50 0))
        (docMatch (if (stringContains? doc target) 25 0))]
    (+ symMatch (+ sigMatch docMatch)))

(schema Bm25Stats (:f totalDocs I64) (:f totalDocLen I64) (:f avgDocLen I64))

fn makeBm25Stats -> Bm25Stats
  (Bm25Stats :totalDocs 0 :totalDocLen 0 :avgDocLen 1)

fn updateStubBm25Incremental stats: Bm25Stats docLen: I64 -> Bm25Stats
  (let [(newDocs (+ stats.totalDocs 1))
        (newTotalLen (+ stats.totalDocLen docLen))
        (avgLen (if (> newDocs 0) (/ newTotalLen newDocs) 1))]
    (Bm25Stats :totalDocs newDocs :totalDocLen newTotalLen :avgDocLen (if (<= avgLen 0) 1 avgLen)))

fn scoreStubBm25Enhanced stub: SymbolStub target: Str stats: Bm25Stats -> I64
  (let [(sym stub.symbol)
        (sig stub.signature)
        (doc stub.docstring)
        (docLen (+ (stringLength sym) (+ (stringLength sig) (stringLength doc))))
        (avgLen stats.avgDocLen)
        (lenNorm (if (> avgLen 0) (/ (* docLen 100) avgLen) 100))
        (rawScore (scoreStubBm25 stub target))
        (damped (if (> lenNorm 200) (/ (* rawScore 200) lenNorm) rawScore))]
    damped)

fn computeStubSimHash stub: SymbolStub -> I64
  (let [(raw (str stub.symbol " " stub.path " " stub.signature))
        (chars (stringChars raw))]
    (fold (fn [(acc I64) (c Str)] -> I64
            (let [(code (stringLength c))]
              (+ (* acc 31) (+ code 17))))
          14695 chars))

fn areStubsNearDuplicates? s1: SymbolStub s2: SymbolStub -> Bool
  (or (= s1.symbol s2.symbol)
      (and (= s1.path s2.path)
           (= s1.signature s2.signature)))

fn dedupStubsLoop stubs: (List SymbolStub) acc: (List SymbolStub) -> (List SymbolStub)
  (if (listEmpty? stubs)
    acc
    (let [(headStub (optionOr (listHead stubs) (stubCreate "" (tierMacroTopology) "" "" "" 0)))
          (tailStubs (optionOr (listTail stubs) (list)))
          (isDup (fold (fn [(found Bool) (existing SymbolStub)] -> Bool
                         (if found true (areStubsNearDuplicates? headStub existing)))
                       false acc))]
      (if isDup
        (dedupStubsLoop tailStubs acc)
        (dedupStubsLoop tailStubs (listAppend acc (list headStub))))))

fn dedupStubs stubs: (List SymbolStub) -> (List SymbolStub)
  (dedupStubsLoop stubs (list))

fn insertRankedStub item: SymbolStub target: Str sorted: (List SymbolStub) -> (List SymbolStub)
  (if (listEmpty? sorted)
    (list item)
    (let [(headStub (optionOr (listHead sorted) (stubCreate "" (tierMacroTopology) "" "" "" 0)))
          (tailStubs (optionOr (listTail sorted) (list)))
          (itemScore (scoreStubBm25 item target))
          (headScore (scoreStubBm25 headStub target))]
      (if (> itemScore headScore)
        (cons item sorted)
        (cons headStub (insertRankedStub item target tailStubs)))))

fn rankStubsByRelevanceLoop unsorted: (List SymbolStub) target: Str sorted: (List SymbolStub) -> (List SymbolStub)
  (if (listEmpty? unsorted)
    sorted
    (let [(item (optionOr (listHead unsorted) (stubCreate "" (tierMacroTopology) "" "" "" 0)))
          (rest (optionOr (listTail unsorted) (list)))]
      (rankStubsByRelevanceLoop rest target (insertRankedStub item target sorted))))

fn rankStubsByRelevance stubs: (List SymbolStub) target: Str -> (List SymbolStub)
  (rankStubsByRelevanceLoop stubs target (list))

fn intelPreloadGraph g: g/SymbolGraph target: Str depth: I64 tokenBudget: I64 -> PreloadedHorizon
  (cond ((stringEmpty? (stringTrim target)) (horizonCreate target depth tokenBudget)) ((<= tokenBudget 0) (PreloadedHorizon :targetSymbol target :maxDepth depth :tokenBudget tokenBudget :totalTokens 0 :stubs (list) :truncated true)) (true (let [(nodes g.nodes) (edges g.edges) (matched (findTargetNode nodes target))] (mt matched ((none) (horizonCreate target depth tokenBudget)) ((some rootN) (let [(rootStub (stubCreate rootN.id (tierMicroAst) rootN.file rootN.signature (str "Full AST for " rootN.name) 0)) (h0 (horizonCreate rootN.id depth tokenBudget)) (h1 (horizonAddStub h0 rootStub))] (if (or h1.truncated (<= depth 0)) h1 (let [(d1Ids (findDepth1Ids rootN.id edges)) (d1Nodes (findNodesByIds d1Ids nodes)) (d1Stubs (map (fn [(n g/GraphNode)] -> SymbolStub (stubCreate n.id (tierMesoSymbol) n.file n.signature "" 0)) d1Nodes)) (d1Dedup (dedupStubs d1Stubs)) (d1Ranked (rankStubsByRelevance d1Dedup target)) (h2 (fold (fn [(acc PreloadedHorizon) (s SymbolStub)] -> PreloadedHorizon (if acc.truncated acc (horizonAddStub acc s))) h1 d1Ranked))] (if (or h2.truncated (<= depth 1)) h2 (let [(d2Ids (findDepth2Ids rootN.id d1Ids edges)) (d2Nodes (findNodesByIds d2Ids nodes)) (d2Stubs (map (fn [(n g/GraphNode)] -> SymbolStub (stubCreate n.id (tierMacroTopology) n.file "" (str "Module/symbol: " n.name) 0)) d2Nodes)) (d2Dedup (dedupStubs d2Stubs)) (d2Ranked (rankStubsByRelevance d2Dedup target)) (h3 (fold (fn [(acc PreloadedHorizon) (s SymbolStub)] -> PreloadedHorizon (if acc.truncated acc (horizonAddStub acc s))) h2 d2Ranked))] h3))))))))))

fn extractShortName fq: Str -> Str
  (if (stringContains? fq "/") (let [(parts (stringSplit fq "/")) (len (listLength parts))] (if (> len 0) (optionOr (listGet parts (- len 1)) fq) fq)) fq)

fn makeNodeFromSymbol sym: ex/SymbolDef -> g/GraphNode
  (g/GraphNode :id sym.name :name (extractShortName sym.name) :kind (ex/kindToString sym.kind) :file sym.file :startLine sym.startLine :endLine sym.endLine :signature sym.signature :exported sym.exported)

fn makeEdgeFromRef ref: ex/SymbolRef -> g/GraphEdge
  (g/GraphEdge :src ref.caller :dst ref.name :kind (g/edgeCalls) :file ref.file :line ref.line)

fn hydrateGraphInto g: g/SymbolGraph fileSyms: (List ex/FileSymbols) -> g/SymbolGraph
  (fold (fn [(accG g/SymbolGraph) (fs ex/FileSymbols)] -> g/SymbolGraph (let [(nodesAdded (fold (fn [(gCurr g/SymbolGraph) (s ex/SymbolDef)] -> g/SymbolGraph (g/graphAddNode gCurr (makeNodeFromSymbol s))) accG fs.symbols)) (edgesAdded (fold (fn [(gCurr g/SymbolGraph) (r ex/SymbolRef)] -> g/SymbolGraph (if (stringEmpty? r.caller) gCurr (g/graphAddEdge gCurr (makeEdgeFromRef r)))) nodesAdded fs.refs))] edgesAdded)) g fileSyms)

fn hydrateGraphFromFileSymbols fileSyms: (List ex/FileSymbols) -> g/SymbolGraph
  (hydrateGraphInto (g/graphCreate) fileSyms)

fn hydrateGraphFromSources sources: (List (Tuple Str Str)) -> g/SymbolGraph
  (let [(fileSyms (map (fn [(pair (Tuple Str Str))] -> ex/FileSymbols (ex/extractAslSymbols (pairFirst pair) (pairSecond pair))) sources))] (hydrateGraphInto (g/graphCreate) fileSyms))

fn extractFnSymbols file: Str source: Str -> (List g/GraphNode)
  (let [(parts (stringSplit source "\n")) (mLine (optionOr (listHead (filter (fn [(l Str)] -> Bool (stringStartsWith? (stringTrim l) "(module ")) parts)) "")) (modName (if (stringEmpty? mLine) "" (let [(mToks (filter (fn [(t Str)] -> Bool (not (stringEmpty? (stringTrim t)))) (stringSplit (stringTrim mLine) " ")))] (stringReplace (stringReplace (optionOr (listGet mToks 1) "") "(" "") ")" "")))) (lines (stringSplit source "\n"))] (fold (fn [(acc (List g/GraphNode)) (line Str)] -> (List g/GraphNode) (let [(trimmed (stringTrim line))] (if (stringStartsWith? trimmed "fn ") (let [(toks (filter (fn [(t Str)] -> Bool (not (stringEmpty? (stringTrim t)))) (stringSplit trimmed " "))) (name (optionOr (listGet toks 1) ""))] (if (stringEmpty? name) acc (let [(fq (if (stringEmpty? modName) name (str modName "/" name))) (node (g/GraphNode :id fq :name name :kind "fn" :file file :startLine 1 :endLine 1 :signature trimmed :exported true))] (listAppend acc (list node))))) acc))) (list) lines))

fn hydrateGraphFromFiles! filePaths: (List Str) -> g/SymbolGraph
  (fold (fn [(accG g/SymbolGraph) (path Str)] -> g/SymbolGraph (mt (fileRead path) ((err _) accG) ((ok src) (let [(fs (ex/extractAslSymbols path src)) (g1 (hydrateGraphInto accG (list fs))) (fnNodes (extractFnSymbols path src))] (fold (fn [(gCurr g/SymbolGraph) (node g/GraphNode)] -> g/SymbolGraph (g/graphAddNode gCurr node)) g1 fnNodes))))) (g/graphCreate) filePaths)

fn defaultWorkspaceFiles! -> (List Str)
  (let [(modules (list "preload.asl" "symbolGraph.asl" "query.asl" "extractor.asl" "codec.asl" "diagram.asl" "health.asl" "intel.asl" "placement.asl" "stmBridge.asl" "textScan.asl" "xref.asl")) (prefix (cond ((fileExists? "asl/packages/asl-intel/src/preload.asl") "asl/packages/asl-intel/src/") ((fileExists? "intel/src/preload.asl") "intel/src/") (else "src/"))) (paths (map (fn [(m Str)] -> Str (str prefix m)) modules))] (filter (fn [(p Str)] -> Bool (fileExists? p)) paths))

fn intelPreloadFiles! filePaths: (List Str) target: Str depth: I64 tokenBudget: I64 -> PreloadedHorizon
  (let [(g (hydrateGraphFromFiles! filePaths))] (intelPreloadGraph g target depth tokenBudget))

fn intelPreload! target: Str depth: I64 tokenBudget: I64 -> PreloadedHorizon
  (let [(paths (defaultWorkspaceFiles!)) (extra (if (and (fileExists? target) (not (listContains? paths target))) (list target) (list))) (allPaths (listAppend paths extra)) (g (hydrateGraphFromFiles! allPaths))] (intelPreloadGraph g target depth tokenBudget))

fn formatStubAsn stub: SymbolStub -> Str
  (str "(:stub :symbol \"" stub.symbol "\" :tier \"" (preloadTierToString stub.tier) "\" :path \"" stub.path "\" :signature \"" stub.signature "\" :docstring \"" stub.docstring "\" :tokens " (stringFromInt64 stub.tokens) ")")

fn formatPreloadContext horizon: PreloadedHorizon -> Str
  (let [(stubs horizon.stubs) (header (str "(:horizon :target \"" horizon.targetSymbol "\" :budget " (stringFromInt64 horizon.tokenBudget) " :tokens " (stringFromInt64 horizon.totalTokens) " :truncated " (if horizon.truncated "true" "false")))] (if (= (listLength stubs) 0) (str header "\n)") (let [(stubFrames (map (fn [(s SymbolStub)] -> Str (formatStubAsn s)) stubs))] (str header "\n  " (stringJoin stubFrames "\n  ") "\n)"))))
