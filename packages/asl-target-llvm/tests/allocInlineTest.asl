(module asl-target-llvm/tests/allocInlineTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn clangLink -> String
  "/usr/bin/clang -O2 -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! emitted path: String -> String
  (mt (lk/linkEntry! path)
    ((err ds) (do (assert false (str path ": links; " (formatDiags ds))) ""))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (do (assert false (str path ": emits; " (formatDiags ds))) ""))
              ((ok code) code))))

fn occurrences text: String piece: String -> Int64
  (- (listLength (stringSplit text piece)) 1)

fn functionText text: String head: String -> String
  (mt (stringIndexOf text head)
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))]
                 (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "\n}\n") (stringLength rest))) rest))))

fn rawText text: String -> String
  (fold (fn [(acc String) (sc Int64)] -> String (stringReplace acc (str "call ptr @gcAsl.allocFast." sc "(") "call ptr @asl_alloc_raw("))
        (stringReplace text "call ptr @gcAsl.allocFastCons(i32 1, i64 40)" "call ptr @asl_alloc_cons()") (range 0 63))

fn statsField text: String key: String -> Int64
  (lineField text "(:gcStats " key)

fn lineField text: String head: String key: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l head)) (stringLines text))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens key)
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! built work: String name: String text: String -> String
  (let [(ll (str work "/" name ".ll"))
        (bin (str work "/" name))]
    (do (assert (ok? (fileWrite ll text)) (str name ": .ll written"))
        (let [(linked (sh (str (clangLink) ll (lib) bin)))]
          (assert (= linked.exitCode 0) (str name ": links against libaslrt.a; " linked.stderr)))
        bin))

fn ! testStructure -> Bool
  (let [(text (emitted "bench/native/record.asl"))
        (step (functionText text "define tailcc %Val @bench$2Fnative$2Frecord$2Estep("))
        (helper (functionText text "define linkonce_odr hidden ptr @gcAsl.allocFast.5("))
        (fast (optionOr (stringSlice helper 0 (optionOr (stringIndexOf helper "\nslow:") 0)) ""))]
    (do (assert (> (stringLength step) 0) "record: step is emitted")
        (assert (= (occurrences step "@asl_alloc_raw(") 0) (str "record: step calls asl_alloc_raw " (occurrences step "@asl_alloc_raw(") " times, want 0"))
        (assert (= (occurrences step "call ptr @gcAsl.allocFast.5(i32 2, i64 56)") 1) "record: step allocates its 56-byte Body through size class 5's fast path")
        (assert (stringContains? helper "\nslow:\n  %r = tail call ptr @asl_alloc_raw(i32 %t, i64 %n)\n") "record: a fast-path miss tail-calls asl_alloc_raw")
        (assert (> (stringLength fast) 0) "record: size class 5's helper has a fast path before its slow block")
        (refute (stringContains? fast "call ") "record: the fast path calls nothing")
        (assert (stringContains? fast "%s = load ptr, ptr @asl_gc_state_ptr\n  %unpublished = icmp eq ptr %s, null\n  br i1 %unpublished, label %slow") "record: an unpublished collector state takes the slow path")
        (assert (stringContains? fast "%over = icmp ult i64 %th, %al\n  %stressed = icmp ne i64 %stress, 0\n  %need = or i1 %over, %stressed\n  br i1 %need, label %slow") "record: crossing the threshold or ASL_GC_STRESS takes the slow path")
        (assert (stringContains? fast "%hasFree = icmp ne i64 %fp, 0\n  br i1 %hasFree, label %slow") "record: a class with free-list pages takes the slow path")
        (assert (stringContains? fast "%fits = icmp slt i64 %bi, %cnt\n  br i1 %fits, label %bump, label %slow") "record: a full active page takes the slow path")
        (assert (= (occurrences text "call ptr @asl_alloc_raw(") (occurrences text "tail call ptr @asl_alloc_raw(i32 %t, i64 %n)")) "record: asl_alloc_raw is called only from fast-path misses")
        true))

fn ! sameStats work: String name: String n: Int64 -> Bool
  (let [(text (emitted (str "bench/native/" name ".asl")))
        (raw (rawText text))
        (inl (built work (str name "Inline") text))
        (ref (built work (str name "Raw") raw))
        (a (sh (str "ASL_GC_STATS=1 " inl " " n)))
        (b (sh (str "ASL_GC_STATS=1 " ref " " n)))]
    (do (assert (> (occurrences raw "call ptr @asl_alloc_") (occurrences text "call ptr @asl_alloc_")) (str name ": the inline build allocates through fast paths the raw build does not"))
        (assert (= (occurrences text "call ptr @asl_alloc_raw(") (occurrences text "tail call ptr @asl_alloc_raw(i32 %t, i64 %n)")) (str name ": asl_alloc_raw is called only from fast-path misses"))
        (assert (= (occurrences text "call ptr @asl_alloc_cons()") (occurrences text "tail call ptr @asl_alloc_cons()")) (str name ": asl_alloc_cons is called only from fast-path misses"))
        (assert (= a.exitCode 0) (str name ": inline build exits 0; " a.stderr))
        (assert (= b.exitCode 0) (str name ": raw build exits 0; " b.stderr))
        (assert (= a.stdout b.stdout) (str name ": same stdout; inline " a.stdout " raw " b.stdout))
        (assert (> (statsField a.stderr ":objectsAllocated") 0) (str name ": the inline build reports objects allocated; " a.stderr))
        (assert (= (statsField a.stderr ":objectsAllocated") (statsField b.stderr ":objectsAllocated")) (str name ": equal objectsAllocated; inline " a.stderr " raw " b.stderr))
        (assert (= (statsField a.stderr ":bytesAllocated") (statsField b.stderr ":bytesAllocated")) (str name ": equal bytesAllocated; inline " a.stderr " raw " b.stderr))
        true))

fn ! testCollects work: String -> Bool
  (let [(bin (built work "recordCollect" (emitted "bench/native/record.asl")))
        (big (sh (str "ASL_GC_STATS=1 ASL_GC_MIN_MIB=1 " bin " 100000")))
        (plain (sh (str bin " 3000")))
        (stressed (sh (str "ASL_GC_STATS=1 ASL_GC_STRESS=1 " bin " 3000")))]
    (do (assert (= big.exitCode 0) (str "record 100000: exits 0; " big.stderr))
        (assert (>= (statsField big.stderr ":bytesAllocated") 4194304) (str "record 100000: allocates at least 4x the 1 MiB threshold; " big.stderr))
        (assert (>= (statsField big.stderr ":collections") 4) (str "record 100000: collects at least 4 times under a 1 MiB threshold; " big.stderr))
        (assert (= stressed.exitCode 0) (str "record 3000 under ASL_GC_STRESS=1: exits 0; " stressed.stderr))
        (assert (= stressed.stdout plain.stdout) (str "record 3000: same output under stress; plain " plain.stdout " stressed " stressed.stdout))
        (assert (>= (statsField stressed.stderr ":objectsAllocated") 3000) (str "record 3000 under ASL_GC_STRESS=1: allocates a Body per step; " stressed.stderr))
        (assert (= (statsField stressed.stderr ":collections") (statsField stressed.stderr ":objectsAllocated")) (str "record 3000 under ASL_GC_STRESS=1: every allocation collects; " stressed.stderr))
        true))

fn strMixSource -> String
  (stringJoin
    (list "(module strMix"
          "  :x [main walk]"
          "  :i [])"
          ""
          "fn walk i: Int64 n: Int64 total: Int64 last: String -> String"
          "  (if (= i n)"
          "    (str total \" \" last)"
          "    (let [(s (str \"k\" i \" \" (* (int64ToFloat64 i) 0.25) \" \" (list i \"q\" 1.5) \":\"))]"
          "      (walk (+ i 1) n (+ total (stringLength s)) s)))"
          ""
          "fn ! main args: (List String) -> (Result Unit String)"
          "  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) \"1000\")) 1000))]"
          "    (do (println (walk 0 n 0 \"\"))"
          "        (ok ())))"
          "")
    "\n")

fn countedHeap text: String -> String
  (str (stringReplace (stringReplace text "call ptr @malloc(" "call ptr @countMalloc(") "call ptr @realloc(" "call ptr @countRealloc(")
       (stringJoin
         (list "@mallocCount = internal global i64 0"
               "@reallocCount = internal global i64 0"
               "@.heapFmt = private constant [38 x i8] c\"(:heapCalls :malloc %ld :realloc %ld)\\0A\""
               "declare i32 @dprintf(i32, ptr, ...)"
               "define ptr @countMalloc(i64 %n) {"
               "  %c = load i64, ptr @mallocCount"
               "  %c1 = add i64 %c, 1"
               "  store i64 %c1, ptr @mallocCount"
               "  %r = call ptr @malloc(i64 %n)"
               "  ret ptr %r"
               "}"
               "define ptr @countRealloc(ptr %p, i64 %n) {"
               "  %c = load i64, ptr @reallocCount"
               "  %c1 = add i64 %c, 1"
               "  store i64 %c1, ptr @reallocCount"
               "  %r = call ptr @realloc(ptr %p, i64 %n)"
               "  ret ptr %r"
               "}"
               "define internal void @printHeapCalls() {"
               "  %m = load i64, ptr @mallocCount"
               "  %r = load i64, ptr @reallocCount"
               "  %w = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @.heapFmt, i64 %m, i64 %r)"
               "  ret void"
               "}"
               "define internal void @registerHeapCalls() {"
               "  %r = call i32 @atexit(ptr @printHeapCalls)"
               "  ret void"
               "}"
               "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @registerHeapCalls, ptr null }]"
               "")
         "\n"))

fn heapCalls text: String -> Int64
  (+ (lineField text "(:heapCalls " ":malloc") (lineField text "(:heapCalls " ":realloc"))

fn ! testStrFormat work: String -> Bool
  (let [(src (str work "/strMix.asl"))
        (written (fileWrite src (strMixSource)))
        (text (emitted src))
        (many (functionText text "define internal %Val @asl_rt_format_many("))
        (render (functionText text "define internal void @rtfmt_render("))
        (bin (built work "strMix" (countedHeap text)))
        (few (sh (str "ASL_GC_STATS=1 " bin " 2010")))
        (more (sh (str "ASL_GC_STATS=1 " bin " 4010")))
        (thousand (sh (str bin " 1000")))]
    (do (assert (ok? written) (str "fileWrite " src))
        (assert (> (stringLength many) 0) "strMix: asl_rt_format_many is emitted")
        (refute (stringContains? many "@asl_rt_format_val(") "strMix: str renders each item into its own buffer, not through a separate string per item")
        (refute (stringContains? many "@malloc(") "strMix: str starts in a stack buffer, not malloc")
        (assert (> (stringLength render) 0) "strMix: rtfmt_render is emitted")
        (refute (stringContains? render "@asl_rt_format_i64(") "strMix: a rendered Int64 is written into the buffer, not allocated as a string first")
        (refute (stringContains? render "@asl_rt_format_float(") "strMix: a rendered Float64 is written into the buffer, not allocated as a string first")
        (assert (= few.exitCode 0) (str "strMix 2010: exits 0; " few.stderr))
        (assert (= more.exitCode 0) (str "strMix 4010: exits 0; " more.stderr))
        (assert (>= (heapCalls few.stderr) 0) (str "strMix 2010: reports its heap calls; " few.stderr))
        (assert (= (heapCalls more.stderr) (heapCalls few.stderr)) (str "strMix: 2000 more str calls make no more malloc or realloc calls; 2010 steps " few.stderr " 4010 steps " more.stderr))
        (assert (= (- (statsField more.stderr ":objectsAllocated") (statsField few.stderr ":objectsAllocated")) (* 2000 4))
                (str "strMix: each step allocates its result string and the 3 cells of its list, nothing per formatted item; 2010 steps " few.stderr " 4010 steps " more.stderr))
        (assert (= thousand.stdout "24840 k999 249.75 (999 \"q\" 1.5):\n") (str "strMix 1000: output as before; " thousand.stdout))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testStructure)
        (sameStats work "record" 200000)
        (sameStats work "list" 200000)
        (sameStats work "allocMix" 100000)
        (testCollects work)
        (testStrFormat work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
