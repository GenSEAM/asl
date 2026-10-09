(module asl-runtime
  :x [rtRetain rtRelease RefHeader makeRefHeader rtFormatF64 rtParseF64 rtStableSort rtStableSortBy rtPanic rtPanicCode listTake listDrop listZip listFlatten listChunk listAny? listAll? listFind alistGet makeSet setContains? setAdd setRemove setUnion setIntersection setDifference setToList setSize makeMap mapPut mapGet mapContains? mapRemove mapKeys mapValues mapSize PureQueue makeQueue queuePush queuePop queuePeek queueEmpty? queueSize strPadLeft strPadRight strTrimLeft strTrimRight strTrim strReplaceAll strSplitLines strSliceSafe]
  :i [(asl-runtime/refcount :a ref)
      (asl-runtime/float :a flt)
      (asl-runtime/sort :a srt)
      (asl-runtime/panic :a pnc)
      (asl-runtime/collections :a col)
      (asl-runtime/strings :a str)])

fn makeRefHeader ptr: String -> ref/RefHeader
  (ref/makeRefHeader ptr)

fn rtRetain hdr: ref/RefHeader -> ref/RefHeader
  (ref/rtRetain hdr)

fn rtRelease hdr: ref/RefHeader -> ref/RefHeader
  (ref/rtRelease hdr)

fn rtFormatF64 val: Float64 -> String
  (flt/rtFormatF64 val)

fn rtParseF64 s: String -> (Option Float64)
  (flt/rtParseF64 s)

fn rtStableSortBy items: (List Str) cmp: (fn [(Str) (Str)] -> Bool) -> (List Str)
  (srt/rtStableSortBy items cmp)

fn rtStableSort items: (List Str) -> (List Str)
  (srt/rtStableSort items)

fn ! rtPanicCode code: Int64 msg: Str -> Unit
  (pnc/rtPanicCode code msg)

fn ! rtPanic msg: Str -> Unit
  (pnc/rtPanic msg)

fn listTake n: Int64 xs: (List Str) -> (List Str)
  (col/listTake n xs)

fn listDrop n: Int64 xs: (List Str) -> (List Str)
  (col/listDrop n xs)

fn listZip xs: (List Str) ys: (List Str) -> (List (Pair Str Str))
  (col/listZip xs ys)

fn listFlatten xss: (List (List Str)) -> (List Str)
  (col/listFlatten xss)

fn listChunk chunkSize: Int64 xs: (List Str) -> (List (List Str))
  (col/listChunk chunkSize xs)

fn listAny? predicate: (fn [Str] -> Bool) xs: (List Str) -> Bool
  (col/listAny? predicate xs)

fn listAll? predicate: (fn [Str] -> Bool) xs: (List Str) -> Bool
  (col/listAll? predicate xs)

fn alistGet key: Str alist: (List (Pair Str Str)) -> (Option Str)
  (col/alistGet key alist)

fn makeSet elements: (List Str) -> col/PureSet
  (col/makeSet elements)

fn setContains? s: col/PureSet item: Str -> Bool
  (col/setContains? s item)

fn setAdd s: col/PureSet item: Str -> col/PureSet
  (col/setAdd s item)

fn setRemove s: col/PureSet item: Str -> col/PureSet
  (col/setRemove s item)

fn setUnion s1: col/PureSet s2: col/PureSet -> col/PureSet
  (col/setUnion s1 s2)

fn setIntersection s1: col/PureSet s2: col/PureSet -> col/PureSet
  (col/setIntersection s1 s2)

fn setDifference s1: col/PureSet s2: col/PureSet -> col/PureSet
  (col/setDifference s1 s2)

fn setToList s: col/PureSet -> (List Str)
  (col/setToList s)

fn setSize s: col/PureSet -> Int64
  (col/setSize s)

fn makeMap -> col/PureMap
  (col/makeMap)

fn mapPut m: col/PureMap key: Str val: Str -> col/PureMap
  (col/mapPut m key val)

fn mapGet m: col/PureMap key: Str -> (Option Str)
  (col/mapGet m key)

fn mapContains? m: col/PureMap key: Str -> Bool
  (col/mapContains? m key)

fn mapRemove m: col/PureMap key: Str -> col/PureMap
  (col/mapRemove m key)

fn mapKeys m: col/PureMap -> (List Str)
  (col/mapKeys m)

fn mapValues m: col/PureMap -> (List Str)
  (col/mapValues m)

fn mapSize m: col/PureMap -> Int64
  (col/mapSize m)

fn listFind pred: (fn [Str] -> Bool) xs: (List Str) -> (Option Str)
  (col/listFind pred xs)

fn makeQueue -> col/PureQueue
  (col/makeQueue)

fn queuePush q: col/PureQueue item: Str -> col/PureQueue
  (col/queuePush q item)

fn queuePop q: col/PureQueue -> (Pair (Option Str) col/PureQueue)
  (col/queuePop q)

fn queuePeek q: col/PureQueue -> (Option Str)
  (col/queuePeek q)

fn queueEmpty? q: col/PureQueue -> Bool
  (col/queueEmpty? q)

fn queueSize q: col/PureQueue -> Int64
  (col/queueSize q)

fn strPadLeft s: String targetLen: Int64 padChar: String -> String
  (str/strPadLeft s targetLen padChar)

fn strPadRight s: String targetLen: Int64 padChar: String -> String
  (str/strPadRight s targetLen padChar)

fn strTrimLeft s: String -> String
  (str/strTrimLeft s)

fn strTrimRight s: String -> String
  (str/strTrimRight s)

fn strTrim s: String -> String
  (str/strTrim s)

fn strReplaceAll s: String oldSub: String newSub: String -> String
  (str/strReplaceAll s oldSub newSub)

fn strSplitLines s: String -> (List String)
  (str/strSplitLines s)

fn strSliceSafe s: String start: Int64 end: Int64 -> String
  (str/strSliceSafe s start end)
