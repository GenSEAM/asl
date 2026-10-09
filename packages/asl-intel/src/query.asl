(module aslIntel/query :x [QueryKind qSearch qCallers qCallees qImpact qAffected qContext ImpactItem QueryResult formatQueryKind filterByDepth makeQueryResult queryCallers queryCallees queryImpact bfsImpact] :i [(symbolGraph :a g) (asl-runtime/collections :a col)])

(enum QueryKind (:c qSearch [] "Search query") (:c qCallers [] "Callers query") (:c qCallees [] "Callees query") (:c qImpact [] "Impact query") (:c qAffected [] "Affected query") (:c qContext [] "Context query"))

(schema ImpactItem (:f symbolId Str) (:f name Str) (:f file Str) (:f depth I64))

(schema QueryResult (:f query Str) (:f kind QueryKind) (:f items (List ImpactItem)) (:f total I64))

fn formatQueryKind k: QueryKind -> Str
  (mt k ((qSearch) "search") ((qCallers) "callers") ((qCallees) "callees") ((qImpact) "impact") ((qAffected) "affected") ((qContext) "context"))

fn filterByDepth items: (List ImpactItem) maxD: I64 -> (List ImpactItem)
  (filter (fn [(item ImpactItem)] (<= item.depth maxD)) items)

fn makeQueryResult q: Str k: QueryKind items: (List ImpactItem) -> QueryResult
  (QueryResult :query q :kind k :items items :total (listLength items))

fn findNodeById g: g/SymbolGraph id: Str -> (Option g/GraphNode)
  (let [(matches (filter (fn [(n g/GraphNode)] -> Bool (= n.id id)) g.nodes))] (if (listEmpty? matches) (none) (some (optionOr (listHead matches) (g/GraphNode :id id :name id :kind "" :file "" :startLine 0 :endLine 0 :signature "" :exported false)))))

fn makeImpactItem g: g/SymbolGraph symId: Str depth: I64 -> ImpactItem
  (mt (findNodeById g symId) ((some node) (ImpactItem :symbolId symId :name node.name :file node.file :depth depth)) ((none) (ImpactItem :symbolId symId :name symId :file "" :depth depth)))

fn queryCallers g: g/SymbolGraph target: Str -> QueryResult
  (let [(callEdges (filter (fn [(e g/GraphEdge)] -> Bool (and (= e.dst target) (let [(k e.kind)] (mt k ((g/edgeCalls) true) (else false))))) g.edges)) (callerIds (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(s e.src)] (if (listContains? acc s) acc (listAppend acc (list s))))) (list) callEdges)) (items (map (fn [(s Str)] -> ImpactItem (makeImpactItem g s 1)) callerIds))] (QueryResult :query target :kind (qCallers) :items items :total (listLength items)))

fn queryCallees g: g/SymbolGraph target: Str -> QueryResult
  (let [(callEdges (filter (fn [(e g/GraphEdge)] -> Bool (and (= e.src target) (let [(k e.kind)] (mt k ((g/edgeCalls) true) (else false))))) g.edges)) (calleeIds (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(d e.dst)] (if (listContains? acc d) acc (listAppend acc (list d))))) (list) callEdges)) (items (map (fn [(d Str)] -> ImpactItem (makeImpactItem g d 1)) calleeIds))] (QueryResult :query target :kind (qCallees) :items items :total (listLength items)))

fn bfsImpact g: g/SymbolGraph frontier: (List (Pair Str I64)) visited: col/PureSet acc: (List ImpactItem) maxDepth: I64 -> (List ImpactItem)
  (if (listEmpty? frontier) acc (let [(curr (optionOr (listHead frontier) (pair "" 0))) (restFrontier (optionOr (listTail frontier) (list))) (currId (pairFirst curr)) (currDepth (pairSecond curr))] (if (>= currDepth maxDepth) (bfsImpact g restFrontier visited acc maxDepth) (let [(newDepth (+ currDepth 1)) (edges (filter (fn [(e g/GraphEdge)] -> Bool (and (= e.dst currId) (mt e.kind ((g/edgeCalls) true) (else false)))) g.edges)) (callerIds (fold (fn [(c-acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(src e.src)] (if (or (col/setContains? visited src) (listContains? c-acc src)) c-acc (listAppend c-acc (list src))))) (list) edges)) (newItems (map (fn [(s Str)] -> ImpactItem (makeImpactItem g s newDepth)) callerIds)) (newPairs (map (fn [(s Str)] -> (Pair Str I64) (pair s newDepth)) callerIds)) (newVisited (fold (fn [(s-acc col/PureSet) (item Str)] -> col/PureSet (col/setInsert s-acc item)) visited callerIds)) (nextFrontier (listAppend restFrontier newPairs)) (nextAcc (listAppend acc newItems))] (bfsImpact g nextFrontier newVisited nextAcc maxDepth)))))

fn queryImpact g: g/SymbolGraph target: Str maxDepth: I64 -> QueryResult
  (let [(limit (if (<= maxDepth 0) 1 maxDepth)) (initFrontier (list (pair target 0))) (initVisited (col/setInsert (col/setEmpty) target)) (items (bfsImpact g initFrontier initVisited (list) limit))] (QueryResult :query target :kind (qImpact) :items items :total (listLength items)))
