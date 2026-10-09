(module aslMem/paged :x [MemoryTier MemorySegment PagedMemoryManager makeSegment makePagedManager shouldPage? touchSegment evictOldest loadSegment isSegmentActive?] :i [])

(enum MemoryTier (:c tierResident [] "Small/medium codebase: 100% in-memory resident index (<0.04ms query)") (:c tierPagedLru [] "Large codebase: On-demand package segment paging with LRU eviction"))

(schema MemorySegment (:f id Str) (:f packageName Str) (:f byteSize I64) (:f lastAccessEpoch I64) (:f isLoaded Bool) (:f symbolCount I64))

(schema PagedMemoryManager (:f tier MemoryTier) (:f maxResidentSegments I64) (:f maxBytes I64) (:f currentBytes I64) (:f segments (List MemorySegment)))

fn makeSegment id: Str pkg: Str bytes: I64 epoch: I64 symbols: I64 -> MemorySegment
  (MemorySegment :id id :packageName pkg :byteSize bytes :lastAccessEpoch epoch :isLoaded false :symbolCount symbols)

fn makePagedManager maxSegments: I64 maxBytes: I64 isLargeCodebase: Bool -> PagedMemoryManager
  (PagedMemoryManager :tier (if isLargeCodebase (tierPagedLru) (tierResident)) :maxResidentSegments maxSegments :maxBytes maxBytes :currentBytes 0 :segments (list))

fn shouldPage? totalBytes: I64 budgetCeiling: I64 -> Bool
  (> totalBytes budgetCeiling)

fn isSegmentActive? seg: MemorySegment -> Bool
  seg.isLoaded

fn touchSegment mgr: PagedMemoryManager segId: Str now: I64 -> PagedMemoryManager
  (let [(updated (map (fn [(s MemorySegment)] -> MemorySegment (if (= s.id segId) (MemorySegment :id s.id :packageName s.packageName :byteSize s.byteSize :lastAccessEpoch now :isLoaded s.isLoaded :symbolCount s.symbolCount) s)) mgr.segments))] (with mgr :segments updated))

fn evictOldest mgr: PagedMemoryManager -> PagedMemoryManager
  (let [(loaded (filter (fn [(s MemorySegment)] -> Bool s.isLoaded) mgr.segments))] (mt (listHead (listSortBy (fn [(s MemorySegment)] -> I64 s.lastAccessEpoch) loaded)) ((none) mgr) ((some oldest) (let [(newSegs (map (fn [(s MemorySegment)] -> MemorySegment (if (= s.id oldest.id) (MemorySegment :id s.id :packageName s.packageName :byteSize s.byteSize :lastAccessEpoch s.lastAccessEpoch :isLoaded false :symbolCount s.symbolCount) s)) mgr.segments)) (freedBytes (- mgr.currentBytes oldest.byteSize))] (with mgr :currentBytes (if (< freedBytes 0) 0 freedBytes) :segments newSegs)))))

fn loadSegment mgr: PagedMemoryManager seg: MemorySegment now: I64 -> PagedMemoryManager
  (let [(loadedCount (listLength (filter (fn [(s MemorySegment)] -> Bool s.isLoaded) mgr.segments))) (preparedMgr (if (>= loadedCount mgr.maxResidentSegments) (evictOldest mgr) mgr)) (activated (with seg :lastAccessEpoch now :isLoaded true)) (newSegs (listAppend preparedMgr.segments (list activated))) (newBytes (+ preparedMgr.currentBytes seg.byteSize))] (PagedMemoryManager :tier preparedMgr.tier :maxResidentSegments preparedMgr.maxResidentSegments :maxBytes preparedMgr.maxBytes :currentBytes newBytes :segments newSegs))
