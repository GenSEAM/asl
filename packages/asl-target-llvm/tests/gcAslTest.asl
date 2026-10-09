(module asl-target-llvm/tests/gcAslTest
  :x [runTests]
  :i [(asl-target-llvm/gcRoute :a gr) (asl-target-llvm/ssa :a ssa)])

fn host -> String
  "asl/host/out/asl-host"

fn abiTest -> String
  "asl/packages/asl-target-llvm/tests/abiPrograms.asl"

fn gcLib -> String
  "asl/host/out/libaslrt.a"

fn hostLib -> String
  "asl/host/out/libaslhost.a"

fn clangLink -> String
  "/usr/bin/clang -Wno-override-module -x ir "

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn programs -> (List (Pair String Int64))
  (list (pair "allocSmall" 0) (pair "switchPick" 3) (pair "fusedVariantInt" 0) (pair "fusedVariantFloat" 0)
        (pair "fusedVariantBool" 0) (pair "fusedRecordInt" 0) (pair "joined" 42) (pair "deepTail" 42) (pair "nestedTail" 42))

fn argsOf name: String -> String
  (if (= name "joined") " ab cde" "")

fn ! linkBoth work: String name: String ll: String -> Bool
  (let [(c (sh (str (clangLink) ll " -x none " work "/gc.o " (gcLib) " -lm -o " work "/gcc/" name)))
        (a (sh (str (clangLink) ll " -x none " (gcLib) " -lm -o " work "/asl/" name)))]
    (do (assert (= c.exitCode 0) (str name ": links with gc.o and libaslrt.a; " c.stderr))
        (assert (= a.exitCode 0) (str name ": links against libaslrt.a; " a.stderr))
        true))

fn ! floorIr work: String -> String
  (let [(path (str work "/floor.ll"))]
    (do (assert (ok? (fileWrite path (ssa/cRuntimeModule))) "floor.ll: the C floor's IR written")
        path))

fn ! runSide work: String side: String env: String name: String args: String -> ProcessOutput
  (sh (str "cd " work "/" side " && " env "./" name args))

fn ! sameRun label: String work: String env: String name: String args: String -> ProcessOutput
  (let [(c (runSide work "gcc" env name args))
        (a (runSide work "asl" env name args))]
    (do (assert (= a.exitCode c.exitCode) (str label ": ASL collector exit " a.exitCode " equals gc.c exit " c.exitCode "; stderr " a.stderr))
        (assert (= a.stdout c.stdout) (str label ": same stdout; gc.c " c.stdout " ASL " a.stdout))
        (assert (= a.stderr c.stderr) (str label ": same stderr; gc.c " c.stderr " ASL " a.stderr))
        c))

fn ! nmNames bin: String -> (List String)
  (let [(out (sh (str "nm " bin)))]
    (do (assert (= out.exitCode 0) (str "nm " bin ": exit " out.exitCode "; stderr: " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listLast (stringSplit (stringTrim line) " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? (stringTrim line)))) (stringLines out.stdout)))))

fn collectorNames -> (List String)
  (list "asl_alloc" "asl_alloc_cons" "asl_alloc_perm" "asl_gc_collect" "asl_gc_root_push" "asl_gc_root_pop" "gcInit" "gcAccount" "gcScanConservative" "gcAsl.state")

fn gcStatics -> (List String)
  (list "sizeClasses" "pageSet" "pageSetCap" "largeIndex" "markStk")

fn heapSource -> String
  (stringJoin (list
    "(module stressMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(schema Item (:f name String) (:f n Int64))"
    ""
    "(enum Shape (:c circle [(r Int64)] \"Round\") (:c rect [(w Int64) (h Int64)] \"Rectangle\"))"
    ""
    "fn area s: Shape -> Int64"
    "  (mt s ((circle r) (* r r)) ((rect w h) (* w h)))"
    ""
    "fn wide a: String b: String c: String d: String it: Item -> String"
    "  (str a b c d it.name (stringFromInt64 it.n))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(items (map (fn [(i Int64)] -> Item (Item :name (str \"i\" (stringFromInt64 i)) :n i)) (range 0 300)))"
    "        (k (str \"k\" (stringFromInt64 (listLength args))))"
    "        (names (fold (fn [(acc String) (it Item)] -> String (if (= it.n 299) (str acc it.name k) acc)) \"\" items))"
    "        (shapes (map (fn [(i Int64)] -> Shape (if (= (mod i 2) 0) (circle i) (rect i 2))) (range 0 200)))"
    "        (total (fold (fn [(acc Int64) (s Shape)] -> Int64 (+ acc (area s))) 0 shapes))"
    "        (w (wide \"a\" \"b\" \"c\" \"d\" (Item :name \"x\" :n 7)))"
    "        (adders (map (fn [(i Int64)] -> (fn [Int64] -> String) (let [(tag (str \"t\" (stringFromInt64 i)))] (fn [(x Int64)] -> String (str tag \":\" (stringFromInt64 (+ x i)))))) (range 0 300)))"
    "        (tags (fold (fn [(acc Int64) (f (fn [Int64] -> String))] -> Int64 (+ acc (stringLength (f 1)))) 0 adders))]"
    "    (do (println names)"
    "        (println (stringFromInt64 total))"
    "        (println w)"
    "        (println (stringFromInt64 tags))"
    "        (ok 0)))")
    "\n")

fn floorSource count: String -> String
  (stringJoin (list
    "(module floorOom"
    "  :x [main]"
    "  :i [])"
    ""
    "fn grow acc: (List Int64) i: Int64 -> (List Int64)"
    "  (if (= i 0) acc (grow (cons i acc) (- i 1)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    (str "  (do (println (stringFromInt64 (listLength (grow (list) " count "))))")
    "      (ok 0))"
    "")
    "\n")

fn hostErrorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn ! buildLl work: String name: String source: String -> String
  (let [(src (str work "/" name ".asl"))
        (ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite src source)) (str name ": source written"))
        (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))]
          (do (assert (= built.exitCode 0) (str name ": asl1 builds it; " built.stderr))
              src))))

fn ! statsLine out: ProcessOutput -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringLines out.stderr))) "")

fn statsPairs line: String -> (List (Pair String String))
  (map (fn [(field String)] -> (Pair String String)
         (let [(kv (stringSplit (stringTrim field) " "))]
           (pair (optionOr (listHead kv) "") (optionOr (listLast kv) ""))))
       (filter (fn [(field String)] -> Bool (not (stringEmpty? (stringTrim field))))
               (stringSplit (stringReplace (stringReplace line "(:gcStats " "") ")" "") ":")))

fn statKeys pairs: (List (Pair String String)) -> (List String)
  (map (fn [(p (Pair String String))] -> String (pairFirst p)) pairs)

fn statOf pairs: (List (Pair String String)) key: String -> String
  (optionOr (mapGet (mapFromPairs pairs) key) "")

fn allocKeys -> (List String)
  (list "objectsAllocated" "bytesAllocated")

fn stressKeys -> (List String)
  (list "collections" "objectsAllocated" "bytesAllocated")

fn policyKeys -> (List String)
  (list "collections" "objectsAllocated" "objectsFreed" "bytesAllocated" "bytesLive" "pagesFreed" "pagesAcquired")

fn ! sameStats label: String work: String env: String name: String args: String keys: (List String) -> Bool
  (let [(c (runSide work "gcc" (str "ASL_GC_STATS=1 " env) name args))
        (a (runSide work "asl" (str "ASL_GC_STATS=1 " env) name args))
        (cs (statsPairs (statsLine c)))
        (as (statsPairs (statsLine a)))]
    (do (assert (= a.exitCode c.exitCode) (str label ": exit under ASL_GC_STATS equal; ASL " a.exitCode " gc.c " c.exitCode))
        (assert (= a.stdout c.stdout) (str label ": stdout under ASL_GC_STATS equal"))
        (assert (> (listLength cs) 0) (str label ": gc.c prints a stats line; stderr " c.stderr))
        (assert (= (statKeys as) (statKeys cs)) (str label ": stats keys equal; gc.c " (statsLine c) " ASL " (statsLine a)))
        (assert (listAll? (fn [(key String)] -> Bool (= (statOf as key) (statOf cs key))) keys)
                (str label ": " (stringJoin keys ", ") " equal; gc.c " (statsLine c) " ASL " (statsLine a)))
        (let [(phases (phasesPairs a))
              (calls (optionOr (stringToInt64 (statOf phases "unmapCalls")) -1))
              (unmapped (optionOr (stringToInt64 (statOf phases "pagesUnmapped")) -1))]
          (do (assert (= (statKeys phases) (list "markNs" "sweepLargeNs" "sweepPagesNs" "releaseNs" "pagesMapped" "pagesUnmapped" "unmapCalls"))
                      (str label ": the ASL collector prints its (:gcPhases ...) line; stderr " a.stderr))
              (assert (and (>= calls 0) (<= calls unmapped)) (str label ": munmap calls " calls " at most the pages unmapped " unmapped))
              (refute (stringContains? c.stderr "(:gcPhases ") (str label ": gc.c prints no phases line"))))
        true))

fn ! phasesPairs out: ProcessOutput -> (List (Pair String String))
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcPhases ")) (stringLines out.stderr))) ""))]
    (if (stringEmpty? line) (list) (statsPairs (stringReplace line "(:gcPhases " "(:gcStats "))))

fn ! members archive: String -> (List String)
  (let [(out (sh (str "ar t " archive)))]
    (do (assert (= out.exitCode 0) (str "ar t " archive ": exit " out.exitCode "; " out.stderr))
        (filter (fn [(m String)] -> Bool (and (not (stringEmpty? m)) (not (stringStartsWith? m "__.SYMDEF")))) (stringLines out.stdout))))

fn ! symbolNames cmd: String -> (List String)
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode 0) (str cmd ": exit " out.exitCode "; " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listLast (stringSplit (stringTrim line) " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? (stringTrim line)))) (stringLines out.stdout)))))

fn ! testArchive work: String -> Bool
  (let [(rt (members (gcLib)))
        (hostMembers (members (hostLib)))
        (made (sh (str "mkdir -p " work "/rt")))]
    (do (assert (= made.exitCode 0) "rt extraction directory made")
        (refute (listContains? rt "gc.o") (str "libaslrt.a has no gc.o; members: " (stringJoin rt " ")))
        (assert (listContains? rt "gcAsl.o") (str "libaslrt.a has the ASL collector member gcAsl.o; members: " (stringJoin rt " ")))
        (assert (listContains? hostMembers "gc.o") "libaslhost.a keeps gc.o, asl-host's collector")
        (assert (= (sh (str "cd " work "/rt && ar x " (resultOr (pathCanonicalize (gcLib)) (gcLib)))).exitCode 0) "libaslrt.a members extracted")
      (let [(gcDefs (symbolNames (str "nm -gU " work "/rt/gcAsl.o")))
            (imports (map (fn [(m String)] -> (Pair String (List String))
                            (pair m (filter (fn [(n String)] -> Bool (listContains? (gr/entryNames) n)) (symbolNames (str "nm -u " work "/rt/" m)))))
                          (filter (fn [(m String)] -> Bool (!= m "gcAsl.o")) rt)))]
       (do
        (assert (listAll? (fn [(n String)] -> Bool (listContains? gcDefs n)) (gr/entryNames)) (str "gcAsl.o defines every gc.c entry point; it defines " (stringJoin gcDefs " ")))
        (assert (listAny? (fn [(mi (Pair String (List String)))] -> Bool (not (listEmpty? (pairSecond mi)))) imports) "some libaslrt.a member imports a gc.c entry point")
        (map (fn [(mi (Pair String (List String)))] -> Bool
               (do (assert (listAll? (fn [(n String)] -> Bool (listContains? gcDefs n)) (pairSecond mi))
                           (str (pairFirst mi) ": every gc.c entry point it imports (" (stringJoin (pairSecond mi) " ") ") is gcAsl.o's"))
                   true))
             imports)
        (let [(src (str work "/stressMod.asl"))
              (written (fileWrite src (heapSource)))
              (plain (sh (str "bin/asl build " src " -o " work "/built/stressMod")))]
          (do (assert (ok? written) "stressMod source written")
              (assert (= plain.exitCode 0) (str "bin/asl build of stressMod succeeds; " plain.stderr))
              (let [(names (nmNames (str work "/built/stressMod")))]
                (do (assert (listAll? (fn [(n String)] -> Bool (listContains? names n)) (collectorNames)) "stressMod: defines the collector entries and gcAsl.state")
                    (assert (listAll? (fn [(n String)] -> Bool (not (listContains? names n))) (gcStatics)) "stressMod: carries no gc.o static")))
              (let [(run (sh (str "cd " work "/built && ASL_GC_STRESS=1 ./stressMod")))
                    (interp (sh (str (host) " run " src)))]
                (do (assert (= run.exitCode 0) (str "the built stressMod exits 0 under stress; " run.stderr))
                    (assert (= run.stdout interp.stdout) (str "the built stressMod prints asl-host run's output; native " run.stdout " host " interp.stdout))
                    true))))
        true))
        true))

fn ! testReference work: String -> Bool
  (let [(ll (str work "/allocSmall.ll"))
        (emitted (sh (str (host) " run " (abiTest) " allocSmall > " ll)))]
    (do (assert (= emitted.exitCode 0) (str "allocSmall: emits .ll; " emitted.stderr))
        (linkBoth work "allocSmall" ll)
        (let [(c (nmNames (str work "/gcc/allocSmall")))
              (a (nmNames (str work "/asl/allocSmall")))]
          (do (assert (listAll? (fn [(n String)] -> Bool (listContains? c n)) (gcStatics)) "the gc.o link carries gc.o's statics")
              (refute (listContains? c "gcAsl.state") "the gc.o link pulls no gcAsl.o")
              (assert (listContains? a "gcAsl.state") "the libaslrt.a link has the ASL collector's state")
              (assert (listAll? (fn [(n String)] -> Bool (not (listContains? a n))) (gcStatics)) "the libaslrt.a link carries no gc.o static")
              true))))

fn ! testPrograms work: String -> Bool
  (do
    (map (fn [(p (Pair String Int64))] -> Bool
           (let [(name (pairFirst p))
                 (ll (str work "/" name ".ll"))
                 (emitted (sh (str (host) " run " (abiTest) " " name " > " ll)))]
             (do (assert (= emitted.exitCode 0) (str name ": emits .ll; " emitted.stderr))
                 (linkBoth work name ll)
                 (let [(plain (sameRun name work "" name (argsOf name)))]
                   (assert (= plain.exitCode (pairSecond p)) (str name ": exit " plain.exitCode ", want " (pairSecond p) "; stderr " plain.stderr)))
                 (sameRun (str name " under ASL_GC_STRESS=1") work "ASL_GC_STRESS=1 " name (argsOf name))
                 (sameRun (str name " under ASL_GC_VERIFY=1") work "ASL_GC_VERIFY=1 " name (argsOf name))
                 (sameStats name work "" name (argsOf name) (allocKeys))
                 (sameStats (str name " under ASL_GC_STRESS=1") work "ASL_GC_STRESS=1 " name (argsOf name) (stressKeys)))))
         (programs))
    true)

fn ! testHeavy work: String -> Bool
  (let [(allocLl (str work "/alloc.ll"))
        (emitted (sh (str (host) " run " (abiTest) " alloc > " allocLl)))]
    (do (assert (= emitted.exitCode 0) (str "alloc: emits .ll; " emitted.stderr))
        (linkBoth work "alloc" allocLl)
        (assert (= (sameRun "alloc" work "" "alloc" "").exitCode 0) "alloc: exits 0")
        (sameStats "alloc" work "" "alloc" "" (allocKeys))
        (buildLl work "stressMod" (heapSource))
        (linkBoth work "stressMod" (str work "/stressMod.ll"))
        (let [(interp (sh (str (host) " run " work "/stressMod.asl")))
              (plain (sameRun "stressMod" work "" "stressMod" " x y"))]
          (do (assert (= plain.exitCode 0) (str "stressMod: exits 0; " plain.stderr))
              (assert (= interp.exitCode 0) (str "stressMod: asl-host run exits 0; " interp.stderr))
              (assert (= (sameRun "stressMod without arguments" work "" "stressMod" "").stdout interp.stdout) "stressMod: native output equals asl-host run's")))
        (sameRun "stressMod under ASL_GC_STRESS=1" work "ASL_GC_STRESS=1 " "stressMod" " x y")
        (sameRun "stressMod under ASL_GC_STRESS=1 ASL_GC_VERIFY=1" work "ASL_GC_STRESS=1 ASL_GC_VERIFY=1 " "stressMod" " x y")
        (sameStats "stressMod" work "" "stressMod" " x y" (allocKeys))
        (sameStats "stressMod under ASL_GC_STRESS=1" work "ASL_GC_STRESS=1 " "stressMod" " x y" (stressKeys))
        (map (fn [(env String)] -> Bool
               (let [(c (sameRun (str "allocSmall under " env) work env "allocSmall" ""))]
                 (do (assert (!= c.exitCode 0) (str "allocSmall under " env ": the setting is refused"))
                     (assert (stringStartsWith? c.stderr "ERR_") (str "allocSmall under " env ": an ERR_ line; " c.stderr))
                     true)))
             (list "ASL_GC_GROWTH=abc " "ASL_GC_GROWTH=0.1 " "ASL_GC_MIN_MIB=x " "ASL_GC_MAX_MIB=-3 " "ASL_GC_MAX_MIB=99999999999999999999 "))
        true))

fn ! testCap work: String -> Bool
  (let [(oomSrc (buildLl work "floorOom" (floorSource "1000000")))
        (fitsSrc (buildLl work "floorFits" (floorSource "1000")))]
    (do (linkBoth work "floorOom" (str work "/floorOom.ll"))
        (linkBoth work "floorFits" (str work "/floorFits.ll"))
        (let [(fits (sameRun "floorFits under ASL_GC_MAX_MIB=8" work "ASL_GC_MAX_MIB=8 " "floorFits" ""))
              (oom (sameRun "floorOom under ASL_GC_MAX_MIB=8" work "ASL_GC_MAX_MIB=8 " "floorOom" ""))
              (interp (sh (str "ASL_GC_MAX_MIB=8 " (host) " run " oomSrc)))
              (want (hostErrorLine interp))]
          (do (assert (= fits.exitCode 0) (str "floorFits: fits the cap; " fits.stderr))
              (assert (= fits.stdout (sh (str (host) " run " fitsSrc)).stdout) "floorFits: output equals asl-host run's")
              (assert (stringStartsWith? want "ERR_OOM: ") (str "floorOom: asl-host run reports ERR_OOM; got " want))
              (assert (= oom.exitCode interp.exitCode) (str "floorOom: exit " oom.exitCode " equals asl-host run's " interp.exitCode))
              (assert (= oom.stderr (str want "\n")) (str "floorOom: stderr is asl-host run's error line " want "; got " oom.stderr))
              (assert (= oom.stdout "") (str "floorOom: prints nothing before the error; got " oom.stdout))
              true))))

fn guardIr -> String
  (stringJoin (list
    "declare void @asl_rt_init()"
    "declare ptr @asl_alloc(i32, i64)"
    "declare ptr @asl_alloc_cons()"
    "declare void @asl_gc_collect()"
    "declare void @asl_gc_root_push(ptr)"
    "declare void @gcFloorFail(ptr, ptr, ...)"
    "declare i32 @setjmp(ptr) returns_twice"
    "declare void @longjmp(ptr, i32) noreturn"
    "declare i32 @snprintf(ptr, i64, ptr, ...)"
    "declare i32 @printf(ptr, ...)"
    "@gcFloorGuard = external global ptr"
    "@gcFloorRaise = external global ptr"
    "@gcExternalRoots = external global ptr"
    "@cur = internal global ptr null"
    "@stage = internal global i32 0"
    "@count = internal global i64 0"
    "@oldRoots = internal global ptr null"
    "@cell = internal global ptr null"
    "@rootVal = internal global { i64, i64 } zeroinitializer"
    "@buf = internal global [4096 x i8] zeroinitializer"
    "@guard = internal constant { ptr, ptr, ptr, ptr, i64 } { ptr @hget, ptr @hset, ptr @rethrow, ptr @buf, i64 4096 }"
    "@code = private constant [11 x i8] c\"ERR_ASSERT\\00\""
    "@finMsg = private constant [17 x i8] c\"finalizer raised\\00\""
    "@rootMsg = private constant [17 x i8] c\"root hook raised\\00\""
    "@fmtRaise = private constant [7 x i8] c\"%s: %s\\00\""
    "@fmtCaught = private constant [21 x i8] c\"stage %d caught: %s\\0A\\00\""
    "@fmtNone = private constant [19 x i8] c\"stage %d no raise\\0A\\00\""
    "@fmtEnd = private constant [70 x i8] c\"finalizer calls %lld, mark after abort %d, after collect %d, type %d\\0A\\00\""
    "define internal ptr @hget() {"
    "  %c = load ptr, ptr @cur"
    "  ret ptr %c"
    "}"
    "define internal void @hset(ptr %j) {"
    "  store ptr %j, ptr @cur"
    "  ret void"
    "}"
    "define internal void @rethrow() noreturn {"
    "  %c = load ptr, ptr @cur"
    "  call void @longjmp(ptr %c, i32 1)"
    "  unreachable"
    "}"
    "define internal void @raise(ptr %code, ptr %msg) noreturn {"
    "  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr @buf, i64 4096, ptr @fmtRaise, ptr %code, ptr %msg)"
    "  call void @rethrow()"
    "  unreachable"
    "}"
    "define internal void @finRaise(ptr %p) {"
    "  %c = load i64, ptr @count"
    "  %c1 = add i64 %c, 1"
    "  store i64 %c1, ptr @count"
    "  call void (ptr, ptr, ...) @gcFloorFail(ptr @code, ptr @finMsg)"
    "  ret void"
    "}"
    "define internal void @markThenRaise(ptr %mark) {"
    "  %v = load { i64, i64 }, ptr @rootVal"
    "  call void %mark({ i64, i64 } %v)"
    "  call void (ptr, ptr, ...) @gcFloorFail(ptr @code, ptr @rootMsg)"
    "  ret void"
    "}"
    "define internal void @make(i32 %n) noinline {"
    "entry:"
    "  br label %loop"
    "loop:"
    "  %i = phi i32 [ 0, %entry ], [ %i1, %body ]"
    "  %more = icmp slt i32 %i, %n"
    "  br i1 %more, label %body, label %done"
    "body:"
    "  %h = call ptr @asl_alloc(i32 7, i64 32)"
    "  %fp = getelementptr inbounds i8, ptr %h, i64 24"
    "  store ptr @finRaise, ptr %fp"
    "  %i1 = add i32 %i, 1"
    "  br label %loop"
    "done:"
    "  ret void"
    "}"
    "define internal void @makeCell() noinline {"
    "  %c = call ptr @asl_alloc_cons()"
    "  %inner = call ptr @asl_alloc_cons()"
    "  %ic = getelementptr inbounds i8, ptr %inner, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %ic"
    "  %icd = getelementptr inbounds i8, ptr %inner, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %icd"
    "  %car = getelementptr inbounds i8, ptr %c, i64 8"
    "  %ii = ptrtoint ptr %inner to i64"
    "  %v0 = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %ii, 1"
    "  store { i64, i64 } %v0, ptr %car"
    "  %cdr = getelementptr inbounds i8, ptr %c, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %cdr"
    "  %ci = ptrtoint ptr %c to i64"
    "  %v = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %ci, 1"
    "  store { i64, i64 } %v, ptr @rootVal"
    "  store ptr %inner, ptr @cell"
    "  call void @asl_gc_root_push(ptr @rootVal)"
    "  ret void"
    "}"
    "define i32 @main() {"
    "entry:"
    "  %top = alloca [128 x i64], align 16"
    "  call void @asl_rt_init()"
    "  store ptr @guard, ptr @gcFloorGuard"
    "  store ptr @raise, ptr @gcFloorRaise"
    "  br label %arm"
    "arm:"
    "  store ptr %top, ptr @cur"
    "  %r = call i32 @setjmp(ptr %top)"
    "  %s = load i32, ptr @stage"
    "  %z = icmp eq i32 %r, 0"
    "  br i1 %z, label %dispatch, label %caught"
    "caught:"
    "  %p1 = call i32 (ptr, ...) @printf(ptr @fmtCaught, i32 %s, ptr @buf)"
    "  %s1 = add i32 %s, 1"
    "  store i32 %s1, ptr @stage"
    "  br label %arm"
    "dispatch:"
    "  switch i32 %s, label %end [ i32 0, label %fin"
    "                              i32 1, label %roots ]"
    "fin:"
    "  call void @make(i32 64)"
    "  call void @asl_gc_collect()"
    "  %p2 = call i32 (ptr, ...) @printf(ptr @fmtNone, i32 0)"
    "  store i32 1, ptr @stage"
    "  br label %arm"
    "roots:"
    "  call void @makeCell()"
    "  %old = load ptr, ptr @gcExternalRoots"
    "  store ptr %old, ptr @oldRoots"
    "  store ptr @markThenRaise, ptr @gcExternalRoots"
    "  call void @asl_gc_collect()"
    "  %p3 = call i32 (ptr, ...) @printf(ptr @fmtNone, i32 1)"
    "  store i32 2, ptr @stage"
    "  br label %arm"
    "end:"
    "  %o = load ptr, ptr @oldRoots"
    "  store ptr %o, ptr @gcExternalRoots"
    "  %cl = load ptr, ptr @cell"
    "  %mp = getelementptr inbounds i8, ptr %cl, i64 5"
    "  %m = load i8, ptr %mp"
    "  %m32 = zext i8 %m to i32"
    "  call void @asl_gc_collect()"
    "  %m2 = load i8, ptr %mp"
    "  %m232 = zext i8 %m2 to i32"
    "  %cnt = load i64, ptr @count"
    "  %ty = getelementptr inbounds i8, ptr %cl, i64 4"
    "  %t = load i8, ptr %ty"
    "  %t32 = zext i8 %t to i32"
    "  %p4 = call i32 (ptr, ...) @printf(ptr @fmtEnd, i64 %cnt, i32 %m32, i32 %m232, i32 %t32)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn shapeIr -> String
  (stringJoin (list
    "declare void @asl_rt_init()"
    "declare ptr @asl_alloc_cons()"
    "declare void @asl_gc_collect()"
    "declare void @asl_gc_root_push(ptr)"
    "declare i32 @puts(ptr)"
    "@rootVal = internal global { i64, i64 } zeroinitializer"
    "@done = private constant [10 x i8] c\"collected\\00\""
    "define internal i64 @consOf(ptr %car, i64 %next) noinline {"
    "  %c = call ptr @asl_alloc_cons()"
    "  %a = getelementptr inbounds i8, ptr %c, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %a"
    "  %d = getelementptr inbounds i8, ptr %c, i64 24"
    "  %v = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %next, 1"
    "  %isNil = icmp eq i64 %next, 0"
    "  %val = select i1 %isNil, { i64, i64 } zeroinitializer, { i64, i64 } %v"
    "  store { i64, i64 } %val, ptr %d"
    "  %ci = ptrtoint ptr %c to i64"
    "  ret i64 %ci"
    "}"
    "define i32 @main(i32 %argc, ptr %argv) {"
    "entry:"
    "  call void @asl_rt_init()"
    "  call void @asl_gc_root_push(ptr @rootVal)"
    "  %deep = icmp sgt i32 %argc, 1"
    "  br i1 %deep, label %build, label %cycle"
    "cycle:"
    "  %a = call i64 @consOf(ptr null, i64 0)"
    "  %b = call i64 @consOf(ptr null, i64 %a)"
    "  %ap = inttoptr i64 %a to ptr"
    "  %ad = getelementptr inbounds i8, ptr %ap, i64 24"
    "  %bv = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %b, 1"
    "  store { i64, i64 } %bv, ptr %ad"
    "  store { i64, i64 } %bv, ptr @rootVal"
    "  br label %collect"
    "build:"
    "  br label %loop"
    "loop:"
    "  %i = phi i64 [ 0, %build ], [ %i1, %loop ]"
    "  %h = phi i64 [ 0, %build ], [ %n, %loop ]"
    "  %n = call i64 @consOf(ptr null, i64 %h)"
    "  %nv = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %n, 1"
    "  store { i64, i64 } %nv, ptr @rootVal"
    "  %i1 = add i64 %i, 1"
    "  %more = icmp slt i64 %i1, 2000000"
    "  br i1 %more, label %loop, label %collect"
    "collect:"
    "  call void @asl_gc_collect()"
    "  %p = call i32 @puts(ptr @done)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn churnIr -> String
  (stringJoin (list
    "declare void @asl_rt_init()"
    "declare ptr @asl_alloc_cons()"
    "declare void @asl_gc_root_push(ptr)"
    "declare i32 @printf(ptr, ...)"
    "@rootVal = internal global { i64, i64 } zeroinitializer"
    "@fmt = private constant [17 x i8] c\"kept %lld cells\\0A\\00\""
    "define internal void @step(i64 %i) noinline {"
    "  %c = call ptr @asl_alloc_cons()"
    "  %a = getelementptr inbounds i8, ptr %c, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %a"
    "  %d = getelementptr inbounds i8, ptr %c, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %d"
    "  %r = urem i64 %i, 10"
    "  %keep = icmp eq i64 %r, 0"
    "  br i1 %keep, label %link, label %done"
    "link:"
    "  %head = load { i64, i64 }, ptr @rootVal"
    "  store { i64, i64 } %head, ptr %d"
    "  %ci = ptrtoint ptr %c to i64"
    "  %v = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %ci, 1"
    "  store { i64, i64 } %v, ptr @rootVal"
    "  br label %done"
    "done:"
    "  ret void"
    "}"
    "define i32 @main() {"
    "entry:"
    "  call void @asl_rt_init()"
    "  call void @asl_gc_root_push(ptr @rootVal)"
    "  br label %loop"
    "loop:"
    "  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]"
    "  call void @step(i64 %i)"
    "  %i1 = add i64 %i, 1"
    "  %more = icmp slt i64 %i1, 3000000"
    "  br i1 %more, label %loop, label %end"
    "end:"
    "  %n = udiv i64 3000000, 10"
    "  %p = call i32 (ptr, ...) @printf(ptr @fmt, i64 %n)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn ! testChurn work: String -> Bool
  (do (assert (ok? (fileWrite (str work "/churn.ll") (churnIr))) "churn: IR written")
      (linkBoth work "churn" (str work "/churn.ll " (floorIr work)))
      (assert (= (sameRun "churn" work "" "churn" "").exitCode 0) "churn: exits 0")
      (map (fn [(env String)] -> Bool (sameStats (str "churn under " env) work env "churn" "" (policyKeys)))
           (list "" "ASL_GC_GROWTH=1.5 ASL_GC_MIN_MIB=1 " "ASL_GC_GROWTH=4 ASL_GC_MIN_MIB=2 " "ASL_GC_GROWTH=0.25 ASL_GC_MIN_MIB=1 " "ASL_GC_MAX_MIB=12 "))
      true)

fn ! testIr work: String -> Bool
  (do (assert (ok? (fileWrite (str work "/guard.ll") (guardIr))) "guard: IR written")
      (assert (ok? (fileWrite (str work "/shape.ll") (shapeIr))) "shape: IR written")
      (linkBoth work "guard" (str work "/guard.ll " (floorIr work)))
      (linkBoth work "shape" (str work "/shape.ll " (floorIr work)))
      (let [(guarded (sameRun "guard" work "" "guard" ""))
            (lines (stringLines guarded.stdout))]
        (do (assert (= guarded.exitCode 0) (str "guard: exits 0; " guarded.stderr))
            (assert (listContains? lines "stage 0 caught: ERR_ASSERT: finalizer raised") (str "guard: the finalizer's raise reaches the guard; " guarded.stdout))
            (assert (listContains? lines "stage 1 caught: ERR_ASSERT: root hook raised") (str "guard: the roots hook's raise reaches the guard; " guarded.stdout))
            true))
      (sameRun "guard under ASL_GC_STRESS=1" work "ASL_GC_STRESS=1 " "guard" "")
      (sameRun "guard under ASL_GC_VERIFY=1" work "ASL_GC_VERIFY=1 " "guard" "")
      (let [(cycle (sameRun "cycle under ASL_GC_VERIFY=1" work "ASL_GC_VERIFY=1 " "shape" ""))
            (deep (sameRun "deep list under ASL_GC_VERIFY=1" work "ASL_GC_VERIFY=1 " "shape" " deep"))
            (plainDeep (sameRun "deep list" work "" "shape" " deep"))
            (plainCycle (sameRun "cycle" work "" "shape" ""))]
        (do (assert (= cycle.exitCode 1) (str "cycle: exit 1 under ASL_GC_VERIFY=1; " cycle.stderr))
            (assert (stringContains? cycle.stderr "ERR_HEAP_CYCLE: ") (str "cycle: ERR_HEAP_CYCLE; " cycle.stderr))
            (assert (= deep.exitCode 1) (str "deep: exit 1 under ASL_GC_VERIFY=1; " deep.stderr))
            (assert (stringStartsWith? deep.stderr "ERR_LIMIT: ") (str "deep: ERR_LIMIT; " deep.stderr))
            (assert (= plainDeep.exitCode 0) (str "deep: collects without verification; " plainDeep.stderr))
            (assert (= plainCycle.exitCode 0) (str "cycle: collects without verification; " plainCycle.stderr))
            true))
      true)

fn timeWord text: String key: String -> String
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l (str key " "))) (stringLines text))) ""))]
    (stringTrim (optionOr (stringSlice line (+ (stringLength key) 1) (stringLength line)) "")))

fn rssBytes text: String -> Int64
  (let [(darwin (filter (fn [(l String)] -> Bool (stringContains? l "maximum resident set size")) (stringLines text)))
        (linux (filter (fn [(l String)] -> Bool (stringContains? l "Maximum resident set size (kbytes):")) (stringLines text)))]
    (cond
      ((not (listEmpty? darwin)) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (stringTrim (optionOr (listHead darwin) "")) " ")) "")) -1))
      ((not (listEmpty? linux)) (* 1024 (optionOr (stringToInt64 (stringTrim (optionOr (listLast (stringSplit (optionOr (listHead linux) "") ":")) ""))) -1)))
      (else -1)))

fn seconds text: String key: String -> Float64
  (optionOr (stringToFloat64 (timeWord text key)) -1.0)

fn perfRow side: String err: String -> String
  (str ":" side " (:wallS " (timeWord err "real") " :userS " (timeWord err "user") " :sysS " (timeWord err "sys") " :gcNs " (statOf (statsPairs (statLineOf err)) "totalGCNs")
       " :collections " (statOf (statsPairs (statLineOf err)) "collections") " :rssBytes " (stringFromInt64 (rssBytes err)) ")")

fn statLineOf text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringLines text))) "")

fn ! perfRound work: String src: String flag: String round: Int64 -> (Pair String String)
  (let [(tag (stringFromInt64 round))
        (one (fn [(side String)] -> String (str "ASL_GC_STATS=1 /usr/bin/time -p " flag " " work "/" side "/asl1 build " src " -o " work "/" side tag ".ll > " work "/" side tag ".out 2> " work "/" side tag ".err")))
        (runs (sh (str "(" (one "gcc") ") & g=$!; (" (one "asl") ") & a=$!; wait $g; ge=$?; wait $a; ae=$?; test $ge -eq 0 && test $ae -eq 0")))
        (same (sh (str "cmp " work "/gcc" tag ".ll " work "/asl" tag ".ll")))
        (gErr (resultOr (fileReadString (str work "/gcc" tag ".err")) ""))
        (aErr (resultOr (fileReadString (str work "/asl" tag ".err")) ""))]
    (do (println (str "(:gcPerfRound :round " tag " " (perfRow "gcc" gErr) " " (perfRow "asl" aErr) " :phases "
                      (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcPhases ")) (stringLines aErr))) "()") ")"))
        (assert (= runs.exitCode 0) (str "perf round " tag ": both self-compiles exit 0; gc.c " gErr " ASL " aErr))
        (assert (= same.exitCode 0) (str "perf round " tag ": the two self-compiles write byte-identical IR; " same.stdout))
        (pair gErr aErr)))

fn median xs: (List Float64) -> Float64
  (optionOr (listGet (listSort xs) (/ (listLength xs) 2)) -1.0)

fn gcSeconds err: String -> Float64
  (/ (int64ToFloat64 (optionOr (stringToInt64 (statOf (statsPairs (statLineOf err)) "totalGCNs")) -1)) 1000000000.0)

fn sideMedians errs: (List String) -> String
  (str "(:wallS " (stringFromFloat64 (median (map (fn [(e String)] -> Float64 (seconds e "real")) errs)))
       " :sysS " (stringFromFloat64 (median (map (fn [(e String)] -> Float64 (seconds e "sys")) errs)))
       " :gcS " (stringFromFloat64 (median (map gcSeconds errs)))
       " :rssBytes " (stringFromFloat64 (median (map rssOf errs))) ")")

fn rssOf err: String -> Float64
  (int64ToFloat64 (rssBytes err))

fn ! testPerf work: String -> Bool
  (let [(ll (str work "/asl1.ll"))
        (src "asl/packages/asl-compiler/src/asl1.asl")
        (lowered (sh (str (host) " run " src " build " src " -o " ll)))
        (c (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " -x none " work "/gc.o " (gcLib) " -lm -o " work "/gcc/asl1")))
        (a (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " -x none " (gcLib) " -lm -o " work "/asl/asl1")))
        (flag (if (stringContains? (sh "uname -s").stdout "Darwin") "-l" "-v"))]
    (do (assert (= lowered.exitCode 0) (str "perf: asl-host lowers asl1; " lowered.stderr))
        (assert (= c.exitCode 0) (str "perf: asl1 links with gc.o; " c.stderr))
        (assert (= a.exitCode 0) (str "perf: asl1 links against libaslrt.a; " a.stderr))
        (let [(rounds (map (fn [(i Int64)] -> (Pair String String) (perfRound work src flag i)) (range 0 (perfRounds))))
              (g (map (fn [(r (Pair String String))] -> String (pairFirst r)) rounds))
              (s (map (fn [(r (Pair String String))] -> String (pairSecond r)) rounds))
              (line (str "(:gcPerf :method \"asl1 build asl1.asl, both links side by side, ASL_GC_STATS=1 /usr/bin/time -p " flag ", median of " (stringFromInt64 (perfRounds)) " rounds\" :gcc "
                         (sideMedians g) " :asl " (sideMedians s) ")"))
              (gGc (median (map gcSeconds g)))
              (aGc (median (map gcSeconds s)))]
          (do (println line)
              (assert (and (> gGc 0.0) (> aGc 0.0)) (str "perf: both print totalGCNs; " line))
              (assert (> (median (map rssOf g)) 0.0) (str "perf: /usr/bin/time reports peak RSS; " line))
              (assert (<= (median (map (fn [(e String)] -> Float64 (seconds e "sys")) s)) 3.0) (str "perf: ASL collector sys time at most 3 s; " line))
              (assert (<= aGc (* 1.10 gGc)) (str "perf: ASL collector GC time at most 1.10x gc.c's; " line))
              (assert (<= (median (map (fn [(e String)] -> Float64 (seconds e "real")) s)) (* 1.05 (median (map (fn [(e String)] -> Float64 (seconds e "real")) g))))
                      (str "perf: ASL collector wall time at most 1.05x gc.c's; " line))
              (assert (<= (median (map rssOf s)) (* 1.15 (median (map rssOf g)))) (str "perf: ASL collector peak RSS at most 1.15x gc.c's; " line))
              true))
        true))

fn perfRounds -> Int64
  3

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (= (sh (str "mkdir -p " work "/gcc " work "/asl")).exitCode 0) "gcc and asl output directories made")
        (let [(built (sh "sh asl/host/build.sh"))]
          (assert (= built.exitCode 0) (str "host libraries build; " built.stderr)))
        (testArchive work)
        (let [(taken (sh (str "ar p " (hostLib) " gc.o > " work "/gc.o")))]
          (assert (= taken.exitCode 0) (str "gc.o taken from libaslhost.a; " taken.stderr)))
        (testReference work)
        (testPrograms work)
        (testHeavy work)
        (testChurn work)
        (testCap work)
        (testIr work)
        (if (= (optionOr (envGet "ASL_GC_PERF") "") "1") (testPerf work) true)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
