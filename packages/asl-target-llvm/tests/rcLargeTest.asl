(module asl-target-llvm/tests/rcLargeTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

; (:m :ref RC-LARGE-RECYCLE-GUARD :do "a probe main replaces the fixture's main and hands recycleSlow synthetic headers: a large non-Handle under the traced runtime must not run its data word as a finaliser, a large Handle runs fin once, and a class past the free-list array traps instead of indexing it")
fn largeHeader ty: Int64 -> Int64
  (+ -72057594037927936 (* ty 4294967296))

fn classHeader cls: Int64 -> Int64
  (* cls 72057594037927936)

fn probeCase label: String h: Int64 fin: Bool -> (List String)
  (list (str label ":")
        (str "  store i64 " h ", ptr %o")
        (str "  store ptr " (if fin "@aslProbe.fin" "null") ", ptr %fp")
        (str "  call void @aslRc.recycleSlow(ptr %o, i64 " h ")")
        "  br label %report")

fn probeText -> String
  (stringJoin
    (listAppend
      (list "@aslProbe.hit = internal global i64 0"
            "declare i64 @gcFreedObjects()"
            "declare void @asl_gc_collect()"
            "define internal i32 @aslProbe.sweep(i32 %argc, ptr %argv) {"
            "entry:"
            "  call void @asl_rt_init()"
            "  %keep = alloca [64 x ptr], align 16"
            "  br label %loop"
            "loop:"
            "  %i = phi i64 [ 0, %entry ], [ %i1, %next ]"
            "  %o = call ptr @asl_alloc_raw(i32 5, i64 4096)"
            "  %h = load i64, ptr %o"
            "  %cls = lshr i64 %h, 56"
            "  %big = icmp eq i64 %cls, 255"
            "  br i1 %big, label %recycle, label %small"
            "recycle:"
            "  %slot = getelementptr [64 x ptr], ptr %keep, i64 0, i64 %i"
            "  store volatile ptr %o, ptr %slot"
            "  call void @aslRc.recycleSlow(ptr %o, i64 %h)"
            "  br label %next"
            "next:"
            "  %i1 = add i64 %i, 1"
            "  %done = icmp eq i64 %i1, 64"
            "  br i1 %done, label %collect, label %loop"
            "collect:"
            "  %f0 = call i64 @gcFreedObjects()"
            "  call void @asl_gc_collect()"
            "  %f1 = call i64 @gcFreedObjects()"
            "  %held = sub i64 %f1, %f0"
            "  %kept = icmp slt i64 %held, 8"
            "  br i1 %kept, label %drop, label %lost"
            "lost:"
            "  ret i32 6"
            "drop:"
            "  call void @llvm.memset.p0.i64(ptr %keep, i8 0, i64 512, i1 true)"
            "  call void @asl_gc_collect()"
            "  %f2 = call i64 @gcFreedObjects()"
            "  %df = sub i64 %f2, %f1"
            "  %enough = icmp sge i64 %df, 32"
            "  %code = select i1 %enough, i32 0, i32 7"
            "  ret i32 %code"
            "small:"
            "  ret i32 9"
            "}"
            "define internal void @aslProbe.fin(ptr %a) {"
            "entry:"
            "  %v = load i64, ptr @aslProbe.hit"
            "  %v1 = add i64 %v, 1"
            "  store i64 %v1, ptr @aslProbe.hit"
            "  ret void"
            "}"
            "define i32 @main(i32 %argc, ptr %argv) {"
            "entry:"
            "  %o = call ptr @malloc(i64 64)"
            "  %dp = getelementptr inbounds i8, ptr %o, i64 16"
            "  store ptr null, ptr %dp"
            "  %fp = getelementptr inbounds i8, ptr %o, i64 24"
            "  switch i32 %argc, label %array [ i32 2, label %handle\n    i32 3, label %range\n    i32 4, label %sweep ]"
            "sweep:"
            "  %sr = call i32 @asl_rt_main(ptr @aslProbe.sweep, i32 %argc, ptr %argv)"
            "  ret i32 %sr")
      (listAppend (probeCase "array" (largeHeader 6) true)
        (listAppend (probeCase "handle" (largeHeader 7) true)
          (listAppend (probeCase "range" (classHeader 100) false)
            (list "report:"
                  "  %hit = load i64, ptr @aslProbe.hit"
                  "  %h = load i64, ptr %o"
                  "  %c = lshr i64 %h, 48"
                  "  %c8 = and i64 %c, 255"
                  "  %stuck = icmp eq i64 %c8, 255"
                  "  %ns = select i1 %stuck, i64 0, i64 1"
                  "  %h10 = mul i64 %hit, 10"
                  "  %code = add i64 %h10, %ns"
                  "  %r = trunc i64 %code to i32"
                  "  ret i32 %r"
                  "}"))))) "\n")

fn ! buildExe! libs: rc/Libs dir: String name: String mode: String probe: Bool -> (Result String String)
  (match (lk/linkEntry! (str "asl/packages/asl-target-llvm/tests/fixtures/rc/" name ".asl"))
    ((err ds) (err (str name " links: " (rc/diagText ds))))
    ((ok m)
     (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
       ((err ds) (err (str name " emits in mode " mode ": " (rc/diagText ds))))
       ((ok code)
        (let [(main "define i32 @main(i32 %argc, ptr %argv)")
              (text (if probe (str (stringReplace code main "define internal i32 @aslProbe.fixtureMain(i32 %argc, ptr %argv)") "\n" (probeText) "\n") code))
              (tag (if probe "probe" "run"))
              (ll (str dir "/" name "." tag "." mode ".ll"))
              (exe (str dir "/" name "." tag "." mode))]
          (if (and probe (not (stringContains? code main)))
            (err (str name " " mode ": no main to replace"))
            (match (fileWrite ll text)
              ((err e) (err (str "cannot write " ll ": " e)))
              ((ok _)
               (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                 (if (!= linked.exitCode 0) (err (str name " " mode " links: " linked.stderr)) (ok exe)))))))))))

; (:m :ref RC-LARGE-TRAP-ARCH :do "llvm.trap lowers to brk on arm64 (SIGTRAP, exit 133) and to ud2 on x86_64 (SIGILL, exit 132); the guard is the trap itself, so the expected exit follows the host architecture, and any other exit (a plain crash 139, a clean 0) still fails")
fn ! trapExit! -> Int64
  (let [(m (rc/sh "uname -m"))]
    (if (or (stringContains? m.stdout "x86_64") (stringContains? m.stdout "amd64")) 132 133))

fn ! testProbe libs: rc/Libs dir: String mode: String -> Bool
  (match (buildExe! libs dir "rcLarge" mode true)
    ((err e) (do (assert false (str "probe build " mode ": " e)) false))
    ((ok exe)
      ; (:m :do "the untraced runtime frees a large object's data word and prefix, so the synthetic array and Handle cases run only traced")
      (let [(q (rc/shellQuote exe))
            (traced (!= mode "notrace"))
            (range (rc/sh (str q " h r")))]
        (do (if traced
              (let [(array (rc/sh q))
                    (handle (rc/sh (str q " h")))
                    (sweep (rc/sh (str q " h r s")))]
                (do (assert (= sweep.exitCode 0) (str mode ": 64 large raw objects recycled at count zero while a stack slot still holds them are marked and survive a collection (a sticky header would make mark skip them and the sweep free them while reachable), then are freed once the slots are cleared (want 0; 6 = freed while reachable, 7 = under 32 freed after the drop, 9 = not large; got " sweep.exitCode " " sweep.stderr ")"))
                    (assert (= array.exitCode 1) (str mode ": a large non-Handle reaching recycleSlow keeps its header (not stuck) and its data word is never called as a finaliser (want 1 = no fin call, not stuck; got " array.exitCode " " array.stderr ")"))
                    (assert (= handle.exitCode 10) (str mode ": a large Handle runs fin once and is stuck (want 10; got " handle.exitCode " " handle.stderr ")"))
                    true))
              true)
            (assert (= range.exitCode (trapExit!)) (str mode ": a size class past the 63-entry free list traps (llvm.trap: SIGTRAP 133 on arm64, SIGILL 132 on x86_64; want " (trapExit!) ") instead of indexing aslRc.free (got " range.exitCode " " range.stderr ")"))
            true))))

fn ! testChurn libs: rc/Libs dir: String mode: String -> Bool
  (match (buildExe! libs dir "rcLarge" mode false)
    ((err e) (do (assert false (str "churn build " mode ": " e)) false))
    ((ok exe)
      (let [(r (rc/sh (rc/shellQuote exe)))]
        (do (assert (= r.exitCode 0) (str mode ": large-array churn exits 0, ASan-clean in ASan modes: " r.stderr))
            (assert (= r.stdout "439600000\n") (str mode ": large-array churn prints its sum, got " r.stdout))
            (if (or (= mode "notraceStats") (= mode "asanNotrace"))
              (do (assert (>= (rc/statOf r.stderr "largeFreed") 2000) (str mode ": every churned array is freed through the large path: " r.stderr)) true)
              true)
            true))))

fn ! runTests -> Bool
  (match (rc/runtimes!)
    ((err e) (do (assert false (str "rcLargeTest runtimes: " e)) false))
    ((ok libs)
      (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/rcLargeTest." (procSelf) "." (monotonicNs)))
            (made (dirCreate dir))]
        (do (assert (ok? made) "rcLargeTest work directory created")
            (assert (testProbe libs dir "1") "traced counted recycleSlow: large path for large objects, trap past the free list")
            (assert (testProbe libs dir "asan") "traced ASan recycleSlow: large path for large objects, trap past the free list")
            (assert (testProbe libs dir "notrace") "untraced recycleSlow: trap past the free list")
            (assert (testChurn libs dir "1") "traced counted large-array churn")
            (assert (testChurn libs dir "asan") "traced ASan large-array churn")
            (assert (testChurn libs dir "asanNotrace") "untraced ASan large-array churn frees every array once")
            (assert (testChurn libs dir "notraceStats") "untraced large-array churn frees every array through the large path")
            (assert (= (rc/sh (str "rm -rf " (rc/shellQuote dir))) (rc/sh "true")) "rcLargeTest work directory removed")
            true))))
