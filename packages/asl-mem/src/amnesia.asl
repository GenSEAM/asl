(module aslMem/amnesia :x [Chunk ChunkDAG RetiredChunk validateMemoryChunk isLowConfidence? chunkDagEmpty chunkDagAdd chunkDagFind detectCycle? chunkDagAncestors evictBelowThreshold transitionToRetired evaluateRetirement retireChunk queryRetiredChunks loadActiveChunks] :i [(viewLayer :a vl) (hydration :a h)])

(schema Chunk (:f id Str) (:f ts I64) (:f conf F64) (:f summary Str) (:f facts (List Str)) (:f directives (List Str)) (:f refs (List Str)))

(schema ChunkDAG (:f chunks (Map Str vl/MemoryChunk)) (:f roots (List Str)) (:f size I64))

fn validateMemoryChunk chunk: vl/MemoryChunk -> Bool
  (and (> (stringLength chunk.id) 0) (and (> chunk.ts 0) (and (>= chunk.conf 0.0) (<= chunk.conf 1.0))))

fn isLowConfidence? chunk: vl/MemoryChunk threshold: F64 -> Bool
  (< chunk.conf threshold)

fn chunkDagEmpty -> ChunkDAG
  (ChunkDAG :chunks (mapEmpty) :roots (list) :size 0)

fn chunkDagFind dag: ChunkDAG id: Str -> (Option vl/MemoryChunk)
  (mapGet dag.chunks id)

fn collectAncestors dag: ChunkDAG id: Str visited: (List Str) -> (List Str)
  (mt (chunkDagFind dag id) ((none) visited) ((some chunk) (let [(parents chunk.refs)] (fold (fn [(acc (List Str)) (pId Str)] -> (List Str) (if (listContains? acc pId) acc (let [(accWithP (collectAncestors dag pId acc))] (if (listContains? accWithP pId) accWithP (listAppend accWithP (list pId)))))) visited parents))))

fn chunkDagAncestors dag: ChunkDAG chunkId: Str -> (List Str)
  (collectAncestors dag chunkId (list))

fn detectCycle? dag: ChunkDAG candidate: vl/MemoryChunk -> Bool
  (let [(candId candidate.id) (refs candidate.refs)] (if (listContains? refs candId) true (fold (fn [(hasCycle Bool) (refId Str)] -> Bool (or hasCycle (or (= refId candId) (listContains? (chunkDagAncestors dag refId) candId)))) false refs)))

fn allRefsExist? chunks: (Map Str vl/MemoryChunk) refs: (List Str) -> Bool
  (fold (fn [(okFlag Bool) (rId Str)] -> Bool (and okFlag (mapHas? chunks rId))) true refs)

fn chunkDagAdd dag: ChunkDAG chunk: vl/MemoryChunk -> (Result ChunkDAG Str)
  (let [(cId chunk.id) (refs chunk.refs)] (cond ((mapHas? dag.chunks cId) (err "chunk ID already exists in DAG")) ((not (allRefsExist? dag.chunks refs)) (err "missing parent reference in DAG")) ((detectCycle? dag chunk) (err "cycle detected in chunk references")) (else (let [(newChunks (mapSet dag.chunks cId chunk)) (newRoots (if (listEmpty? refs) (listAppend dag.roots (list cId)) dag.roots)) (newSize (+ dag.size 1))] (ok (ChunkDAG :chunks newChunks :roots newRoots :size newSize))))))

fn evictBelowThreshold chunks: (List vl/MemoryChunk) threshold: F64 -> (List vl/MemoryChunk)
  (filter (fn [(c vl/MemoryChunk)] -> Bool (not (isLowConfidence? c threshold))) chunks)

(schema RetiredChunk (:f chunk vl/MemoryChunk) (:f status Str) (:f closureCondition Str) (:f retiredAt I64))

fn transitionToRetired chunk: vl/MemoryChunk closureCondition: Str nowTs: I64 -> RetiredChunk
  (RetiredChunk :chunk chunk :status "retired" :closureCondition closureCondition :retiredAt nowTs)

fn evaluateRetirement chunk: vl/MemoryChunk closureCondition: Str isSatisfied: Bool nowTs: I64 -> (Option RetiredChunk)
  (if isSatisfied (some (transitionToRetired chunk closureCondition nowTs)) (none))

fn retireChunk dag: ChunkDAG chunkId: Str closureCondition: Str nowTs: I64 -> (Option RetiredChunk)
  (mt (chunkDagFind dag chunkId) ((none) (none)) ((some c) (some (transitionToRetired c closureCondition nowTs))))

fn queryRetiredChunks retiredList: (List RetiredChunk) query: Str -> (List RetiredChunk)
  (filter (fn [(rc RetiredChunk)] -> Bool (let [(c rc.chunk)] (or (stringContains? c.id query) (or (stringContains? c.summary query) (stringContains? rc.closureCondition query))))) retiredList)

fn loadActiveChunks dag: ChunkDAG retiredIds: (List Str) -> (List vl/MemoryChunk)
  (let [(allChunks (mapValues dag.chunks))] (filter (fn [(c vl/MemoryChunk)] -> Bool (not (listContains? retiredIds c.id))) allChunks))
