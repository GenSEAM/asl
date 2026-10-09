(module asl-target-llvm/gcAsl
  :x [GcCtx gcFactNames gcFacts gcFactsFor gcStrings gcExterns gcFunctions helperDefinitions helperDefinitionsFor functionName stateWords stateBlockText]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)])

schema GcCtx
  k: (Map String Int64)
  errno: String
  target: target/TargetFacts

fn pn name: String -> String
  (str "asl-target-llvm/gcAsl." name)

fn functionName name: String -> String
  (pn name)

fn pageSize -> Int64
  16384

fn pageHeader -> Int64
  512

fn numClasses -> Int64
  63

fn maxSmall -> Int64
  512

fn largeClass -> Int64
  255

fn runPages -> Int64
  64

fn maxRoots -> Int64
  4096

fn frameBytes -> Int64
  24

fn sAllocated -> Int64
  0

fn sThreshold -> Int64
  1

fn sMinBytes -> Int64
  2

fn sMaxBytes -> Int64
  3

fn sGrowthBits -> Int64
  4

fn sStress -> Int64
  5

fn sStats -> Int64
  6

fn sVerify -> Int64
  7

fn sCollections -> Int64
  8

fn sObjectsAllocated -> Int64
  9

fn sObjectsFreed -> Int64
  10

fn sBytesAllocated -> Int64
  11

fn sBytesLive -> Int64
  12

fn sTotalNs -> Int64
  13

fn sPagesFreed -> Int64
  14

fn sPagesAcquired -> Int64
  15

fn sRootCount -> Int64
  16

fn sProtos -> Int64
  17

fn sProtoCount -> Int64
  18

fn sProtoCap -> Int64
  19

fn sMarkStack -> Int64
  20

fn sMarkSp -> Int64
  21

fn sMarkCap -> Int64
  22

fn sDfsStack -> Int64
  23

fn sDfsSp -> Int64
  24

fn sDfsCap -> Int64
  25

fn sCachedPages -> Int64
  26

fn sCachedCount -> Int64
  27

fn sLargeObjects -> Int64
  28

fn sPageSet -> Int64
  29

fn sPageSetCap -> Int64
  30

fn sPageSetCount -> Int64
  31

fn sLargeIndex -> Int64
  32

fn sLargeCount -> Int64
  33

fn sLargeCap -> Int64
  34

fn sLargeSorted -> Int64
  35

fn sHeapLo -> Int64
  36

fn sHeapHi -> Int64
  37

fn sCollecting -> Int64
  38

fn sFailNextGrow -> Int64
  39

fn sFreshNext -> Int64
  40

fn sFreshEnd -> Int64
  41

fn sTimespec -> Int64
  42

fn sEndPtr -> Int64
  46

fn sReleaseBuf -> Int64
  47

fn sReleaseCap -> Int64
  48

fn sMarkNs -> Int64
  49

fn sSweepLargeNs -> Int64
  50

fn sSweepPagesNs -> Int64
  51

fn sReleaseNs -> Int64
  52

fn sPagesMapped -> Int64
  53

fn sPagesUnmapped -> Int64
  54

fn sUnmapCalls -> Int64
  55

fn sClasses -> Int64
  64

fn sRoots -> Int64
  256

fn stateWords -> Int64
  (+ (sRoots) (maxRoots))

fn stateBlockText -> String
  (let [(init (map (fn [(i Int64)] -> String
                     (str "i64 " (cond ((= i (sThreshold)) "8388608") ((= i (sMinBytes)) "8388608") ((= i (sGrowthBits)) "4611686018427387904")
                                       ((= i (sLargeSorted)) "1") ((= i (sHeapLo)) "-1") (else "0"))))
                   (range 0 64)))]
    (str "@gcAsl.state = internal global { [64 x i64], [" (- (stateWords) 64) " x i64] } { [64 x i64] [" (stringJoin init ", ") "], ["
         (- (stateWords) 64) " x i64] zeroinitializer }, align 16"))

fn gcFactNames -> (List String)
  (list "PROT_READ" "PROT_WRITE" "MAP_PRIVATE" "MAP_ANON" "CLOCK_MONOTONIC" "timespec.size" "timespec.tv_sec" "timespec.tv_nsec")

fn factOf facts: libc/TripleFacts name: String -> (Option Int64)
  (mt (stringIndexOf name ".")
    ((none) (libc/libcConst facts name))
    ((some i)
      (let [(sname (optionOr (stringSlice name 0 i) ""))
            (field (optionOr (stringSlice name (+ i 1) (stringLength name)) ""))]
        (if (= field "size")
          (libc/structSize facts sname)
          (mt (libc/pairFind facts.structs sname)
            ((some sf) (libc/structFieldOffset sf field))
            ((none) (none)))))))

fn gcFacts facts: libc/TripleFacts -> (Result GcCtx String)
  (gcFactsFor facts (target/nativeTargetFacts facts.triple))

fn gcFactsFor facts: libc/TripleFacts target: target/TargetFacts -> (Result GcCtx String)
  (if (target/isWasm32 target)
    (ok (GcCtx :k (mapEmpty) :errno "" :target target))
    (let [(resolved (fold (fn [(acc (Result (Map String Int64) String)) (n String)] -> (Result (Map String Int64) String)
                          (mt acc
                            ((err e) (err e))
                            ((ok m) (mt (factOf facts n)
                                      ((some v) (ok (mapSet m n v)))
                                      ((none) (err (str "libc.asl has no " n " for " facts.triple)))))))
                        (ok (mapEmpty)) (gcFactNames)))]
    (mt resolved
      ((err e) (err e))
      ((ok m)
        (cond
          ((> (optionOr (mapGet m "timespec.size") 0) 32) (err (str "struct timespec exceeds 32 bytes on " facts.triple)))
          ((stringEmpty? facts.errnoAccessor) (err (str "libc.asl names no errno accessor for " facts.triple)))
          (else (ok (GcCtx :k m :errno facts.errnoAccessor :target target))))))))

fn fact c: GcCtx name: String -> Int64
  (optionOr (mapGet c.k name) 0)

fn wasm? c: GcCtx -> Bool
  (target/isWasm32 c.target)

fn freeName c: GcCtx -> String
  (if (wasm? c) "asl_wasm_free" "free")

fn exitName c: GcCtx -> String
  (if (wasm? c) "asl_wasm_exit" "exit")

fn clockName -> String
  "asl_wasm_now_ns"

fn statsFormat -> String
  "(:gcStats :collections %llu :objectsAllocated %llu :objectsFreed %llu :bytesAllocated %llu :bytesLive %llu :totalGCNs %llu :pagesFreed %llu :pagesAcquired %llu)\n"

fn phasesFormat -> String
  "(:gcPhases :markNs %llu :sweepLargeNs %llu :sweepPagesNs %llu :releaseNs %llu :pagesMapped %llu :pagesUnmapped %llu :unmapCalls %llu)\n"

fn gcStrings -> (List String)
  (list "ERR_INTERNAL" "gc root stack overflow" "ERR_OOM" "out of memory growing the GC page set to %zu entries"
        "gc page set is empty on page release" "gc page %p missing from the page set" "out of memory allocating GC page"
        "out of memory growing the large object index to %zu entries" "out of memory allocating %zu bytes" "live heap exceeds ASL_GC_MAX_MIB=%zu"
        "gcScanConservative outside a collection" "gcScanConservative range %p..%p is inverted" "ERR_HEAP_CYCLE" "cycle of depth %d detected in %s"
        "(:gcCycle :type %s :depth %d)\n" "ERR_LIMIT" "heap verification stack depth limit exceeded" "ERR_OOM\n" (statsFormat)
        "ASL_GC_STRESS" "ASL_GC_STATS" "ASL_GC_GROWTH" "ASL_GC_MIN_MIB" "ASL_GC_MAX_MIB" "ASL_GC_VERIFY"
        "ERR_ENV: ASL_GC_GROWTH must be a number in [0.25, 64], got '%s'\n" "ERR_ENV: ASL_GC_MIN_MIB must be an integer in [1, 65536], got '%s'\n"
        "ERR_ENV: ASL_GC_MAX_MIB must be an integer in [1, 65536], got '%s'\n" "cannot unmap GC memory at %p"
        (phasesFormat) "out of memory releasing %zu GC pages"
        ":cons" ":record" ":ctor" ":closure" ":string" ":bytes" ":array" ":handle" ":unknown")

fn appendAll lists: (List (List V)) -> (List V)
  (fold (fn [(acc (List V)) (l (List V))] -> (List V) (listAppend acc l)) (list) lists)

fn i1 -> ty/SsaTy
  (ty/tyI1)

fn i64 -> ty/SsaTy
  (ty/tyI64)

fn i32 -> ty/SsaTy
  (ty/tyI32)

fn f64 -> ty/SsaTy
  (ty/tyF64)

fn ptr -> ty/SsaTy
  (ty/tyPtr)

fn ins d: String t: ty/SsaTy op: ty/SsaOp -> (List ty/SsaInstr)
  (list (ty/ssaInstr d t op))

fn k d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i64) (ty/opConst (ty/constInt n)))

fn k32 d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i32) (ty/opConst (ty/constInt n)))

fn kf d: String x: Float64 -> (List ty/SsaInstr)
  (ins d (f64) (ty/opConst (ty/constFloat x)))

fn cs d: String text: String -> (List ty/SsaInstr)
  (ins d (ptr) (ty/opConst (ty/constStr (optionOr (listIndexOf (gcStrings) text) -1))))

fn pr d: String t: ty/SsaTy name: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opPrim name args))

fn ex d: String t: ty/SsaTy callee: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opCall callee args))

fn cl d: String name: String args: (List String) -> (List ty/SsaInstr)
  (ins d (i64) (ty/opCall (pn name) args))

fn i2p d: String i: String -> (List ty/SsaInstr)
  (pr d (ptr) "rawIntToPtr" (list i))

fn p2i d: String p: String -> (List ty/SsaInstr)
  (pr d (i64) "rawPtrToInt" (list p))

fn add d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawAddI64" (list a b))

fn addK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (add d a (str d ".k"))))

fn sub d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawSubI64" (list a b))

fn mul d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawMulI64" (list a b))

fn mulK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (mul d a (str d ".k"))))

fn quot d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "quotInt" (list a b))

fn band d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawAndI64" (list a b))

fn bandK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (band d a (str d ".k"))))

fn bor d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawOrI64" (list a b))

fn bxor d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawXorI64" (list a b))

fn shl d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawShlI64" (list a b))

fn shlK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (shl d a (str d ".k"))))

fn shr d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawLshrI64" (list a b))

fn shrK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (shr d a (str d ".k"))))

fn byteAtK d: String h: String shift: Int64 -> (List ty/SsaInstr)
  (appendAll (list (shrK (str d ".s") h shift) (bandK d (str d ".s") 255)))

fn cmp d: String name: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) name (list a b))

fn cmpK d: String name: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (cmp d name a (str d ".k"))))

fn flip d: String a: String -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".one") 1) (k (str d ".sh") 63) (shl (str d ".min") (str d ".one") (str d ".sh")) (bxor d a (str d ".min"))))

fn ult d: String a: String b: String -> (List ty/SsaInstr)
  (appendAll (list (flip (str d ".a") a) (flip (str d ".b") b) (cmp d "ltInt" (str d ".a") (str d ".b"))))

fn ule d: String a: String b: String -> (List ty/SsaInstr)
  (appendAll (list (flip (str d ".a") a) (flip (str d ".b") b) (cmp d "leInt" (str d ".a") (str d ".b"))))

fn ultK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".n") n) (ult d a (str d ".n"))))

fn orB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "orBool" (list a b))

fn andB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "andBool" (list a b))

fn notB d: String a: String -> (List ty/SsaInstr)
  (pr d (i1) "notBool" (list a))

fn n32 d: String v: String -> (List ty/SsaInstr)
  (pr d (i32) "rawNarrowI32" (list v))

fn w64 d: String v: String -> (List ty/SsaInstr)
  (pr d (i64) "rawWidenI32" (list v))

fn ld d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (pr d (i64) "rawLoadI64" (list (str d ".ptr") (str d ".off")))))

fn ldS32 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (pr (str d ".w") (i32) "rawLoadI32" (list (str d ".ptr") (str d ".off"))) (w64 d (str d ".w"))))

fn ldU32 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (ldS32 (str d ".s") addr off) (bandK d (str d ".s") 4294967295)))

fn ld8 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (pr (str d ".w") (i32) "rawLoadI8" (list (str d ".ptr") (str d ".off"))) (w64 d (str d ".w"))))

fn st d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (pr d (i1) "rawStoreI64" (list (str d ".ptr") (str d ".off") v))))

fn stK d: String addr: String off: Int64 n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".v") n) (st d addr off (str d ".v"))))

fn st8K d: String addr: String off: Int64 n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (k32 (str d ".v") n) (pr d (i1) "rawStoreI8" (list (str d ".ptr") (str d ".off") (str d ".v")))))

fn st8 d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".ptr") addr) (k (str d ".off") off) (n32 (str d ".n") v) (pr d (i1) "rawStoreI8" (list (str d ".ptr") (str d ".off") (str d ".n")))))

fn state -> (List ty/SsaInstr)
  (ex "s" (i64) "gcAslState" (list))

fn sld d: String slot: Int64 -> (List ty/SsaInstr)
  (ld d "s" (* 8 slot))

fn sst d: String slot: Int64 v: String -> (List ty/SsaInstr)
  (st d "s" (* 8 slot) v)

fn sstK d: String slot: Int64 n: Int64 -> (List ty/SsaInstr)
  (stK d "s" (* 8 slot) n)

fn sinc d: String slot: Int64 by: String -> (List ty/SsaInstr)
  (appendAll (list (sld (str d ".old") slot) (add (str d ".new") (str d ".old") by) (sst d slot (str d ".new"))))

fn sincK d: String slot: Int64 n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".by") n) (sinc d slot (str d ".by"))))

fn classAddr d: String sc: String -> (List ty/SsaInstr)
  (appendAll (list (mulK (str d ".m") sc 24) (add (str d ".a") "s" (str d ".m")) (addK d (str d ".a") (* 8 (sClasses)))))

fn elem d: String base: String i: String size: Int64 -> (List ty/SsaInstr)
  (appendAll (list (mulK (str d ".m") i size) (add d base (str d ".m"))))

fn hasObj d: String tag: String obj: String -> (List ty/SsaInstr)
  (appendAll (list (cmpK (str d ".lo") "geInt" tag 5) (cmpK (str d ".hi") "leInt" tag 15) (cmpK (str d ".ne") "neInt" tag 10) (cmpK (str d ".nz") "neInt" obj 0)
                   (andB (str d ".a") (str d ".lo") (str d ".hi")) (andB (str d ".b") (str d ".ne") (str d ".nz")) (andB d (str d ".a") (str d ".b"))))

fn blk label: String parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) (appendAll parts) term)

fn blkp label: String params: (List String) parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (map (fn [(p String)] -> ty/SsaParam (ty/ssaParam p (i64))) params) (appendAll parts) term)

fn jmp label: String args: (List String) -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge label args))

fn br c: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes (list)) (ty/ssaEdge no (list)))

fn brA c: String yes: String yesArgs: (List String) no: String noArgs: (List String) -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes yesArgs) (ty/ssaEdge no noArgs))

fn ret v: String -> ty/SsaTerm
  (ty/termReturn v)

fn retZero label: String parts: (List (List ty/SsaInstr)) -> ty/SsaBlock
  (blk label (listAppend parts (list (k (str label ".z") 0))) (ret (str label ".z")))

fn fun name: String params: (List String) blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction (pn name) (list) (map (fn [(p String)] -> ty/SsaParam (ty/ssaParam p (i64))) params) (i64) blocks)

fn failB label: String code: String fmt: String args: (List (List ty/SsaInstr)) argNames: (List String) -> ty/SsaBlock
  (retZero label (listAppend args (list (cs (str label ".c") code) (cs (str label ".f") fmt)
                                        (ex (str label ".r") (i64) "gcFloorFail" (listAppend (list (str label ".c") (str label ".f")) argNames)))))

fn exitB c: GcCtx label: String code: Int64 -> ty/SsaBlock
  (retZero label (list (k32 (str label ".c") code) (ex (str label ".r") (i64) (exitName c) (list (str label ".c")))))

fn helperExterns -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped "gcAslState" (list) (i64)) (ty/ssaExternTyped "gcAslCollect" (list) (i64))
        (ty/ssaExternTyped "gcAslMutatorRoots" (list) (i64)) (ty/ssaExternTyped "gcAslExternalRoots" (list) (i64))
        (ty/ssaExternTyped "gcAslStackBase" (list) (i64)) (ty/ssaExternTyped "gcAslStackTop" (list) (i64))
        (ty/ssaExternTyped "gcAslCallFin" (list (i64) (i64)) (i64)) (ty/ssaExternTyped "gcAslFinGuarded" (list (i64) (i64) (i64)) (i64))
        (ty/ssaExternTyped "gcAslRethrow" (list (i64)) (i64)) (ty/ssaExternTyped "gcAslSortLarge" (list (i64) (i64)) (i64))
        (ty/ssaExternTyped "gcAslCtz" (list (i64)) (i64)) (ty/ssaExternTyped "gcAslAtexitStats" (list) (i64))
        (ty/ssaExternTyped "gcAslF64Bits" (list (f64)) (i64)) (ty/ssaExternTyped "gcAslBitsF64" (list (i64)) (f64))
        (ty/ssaExternTyped "gcAslF64ToU64" (list (f64)) (i64)))

fn helperExternsFor c: GcCtx -> (List ty/SsaExtern)
  (if (wasm? c)
    (listAppend (filter (fn [(e ty/SsaExtern)] -> Bool (!= e.name "gcAslAtexitStats")) (helperExterns)) (list (ty/ssaExternTyped "gcAslShadowTop" (list) (i64))))
    (helperExterns))

fn gcExterns c: GcCtx -> (List ty/SsaExtern)
  (let [(t (fn [(name String) (params (List ty/SsaTy)) (r ty/SsaTy)] -> ty/SsaExtern (ty/ssaExternTyped name params r)))]
    (if (wasm? c)
      (listAppend (helperExternsFor c)
        (list (t "calloc" (list (i64) (i64)) (ptr)) (t "realloc" (list (ptr) (i64)) (ptr)) (t (freeName c) (list (ptr)) (i64))
              (t "memset" (list (ptr) (i32) (i64)) (ptr)) (t "memcpy" (list (ptr) (ptr) (i64)) (ptr)) (t "strlen" (list (ptr)) (i64))
              (t "llvm.wasm.memory.grow.i32" (list (i32) (i32)) (i32)) (t (clockName) (list) (i64)) (t (exitName c) (list (i32)) (i64))
              (ty/ssaExternVariadic "dprintf" (list (i32) (ptr)) (i32)) (ty/ssaExternVariadic "gcFloorFail" (list (ptr) (ptr)) (i64))))
    (listAppend (helperExterns)
      (listAppend
        (list (t "calloc" (list (i64) (i64)) (ptr)) (t "realloc" (list (ptr) (i64)) (ptr)) (t "free" (list (ptr)) (i64))
              (t "memset" (list (ptr) (i32) (i64)) (ptr)) (t "memcpy" (list (ptr) (ptr) (i64)) (ptr)) (t "strlen" (list (ptr)) (i64)))
        (listAppend
          (if (target/growsLinearMemory c.target)
            (list (t "llvm.wasm.memory.grow.i32" (list (i32) (i32)) (i32)))
            (list (t "mmap" (list (ptr) (i64) (i32) (i32) (i32) (i64)) (ptr)) (t "munmap" (list (ptr) (i64)) (i32))) )
          (list (t "getenv" (list (ptr)) (ptr)) (t "strtod" (list (ptr) (ptr)) (f64)) (t "strtoull" (list (ptr) (ptr) (i32)) (i64))
                (t c.errno (list) (ptr)) (t "clock_gettime" (list (i32) (ptr)) (i32)) (t "exit" (list (i32)) (i64))
                (ty/ssaExternVariadic "dprintf" (list (i32) (ptr)) (i32)) (ty/ssaExternVariadic "gcFloorFail" (list (ptr) (ptr)) (i64))))))))

fn helperDefinitions -> (List (Pair String String))
  (list (pair "declare tailcc i64 @gcAslState()"
              "define internal tailcc i64 @gcAslState() {\n  %p = ptrtoint ptr @gcAsl.state to i64\n  ret i64 %p\n}")
        (pair "declare tailcc i64 @gcAslCollect()"
              "define internal tailcc i64 @gcAslCollect() {\n  call void @asl_gc_collect()\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslMutatorRoots()"
              "define internal tailcc i64 @gcAslMutatorRoots() {\n  call void @gcMutatorRoots(ptr @gcAslMarkRootC)\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslExternalRoots()"
              "define internal tailcc i64 @gcAslExternalRoots() {\nentry:\n  %f = load ptr, ptr @gcExternalRoots\n  %z = icmp eq ptr %f, null\n  br i1 %z, label %done, label %call\ncall:\n  call void %f(ptr @gcAslMarkRootC)\n  br label %done\ndone:\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslStackBase()"
              "define internal tailcc i64 @gcAslStackBase() {\n  %p = load ptr, ptr @gcStackBase\n  %i = ptrtoint ptr %p to i64\n  ret i64 %i\n}")
        (pair "declare tailcc i64 @gcAslStackTop()"
              "define internal tailcc i64 @gcAslStackTop() {\n  %p = load ptr, ptr @gcStackTop\n  %i = ptrtoint ptr %p to i64\n  ret i64 %i\n}")
        (pair "declare tailcc i64 @gcAslCallFin(i64, i64)"
              "define internal tailcc i64 @gcAslCallFin(i64 %f, i64 %a) {\n  %fp = inttoptr i64 %f to ptr\n  %ap = inttoptr i64 %a to ptr\n  call void %fp(ptr %ap)\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslFinGuarded(i64, i64, i64)"
              (str "define internal tailcc i64 @gcAslFinGuarded(i64 %f, i64 %a, i64 %g) {\nentry:\n  %jb = alloca [128 x i64], align 16\n"
                   "  %gp = inttoptr i64 %g to ptr\n  %getp = getelementptr inbounds i8, ptr %gp, i64 0\n  %get = load ptr, ptr %getp\n"
                   "  %setp = getelementptr inbounds i8, ptr %gp, i64 8\n  %set = load ptr, ptr %setp\n  %prev = call ptr %get()\n"
                   "  %r = call i32 @setjmp(ptr %jb)\n  %z = icmp eq i32 %r, 0\n  br i1 %z, label %run, label %caught\n"
                   "run:\n  call void %set(ptr %jb)\n  %fp = inttoptr i64 %f to ptr\n  %ap = inttoptr i64 %a to ptr\n  call void %fp(ptr %ap)\n"
                   "  call void %set(ptr %prev)\n  ret i64 0\ncaught:\n  call void %set(ptr %prev)\n  ret i64 1\n}"))
        (pair "declare tailcc i64 @gcAslRethrow(i64)"
              "define internal tailcc i64 @gcAslRethrow(i64 %g) {\n  %gp = inttoptr i64 %g to ptr\n  %rp = getelementptr inbounds i8, ptr %gp, i64 16\n  %r = load ptr, ptr %rp\n  call void %r()\n  unreachable\n}")
        (pair "declare tailcc i64 @gcAslSortLarge(i64, i64)"
              "define internal tailcc i64 @gcAslSortLarge(i64 %base, i64 %n) {\n  %bp = inttoptr i64 %base to ptr\n  call void @qsort(ptr %bp, i64 %n, i64 8, ptr @gcAslLargeCmp)\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslCtz(i64)"
              "define internal tailcc i64 @gcAslCtz(i64 %w) {\n  %r = call i64 @llvm.cttz.i64(i64 %w, i1 true)\n  ret i64 %r\n}")
        (pair "declare tailcc i64 @gcAslAtexitStats()"
              "define internal tailcc i64 @gcAslAtexitStats() {\n  %r = call i32 @atexit(ptr @gcAslPrintStatsC)\n  ret i64 0\n}")
        (pair "declare tailcc i64 @gcAslF64Bits(double)"
              "define internal tailcc i64 @gcAslF64Bits(double %d) {\n  %b = bitcast double %d to i64\n  ret i64 %b\n}")
        (pair "declare tailcc double @gcAslBitsF64(i64)"
              "define internal tailcc double @gcAslBitsF64(i64 %b) {\n  %d = bitcast i64 %b to double\n  ret double %d\n}")
        (pair "declare tailcc i64 @gcAslF64ToU64(double)"
              "define internal tailcc i64 @gcAslF64ToU64(double %d) {\n  %u = fptoui double %d to i64\n  ret i64 %u\n}"))

fn helperDefinitionsFor target: target/TargetFacts -> (List (Pair String String))
  (if (target/isWasm32 target)
    (map (fn [(d (Pair String String))] -> (Pair String String)
           (if (= (pairFirst d) "declare tailcc i64 @gcAslState()")
             (pair (pairFirst d) (stringReplace (pairSecond d) "define internal tailcc" "define tailcc"))
             (if (= (pairFirst d) "declare tailcc i64 @gcAslFinGuarded(i64, i64, i64)")
               (pair (pairFirst d) "define internal tailcc i64 @gcAslFinGuarded(i64 %f, i64 %a, i64 %g) {\n  %fp = inttoptr i64 %f to ptr\n  %ap = inttoptr i64 %a to ptr\n  call void %fp(ptr %ap)\n  ret i64 0\n}")
               d)))
         (listAppend (filter (fn [(d (Pair String String))] -> Bool (!= (pairFirst d) "declare tailcc i64 @gcAslAtexitStats()")) (helperDefinitions))
                     (list (pair "declare tailcc i64 @gcAslShadowTop()"
                                 "define internal tailcc i64 @gcAslShadowTop() {\n  %v = load i64, ptr @asl_gc_shadow_top\n  ret i64 %v\n}"))))
    (helperDefinitions))

fn rootPushFn -> ty/SsaFunction
  (fun "rootPush" (list "v")
    (list (blk "entry" (list (state) (sld "n" (sRootCount)) (cmpK "full" "eqInt" "n" (maxRoots))) (br "full" "full" "put"))
          (failB "full" "ERR_INTERNAL" "gc root stack overflow" (list) (list))
          (retZero "put" (list (addK "base" "s" (* 8 (sRoots))) (elem "at" "base" "n" 8) (st "w" "at" 0 "v") (addK "n1" "n" 1) (sst "c" (sRootCount) "n1")))))

fn rootPopFn -> ty/SsaFunction
  (fun "rootPop" (list "n")
    (list (retZero "entry" (list (state) (sld "c" (sRootCount)) (sub "c1" "c" "n") (sst "w" (sRootCount) "c1")))))

fn registerProtoFn c: GcCtx -> ty/SsaFunction
  (fun "registerProto" (list "p")
    (list (blk "entry" (list (state) (sld "n" (sProtoCount)) (sld "cap" (sProtoCap)) (cmp "full" "eqInt" "n" "cap")) (br "full" "grow" "put"))
          (blk "grow" (list (cmpK "z" "eqInt" "cap" 0) (k "first" 64) (mulK "twice" "cap" 2)) (brA "z" "sized" (list "first") "sized" (list "twice")))
          (blkp "sized" (list "nc") (list (mulK "bytes" "nc" 8) (sld "old" (sProtos)) (i2p "oldp" "old") (ex "r" (ptr) "realloc" (list "oldp" "bytes"))
                                         (p2i "ri" "r") (sst "w1" (sProtos) "ri") (sst "w2" (sProtoCap) "nc") (cmpK "dead" "eqInt" "ri" 0))
            (br "dead" "die" "put"))
          (exitB c "die" 70)
          (retZero "put" (list (sld "arr" (sProtos)) (elem "at" "arr" "n" 8) (st "w3" "at" 0 "p") (addK "n1" "n" 1) (sst "w4" (sProtoCount) "n1")))))

fn markObjFn -> ty/SsaFunction
  (fun "markObj" (list "o")
    (list (blk "entry" (list (state) (ld "h" "o" 0) (byteAtK "mark" "h" 40) (byteAtK "perm" "h" 48) (bor "mp" "mark" "perm") (cmpK "skip" "neInt" "mp" 0))
            (br "skip" "done" "set"))
          (blk "set" (list (st8K "m" "o" 5 1) (shrK "cls" "h" 56) (cmpK "pooled" "neInt" "cls" (largeClass))) (br "pooled" "page" "push"))
          (blk "page" (list (bandK "pg" "o" (- 0 (pageSize))) (ld "mc" "pg" 48) (addK "mc1" "mc" 1) (st "w" "pg" 48 "mc1")) (jmp "push" (list)))
          (blk "push" (list (sld "sp" (sMarkSp)) (sld "cap" (sMarkCap)) (cmp "full" "eqInt" "sp" "cap")) (br "full" "grow" "put"))
          (blk "grow" (list (cl "g" "growMark" (list "cap"))) (jmp "put" (list)))
          (retZero "put" (list (sld "stk" (sMarkStack)) (elem "at" "stk" "sp" 8) (st "w3" "at" 0 "o") (addK "sp1" "sp" 1) (sst "w4" (sMarkSp) "sp1")))
          (retZero "done" (list))))

fn growMarkFn c: GcCtx -> ty/SsaFunction
  (fun "growMark" (list "cap")
    (list (blk "entry" (list (state) (cmpK "z" "eqInt" "cap" 0) (k "first" 1024) (mulK "twice" "cap" 2)) (brA "z" "sized" (list "first") "sized" (list "twice")))
          (blkp "sized" (list "nc") (list (mulK "bytes" "nc" 8) (sld "old" (sMarkStack)) (i2p "oldp" "old") (ex "r" (ptr) "realloc" (list "oldp" "bytes"))
                                         (p2i "ri" "r") (sst "w1" (sMarkStack) "ri") (sst "w2" (sMarkCap) "nc") (cmpK "dead" "eqInt" "ri" 0))
            (br "dead" "die" "done"))
          (exitB c "die" 70)
          (blk "done" (list) (ret "ri"))))

fn markValFn -> ty/SsaFunction
  (fun "markVal" (list "tag" "obj")
    (list (blk "entry" (list (hasObj "has" "tag" "obj")) (br "has" "mark" "done"))
          (retZero "mark" (list (cl "r" "markObj" (list "obj"))))
          (retZero "done" (list))))

fn typeChain prefix: String ty: String cases: (List (Pair Int64 String)) dflt: String -> (List ty/SsaBlock)
  (let [(n (listLength cases))]
    (map (fn [(i Int64)] -> ty/SsaBlock
           (let [(c (optionOr (listGet cases i) (pair 0 dflt)))
                 (here (str prefix (stringFromInt64 i)))
                 (next (if (= i (- n 1)) dflt (str prefix (stringFromInt64 (+ i 1)))))]
             (blk here (list (cmpK (str here ".eq") "eqInt" ty (pairFirst c))) (br (str here ".eq") (pairSecond c) next))))
         (range 0 n)))

fn objCases -> (List (Pair Int64 String))
  (list (pair 1 "cons") (pair 2 "rec") (pair 3 "ctor") (pair 4 "clo"))

fn drainFn -> ty/SsaFunction
  (fun "drain" (list)
    (listAppend
      (list (blk "entry" (list (state) (sld "sp0" (sMarkSp)) (sld "stk0" (sMarkStack)) (sld "cap0" (sMarkCap))) (jmp "loop" (list "sp0" "stk0" "cap0")))
            (blkp "loop" (list "sp" "stk" "cap") (list (cmpK "empty" "eqInt" "sp" 0)) (br "empty" "done" "pop"))
            (blk "pop" (list (addK "sp1" "sp" -1) (elem "at" "stk" "sp1" 8) (ld "o" "at" 0) (ld "h" "o" 0) (byteAtK "type" "h" 32) (k "z0" 0))
              (jmp "t0" (list)))
            (blk "cons" (list (addK "cb" "o" 8) (k "cn" 2)) (jmp "kids" (list "cb" "cn" "z0" "sp1" "stk" "cap")))
            (blk "rec" (list (ldS32 "rn" "o" 12) (addK "rb" "o" 24)) (jmp "kids" (list "rb" "rn" "z0" "sp1" "stk" "cap")))
            (blk "ctor" (list (ldS32 "fn" "o" 12) (addK "fb" "o" 16)) (jmp "kids" (list "fb" "fn" "z0" "sp1" "stk" "cap")))
            (blk "clo" (list (ldS32 "un" "o" 16) (addK "ub" "o" 24)) (jmp "kids" (list "ub" "un" "z0" "sp1" "stk" "cap")))
            (blk "leaf" (list) (jmp "loop" (list "sp1" "stk" "cap")))
            (blkp "kids" (list "base" "n" "i" "ksp" "kstk" "kcap") (list (cmp "more" "ltInt" "i" "n")) (brA "more" "kid" (list) "loop" (list "ksp" "kstk" "kcap")))
            (blk "kid" (list (elem "a" "base" "i" 16) (ldU32 "tag" "a" 0) (ld "obj" "a" 8) (addK "i1" "i" 1) (hasObj "has" "tag" "obj"))
              (brA "has" "test" (list) "kids" (list "base" "n" "i1" "ksp" "kstk" "kcap")))
            (blk "test" (list (ld "oh" "obj" 0) (byteAtK "mark" "oh" 40) (byteAtK "perm" "oh" 48) (bor "mp" "mark" "perm") (cmpK "skip" "neInt" "mp" 0))
              (brA "skip" "kids" (list "base" "n" "i1" "ksp" "kstk" "kcap") "set" (list)))
            (blk "set" (list (st8K "m" "obj" 5 1) (shrK "cls" "oh" 56) (cmpK "pooled" "neInt" "cls" (largeClass))) (br "pooled" "page" "push"))
            (blk "page" (list (bandK "pg" "obj" (- 0 (pageSize))) (ld "mc" "pg" 48) (addK "mc1" "mc" 1) (st "w" "pg" 48 "mc1")) (jmp "push" (list)))
            (blk "push" (list (cmp "full" "eqInt" "ksp" "kcap")) (brA "full" "grow" (list) "put" (list "kstk" "kcap")))
            (blk "grow" (list (sst "gw" (sMarkSp) "ksp") (cl "nstk" "growMark" (list "kcap")) (sld "ncap" (sMarkCap))) (jmp "put" (list "nstk" "ncap")))
            (blkp "put" (list "pstk" "pcap") (list (elem "pat" "pstk" "ksp" 8) (st "pw" "pat" 0 "obj") (addK "ksp1" "ksp" 1))
              (jmp "kids" (list "base" "n" "i1" "ksp1" "pstk" "pcap")))
            (retZero "done" (list (sst "dw" (sMarkSp) "sp"))))
      (typeChain "t" "type" (objCases) "leaf")))

fn markRootFn -> ty/SsaFunction
  (fun "markRoot" (list "w0" "w1")
    (list (retZero "entry" (list (bandK "tag" "w0" 4294967295) (cl "m" "markVal" (list "tag" "w1")) (cl "d" "drain" (list))))))

fn markValAt d: String a: String -> (List ty/SsaInstr)
  (appendAll (list (ldU32 (str d ".t") a 0) (ld (str d ".o") a 8) (cl (str d ".m") "markVal" (list (str d ".t") (str d ".o"))) (cl (str d ".d") "drain" (list))))

fn shadowFrameBlocks next: String -> (List ty/SsaBlock)
  (list (blk "frames" (list (ex "ftop" (i64) "gcAslShadowTop" (list))) (jmp "floop" (list "ftop")))
        (blkp "floop" (list "fp") (list (cmpK "fmore" "neInt" "fp" 0)) (br "fmore" "fbody" next))
        (blk "fbody" (list (ld "fcount" "fp" 8) (addK "fbase" "fp" 16) (k "fi0" 0)) (jmp "fsloop" (list "fi0")))
        (blkp "fsloop" (list "fi") (list (cmp "fsmore" "ltInt" "fi" "fcount")) (br "fsmore" "fsbody" "fnext"))
        (blk "fsbody" (list (elem "fat" "fbase" "fi" 16) (markValAt "fm" "fat") (addK "fi1" "fi" 1)) (jmp "fsloop" (list "fi1")))
        (blk "fnext" (list (ld "fprev" "fp" 0)) (jmp "floop" (list "fprev"))))

fn markPhaseFn c: GcCtx -> ty/SsaFunction
  (fun "markPhase" (list)
    (appendAll
      (list (list (blk "entry"
                       (appendAll (list (list (state) (sstK "c1" (sCollecting) 1) (ex "mr" (i64) "gcAslMutatorRoots" (list)) (ex "er" (i64) "gcAslExternalRoots" (list)))
                                         (if (target/growsLinearMemory c.target) (list)
                                           (list (ex "base" (i64) "gcAslStackBase" (list)) (ex "topp" (i64) "gcAslStackTop" (list))
                                                 (cmpK "bz" "eqInt" "base" 0) (cmpK "tz" "eqInt" "topp" 0) (orB "skip" "bz" "tz")))))
                       (if (target/growsLinearMemory c.target) (jmp (if (wasm? c) "frames" "roots") (list)) (brA "skip" "roots" (list) "sloop" (list "base")))))
            (if (target/growsLinearMemory c.target) (list)
              (list (blkp "sloop" (list "p") (list (ld "top" "topp" 0) (ult "more" "p" "top")) (br "more" "sbody" "roots"))
                    (blk "sbody" (list (markValAt "sv" "p") (addK "p1" "p" 16)) (jmp "sloop" (list "p1")))))
            (if (wasm? c) (shadowFrameBlocks "roots") (list))
            (list
          (blk "roots" (list (k "r0" 0)) (jmp "rloop" (list "r0")))
          (blkp "rloop" (list "ri") (list (sld "rn" (sRootCount)) (cmp "rmore" "ltInt" "ri" "rn")) (br "rmore" "rbody" "protos"))
          (blk "rbody" (list (addK "rbase" "s" (* 8 (sRoots))) (elem "rat" "rbase" "ri" 8) (ld "rv" "rat" 0) (markValAt "rm" "rv") (addK "ri1" "ri" 1)) (jmp "rloop" (list "ri1")))
          (blk "protos" (list (k "p0" 0)) (jmp "ploop" (list "p0")))
          (blkp "ploop" (list "pi") (list (sld "pn" (sProtoCount)) (cmp "pmore" "ltInt" "pi" "pn")) (br "pmore" "pbody" "done"))
          (blk "pbody" (list (sld "parr" (sProtos)) (elem "pat" "parr" "pi" 8) (ld "proto" "pat" 0) (ldS32 "nk" "proto" 48) (ld "consts" "proto" 40) (k "k0" 0))
            (jmp "kloop" (list "k0")))
          (blkp "kloop" (list "ki") (list (cmp "kmore" "ltInt" "ki" "nk")) (br "kmore" "kbody" "pnext"))
          (blk "kbody" (list (elem "kat" "consts" "ki" 16) (markValAt "km" "kat") (addK "ki1" "ki" 1)) (jmp "kloop" (list "ki1")))
          (blk "pnext" (list (addK "pi1" "pi" 1)) (jmp "ploop" (list "pi1")))
          (retZero "done" (list (sstK "c0" (sCollecting) 0)))))))

fn poolScanFn -> ty/SsaFunction
  (fun "poolScan" (list "mode")
    (list (blk "entry" (list (state) (cmpK "clear" "eqInt" "mode" 1) (k "sc0" 0)) (jmp "cloop" (list "sc0")))
          (blkp "cloop" (list "sc") (list (cmpK "cmore" "ltInt" "sc" (numClasses))) (br "cmore" "cbody" "done"))
          (blk "cbody" (list (classAddr "ca" "sc") (ld "p0" "ca" 0)) (jmp "ploop" (list "p0")))
          (blkp "ploop" (list "p") (list (cmpK "pz" "eqInt" "p" 0)) (br "pz" "cnext" "pbody"))
          (blk "pbody" (list) (br "clear" "preset" "pwords"))
          (blk "preset" (list (stK "mc" "p" 48 0)) (jmp "pwords" (list)))
          (blk "pwords" (list (ld "cnt" "p" 32) (addK "cnt63" "cnt" 63) (shrK "nw" "cnt63" 6) (k "kk0" 0)) (jmp "wloop" (list "kk0")))
          (blkp "wloop" (list "kk") (list (cmp "wmore" "ltInt" "kk" "nw")) (br "wmore" "wbody" "pnext"))
          (blk "wbody" (list (addK "wbase" "p" 72) (elem "wat" "wbase" "kk" 8) (ld "w0" "wat" 0)) (jmp "bloop" (list "w0")))
          (blkp "bloop" (list "w") (list (cmpK "wz" "eqInt" "w" 0)) (br "wz" "wnext" "bbody"))
          (blk "bbody" (list (ex "t" (i64) "gcAslCtz" (list "w")) (shlK "kb" "kk" 6) (add "idx" "kb" "t") (ld "ss" "p" 24) (mul "off" "idx" "ss")
                             (addK "first" "p" (pageHeader)) (add "o" "first" "off"))
            (br "clear" "bclear" "bverify"))
          (blk "bclear" (list (st8K "m" "o" 5 0)) (jmp "bstep" (list)))
          (blk "bverify" (list (cl "v" "verifyDfs" (list "o"))) (jmp "bstep" (list)))
          (blk "bstep" (list (addK "wm1" "w" -1) (band "w1" "w" "wm1")) (jmp "bloop" (list "w1")))
          (blk "wnext" (list (addK "kk1" "kk" 1)) (jmp "wloop" (list "kk1")))
          (blk "pnext" (list (ld "nx" "p" 0)) (jmp "ploop" (list "nx")))
          (blk "cnext" (list (addK "sc1" "sc" 1)) (jmp "cloop" (list "sc1")))
          (retZero "done" (list))))

fn clearMarksFn -> ty/SsaFunction
  (fun "clearMarks" (list)
    (list (blk "entry" (list (state) (sld "l0" (sLargeObjects))) (jmp "loop" (list "l0")))
          (blkp "loop" (list "lo") (list (cmpK "z" "eqInt" "lo" 0)) (br "z" "pooled" "body"))
          (blk "body" (list (st8K "m" "lo" 29 0) (ld "nx" "lo" 0)) (jmp "loop" (list "nx")))
          (retZero "pooled" (list (k "one" 1) (cl "r" "poolScan" (list "one"))))))

fn abortMarkFn -> ty/SsaFunction
  (fun "abortMark" (list)
    (list (retZero "entry" (list (state) (sstK "c" (sCollecting) 0) (sstK "sp" (sMarkSp) 0) (cl "r" "clearMarks" (list))))))

fn numChildrenFn -> ty/SsaFunction
  (fun "numChildren" (list "o")
    (listAppend
      (list (blk "entry" (list (ld "h" "o" 0) (byteAtK "type" "h" 32)) (jmp "t0" (list)))
            (blk "cons" (list (k "cn" 2)) (ret "cn"))
            (blk "rec" (list (ldS32 "rn" "o" 12)) (ret "rn"))
            (blk "ctor" (list (ldS32 "fn" "o" 12)) (ret "fn"))
            (blk "clo" (list (ldS32 "un" "o" 16)) (ret "un"))
            (retZero "leaf" (list)))
      (typeChain "t" "type" (objCases) "leaf")))

fn childAddrFn -> ty/SsaFunction
  (fun "childAddr" (list "o" "idx")
    (listAppend
      (list (blk "entry" (list (ld "h" "o" 0) (byteAtK "type" "h" 32)) (jmp "t0" (list)))
            (blk "cons" (list (cmpK "car" "eqInt" "idx" 0) (addK "ca" "o" 8) (addK "cd" "o" 24)) (brA "car" "out" (list "ca") "out" (list "cd")))
            (blk "rec" (list (addK "rb" "o" 24) (elem "ra" "rb" "idx" 16)) (jmp "out" (list "ra")))
            (blk "ctor" (list (addK "fb" "o" 16) (elem "fa" "fb" "idx" 16)) (jmp "out" (list "fa")))
            (blk "clo" (list (addK "ub" "o" 24) (elem "ua" "ub" "idx" 16)) (jmp "out" (list "ua")))
            (blkp "out" (list "a") (list) (ret "a"))
            (retZero "leaf" (list)))
      (typeChain "t" "type" (objCases) "leaf")))

fn typeNameFn -> ty/SsaFunction
  (let [(names (list (pair 1 ":cons") (pair 2 ":record") (pair 3 ":ctor") (pair 4 ":closure") (pair 0 ":string") (pair 5 ":bytes") (pair 6 ":array") (pair 7 ":handle")))]
    (fun "typeName" (list "type")
      (listAppend
        (listAppend
          (list (blk "entry" (list) (jmp "t0" (list)))
                (blk "other" (list (cs "u" ":unknown") (p2i "ui" "u")) (ret "ui")))
          (map (fn [(p (Pair Int64 String))] -> ty/SsaBlock
                 (let [(l (str "n" (stringFromInt64 (pairFirst p))))]
                   (blk l (list (cs (str l ".s") (pairSecond p)) (p2i (str l ".i") (str l ".s"))) (ret (str l ".i")))))
               names))
        (typeChain "t" "type" (map (fn [(p (Pair Int64 String))] -> (Pair Int64 String) (pair (pairFirst p) (str "n" (stringFromInt64 (pairFirst p))))) names) "other"))))

fn verifyDfsFn c: GcCtx -> ty/SsaFunction
  (fun "verifyDfs" (list "start")
    (list (blk "entry" (list (state) (ld "h0" "start" 0) (byteAtK "m0" "h0" 40) (cmpK "seen" "neInt" "m0" 0)) (br "seen" "done" "init"))
          (blk "init" (list (sstK "sp0" (sDfsSp) 0) (sld "cap0" (sDfsCap)) (ultK "small" "cap0" 1024)) (br "small" "alloc0" "seed"))
          (blk "alloc0" (list (k "cap1" 1024) (sst "wc" (sDfsCap) "cap1") (k "nb" (* 1024 (frameBytes))) (sld "old" (sDfsStack)) (i2p "oldp" "old")
                              (ex "r0" (ptr) "realloc" (list "oldp" "nb")) (p2i "r0i" "r0") (sst "ws" (sDfsStack) "r0i") (cmpK "dead0" "eqInt" "r0i" 0))
            (br "dead0" "oom" "seed"))
          (retZero "oom" (list (k32 "fd" 2) (cs "msg" "ERR_OOM\n") (ex "pr" (i32) "dprintf" (list "fd" "msg")) (k32 "code" 70) (ex "ex" (i64) (exitName c) (list "code"))))
          (blk "seed" (list (st8K "g0" "start" 5 1) (cl "nc0" "numChildren" (list "start")) (sld "stk0" (sDfsStack)) (sld "sps" (sDfsSp)) (elem "f0" "stk0" "sps" (frameBytes))
                            (st "f0o" "f0" 0 "start") (stK "f0i" "f0" 8 0) (st "f0n" "f0" 16 "nc0") (addK "sps1" "sps" 1) (sst "wsp" (sDfsSp) "sps1"))
            (jmp "loop" (list)))
          (blk "loop" (list (sld "sp" (sDfsSp)) (cmpK "empty" "eqInt" "sp" 0)) (br "empty" "done" "top"))
          (blk "top" (list (sld "stk" (sDfsStack)) (addK "spm1" "sp" -1) (elem "f" "stk" "spm1" (frameBytes)) (ld "o" "f" 0) (ld "ci" "f" 8) (ld "nc" "f" 16)
                           (cmp "has" "ltInt" "ci" "nc"))
            (br "has" "child" "pop"))
          (blk "pop" (list (st8K "b" "o" 5 2) (sst "wpop" (sDfsSp) "spm1")) (jmp "loop" (list)))
          (blk "child" (list (cl "ca" "childAddr" (list "o" "ci")) (addK "ci1" "ci" 1) (st "wci" "f" 8 "ci1") (ldU32 "tag" "ca" 0) (ld "obj" "ca" 8) (hasObj "isObj" "tag" "obj"))
            (br "isObj" "cobj" "loop"))
          (blk "cobj" (list (ld "ch" "obj" 0) (byteAtK "cperm" "ch" 48) (cmpK "cp" "neInt" "cperm" 0)) (br "cp" "loop" "cmark"))
          (blk "cmark" (list (byteAtK "cm" "ch" 40) (cmpK "grey" "eqInt" "cm" 1)) (br "grey" "cycle" "cwhite"))
          (blk "cwhite" (list (cmpK "white" "eqInt" "cm" 0)) (br "white" "cpush" "loop"))
          (blk "cpush" (list (sld "sp2" (sDfsSp)) (sld "cap2" (sDfsCap)) (cmp "full" "eqInt" "sp2" "cap2")) (br "full" "cgrow" "cput"))
          (blk "cgrow" (list (k "lim" 1048576) (ule "atLim" "lim" "cap2")) (br "atLim" "limit" "cgrow2"))
          (failB "limit" "ERR_LIMIT" "heap verification stack depth limit exceeded" (list) (list))
          (blk "cgrow2" (list (mulK "cap3" "cap2" 2) (sst "wc3" (sDfsCap) "cap3") (mulK "nb3" "cap3" (frameBytes)) (sld "old3" (sDfsStack)) (i2p "old3p" "old3")
                              (ex "r3" (ptr) "realloc" (list "old3p" "nb3")) (p2i "r3i" "r3") (sst "ws3" (sDfsStack) "r3i") (cmpK "dead3" "eqInt" "r3i" 0))
            (br "dead3" "oom" "cput"))
          (blk "cput" (list (st8K "g1" "obj" 5 1) (cl "ncc" "numChildren" (list "obj")) (sld "stk4" (sDfsStack)) (sld "sp4" (sDfsSp)) (elem "f4" "stk4" "sp4" (frameBytes))
                            (st "f4o" "f4" 0 "obj") (stK "f4i" "f4" 8 0) (st "f4n" "f4" 16 "ncc") (addK "sp41" "sp4" 1) (sst "wsp4" (sDfsSp) "sp41"))
            (jmp "loop" (list)))
          (blk "cycle" (list) (jmp "dloop" (list "spm1")))
          (blkp "dloop" (list "di") (list (cmpK "dneg" "ltInt" "di" 0) (k "d1" 1)) (brA "dneg" "report" (list "d1") "dbody" (list)))
          (blk "dbody" (list (elem "dat" "stk" "di" (frameBytes)) (ld "dobj" "dat" 0) (cmp "deq" "eqInt" "dobj" "obj")) (br "deq" "found" "dnext"))
          (blk "found" (list (sub "dd" "sp" "di")) (jmp "report" (list "dd")))
          (blk "dnext" (list (addK "di1" "di" -1)) (jmp "dloop" (list "di1")))
          (blkp "report" (list "depth") (list (byteAtK "ctype" "ch" 32) (cl "tni" "typeName" (list "ctype")) (i2p "tn" "tni") (n32 "d32" "depth") (k32 "efd" 2)
                                              (cs "cyc" "(:gcCycle :type %s :depth %d)\n") (ex "pc" (i32) "dprintf" (list "efd" "cyc" "tn" "d32")))
            (jmp "raise" (list)))
          (failB "raise" "ERR_HEAP_CYCLE" "cycle of depth %d detected in %s" (list) (list "d32" "tn"))
          (retZero "done" (list))))

fn verifyHeapFn -> ty/SsaFunction
  (fun "verifyHeap" (list)
    (list (blk "entry" (list (state) (sld "l0" (sLargeObjects))) (jmp "loop" (list "l0")))
          (blkp "loop" (list "lo") (list (cmpK "z" "eqInt" "lo" 0)) (br "z" "pooled" "body"))
          (blk "body" (list (addK "o" "lo" 24) (cl "v" "verifyDfs" (list "o")) (ld "nx" "lo" 0)) (jmp "loop" (list "nx")))
          (retZero "pooled" (list (k "zero" 0) (cl "r" "poolScan" (list "zero")) (cl "c" "clearMarks" (list))))))

fn pageSlotFn -> ty/SsaFunction
  (fun "pageSlot" (list "base" "cap")
    (list (blk "entry" (list (shrK "b" "base" 14) (mulK "h" "b" -7046029254386353131) (shrK "h20" "h" 20) (addK "m" "cap" -1) (band "i" "h20" "m")) (ret "i"))))

fn pageSetPutFn -> ty/SsaFunction
  (fun "pageSetPut" (list "p")
    (list (blk "entry" (list (state) (sld "cap" (sPageSetCap)) (sld "set" (sPageSet)) (addK "m" "cap" -1) (cl "i0" "pageSlot" (list "p" "cap"))) (jmp "loop" (list "i0")))
          (blkp "loop" (list "i") (list (elem "a" "set" "i" 8) (ld "e" "a" 0) (cmpK "empty" "eqInt" "e" 0)) (br "empty" "put" "check"))
          (blk "check" (list (cmp "same" "eqInt" "e" "p")) (br "same" "done" "next"))
          (blk "next" (list (addK "i1" "i" 1) (band "i2" "i1" "m")) (jmp "loop" (list "i2")))
          (retZero "put" (list (st "w" "a" 0 "p") (sincK "cnt" (sPageSetCount) 1)))
          (retZero "done" (list))))

fn pageSetReserveFn c: GcCtx -> ty/SsaFunction
  (fun "pageSetReserve" (list)
    (list (blk "entry" (list (state) (sld "cnt" (sPageSetCount)) (sld "cap" (sPageSetCap)) (addK "c1" "cnt" 1) (mulK "need" "c1" 2) (ule "fits" "need" "cap"))
            (br "fits" "done" "grow"))
          (blk "grow" (list (cmpK "z" "eqInt" "cap" 0) (k "first" 256) (mulK "twice" "cap" 2)) (brA "z" "sized" (list "first") "sized" (list "twice")))
          (blkp "sized" (list "nc") (list (sld "fail" (sFailNextGrow)) (sstK "wf" (sFailNextGrow) 0) (cmpK "forced" "neInt" "fail" 0)) (br "forced" "oom" "alloc"))
          (blk "alloc" (list (k "eight" 8) (ex "r" (ptr) "calloc" (list "nc" "eight")) (p2i "ri" "r") (cmpK "dead" "eqInt" "ri" 0)) (br "dead" "oom" "rehash"))
          (failB "oom" "ERR_OOM" "out of memory growing the GC page set to %zu entries" (list) (list "nc"))
          (blk "rehash" (list (sld "old" (sPageSet)) (sst "w1" (sPageSet) "ri") (sst "w2" (sPageSetCap) "nc") (sstK "w3" (sPageSetCount) 0) (k "i0" 0)) (jmp "hloop" (list "i0")))
          (blkp "hloop" (list "i") (list (cmp "more" "ltInt" "i" "cap")) (br "more" "hbody" "release"))
          (blk "hbody" (list (elem "at" "old" "i" 8) (ld "e" "at" 0) (cmpK "ez" "eqInt" "e" 0)) (br "ez" "hnext" "hput"))
          (blk "hput" (list (cl "pp" "pageSetPut" (list "e"))) (jmp "hnext" (list)))
          (blk "hnext" (list (addK "i1" "i" 1)) (jmp "hloop" (list "i1")))
          (retZero "release" (list (i2p "oldp" "old") (ex "fr" (i64) (freeName c) (list "oldp"))))
          (retZero "done" (list))))

fn pageSetGetFn -> ty/SsaFunction
  (fun "pageSetGet" (list "base")
    (list (blk "entry" (list (state) (sld "cap" (sPageSetCap)) (cmpK "z" "eqInt" "cap" 0)) (br "z" "none" "start"))
          (blk "start" (list (sld "set" (sPageSet)) (addK "m" "cap" -1) (cl "i0" "pageSlot" (list "base" "cap"))) (jmp "loop" (list "i0")))
          (blkp "loop" (list "i") (list (elem "a" "set" "i" 8) (ld "e" "a" 0) (cmpK "empty" "eqInt" "e" 0)) (br "empty" "none" "check"))
          (blk "check" (list (cmp "hit" "eqInt" "e" "base")) (br "hit" "found" "next"))
          (blk "found" (list) (ret "e"))
          (blk "next" (list (addK "i1" "i" 1) (band "i2" "i1" "m")) (jmp "loop" (list "i2")))
          (retZero "none" (list))))

fn pageSetDelFn -> ty/SsaFunction
  (fun "pageSetDel" (list "p")
    (list (blk "entry" (list (state) (sld "cap" (sPageSetCap)) (cmpK "z" "eqInt" "cap" 0)) (br "z" "empty" "start"))
          (failB "empty" "ERR_INTERNAL" "gc page set is empty on page release" (list) (list))
          (blk "start" (list (sld "set" (sPageSet)) (addK "m" "cap" -1) (cl "i0" "pageSlot" (list "p" "cap"))) (jmp "find" (list "i0")))
          (blkp "find" (list "i") (list (elem "a" "set" "i" 8) (ld "e" "a" 0) (cmp "hit" "eqInt" "e" "p")) (br "hit" "clear" "miss"))
          (blk "miss" (list (cmpK "ez" "eqInt" "e" 0)) (br "ez" "missing" "step"))
          (failB "missing" "ERR_INTERNAL" "gc page %p missing from the page set" (list (i2p "pp" "p")) (list "pp"))
          (blk "step" (list (addK "i1" "i" 1) (band "i2" "i1" "m")) (jmp "find" (list "i2")))
          (blk "clear" (list (stK "w0" "a" 0 0) (sincK "cnt" (sPageSetCount) -1) (addK "j1" "i" 1) (band "j0" "j1" "m")) (jmp "shift" (list "i" "j0")))
          (blkp "shift" (list "hole" "j") (list (elem "ja" "set" "j" 8) (ld "ej" "ja" 0) (cmpK "jz" "eqInt" "ej" 0)) (br "jz" "done" "test"))
          (blk "test" (list (cl "h" "pageSlot" (list "ej" "cap"))
                            (cmp "jgt" "gtInt" "j" "hole") (cmp "hle" "leInt" "h" "hole") (cmp "hgt" "gtInt" "h" "j") (orB "out1" "hle" "hgt") (andB "c1" "jgt" "out1")
                            (cmp "jlt" "ltInt" "j" "hole") (andB "c2a" "jlt" "hle") (andB "c2" "c2a" "hgt") (orB "move" "c1" "c2"))
            (brA "move" "moved" (list) "snext" (list "hole")))
          (blk "moved" (list (elem "ha" "set" "hole" 8) (st "wm" "ha" 0 "ej") (stK "wz" "ja" 0 0)) (jmp "snext" (list "j")))
          (blkp "snext" (list "nh") (list (addK "jn" "j" 1) (band "jn2" "jn" "m")) (jmp "shift" (list "nh" "jn2")))
          (retZero "done" (list))))

fn wasmPageSize -> Int64
  65536

fn unmapFn -> ty/SsaFunction
  (fun "unmap" (list "addr" "len")
    (list (blk "entry" (list (i2p "ap" "addr") (ex "r" (i32) "munmap" (list "ap" "len")) (w64 "r64" "r") (cmpK "bad" "neInt" "r64" 0)) (br "bad" "fail" "done"))
          (failB "fail" "ERR_INTERNAL" "cannot unmap GC memory at %p" (list) (list "ap"))
          (retZero "done" (list))))

fn freshPageFn c: GcCtx -> ty/SsaFunction
  (if (target/growsLinearMemory c.target)
    (freshGrowPageFn)
    (freshMmapPageFn c))

fn freshGrowPageFn -> ty/SsaFunction
  (fun "freshPage" (list)
    (list (blk "entry" (list (state) (sld "nx" (sFreshNext)) (sld "end" (sFreshEnd)) (cmp "have" "ltInt" "nx" "end")) (br "have" "take" "grow"))
          (blk "take" (list (addK "nx1" "nx" (pageSize)) (sst "w" (sFreshNext) "nx1")) (ret "nx"))
          (blk "grow" (list (k32 "mem" 0) (k32 "delta" (/ (* (runPages) (pageSize)) (wasmPageSize))) (ex "old" (i32) "llvm.wasm.memory.grow.i32" (list "mem" "delta"))
                            (w64 "old64" "old") (cmpK "failed" "eqInt" "old64" -1))
            (br "failed" "oom" "use"))
          (failB "oom" "ERR_OOM" "out of memory allocating GC page" (list) (list))
          (blk "use" (list (mulK "base" "old64" (wasmPageSize)) (k "len" (* (runPages) (pageSize))) (addK "b1" "base" (pageSize)) (sst "w1" (sFreshNext) "b1")
                           (add "be" "base" "len") (sst "w2" (sFreshEnd) "be") (sincK "pm" (sPagesMapped) (runPages)))
            (ret "base"))))

fn freshMmapPageFn c: GcCtx -> ty/SsaFunction
  (fun "freshPage" (list)
    (list (blk "entry" (list (state) (sld "nx" (sFreshNext)) (sld "end" (sFreshEnd)) (cmp "have" "ltInt" "nx" "end")) (br "have" "take" "map"))
          (blk "take" (list (addK "nx1" "nx" (pageSize)) (sst "w" (sFreshNext) "nx1")) (ret "nx"))
          (blk "map" (list (k "len" (* (runPages) (pageSize))) (k "zero" 0) (i2p "nul" "zero") (k "pr" (fact c "PROT_READ")) (k "pw" (fact c "PROT_WRITE")) (bor "prot64" "pr" "pw") (n32 "prot" "prot64")
                           (k "mp" (fact c "MAP_PRIVATE")) (k "ma" (fact c "MAP_ANON")) (bor "flags64" "mp" "ma") (n32 "flags" "flags64") (k32 "fd" -1)
                           (ex "r" (ptr) "mmap" (list "nul" "len" "prot" "flags" "fd" "zero")) (p2i "ri" "r") (cmpK "failed" "eqInt" "ri" -1))
            (br "failed" "oom" "mapped"))
          (failB "oom" "ERR_OOM" "out of memory allocating GC page" (list) (list))
          (blk "mapped" (list (bandK "low" "ri" (- (pageSize) 1)) (cmpK "aligned" "eqInt" "low" 0)) (brA "aligned" "use" (list "ri") "remap" (list)))
          (blk "remap" (list (cl "u0" "unmap" (list "ri" "len")) (k "len2" (* (+ (runPages) 1) (pageSize)))
                             (ex "r2" (ptr) "mmap" (list "nul" "len2" "prot" "flags" "fd" "zero")) (p2i "r2i" "r2") (cmpK "failed2" "eqInt" "r2i" -1))
            (br "failed2" "oom" "trim"))
          (blk "trim" (list (addK "up" "r2i" (- (pageSize) 1)) (bandK "a" "up" (- 0 (pageSize))) (sub "head" "a" "r2i") (cmpK "hz" "eqInt" "head" 0)) (br "hz" "cuttail" "cuthead"))
          (blk "cuthead" (list (cl "u1" "unmap" (list "r2i" "head"))) (jmp "cuttail" (list)))
          (blk "cuttail" (list (add "tailAt" "a" "len") (add "mapEnd" "r2i" "len2") (sub "tail" "mapEnd" "tailAt") (cmpK "tz" "eqInt" "tail" 0))
            (brA "tz" "use" (list "a") "cut2" (list)))
          (blk "cut2" (list (cl "u2" "unmap" (list "tailAt" "tail"))) (jmp "use" (list "a")))
          (blkp "use" (list "base") (list (addK "b1" "base" (pageSize)) (sst "w1" (sFreshNext) "b1") (add "be" "base" "len") (sst "w2" (sFreshEnd) "be")
                                          (sincK "pm" (sPagesMapped) (runPages)))
            (ret "base"))))

fn widenHeapFn -> ty/SsaFunction
  (fun "widenHeap" (list "lo" "hi")
    (list (blk "entry" (list (state) (sld "hl" (sHeapLo)) (ult "below" "lo" "hl")) (br "below" "setlo" "high"))
          (blk "setlo" (list (sst "w1" (sHeapLo) "lo")) (jmp "high" (list)))
          (blk "high" (list (sld "hh" (sHeapHi)) (ult "above" "hh" "hi")) (br "above" "sethi" "done"))
          (retZero "sethi" (list (sst "w2" (sHeapHi) "hi")))
          (retZero "done" (list))))

fn newPageFn -> ty/SsaFunction
  (fun "newPage" (list "sc")
    (list (blk "entry" (list (state) (cl "rs" "pageSetReserve" (list)) (sincK "pa" (sPagesAcquired) 1) (sld "cc" (sCachedCount)) (cmpK "has" "gtInt" "cc" 0))
            (br "has" "cached" "fresh"))
          (blk "cached" (list (sld "cp" (sCachedPages)) (ld "cnx" "cp" 0) (sst "w1" (sCachedPages) "cnx") (addK "cc1" "cc" -1) (sst "w2" (sCachedCount) "cc1"))
            (jmp "got" (list "cp")))
          (blk "fresh" (list (cl "fp" "freshPage" (list))) (jmp "got" (list "fp")))
          (blkp "got" (list "p") (list (i2p "pp" "p") (k32 "z32" 0) (k "hb" (pageHeader)) (ex "ms" (ptr) "memset" (list "pp" "z32" "hb"))
                                       (st "wc" "p" 16 "sc") (addK "sc2" "sc" 2) (mulK "ss" "sc2" 8) (st "wss" "p" 24 "ss") (k "room" (- (pageSize) (pageHeader)))
                                       (quot "cnt" "room" "ss") (st "wcnt" "p" 32 "cnt") (stK "wb" "p" 56 (pageHeader)) (cl "put" "pageSetPut" (list "p"))
                                       (addK "pe" "p" (pageSize)) (cl "wh" "widenHeap" (list "p" "pe")))
            (ret "p"))))

fn freePageFn -> ty/SsaFunction
  (fun "freePage" (list "p")
    (list (retZero "entry" (list (state) (cl "d" "pageSetDel" (list "p")) (sincK "pf" (sPagesFreed) 1) (sld "cp" (sCachedPages)) (st "w0" "p" 0 "cp")
                                 (sst "w1" (sCachedPages) "p") (sld "cc" (sCachedCount)) (addK "cc1" "cc" 1) (sst "w2" (sCachedCount) "cc1")))))

fn releaseCacheFn c: GcCtx -> ty/SsaFunction
  (if (target/growsLinearMemory c.target)
    (fun "releaseCache" (list "limit") (list (retZero "entry" (list))))
    (releaseMappedCacheFn))

fn releaseMappedCacheFn -> ty/SsaFunction
  (fun "releaseCache" (list "limit")
    (list (blk "entry" (list (state) (sld "cc" (sCachedCount)) (ult "over" "limit" "cc")) (br "over" "size" "done"))
          (blk "size" (list (sub "n" "cc" "limit") (sld "cap" (sReleaseCap)) (ult "small" "cap" "n")) (br "small" "grow" "fill"))
          (blk "grow" (list (mulK "bytes" "n" 8) (sld "old" (sReleaseBuf)) (i2p "oldp" "old") (ex "r" (ptr) "realloc" (list "oldp" "bytes")) (p2i "ri" "r") (cmpK "dead" "eqInt" "ri" 0))
            (br "dead" "oom" "grown"))
          (failB "oom" "ERR_OOM" "out of memory releasing %zu GC pages" (list) (list "n"))
          (blk "grown" (list (sst "w1" (sReleaseBuf) "ri") (sst "w2" (sReleaseCap) "n")) (jmp "fill" (list)))
          (blk "fill" (list (sld "buf" (sReleaseBuf)) (sld "head" (sCachedPages)) (k "i0" 0)) (jmp "floop" (list "i0" "head")))
          (blkp "floop" (list "i" "p") (list (cmp "more" "ltInt" "i" "n")) (br "more" "fbody" "sort"))
          (blk "fbody" (list (elem "at" "buf" "i" 8) (st "w3" "at" 0 "p") (ld "nx" "p" 0) (addK "i1" "i" 1)) (jmp "floop" (list "i1" "nx")))
          (blk "sort" (list (sst "w4" (sCachedPages) "p") (sst "w5" (sCachedCount) "limit") (ex "q" (i64) "gcAslSortLarge" (list "buf" "n"))
                            (sinc "pu" (sPagesUnmapped) "n") (ld "first" "buf" 0) (k "j0" 1) (k "ps" (pageSize)))
            (jmp "rloop" (list "j0" "first" "ps")))
          (blkp "rloop" (list "j" "start" "len") (list (cmp "rmore" "ltInt" "j" "n")) (br "rmore" "rbody" "last"))
          (blk "rbody" (list (elem "jat" "buf" "j" 8) (ld "pg" "jat" 0) (add "end" "start" "len") (cmp "adjacent" "eqInt" "pg" "end") (addK "j1" "j" 1))
            (br "adjacent" "extend" "cut"))
          (blk "extend" (list (addK "len1" "len" (pageSize))) (jmp "rloop" (list "j1" "start" "len1")))
          (blk "cut" (list (cl "u" "unmap" (list "start" "len")) (sincK "uc" (sUnmapCalls) 1)) (jmp "rloop" (list "j1" "pg" "ps")))
          (retZero "last" (list (cl "ul" "unmap" (list "start" "len")) (sincK "ucl" (sUnmapCalls) 1)))
          (retZero "done" (list))))

fn poolAllocFn -> ty/SsaFunction
  (fun "poolAlloc" (list "sc" "ss")
    (list (blk "entry" (list (state) (classAddr "ca" "sc") (ld "fp" "ca" 8) (cmpK "has" "neInt" "fp" 0)) (br "has" "fromFree" "fromBump"))
          (blk "fromFree" (list (ld "fslot" "fp" 64) (ld "fnx" "fslot" 0) (st "w1" "fp" 64 "fnx") (cmpK "drained" "eqInt" "fnx" 0))
            (brA "drained" "unlink" (list) "have" (list "fp" "fslot")))
          (blk "unlink" (list (ld "nf" "fp" 8) (st "w2" "ca" 8 "nf") (stK "w3" "fp" 8 0)) (jmp "have" (list "fp" "fslot")))
          (blk "fromBump" (list (ld "ap" "ca" 16) (cmpK "noActive" "eqInt" "ap" 0)) (brA "noActive" "fresh" (list) "room" (list)))
          (blk "room" (list (ld "bump" "ap" 56) (add "end" "bump" "ss") (cmpK "over" "gtInt" "end" (pageSize))) (brA "over" "fresh" (list) "bumpIt" (list "ap")))
          (blk "fresh" (list (cl "np" "newPage" (list "sc")) (ld "head" "ca" 0) (st "w4" "np" 0 "head") (st "w5" "ca" 0 "np") (st "w6" "ca" 16 "np")) (jmp "bumpIt" (list "np")))
          (blkp "bumpIt" (list "bp") (list (ld "b" "bp" 56) (add "bslot" "bp" "b") (add "b1" "b" "ss") (st "w7" "bp" 56 "b1")) (jmp "have" (list "bp" "bslot")))
          (blkp "have" (list "hp" "hs") (list (sub "rel" "hs" "hp") (addK "rel2" "rel" (- 0 (pageHeader))) (quot "idx" "rel2" "ss") (shrK "word" "idx" 6) (addK "wbase" "hp" 72)
                                              (elem "wat" "wbase" "word" 8) (bandK "bitn" "idx" 63) (k "one" 1) (shl "bit" "one" "bitn") (ld "wv" "wat" 0) (bor "wv1" "wv" "bit")
                                              (st "w8" "wat" 0 "wv1") (ld "ac" "hp" 40) (addK "ac1" "ac" 1) (st "w9" "hp" 40 "ac1"))
            (ret "hs"))))

fn collectFirst label: String bytes: String next: String -> ty/SsaBlock
  (blk label (list (state) (sld "stress" (sStress)) (sld "al" (sAllocated)) (add "al2" "al" bytes) (sld "th" (sThreshold)) (ult "over" "th" "al2") (cmpK "st1" "neInt" "stress" 0)
                   (orB "need" "st1" "over"))
    (br "need" "collect" next))

fn collectB next: String -> ty/SsaBlock
  (blk "collect" (list (ex "gc" (i64) "gcAslCollect" (list))) (jmp next (list)))

fn countAlloc d: String bytes: String -> (List ty/SsaInstr)
  (appendAll (list (sinc (str d ".a") (sAllocated) bytes) (sincK (str d ".o") (sObjectsAllocated) 1) (sinc (str d ".b") (sBytesAllocated) bytes)))

fn allocFn -> ty/SsaFunction
  (allocSized "alloc" true)

fn allocRawFn -> ty/SsaFunction
  (allocSized "allocRaw" false)

fn allocSized name: String zero: Bool -> ty/SsaFunction
  (fun name (list "type" "bytes")
    (list (blk "entry" (list (k "none" 0)) (jmp "check" (list)))
          (collectFirst "check" "none" "sized")
          (collectB "sized")
          (blk "sized" (list (k "max" (maxSmall)) (ult "big" "max" "bytes") (cmpK "arr" "eqInt" "type" 6) (cmpK "hnd" "eqInt" "type" 7) (orB "o1" "big" "arr") (orB "large" "o1" "hnd"))
            (br "large" "large" "small"))
          (blk "large" (list (cl "lo" "allocLarge" (list "type" "bytes"))) (ret "lo"))
          (blk "small" (list (cmpK "tiny" "ltInt" "bytes" 16) (k "sixteen" 16)) (brA "tiny" "fit" (list "sixteen") "fit" (list "bytes")))
          (blkp "fit" (list "b") (appendAll (list (list (addK "b7" "b" 7) (shrK "b8" "b7" 3) (addK "sc" "b8" -2) (addK "sc2" "sc" 2) (mulK "ss" "sc2" 8) (cl "o" "poolAlloc" (list "sc" "ss")))
                                                  (if zero (list (i2p "op" "o") (k32 "z32" 0) (ex "ms" (ptr) "memset" (list "op" "z32" "ss"))) (list))
                                                  (list (shlK "ty" "type" 32) (shlK "cls" "sc" 56) (bor "h1" "bytes" "ty") (bor "h" "h1" "cls") (st "wh" "o" 0 "h"))
                                                  (list (countAlloc "n" "bytes"))))
            (ret "o"))))

fn largeClassBits -> Int64
  -72057594037927936

fn consHeader -> Int64
  (+ 40 (+ 4294967296 (* 3 72057594037927936)))

fn allocConsFn -> ty/SsaFunction
  (fun "allocCons" (list)
    (list (blk "entry" (list (k "none" 0)) (jmp "check" (list)))
          (collectFirst "check" "none" "go")
          (collectB "go")
          (blk "go" (list (k "sc" 3) (k "ss" 40) (cl "o" "poolAlloc" (list "sc" "ss")) (k "h" (consHeader)) (st "wh" "o" 0 "h") (countAlloc "n" "ss")) (ret "o"))))

fn allocPermFn -> ty/SsaFunction
  (fun "allocPerm" (list "type" "bytes")
    (list (blk "entry" (list (state) (k "one" 1) (ex "r" (ptr) "calloc" (list "one" "bytes")) (p2i "o" "r") (cmpK "dead" "eqInt" "o" 0)) (br "dead" "oom" "init"))
          (failB "oom" "ERR_OOM" "out of memory allocating %zu bytes" (list) (list "bytes"))
          (blk "init" (list (bandK "size" "bytes" 4294967295) (shlK "ty" "type" 32) (k "permBits" (+ 281474976710656 (largeClassBits)))
                            (bor "h1" "size" "ty") (bor "h" "h1" "permBits") (st "wh" "o" 0 "h") (sincK "oa" (sObjectsAllocated) 1) (sinc "ba" (sBytesAllocated) "bytes"))
            (ret "o"))))

fn allocLargeFn -> ty/SsaFunction
  (fun "allocLarge" (list "type" "bytes")
    (list (blk "entry" (list (state) (k "eight" 8) (ult "gt8" "eight" "bytes") (sub "x" "bytes" "eight") (k "zero" 0)) (brA "gt8" "extra" (list "x") "extra" (list "zero")))
          (blkp "extra" (list "ex") (list (addK "total" "ex" 32) (ult "wrapped" "total" "ex")) (br "wrapped" "oomBytes" "index"))
          (blk "index" (list (sld "n" (sLargeCount)) (sld "cap" (sLargeCap)) (cmp "full" "eqInt" "n" "cap")) (br "full" "grow" "alloc"))
          (blk "grow" (list (cmpK "z" "eqInt" "cap" 0) (k "first" 256) (mulK "twice" "cap" 2)) (brA "z" "gsized" (list "first") "gsized" (list "twice")))
          (blkp "gsized" (list "nc") (list (mulK "nb" "nc" 8) (sld "old" (sLargeIndex)) (i2p "oldp" "old") (ex "gr" (ptr) "realloc" (list "oldp" "nb")) (p2i "gri" "gr")
                                           (cmpK "gdead" "eqInt" "gri" 0))
            (br "gdead" "oomIndex" "gset"))
          (failB "oomIndex" "ERR_OOM" "out of memory growing the large object index to %zu entries" (list) (list "nc"))
          (blk "gset" (list (sst "w1" (sLargeIndex) "gri") (sst "w2" (sLargeCap) "nc")) (jmp "alloc" (list)))
          (blk "alloc" (list (k "one" 1) (ex "r" (ptr) "calloc" (list "one" "total")) (p2i "lo" "r") (cmpK "dead" "eqInt" "lo" 0)) (br "dead" "oomBytes" "fill"))
          (failB "oomBytes" "ERR_OOM" "out of memory allocating %zu bytes" (list) (list "bytes"))
          (blk "fill" (list (addK "span" "total" -24) (st "w3" "lo" 16 "span") (cmpK "nz" "neInt" "n" 0)) (br "nz" "cmpLast" "push"))
          (blk "cmpLast" (list (sld "idx0" (sLargeIndex)) (addK "nm1" "n" -1) (elem "lastAt" "idx0" "nm1" 8) (ld "last" "lastAt" 0) (ult "below" "lo" "last"))
            (br "below" "unsorted" "push"))
          (blk "unsorted" (list (sstK "w4" (sLargeSorted) 0)) (jmp "push" (list)))
          (blk "push" (list (sld "idx" (sLargeIndex)) (elem "at" "idx" "n" 8) (st "w5" "at" 0 "lo") (addK "n1" "n" 1) (sst "w6" (sLargeCount) "n1")
                            (add "loEnd" "lo" "total") (cl "wh" "widenHeap" (list "lo" "loEnd")) (st "w7" "lo" 8 "bytes") (k "u32" 4294967295) (ult "huge" "u32" "bytes"))
            (brA "huge" "head" (list "u32") "head" (list "bytes")))
          (blkp "head" (list "size") (list (shlK "ty" "type" 32) (k "cls" (largeClassBits)) (bor "h1" "size" "ty") (bor "h" "h1" "cls") (st "w8" "lo" 24 "h")
                                           (sld "lhead" (sLargeObjects)) (st "w9" "lo" 0 "lhead") (sst "w10" (sLargeObjects) "lo") (countAlloc "c" "bytes") (addK "o" "lo" 24))
            (ret "o"))))

fn accountFn -> ty/SsaFunction
  (fun "account" (list "o" "bytes")
    (list (blk "entry" (list (state) (ld "h" "o" 0) (shrK "cls" "h" 56) (byteAtK "perm" "h" 48) (cmpK "isLarge" "eqInt" "cls" (largeClass)) (cmpK "notPerm" "eqInt" "perm" 0)
                             (andB "owned" "isLarge" "notPerm"))
            (br "owned" "large" "header"))
          (blk "large" (list (addK "lo" "o" -24) (ld "lb" "lo" 8) (add "lb1" "lb" "bytes") (st "w1" "lo" 8 "lb1")) (jmp "header" (list)))
          (retZero "header" (list (add "hs" "h" "bytes") (bandK "low" "hs" 4294967295) (bandK "high" "h" -4294967296) (bor "h1" "high" "low") (st "w2" "o" 0 "h1")
                                  (sinc "a" (sAllocated) "bytes") (sinc "b" (sBytesAllocated) "bytes")))))

fn willAllocateFn -> ty/SsaFunction
  (fun "willAllocate" (list "bytes")
    (list (collectFirst "entry" "bytes" "done")
          (collectB "done")
          (retZero "done" (list))))

fn freedObjectsFn -> ty/SsaFunction
  (fun "freedObjects" (list)
    (list (blk "entry" (list (state) (sld "n" (sObjectsFreed))) (ret "n"))))

fn failNextGrowFn -> ty/SsaFunction
  (fun "failNextGrow" (list)
    (list (retZero "entry" (list (state) (sstK "w" (sFailNextGrow) 1)))))

fn findObjFn -> ty/SsaFunction
  (fun "findObj" (list "w")
    (list (blk "entry" (list (state) (sld "hl" (sHeapLo)) (sld "hh" (sHeapHi)) (ult "below" "w" "hl") (ule "above" "hh" "w") (orB "out" "below" "above")) (br "out" "none" "page"))
          (blk "page" (list (bandK "base" "w" (- 0 (pageSize))) (cl "p" "pageSetGet" (list "base")) (cmpK "pz" "eqInt" "p" 0)) (br "pz" "large" "inPage"))
          (blk "inPage" (list (addK "first" "p" (pageHeader)) (ult "bel" "w" "first")) (br "bel" "none" "slot"))
          (blk "slot" (list (ld "ss" "p" 24) (sub "rel" "w" "first") (quot "idx" "rel" "ss") (ld "cnt" "p" 32) (cmp "oob" "geInt" "idx" "cnt")) (br "oob" "none" "bit"))
          (blk "bit" (list (shrK "word" "idx" 6) (addK "wbase" "p" 72) (elem "wat" "wbase" "word" 8) (ld "wv" "wat" 0) (bandK "bn" "idx" 63) (shr "sh" "wv" "bn") (bandK "b" "sh" 1)
                           (cmpK "clear" "eqInt" "b" 0))
            (br "clear" "none" "hit"))
          (blk "hit" (list (mul "off" "idx" "ss") (add "o" "first" "off")) (ret "o"))
          (blk "large" (list (sld "n" (sLargeCount)) (cmpK "nz" "eqInt" "n" 0)) (br "nz" "none" "sorted"))
          (blk "sorted" (list (sld "srt" (sLargeSorted)) (cmpK "unsorted" "eqInt" "srt" 0)) (br "unsorted" "sort" "search"))
          (blk "sort" (list (sld "ix" (sLargeIndex)) (ex "q" (i64) "gcAslSortLarge" (list "ix" "n")) (sstK "w1" (sLargeSorted) 1)) (jmp "search" (list)))
          (blk "search" (list (sld "idxs" (sLargeIndex)) (k "l0" 0)) (jmp "bs" (list "l0" "n")))
          (blkp "bs" (list "l" "h") (list (cmp "more" "ltInt" "l" "h")) (br "more" "bsBody" "bsDone"))
          (blk "bsBody" (list (sub "span" "h" "l") (shrK "half" "span" 1) (add "mid" "l" "half") (elem "mat" "idxs" "mid" 8) (ld "e" "mat" 0) (ule "le" "e" "w") (addK "mid1" "mid" 1))
            (brA "le" "bs" (list "mid1" "h") "bs" (list "l" "mid")))
          (blk "bsDone" (list (cmpK "lz" "eqInt" "l" 0)) (br "lz" "none" "pick"))
          (blk "pick" (list (addK "lm1" "l" -1) (elem "pat" "idxs" "lm1" 8) (ld "lob" "pat" 0) (addK "start" "lob" 24) (ule "ge" "start" "w")) (br "ge" "spanCheck" "none"))
          (blk "spanCheck" (list (sub "d" "w" "start") (ld "lspan" "lob" 16) (ult "inside" "d" "lspan")) (br "inside" "retStart" "none"))
          (blk "retStart" (list) (ret "start"))
          (retZero "none" (list))))

fn scanConservativeFn -> ty/SsaFunction
  (fun "scanConservative" (list "lo" "hi")
    (list (blk "entry" (list (state) (sld "c" (sCollecting)) (cmpK "idle" "eqInt" "c" 0)) (br "idle" "idle" "range"))
          (failB "idle" "ERR_INTERNAL" "gcScanConservative outside a collection" (list) (list))
          (blk "range" (list (ult "inv" "hi" "lo")) (br "inv" "inverted" "scan"))
          (failB "inverted" "ERR_INTERNAL" "gcScanConservative range %p..%p is inverted" (list (i2p "lop" "lo") (i2p "hip" "hi")) (list "lop" "hip"))
          (blk "scan" (list (addK "lo7" "lo" 7) (bandK "a0" "lo7" -8)) (jmp "loop" (list "a0")))
          (blkp "loop" (list "a") (list (addK "end" "a" 8) (ule "fits" "end" "hi")) (br "fits" "body" "done"))
          (blk "body" (list (ld "w" "a" 0) (cl "o" "findObj" (list "w")) (cmpK "oz" "eqInt" "o" 0)) (br "oz" "next" "mark"))
          (blk "mark" (list (cl "m" "markObj" (list "o")) (cl "d" "drain" (list))) (jmp "next" (list)))
          (blk "next" (list (addK "a1" "a" 8)) (jmp "loop" (list "a1")))
          (retZero "done" (list))))

fn monoNsFn c: GcCtx -> ty/SsaFunction
  (if (wasm? c)
    (fun "monoNs" (list) (list (blk "entry" (list (ex "t" (i64) (clockName) (list))) (ret "t"))))
    (fun "monoNs" (list)
    (list (blk "entry" (list (state) (addK "ts" "s" (* 8 (sTimespec))) (i2p "tsp" "ts") (k32 "clk" (fact c "CLOCK_MONOTONIC")) (ex "r" (i32) "clock_gettime" (list "clk" "tsp"))
                             (ld "sec" "ts" (fact c "timespec.tv_sec")) (ld "nsec" "ts" (fact c "timespec.tv_nsec")) (mulK "sns" "sec" 1000000000) (add "t" "sns" "nsec"))
            (ret "t")))))

fn beginFn -> ty/SsaFunction
  (fun "begin" (list)
    (list (blk "entry" (list (state) (sld "on" (sStats)) (sincK "c" (sCollections) 1) (cmpK "timed" "neInt" "on" 0)) (br "timed" "timed" "untimed"))
          (blk "timed" (list (cl "t" "monoNs" (list))) (ret "t"))
          (retZero "untimed" (list))))

fn stampFn -> ty/SsaFunction
  (fun "stamp" (list "slot" "since")
    (list (blk "entry" (list (state) (sld "on" (sStats)) (cmpK "timed" "neInt" "on" 0)) (br "timed" "timed" "off"))
          (blk "timed" (list (cl "now" "monoNs" (list)) (sub "dt" "now" "since") (mulK "off" "slot" 8) (add "at" "s" "off") (ld "old" "at" 0) (add "new" "old" "dt")
                             (st "w" "at" 0 "new"))
            (ret "now"))
          (retZero "off" (list))))

fn sweepLargeFn c: GcCtx -> ty/SsaFunction
  (fun "sweepLarge" (list "guard" "fe")
    (list (blk "entry" (list (state) (sld "n" (sLargeCount)) (sld "idx" (sLargeIndex)) (k "z0" 0)) (jmp "cloop" (list "z0" "z0")))
          (blkp "cloop" (list "i" "kept") (list (cmp "cmore" "ltInt" "i" "n")) (br "cmore" "cbody" "cdone"))
          (blk "cbody" (list (elem "ia" "idx" "i" 8) (ld "l" "ia" 0) (ld8 "lm" "l" 29) (cmpK "lmarked" "neInt" "lm" 0)) (brA "lmarked" "keep" (list) "cnext" (list "kept")))
          (blk "keep" (list (elem "ka" "idx" "kept" 8) (st "wk" "ka" 0 "l") (addK "kept1" "kept" 1)) (jmp "cnext" (list "kept1")))
          (blkp "cnext" (list "kn") (list (addK "i1" "i" 1)) (jmp "cloop" (list "i1" "kn")))
          (blk "cdone" (list (sst "wn" (sLargeCount) "kept") (addK "head" "s" (* 8 (sLargeObjects)))) (jmp "lloop" (list "head" "z0")))
          (blkp "lloop" (list "prev" "live") (list (ld "lo" "prev" 0) (cmpK "lz" "eqInt" "lo" 0)) (br "lz" "ldone" "lbody"))
          (blk "lbody" (list (ld8 "m" "lo" 29) (cmpK "marked" "neInt" "m" 0)) (br "marked" "lkeep" "lfree"))
          (blk "lkeep" (list (st8K "um" "lo" 29 0) (ld "lb" "lo" 8) (add "live1" "live" "lb")) (jmp "lloop" (list "lo" "live1")))
          (blk "lfree" (list (ld "lnx" "lo" 0) (st "wu" "prev" 0 "lnx") (ld8 "type" "lo" 28) (cmpK "isArr" "eqInt" "type" 6)) (br "isArr" "freeData" "handle"))
          (blk "freeData" (list (ld "data" "lo" 48) (i2p "dp" "data") (ex "fd" (i64) (freeName c) (list "dp"))) (jmp "handle" (list)))
          (blk "handle" (list (cmpK "isHandle" "eqInt" "type" 7)) (br "isHandle" "hfin" "release"))
          (blk "hfin" (list (ld "fin" "lo" 48) (cmpK "nofin" "eqInt" "fin" 0)) (br "nofin" "release" "hcall"))
          (blk "hcall" (list (ld "harg" "lo" 40) (cmpK "plain" "eqInt" "guard" 0)) (br "plain" "hplain" "hguard"))
          (blk "hplain" (list (ex "fr" (i64) "gcAslCallFin" (list "fin" "harg"))) (jmp "release" (list)))
          (blk "hguard" (list (ex "gr" (i64) "gcAslFinGuarded" (list "fin" "harg" "guard")) (cmpK "raised" "neInt" "gr" 0)) (br "raised" "hraised" "release"))
          (blk "hraised" (list (ld8 "f0" "fe" 0) (cmpK "firstErr" "eqInt" "f0" 0)) (br "firstErr" "hsize" "release"))
          (blk "hsize" (list (ld "msz" "guard" 32) (k "cap" 4096) (ult "smaller" "msz" "cap")) (brA "smaller" "hcopy" (list "msz") "hcopy" (list "cap")))
          (blkp "hcopy" (list "cn") (list (cmpK "cnz" "neInt" "cn" 0)) (br "cnz" "hcopy2" "release"))
          (blk "hcopy2" (list (ld "msg" "guard" 24) (i2p "fep" "fe") (i2p "msgp" "msg") (ex "mc" (ptr) "memcpy" (list "fep" "msgp" "cn")) (add "endAt" "fe" "cn")
                              (st8K "nul" "endAt" -1 0))
            (jmp "release" (list)))
          (blk "release" (list (i2p "lop" "lo") (ex "fl" (i64) (freeName c) (list "lop")) (sincK "freed" (sObjectsFreed) 1)) (jmp "lloop" (list "prev" "live")))
          (blk "ldone" (list) (ret "live"))))

fn sweepPagesFn -> ty/SsaFunction
  (fun "sweepPages" (list "live")
    (list (blk "entry" (list (state) (k "sc0" 0)) (jmp "cloop" (list "sc0" "live")))
          (blkp "cloop" (list "sc" "lv") (list (cmpK "cmore" "ltInt" "sc" (numClasses))) (br "cmore" "cbody" "done"))
          (blk "cbody" (list (classAddr "ca" "sc") (stK "w1" "ca" 8 0) (stK "w2" "ca" 16 0)) (jmp "ploop" (list "ca" "lv")))
          (blkp "ploop" (list "pp" "lv2") (list (ld "p" "pp" 0) (cmpK "pz" "eqInt" "p" 0)) (brA "pz" "cnext" (list "lv2") "pbody" (list)))
          (blk "pbody" (list (ld "mc" "p" 48) (cmpK "empty" "eqInt" "mc" 0)) (br "empty" "pfree" "psweep"))
          (blk "pfree" (list (ld "pnx" "p" 0) (st "w3" "pp" 0 "pnx") (ld "ac" "p" 40) (sinc "fr" (sObjectsFreed) "ac") (cl "fp" "freePage" (list "p"))) (jmp "ploop" (list "pp" "lv2")))
          (blk "psweep" (list (ld "ss" "p" 24) (ld "bump" "p" 56) (addK "used" "bump" (- 0 (pageHeader))) (quot "lim" "used" "ss") (k "i0" 0))
            (jmp "sloop" (list "i0" "lv2" "i0" "i0")))
          (blkp "sloop" (list "idx" "lv3" "fl" "nd") (list (cmp "smore" "ltInt" "idx" "lim")) (br "smore" "sbody" "sdone"))
          (blk "sbody" (list (mul "off" "idx" "ss") (addK "first" "p" (pageHeader)) (add "o" "first" "off") (shrK "word" "idx" 6) (addK "wbase" "p" 72) (elem "wa" "wbase" "word" 8)
                             (ld "w" "wa" 0) (bandK "bn" "idx" 63) (k "one" 1) (shl "bit" "one" "bn") (band "wb" "w" "bit") (cmpK "inUse" "neInt" "wb" 0) (addK "idx1" "idx" 1))
            (brA "inUse" "sused" (list) "sfree" (list "nd")))
          (blk "sused" (list (ld8 "m" "o" 5) (cmpK "marked" "neInt" "m" 0)) (br "marked" "slive" "sdead"))
          (blk "slive" (list (st8K "um" "o" 5 0) (ldU32 "sz" "o" 0) (add "lv4" "lv3" "sz")) (jmp "sloop" (list "idx1" "lv4" "fl" "nd")))
          (blk "sdead" (list (addK "nd1" "nd" 1) (k "all" -1) (bxor "nbit" "bit" "all") (band "w1b" "w" "nbit") (st "w5" "wa" 0 "w1b")) (jmp "sfree" (list "nd1")))
          (blkp "sfree" (list "nd2") (list (st "w6" "o" 0 "fl")) (jmp "sloop" (list "idx1" "lv3" "o" "nd2")))
          (blk "sdone" (list (st "w7" "p" 64 "fl") (sinc "fr2" (sObjectsFreed) "nd") (st "w8" "p" 40 "mc") (stK "w9" "p" 48 0) (cmpK "hasFree" "neInt" "fl" 0))
            (br "hasFree" "pushFree" "activeCheck"))
          (blk "pushFree" (list (ld "ffp" "ca" 8) (st "w10" "p" 8 "ffp") (st "w11" "ca" 8 "p")) (jmp "pnext" (list)))
          (blk "activeCheck" (list (ld "act" "ca" 16) (cmpK "noAct" "eqInt" "act" 0) (add "bend" "bump" "ss") (k "psz" (pageSize)) (ule "roomy" "bend" "psz") (andB "mkAct" "noAct" "roomy"))
            (br "mkAct" "setActive" "pnext"))
          (blk "setActive" (list (st "w12" "ca" 16 "p")) (jmp "pnext" (list)))
          (blk "pnext" (list) (jmp "ploop" (list "p" "lv3")))
          (blkp "cnext" (list "lv7") (list (addK "sc1" "sc" 1)) (jmp "cloop" (list "sc1" "lv7")))
          (blk "done" (list) (ret "lv"))))

fn sweepPhaseFn -> ty/SsaFunction
  (fun "sweepPhase" (list "t0" "guard" "fe")
    (list (blk "entry" (list (state) (k "slm" (sMarkNs)) (cl "tm" "stamp" (list "slm" "t0")) (cl "live1" "sweepLarge" (list "guard" "fe")) (k "sll" (sSweepLargeNs))
                             (cl "tl" "stamp" (list "sll" "tm")) (cl "live" "sweepPages" (list "live1")) (k "slp" (sSweepPagesNs)) (cl "tp" "stamp" (list "slp" "tl"))
                             (sstK "w1" (sAllocated) 0) (sst "w2" (sBytesLive) "live")
                             (sld "gb" (sGrowthBits)) (ex "growth" (f64) "gcAslBitsF64" (list "gb")) (pr "lf" (f64) "intToFloat" (list "live")) (pr "next" (f64) "mulFloat" (list "lf" "growth"))
                             (kf "capF" 70368744177664.0) (cmp "big" "geFloat" "next" "capF") (k "capI" 70368744177664))
            (brA "big" "floor" (list "capI") "conv" (list)))
          (blk "conv" (list (ex "nexti" (i64) "gcAslF64ToU64" (list "next"))) (jmp "floor" (list "nexti")))
          (blkp "floor" (list "t") (list (sld "minb" (sMinBytes)) (ult "low" "t" "minb")) (brA "low" "cap" (list "minb") "cap" (list "t")))
          (blkp "cap" (list "t2") (list (sld "maxb" (sMaxBytes)) (cmpK "nomax" "eqInt" "maxb" 0)) (brA "nomax" "set" (list "t2") "room" (list)))
          (blk "room" (list (ult "under" "live" "maxb") (sub "left" "maxb" "live") (k "none" 0)) (brA "under" "roomed" (list "left") "roomed" (list "none")))
          (blkp "roomed" (list "rm") (list (ult "tight" "rm" "t2")) (brA "tight" "set" (list "rm") "set" (list "t2")))
          (blkp "set" (list "t3") (list (sst "w3" (sThreshold) "t3") (shrK "keep" "t3" 14) (cl "rc" "releaseCache" (list "keep")) (k "slr" (sReleaseNs))
                                        (cl "tr" "stamp" (list "slr" "tp")) (sld "ver" (sVerify)) (cmpK "verifying" "neInt" "ver" 0))
            (br "verifying" "verify" "stats"))
          (blk "verify" (list (cl "vh" "verifyHeap" (list))) (jmp "stats" (list)))
          (blk "stats" (list (sld "on" (sStats)) (cmpK "timed" "neInt" "on" 0)) (br "timed" "time" "finErr"))
          (blk "time" (list (cl "t1" "monoNs" (list)) (sub "dt" "t1" "t0") (sinc "tn" (sTotalNs) "dt")) (jmp "finErr" (list)))
          (blk "finErr" (list (ld8 "f0" "fe" 0) (cmpK "raised" "neInt" "f0" 0)) (br "raised" "rethrow" "heapCap"))
          (blk "rethrow" (list (i2p "fep" "fe") (ex "len" (i64) "strlen" (list "fep")) (addK "n0" "len" 1) (ld "msz" "guard" 32) (ult "fits" "n0" "msz"))
            (brA "fits" "copy" (list "n0") "copy" (list "msz")))
          (blkp "copy" (list "n") (list (cmpK "nz" "neInt" "n" 0)) (br "nz" "copy2" "throw"))
          (blk "copy2" (list (ld "msg" "guard" 24) (i2p "msgp" "msg") (ex "mc" (ptr) "memcpy" (list "msgp" "fep" "n")) (add "endAt" "msg" "n") (st8K "nul" "endAt" -1 0)) (jmp "throw" (list)))
          (retZero "throw" (list (ex "rt" (i64) "gcAslRethrow" (list "guard"))))
          (blk "heapCap" (list (sld "maxc" (sMaxBytes)) (cmpK "capped" "neInt" "maxc" 0)) (br "capped" "capCheck" "done"))
          (blk "capCheck" (list (ult "over" "maxc" "live")) (br "over" "oom" "done"))
          (failB "oom" "ERR_OOM" "live heap exceeds ASL_GC_MAX_MIB=%zu" (list (shrK "mib" "maxc" 20)) (list "mib"))
          (retZero "done" (list))))

fn isOneFn -> ty/SsaFunction
  (fun "isOne" (list "addr")
    (list (blk "entry" (list (cmpK "z" "eqInt" "addr" 0)) (br "z" "no" "check"))
          (blk "check" (list (ld8 "c" "addr" 0) (cmpK "one" "eqInt" "c" 49)) (br "one" "yes" "no"))
          (blk "yes" (list (k "y" 1)) (ret "y"))
          (retZero "no" (list))))

fn presentFn -> ty/SsaFunction
  (fun "present" (list "addr")
    (list (blk "entry" (list (cmpK "z" "eqInt" "addr" 0)) (br "z" "no" "check"))
          (blk "check" (list (ld8 "c" "addr" 0) (cmpK "empty" "eqInt" "c" 0)) (br "empty" "no" "yes"))
          (blk "yes" (list (k "y" 1)) (ret "y"))
          (retZero "no" (list))))

fn errnoZero c: GcCtx d: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".loc") (ptr) c.errno (list)) (k (str d ".o") 0) (k32 (str d ".z") 0) (pr d (i1) "rawStoreI32" (list (str d ".loc") (str d ".o") (str d ".z")))))

fn errnoRead c: GcCtx d: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".loc") (ptr) c.errno (list)) (p2i (str d ".i") (str d ".loc")) (ldS32 d (str d ".i") 0)))

fn mibOfFn c: GcCtx -> ty/SsaFunction
  (fun "mibOf" (list "addr")
    (list (blk "entry" (list (state) (errnoZero c "ez") (i2p "ap" "addr") (addK "endAt" "s" (* 8 (sEndPtr))) (i2p "endp" "endAt") (k32 "ten" 10)
                             (ex "v" (i64) "strtoull" (list "ap" "endp" "ten")) (errnoRead c "er") (ld "end" "endAt" 0) (ld8 "endc" "end" 0) (ld8 "c0" "addr" 0)
                             (cmpK "e1" "neInt" "er" 0) (cmpK "e2" "neInt" "endc" 0) (cmpK "e3" "eqInt" "c0" 45) (ultK "e4" "v" 1) (k "most" 65536) (ult "e5" "most" "v")
                             (orB "b1" "e1" "e2") (orB "b2" "b1" "e3") (orB "b3" "b2" "e4") (orB "bad" "b3" "e5"))
            (br "bad" "bad" "good"))
          (blk "good" (list) (ret "v"))
          (retZero "bad" (list))))

fn envFailB label: String fmt: String text: String -> ty/SsaBlock
  (retZero label (list (k32 (str label ".fd") 2) (cs (str label ".f") fmt) (i2p (str label ".t") text) (ex (str label ".p") (i32) "dprintf" (list (str label ".fd") (str label ".f") (str label ".t")))
                       (k32 (str label ".c") 2) (ex (str label ".x") (i64) "exit" (list (str label ".c")))))

fn getenvI d: String name: String -> (List ty/SsaInstr)
  (appendAll (list (cs (str d ".n") name) (ex (str d ".p") (ptr) "getenv" (list (str d ".n"))) (p2i d (str d ".p"))))

fn initFn c: GcCtx -> ty/SsaFunction
  (fun "init" (list)
    (list (blk "entry" (list (state) (getenvI "es" "ASL_GC_STRESS") (cl "stress" "isOne" (list "es")) (sst "w1" (sStress) "stress")
                             (getenvI "et" "ASL_GC_STATS") (cl "stats" "isOne" (list "et")) (cmpK "statsOn" "neInt" "stats" 0))
            (br "statsOn" "statsOn" "growth"))
          (blk "statsOn" (list (sstK "w2" (sStats) 1) (ex "ax" (i64) "gcAslAtexitStats" (list))) (jmp "growth" (list)))
          (blk "growth" (list (getenvI "eg" "ASL_GC_GROWTH") (cl "gp" "present" (list "eg")) (cmpK "hasG" "neInt" "gp" 0)) (br "hasG" "gparse" "minMib"))
          (blk "gparse" (list (errnoZero c "gz") (i2p "egp" "eg") (addK "endAt" "s" (* 8 (sEndPtr))) (i2p "endp" "endAt") (ex "d" (f64) "strtod" (list "egp" "endp"))
                              (errnoRead c "ger") (ld "end" "endAt" 0) (ld8 "endc" "end" 0) (pr "dd" (f64) "subFloat" (list "d" "d")) (kf "zf" 0.0) (cmp "finite" "eqFloat" "dd" "zf")
                              (kf "lof" 0.25) (kf "hif" 64.0) (cmp "low" "ltFloat" "d" "lof") (cmp "high" "gtFloat" "d" "hif")
                              (cmpK "g1" "neInt" "ger" 0) (cmpK "g2" "neInt" "endc" 0) (notB "g3" "finite") (orB "gb1" "g1" "g2") (orB "gb2" "gb1" "g3") (orB "gb3" "gb2" "low") (orB "gbad" "gb3" "high"))
            (br "gbad" "gbad" "gok"))
          (envFailB "gbad" "ERR_ENV: ASL_GC_GROWTH must be a number in [0.25, 64], got '%s'\n" "eg")
          (blk "gok" (list (ex "bits" (i64) "gcAslF64Bits" (list "d")) (sst "w3" (sGrowthBits) "bits")) (jmp "minMib" (list)))
          (blk "minMib" (list (getenvI "em" "ASL_GC_MIN_MIB") (cl "mp" "present" (list "em")) (cmpK "hasM" "neInt" "mp" 0)) (br "hasM" "mparse" "maxMib"))
          (blk "mparse" (list (cl "mv" "mibOf" (list "em")) (cmpK "mbad" "eqInt" "mv" 0)) (br "mbad" "mbad" "mok"))
          (envFailB "mbad" "ERR_ENV: ASL_GC_MIN_MIB must be an integer in [1, 65536], got '%s'\n" "em")
          (blk "mok" (list (shlK "mb" "mv" 20) (sst "w4" (sMinBytes) "mb")) (jmp "maxMib" (list)))
          (blk "maxMib" (list (getenvI "ex" "ASL_GC_MAX_MIB") (cl "xp" "present" (list "ex")) (cmpK "hasX" "neInt" "xp" 0)) (br "hasX" "xparse" "thresh"))
          (blk "xparse" (list (cl "xv" "mibOf" (list "ex")) (cmpK "xbad" "eqInt" "xv" 0)) (br "xbad" "xbad" "xok"))
          (envFailB "xbad" "ERR_ENV: ASL_GC_MAX_MIB must be an integer in [1, 65536], got '%s'\n" "ex")
          (blk "xok" (list (shlK "xb" "xv" 20) (sst "w5" (sMaxBytes) "xb")) (jmp "thresh" (list)))
          (blk "thresh" (list (sld "maxb" (sMaxBytes)) (sld "minb" (sMinBytes)) (cmpK "capped" "neInt" "maxb" 0) (ult "smaller" "maxb" "minb") (andB "useMax" "capped" "smaller"))
            (brA "useMax" "first" (list "maxb") "first" (list "minb")))
          (blkp "first" (list "t") (list (sst "w6" (sThreshold) "t") (getenvI "ev" "ASL_GC_VERIFY") (cl "ver" "isOne" (list "ev")) (sst "w7" (sVerify) "ver") (k "z" 0))
            (ret "z"))))

fn wasmInitFn -> ty/SsaFunction
  (fun "init" (list) (list (retZero "entry" (list))))

fn printStatsFn -> ty/SsaFunction
  (fun "printStats" (list)
    (list (retZero "entry" (list (state) (k32 "fd" 2) (cs "fmt" (statsFormat))
                                 (sld "c" (sCollections)) (sld "oa" (sObjectsAllocated)) (sld "of" (sObjectsFreed)) (sld "ba" (sBytesAllocated)) (sld "bl" (sBytesLive))
                                 (sld "tn" (sTotalNs)) (sld "pf" (sPagesFreed)) (sld "pa" (sPagesAcquired))
                                 (ex "r" (i32) "dprintf" (list "fd" "fmt" "c" "oa" "of" "ba" "bl" "tn" "pf" "pa"))
                                 (cs "pfmt" (phasesFormat)) (sld "mn" (sMarkNs)) (sld "ln" (sSweepLargeNs)) (sld "sn" (sSweepPagesNs)) (sld "rn" (sReleaseNs))
                                 (sld "pm" (sPagesMapped)) (sld "pu" (sPagesUnmapped)) (sld "uc" (sUnmapCalls))
                                 (ex "r2" (i32) "dprintf" (list "fd" "pfmt" "mn" "ln" "sn" "rn" "pm" "pu" "uc"))))))

fn gcFunctions c: GcCtx -> (List ty/SsaFunction)
  (appendAll
    (list (list (rootPushFn) (rootPopFn) (registerProtoFn c) (markObjFn) (growMarkFn c) (markValFn) (drainFn) (markRootFn) (markPhaseFn c) (poolScanFn) (clearMarksFn)
                (abortMarkFn) (numChildrenFn) (childAddrFn) (typeNameFn) (verifyDfsFn c) (verifyHeapFn) (pageSlotFn) (pageSetPutFn) (pageSetReserveFn c) (pageSetGetFn)
                (pageSetDelFn))
          (if (target/growsLinearMemory c.target) (list) (list (unmapFn)))
          (list (freshPageFn c) (widenHeapFn) (newPageFn) (freePageFn) (releaseCacheFn c) (poolAllocFn) (allocFn) (allocRawFn) (allocConsFn) (allocPermFn) (allocLargeFn)
                (accountFn) (willAllocateFn) (freedObjectsFn) (failNextGrowFn) (findObjFn) (scanConservativeFn) (monoNsFn c) (beginFn) (stampFn) (sweepLargeFn c) (sweepPagesFn)
                (sweepPhaseFn))
          (if (wasm? c) (list (wasmInitFn)) (list (isOneFn) (presentFn) (mibOfFn c) (initFn c) (printStatsFn)))))
