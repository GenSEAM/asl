(module asl-mem/paged
  :d "Adaptive tiered memory manager: fully in-memory index vs paged LRU segment eviction."
  :x [MemoryTier MemorySegment PagedMemoryManager
      make-segment make-paged-manager should-page?
      touch-segment evict-oldest load-segment is-segment-active?]
  :i [])

(dfe MemoryTier
  (:c tier-resident [] "Small/medium codebase: 100% in-memory resident index (<0.04ms query)")
  (:c tier-paged-lru [] "Large codebase: On-demand package segment paging with LRU eviction"))

(dfs MemorySegment
  (:f id Str "Unique segment identifier (package name or module path)")
  (:f package-name Str "Package domain")
  (:f byte-size I64 "Memory footprint in bytes")
  (:f last-access-epoch I64 "Epoch timestamp of last access")
  (:f is-loaded Bool "True if active in resident memory")
  (:f symbol-count I64 "Number of indexed symbols"))

(dfs PagedMemoryManager
  (:f tier MemoryTier "Current operational memory tier")
  (:f max-resident-segments I64 "Maximum number of concurrent resident segments")
  (:f max-bytes I64 "Memory budget ceiling in bytes")
  (:f current-bytes I64 "Active memory consumption in bytes")
  (:f segments (List MemorySegment) "Managed memory segments"))

(df make-segment [(id Str) (pkg Str) (bytes I64) (epoch I64) (symbols I64)] -> MemorySegment
  :d "Constructs an unloaded memory segment."
  (MemorySegment
    :id id
    :package-name pkg
    :byte-size bytes
    :last-access-epoch epoch
    :is-loaded false
    :symbol-count symbols))

(df make-paged-manager [(max-segments I64) (max-bytes I64) (is-large-codebase Bool)] -> PagedMemoryManager
  :d "Initializes an adaptive memory manager configured for resident or paged LRU operation."
  (PagedMemoryManager
    :tier (if is-large-codebase (tier-paged-lru) (tier-resident))
    :max-resident-segments max-segments
    :max-bytes max-bytes
    :current-bytes 0
    :segments (list)))

(df should-page? [(total-bytes I64) (budget-ceiling I64)] -> Bool
  :d "Determines whether memory pressure dictates switching from full resident to paged LRU mode."
  (> total-bytes budget-ceiling))

(df is-segment-active? [(seg MemorySegment)] -> Bool
  :d "Returns true if segment is currently resident in memory."
  (.-is-loaded seg))

(df touch-segment [(mgr PagedMemoryManager) (seg-id Str) (now I64)] -> PagedMemoryManager
  :d "Updates the access epoch timestamp of a segment to prevent LRU eviction."
  (let [(updated (map (fn [(s MemorySegment)] -> MemorySegment
                        (if (= (.-id s) seg-id)
                          (MemorySegment
                            :id (.-id s)
                            :package-name (.-package-name s)
                            :byte-size (.-byte-size s)
                            :last-access-epoch now
                            :is-loaded (.-is-loaded s)
                            :symbol-count (.-symbol-count s))
                          s))
                      (.-segments mgr)))]
    (PagedMemoryManager
      :tier (.-tier mgr)
      :max-resident-segments (.-max-resident-segments mgr)
      :max-bytes (.-max-bytes mgr)
      :current-bytes (.-current-bytes mgr)
      :segments updated)))

(df evict-oldest [(mgr PagedMemoryManager)] -> PagedMemoryManager
  :d "Unloads the least recently accessed segment to maintain budget ceiling."
  (let [(loaded (filter (fn [(s MemorySegment)] -> Bool (.-is-loaded s)) (.-segments mgr)))]
    (mt (list-head (list-sort-by (fn [(s MemorySegment)] -> I64 (.-last-access-epoch s)) loaded))
      ((none) mgr)
      ((some oldest)
       (let [(new-segs (map (fn [(s MemorySegment)] -> MemorySegment
                              (if (= (.-id s) (.-id oldest))
                                (MemorySegment
                                  :id (.-id s)
                                  :package-name (.-package-name s)
                                  :byte-size (.-byte-size s)
                                  :last-access-epoch (.-last-access-epoch s)
                                  :is-loaded false
                                  :symbol-count (.-symbol-count s))
                                s))
                            (.-segments mgr)))
             (freed-bytes (- (.-current-bytes mgr) (.-byte-size oldest)))]
         (PagedMemoryManager
           :tier (.-tier mgr)
           :max-resident-segments (.-max-resident-segments mgr)
           :max-bytes (.-max-bytes mgr)
           :current-bytes (if (< freed-bytes 0) 0 freed-bytes)
           :segments new-segs))))))

(df load-segment [(mgr PagedMemoryManager) (seg MemorySegment) (now I64)] -> PagedMemoryManager
  :d "Loads segment into resident memory, performing LRU eviction if capacity is reached."
  (let [(loaded-count (list-length (filter (fn [(s MemorySegment)] -> Bool (.-is-loaded s)) (.-segments mgr))))
        (prepared-mgr (if (>= loaded-count (.-max-resident-segments mgr))
                        (evict-oldest mgr)
                        mgr))
        (activated (MemorySegment
                     :id (.-id seg)
                     :package-name (.-package-name seg)
                     :byte-size (.-byte-size seg)
                     :last-access-epoch now
                     :is-loaded true
                     :symbol-count (.-symbol-count seg)))
        (new-segs (list-append (.-segments prepared-mgr) (list activated)))
        (new-bytes (+ (.-current-bytes prepared-mgr) (.-byte-size seg)))]
    (PagedMemoryManager
      :tier (.-tier prepared-mgr)
      :max-resident-segments (.-max-resident-segments prepared-mgr)
      :max-bytes (.-max-bytes prepared-mgr)
      :current-bytes new-bytes
      :segments new-segs)))
