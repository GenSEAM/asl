(module asl-target-llvm/tests/gcSweepTest
  :x [runTests]
  :i [(asl-target-llvm/ssa :a ssa)])

fn lib -> String
  "asl/host/out/libaslrt.a"

fn hostLib -> String
  "asl/host/out/libaslhost.a"

fn clangLink -> String
  "/usr/bin/clang -Wno-override-module -x ir "

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn consHeaderHex -> String
  "300000100000028"

fn deadIr -> String
  (stringJoin (list
    "declare void @asl_rt_init()"
    "declare ptr @asl_alloc_cons()"
    "declare void @asl_gc_collect()"
    "declare void @asl_gc_root_push(ptr)"
    "declare ptr @gcFindObj(i64)"
    "declare i32 @printf(ptr, ...)"
    "@keepVal = internal global { i64, i64 } zeroinitializer"
    "@deadAddr = internal global i64 0"
    "@fmt = private constant [39 x i8] c\"header %llx found %d kept %d reuse %d\\0A\\00\""
    "define internal void @make() noinline {"
    "  %b = call ptr @asl_alloc_cons()"
    "  %ba = getelementptr inbounds i8, ptr %b, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %ba"
    "  %bd = getelementptr inbounds i8, ptr %b, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %bd"
    "  %bi = ptrtoint ptr %b to i64"
    "  %bv = insertvalue { i64, i64 } { i64 6, i64 0 }, i64 %bi, 1"
    "  store { i64, i64 } %bv, ptr @keepVal"
    "  %a = call ptr @asl_alloc_cons()"
    "  %aa = getelementptr inbounds i8, ptr %a, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %aa"
    "  %ad = getelementptr inbounds i8, ptr %a, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %ad"
    "  %ai = ptrtoint ptr %a to i64"
    "  %x = xor i64 %ai, 6148914691236517205"
    "  store i64 %x, ptr @deadAddr"
    "  ret void"
    "}"
    "define i32 @main() {"
    "entry:"
    "  call void @asl_rt_init()"
    "  call void @asl_gc_root_push(ptr @keepVal)"
    "  call void @make()"
    "  call void @asl_gc_collect()"
    "  %x = load i64, ptr @deadAddr"
    "  %ai = xor i64 %x, 6148914691236517205"
    "  %ap = inttoptr i64 %ai to ptr"
    "  %h = load i64, ptr %ap"
    "  %f = call ptr @gcFindObj(i64 %ai)"
    "  %found = icmp ne ptr %f, null"
    "  %fz = zext i1 %found to i32"
    "  %kv = load { i64, i64 }, ptr @keepVal"
    "  %bi = extractvalue { i64, i64 } %kv, 1"
    "  %kf = call ptr @gcFindObj(i64 %bi)"
    "  %kept = icmp ne ptr %kf, null"
    "  %kz = zext i1 %kept to i32"
    "  %c = call ptr @asl_alloc_cons()"
    "  %same = icmp eq ptr %c, %ap"
    "  %sz = zext i1 %same to i32"
    "  %p = call i32 (ptr, ...) @printf(ptr @fmt, i64 %h, i32 %fz, i32 %kz, i32 %sz)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn sparseIr -> String
  (stringJoin (list
    "declare void @asl_rt_init()"
    "declare ptr @asl_alloc_cons()"
    "declare void @asl_gc_root_push(ptr)"
    "declare i32 @printf(ptr, ...)"
    "@rootVal = internal global { i64, i64 } zeroinitializer"
    "@fmt = private constant [9 x i8] c\"done %d\\0A\\00\""
    "define internal void @step(i64 %i) noinline {"
    "  %c = call ptr @asl_alloc_cons()"
    "  %a = getelementptr inbounds i8, ptr %c, i64 8"
    "  store { i64, i64 } zeroinitializer, ptr %a"
    "  %d = getelementptr inbounds i8, ptr %c, i64 24"
    "  store { i64, i64 } zeroinitializer, ptr %d"
    "  %w = urem i64 %i, 65536"
    "  %wipe = icmp eq i64 %w, 0"
    "  br i1 %wipe, label %reset, label %check"
    "reset:"
    "  store { i64, i64 } zeroinitializer, ptr @rootVal"
    "  br label %check"
    "check:"
    "  %r = urem i64 %i, 64"
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
    "  %more = icmp slt i64 %i1, 20000000"
    "  br i1 %more, label %loop, label %end"
    "end:"
    "  %p = call i32 (ptr, ...) @printf(ptr @fmt, i32 1)"
    "  ret i32 0"
    "}"
    "")
    "\n")

fn fieldsOf line: String prefix: String -> (List (Pair String String))
  (map (fn [(field String)] -> (Pair String String)
         (let [(kv (stringSplit (stringTrim field) " "))]
           (pair (optionOr (listHead kv) "") (optionOr (listLast kv) ""))))
       (filter (fn [(field String)] -> Bool (not (stringEmpty? (stringTrim field))))
               (stringSplit (stringReplace (stringReplace line prefix "") ")" "") ":")))

fn lineOf text: String prefix: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l prefix)) (stringLines text))) "")

fn numOf pairs: (List (Pair String String)) key: String -> Int64
  (optionOr (stringToInt64 (optionOr (mapGet (mapFromPairs pairs) key) "")) -1)

fn policyStats line: String -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p)))
                   (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) "totalGCNs")) (fieldsOf line "(:gcStats ")))
              " ")

fn ! linkBoth work: String name: String -> Bool
  (let [(ll (str work "/" name ".ll " work "/floor.ll"))
        (a (sh (str (clangLink) ll " -x none " (lib) " -lm -o " work "/asl/" name)))
        (c (sh (str (clangLink) ll " -x none " work "/gc.o " work "/rtNoGc.a -lm -o " work "/gcc/" name)))]
    (do (assert (= a.exitCode 0) (str name ": links against libaslrt.a; " a.stderr))
        (assert (= c.exitCode 0) (str name ": links against gc.o and libaslrt.a without gcAsl.o; " c.stderr))
        true))

fn ! testDeadSlot work: String -> Bool
  (do (assert (ok? (fileWrite (str work "/dead.ll") (deadIr))) "dead: IR written")
      (linkBoth work "dead")
      (let [(want (str "header " (consHeaderHex) " found 0 kept 1 reuse 1\n"))
            (plain (sh (str "cd " work "/asl && ./dead")))
            (stressed (sh (str "cd " work "/asl && ASL_GC_STRESS=1 ./dead")))
            (verified (sh (str "cd " work "/asl && ASL_GC_VERIFY=1 ./dead")))
            (floor (sh (str "cd " work "/gcc && ./dead")))]
        (do (assert (= plain.exitCode 0) (str "dead: exits 0; " plain.stderr))
            (assert (= plain.stdout want) (str "dead: the swept page keeps the dead cons header intact, the kept cons alive and the dead slot is the next cons; got " plain.stdout))
            (assert (= stressed.stdout want) (str "dead: same under ASL_GC_STRESS=1; got " stressed.stdout stressed.stderr))
            (assert (= verified.stdout want) (str "dead: same under ASL_GC_VERIFY=1; got " verified.stdout verified.stderr))
            (assert (= floor.stdout "header 0 found 0 kept 1 reuse 1\n") (str "dead: gc.c threads its free list through the dead slot; got " floor.stdout))
            true)))

fn ! testSteadyPages work: String -> Bool
  (do (assert (ok? (fileWrite (str work "/sparse.ll") (sparseIr))) "sparse: IR written")
      (linkBoth work "sparse")
      (map (fn [(env String)] -> Bool
             (let [(a (sh (str "cd " work "/asl && ASL_GC_STATS=1 " env "./sparse")))
                   (c (sh (str "cd " work "/gcc && ASL_GC_STATS=1 " env "./sparse")))
                   (stats (fieldsOf (lineOf a.stderr "(:gcStats ") "(:gcStats "))
                   (phases (fieldsOf (lineOf a.stderr "(:gcPhases ") "(:gcPhases "))
                   (label (str "sparse under '" env "'"))]
               (do (assert (= a.exitCode 0) (str label ": exits 0; " a.stderr))
                   (assert (= a.stdout "done 1\n") (str label ": prints done; got " a.stdout))
                   (assert (>= (numOf stats "collections") 50) (str label ": at least 50 collections; " (lineOf a.stderr "(:gcStats ")))
                   (assert (= (numOf phases "pagesUnmapped") 0) (str label ": the page cache keeps a cycle's pages, none unmapped; " (lineOf a.stderr "(:gcPhases ")))
                   (assert (= (numOf phases "unmapCalls") 0) (str label ": no munmap call; " (lineOf a.stderr "(:gcPhases ")))
                   (assert (<= (numOf phases "pagesMapped") 640) (str label ": at most 640 pages mapped in steady state; " (lineOf a.stderr "(:gcPhases ")))
                   (assert (= (policyStats (lineOf a.stderr "(:gcStats ")) (policyStats (lineOf c.stderr "(:gcStats "))) (str label ": stats equal gc.c's but totalGCNs; ASL " (lineOf a.stderr "(:gcStats ") " gc.c " (lineOf c.stderr "(:gcStats ")))
                   true)))
           (list "ASL_GC_MIN_MIB=8 " "ASL_GC_GROWTH=1.5 ASL_GC_MIN_MIB=4 "))
      true)

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (= (sh (str "mkdir -p " work "/gcc " work "/asl")).exitCode 0) "gcc and asl output directories made")
        (assert (= (sh "sh asl/host/build.sh").exitCode 0) "host libraries build")
        (assert (ok? (fileWrite (str work "/floor.ll") (ssa/cRuntimeModule))) "floor.ll: the C floor's IR written")
        (assert (= (sh (str "ar p " (hostLib) " gc.o > " work "/gc.o")).exitCode 0) "gc.o taken from libaslhost.a")
        (assert (= (sh (str "cp " (lib) " " work "/rtNoGc.a && ar d " work "/rtNoGc.a gcAsl.o")).exitCode 0) "libaslrt.a copied without gcAsl.o")
        (testDeadSlot work)
        (testSteadyPages work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
