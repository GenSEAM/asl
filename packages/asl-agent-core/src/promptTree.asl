(module aslAgentCore/promptTree :x [PromptRadixNode PromptTree AssembledPrompt promptTreeInit promptTreeBranch promptTreeAssemble promptTreeCalcSavings] :i [(asl-text/text :a txt)])

(schema PromptRadixNode (:f id Str) (:f parentId (Option Str)) (:f content Str) (:f tokenEstimate I64) (:f depth I64))

(schema PromptTree (:f nodes (List PromptRadixNode)) (:f rootId Str))

(schema AssembledPrompt (:f nodeId Str) (:f fullText Str) (:f sharedTokens I64) (:f deltaTokens I64) (:f sharingRatioPct I64))

fn promptTreeInit rootId: Str sharedContext: Str -> PromptTree
  (let [(toks (txt/estimateTokens sharedContext)) (rootNode (PromptRadixNode :id rootId :parentId (none) :content sharedContext :tokenEstimate toks :depth 0))] (PromptTree :nodes (list rootNode) :rootId rootId))

fn findPromptNode tree: PromptTree targetId: Str -> (Option PromptRadixNode)
  (fold (fn [(acc (Option PromptRadixNode)) (n PromptRadixNode)] -> (Option PromptRadixNode) (mt acc ((some found) (some found)) ((none) (if (= n.id targetId) (some n) (none))))) (none) tree.nodes)

fn promptTreeBranch tree: PromptTree branchId: Str parentId: Str deltaContext: Str -> PromptTree
  (let [(pOpt (findPromptNode tree parentId))] (mt pOpt ((none) tree) ((some parentNode) (let [(toks (txt/estimateTokens deltaContext)) (newNode (PromptRadixNode :id branchId :parentId (some parentId) :content deltaContext :tokenEstimate toks :depth (+ parentNode.depth 1))) (nextNodes (listAppend tree.nodes (list newNode)))] (with tree :nodes nextNodes)))))

(schema AssemblyAcc (:f txt Str) (:f shared I64))

fn walkTree tree: PromptTree parentId: Str acc: AssemblyAcc -> (Option AssemblyAcc)
  (let [(nodeOpt (findPromptNode tree parentId))] (mt nodeOpt ((none) (none)) ((some node) (let [(nextText (str node.content "\n\n" acc.txt)) (nextShared (+ acc.shared node.tokenEstimate)) (nextAcc (AssemblyAcc :txt nextText :shared nextShared))] (mt node.parentId ((none) (some nextAcc)) ((some pid) (walkTree tree pid nextAcc)))))))

fn promptTreeAssemble tree: PromptTree targetId: Str -> (Option AssembledPrompt)
  (let [(leafOpt (findPromptNode tree targetId))] (mt leafOpt ((none) (none)) ((some leaf) (mt leaf.parentId ((none) (some (AssembledPrompt :nodeId targetId :fullText leaf.content :sharedTokens 0 :deltaTokens leaf.tokenEstimate :sharingRatioPct 0))) ((some pid) (let [(accOpt (walkTree tree pid (AssemblyAcc :txt leaf.content :shared 0)))] (mt accOpt ((none) (none)) ((some acc) (let [(full acc.txt) (shared acc.shared) (delta leaf.tokenEstimate) (total (+ shared delta)) (ratio (if (<= total 0) 0 (/ (* shared 100) total)))] (some (AssembledPrompt :nodeId targetId :fullText full :sharedTokens shared :deltaTokens delta :sharingRatioPct ratio)))))))))))

fn promptTreeCalcSavings tree: PromptTree leafIds: (List Str) -> I64
  (let [(rootOpt (findPromptNode tree tree.rootId))] (mt rootOpt ((none) 0) ((some root) (let [(rootToks root.tokenEstimate) (swarmCount (listLength leafIds))] (if (<= swarmCount 1) 0 (* rootToks (- swarmCount 1)))))))
