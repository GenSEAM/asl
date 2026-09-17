(module asl-runtime
  :d "Pure AgentScript runtime: refcounting, shortest float round-trip, stable sort, and panic handlers"
  :x [rtRetain
      rtRelease
      RefHeader
      makeRefHeader
      rtFormatF64
      rtParseF64
      rtStableSort
      rtStableSortBy
      rtPanic
      rtPanicCode]
  :i [(asl-runtime/refcount :a ref)
      (asl-runtime/float :a flt)
      (asl-runtime/sort :a srt)
      (asl-runtime/panic :a pnc)])

(df makeRefHeader [(ptr String)] -> ref/RefHeader
  :d "Initializes a refcounted header with initial reference count 1."
  (ref/makeRefHeader ptr))

(df rtRetain [(hdr ref/RefHeader)] -> ref/RefHeader
  :d "Increments reference count of heap object."
  (ref/rtRetain hdr))

(df rtRelease [(hdr ref/RefHeader)] -> ref/RefHeader
  :d "Decrements reference count; sets isFreed true when count reaches zero."
  (ref/rtRelease hdr))

(df rtFormatF64 [(val Float64)] -> String
  :d "Formats a 64-bit float using shortest lossless round-trip representation."
  (flt/rtFormatF64 val))

(df rtParseF64 [(s String)] -> Float64
  :d "Parses a string into a 64-bit IEEE 754 float."
  (flt/rtParseF64 s))

(df rtStableSortBy [(items (List Str)) (cmp (fn [(Str) (Str)] -> Bool))] -> (List Str)
  :d "Stably sorts a list of strings using a custom comparison predicate."
  (srt/rtStableSortBy items cmp))

(df rtStableSort [(items (List Str))] -> (List Str)
  :d "Stably sorts a list of strings in ascending lexicographical order."
  (srt/rtStableSort items))

(df ! rtPanicCode [(code Int64) (msg Str)] -> Unit
  :d "Emits a runtime panic message and terminates with exit code."
  (pnc/rtPanicCode code msg))

(df ! rtPanic [(msg Str)] -> Unit
  :d "Emits a runtime panic message and terminates with default exit code 1."
  (pnc/rtPanic msg))
