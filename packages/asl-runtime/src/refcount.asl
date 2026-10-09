(module asl-runtime/refcount :x [rtRetain rtRelease RefHeader makeRefHeader] :i [])

(schema RefHeader (:f ptr String) (:f refCount Int64) (:f isFreed Bool))

fn makeRefHeader ptr: String -> RefHeader
  (RefHeader :ptr ptr :refCount 1 :isFreed false)

fn rtRetain hdr: RefHeader -> RefHeader
  (with hdr :refCount (+ hdr.refCount 1) :isFreed false)

fn rtRelease hdr: RefHeader -> RefHeader
  (let [(cnt (- hdr.refCount 1))] (if (<= cnt 0) (with hdr :refCount 0 :isFreed true) (with hdr :refCount cnt :isFreed false)))
