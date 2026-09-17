(module asl-runtime/refcount
  :d "Pure AgentScript refcounting model and memory lifecycle tracking"
  :x [rtRetain
      rtRelease
      RefHeader
      makeRefHeader]
  :i [])

(dfs RefHeader
  (:f ptr String "Pointer address or resource identifier")
  (:f refCount Int64 "Active reference count")
  (:f isFreed Bool "True if memory has been deallocated"))

(df makeRefHeader [(ptr String)] -> RefHeader
  :d "Initializes a refcounted header with initial reference count 1."
  (RefHeader :ptr ptr :refCount 1 :isFreed false))

(df rtRetain [(hdr RefHeader)] -> RefHeader
  :d "Increments reference count of heap object."
  (RefHeader :ptr (.-ptr hdr)
             :refCount (+ (.-refCount hdr) 1)
             :isFreed false))

(df rtRelease [(hdr RefHeader)] -> RefHeader
  :d "Decrements reference count; sets isFreed true when count reaches zero."
  (let [(cnt (- (.-refCount hdr) 1))]
    (if (<= cnt 0)
        (RefHeader :ptr (.-ptr hdr) :refCount 0 :isFreed true)
        (RefHeader :ptr (.-ptr hdr) :refCount cnt :isFreed false))))
