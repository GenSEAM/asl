(module asl-target-llvm/rtAbi
  :x [abiText entryNames spillSlots main]
  :i [(asl-target-llvm/libc :a libc)
      (asl-target-llvm/gcRoute :a gr)])

fn entryNames -> (List String)
  (list "asl_rt_spill" "asl_rt_init" "asl_rt_main" "asl_rt_global_root" "abiGcRoots" "gcMutatorRoots")

fn spillSlots -> Int64
  1024

fn mainStackBytes -> Int64
  1073741824

fn cString name: String text: String -> String
  (str "@" name " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn keywords -> (List (Pair String String))
  (list (pair "KW_SOME" "some") (pair "KW_NONE" "none") (pair "KW_OK" "ok") (pair "KW_ERR" "err") (pair "KW_PARTIAL" "partial"))

fn dataLines -> (List String)
  (listAppend
    (list "%Val = type { i64, i64 }"
          ""
          (str "@asl_rt_spill = global [" (spillSlots) " x %Val] zeroinitializer, align 16")
          "@rtAbi.ready = internal global i32 0, align 4"
          "@rtAbi.slots = internal global ptr null, align 8"
          "@rtAbi.count = internal global i32 0, align 4"
          "@rtAbi.cap = internal global i32 0, align 4"
          "@rtAbi.stackTop = internal global ptr null, align 8"
          (cString "rtAbi.errInternal" "ERR_INTERNAL")
          (cString "rtAbi.errLimit" "ERR_LIMIT")
          (cString "rtAbi.errOom" "ERR_OOM")
          (cString "rtAbi.noStack" "cannot locate the native stack")
          "@rtAbi.mainBody = internal global ptr null, align 8"
          "@rtAbi.mainArgc = internal global i32 0, align 4"
          "@rtAbi.mainArgv = internal global ptr null, align 8"
          (cString "rtAbi.noMainThread" "cannot run main on a %lld-byte thread stack: sigfillset %d, pthread_sigmask %d, pthread_attr_init %d, pthread_attr_setstacksize %d, pthread_create %d")
          (cString "rtAbi.mainJoined" "the main thread ended without exit: pthread_join %d")
          (cString "rtAbi.noMainMask" "cannot restore the signal mask on the main thread: pthread_sigmask %d")
          (cString "rtAbi.tooMany" "more than %d global roots")
          (cString "rtAbi.noMemory" "out of memory growing the global root table to %d slots"))
    (map (fn [(k (Pair String String))] -> String (cString (str "rtAbi.kw." (pairSecond k)) (pairSecond k))) (keywords)))

fn internKeyword k: (Pair String String) -> String
  (let [(text (pairSecond k))]
    (str "  %id." text " = call i32 @aslInternShared(ptr @rtAbi.kw." text ", i64 " (stringLength text) ")\n"
         "  store i32 %id." text ", ptr @" (pairFirst k) "\n"))

fn initText -> String
  (str "define void @asl_rt_init() {\n"
       "entry:\n"
       "  %ready = load i32, ptr @rtAbi.ready\n"
       "  %done = icmp ne i32 %ready, 0\n"
       "  br i1 %done, label %out, label %init\n"
       "init:\n"
       "  call void @gcInit()\n"
       (stringJoin (map (fn [(k (Pair String String))] -> String (internKeyword k)) (keywords)) "")
       "  call void @rtAbi.locateStack()\n"
       "  store ptr @rtAbi.externalRoots, ptr @gcExternalRoots\n"
       "  store i32 1, ptr @rtAbi.ready\n"
       "  br label %out\n"
       "out:\n"
       "  ret void\n"
       "}")

; (:m :ref FLEETGUARD-NODE2-STACK :do "when only pthread_create fails (Linux counts threads against RLIMIT_NPROC, so a fork-starved or ulimit -u user gets EAGAIN) main runs on the process stack through the same mainThread entry, which restores the mask and exits; a guard must still start when tasks are exhausted. Any other setup failure stays ERR_INTERNAL")
fn mainText facts: libc/TripleFacts maskBytes: Int64 attrBytes: Int64 -> String
  (let [(thread (if (= facts.triple "darwin-arm64") "ptr" "i64"))
        (block (optionOr (libc/libcConst facts "SIG_BLOCK") 0))
        (setMask (optionOr (libc/libcConst facts "SIG_SETMASK") 0))
        (sigpipe (optionOr (libc/libcConst facts "SIGPIPE") 13))
        (sigIgn (optionOr (libc/libcConst facts "SIG_IGN") 1))]
    (stringJoin
      (list (str "@rtAbi.mainMask = internal global [" maskBytes " x i8] zeroinitializer, align 8")
            ""
            "define i32 @asl_rt_main(ptr %body, i32 %argc, ptr %argv) {"
            "entry:"
            "  store ptr %body, ptr @rtAbi.mainBody"
            "  store i32 %argc, ptr @rtAbi.mainArgc"
            "  store ptr %argv, ptr @rtAbi.mainArgv"
            (str "  %sigpipeIgnored = call ptr @signal(i32 " sigpipe ", ptr inttoptr (i64 " sigIgn " to ptr))")
            (str "  %all = alloca [" maskBytes " x i8], align 8")
            (str "  %attr = alloca [" attrBytes " x i8], align 16")
            (str "  %thread = alloca " thread ", align 8")
            "  %filled = call i32 @sigfillset(ptr %all)"
            (str "  %masked = call i32 @pthread_sigmask(i32 " block ", ptr %all, ptr @rtAbi.mainMask)")
            "  %inited = call i32 @pthread_attr_init(ptr %attr)"
            (str "  %sized = call i32 @pthread_attr_setstacksize(ptr %attr, i64 " (mainStackBytes) ")")
            "  %started = call i32 @pthread_create(ptr %thread, ptr %attr, ptr @rtAbi.mainThread, ptr null)"
            "  %destroyed = call i32 @pthread_attr_destroy(ptr %attr)"
            "  %any1 = or i32 %filled, %masked"
            "  %any2 = or i32 %any1, %inited"
            "  %any3 = or i32 %any2, %sized"
            "  %any4 = or i32 %any3, %started"
            "  %failed = icmp ne i32 %any4, 0"
            "  br i1 %failed, label %noThread, label %join"
            "join:"
            (str "  %handle = load " thread ", ptr %thread")
            (str "  %joined = call i32 @pthread_join(" thread " %handle, ptr null)")
            "  %joinedText = alloca [128 x i8], align 1"
            "  %joinedLen = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %joinedText, i64 128, ptr @rtAbi.mainJoined, i32 %joined)"
            "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errInternal, ptr %joinedText)"
            "  unreachable"
            "noThread:"
            "  %onlyCreate = icmp eq i32 %any3, 0"
            "  br i1 %onlyCreate, label %inline, label %fail"
            "inline:"
            "  %inlined = call ptr @rtAbi.mainThread(ptr null)"
            "  unreachable"
            "fail:"
            "  %noThreadText = alloca [256 x i8], align 1"
            (str "  %noThreadLen = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %noThreadText, i64 256, ptr @rtAbi.noMainThread, i64 " (mainStackBytes) ", i32 %filled, i32 %masked, i32 %inited, i32 %sized, i32 %started)")
            "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errInternal, ptr %noThreadText)"
            "  unreachable"
            "}"
            ""
            "define internal ptr @rtAbi.mainThread(ptr %unused) {"
            "entry:"
            (str "  %restored = call i32 @pthread_sigmask(i32 " setMask ", ptr @rtAbi.mainMask, ptr null)")
            "  %restoreFailed = icmp ne i32 %restored, 0"
            "  br i1 %restoreFailed, label %noMask, label %run"
            "run:"
            "  %body = load ptr, ptr @rtAbi.mainBody"
            "  %argc = load i32, ptr @rtAbi.mainArgc"
            "  %argv = load ptr, ptr @rtAbi.mainArgv"
            "  %code = call i32 %body(i32 %argc, ptr %argv)"
            "  %mainThreadFlushed = call i32 @fflush(ptr null)"
            "  call void @exit(i32 %code)"
            "  unreachable"
            "noMask:"
            "  %noMaskText = alloca [128 x i8], align 1"
            "  %noMaskLen = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %noMaskText, i64 128, ptr @rtAbi.noMainMask, i32 %restored)"
            "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errInternal, ptr %noMaskText)"
            "  unreachable"
            "}")
      "\n"))

fn mainSizes facts: libc/TripleFacts -> (Result (Pair Int64 Int64) String)
  (match (libc/structSize facts "sigset_t")
    ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no sigset_t size for " facts.triple)))
    ((some mask) (match (libc/structSize facts "pthread_attr_t")
                   ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no pthread_attr_t size for " facts.triple)))
                   ((some attr) (if (or (none? (libc/libcConst facts "SIG_BLOCK")) (none? (libc/libcConst facts "SIG_SETMASK")))
                                  (err (str "ERR_LLVM_RTABI: libc.asl has no SIG_BLOCK or SIG_SETMASK for " facts.triple))
                                  (ok (pair mask attr)))))))

fn globalRootText -> String
  (stringJoin
    (list "define void @asl_rt_global_root(ptr %slot) {"
          "entry:"
          "  %n = load i32, ptr @rtAbi.count"
          "  %cap = load i32, ptr @rtAbi.cap"
          "  %full = icmp eq i32 %n, %cap"
          "  br i1 %full, label %grow, label %put"
          "grow:"
          "  %limit = icmp sgt i32 %cap, 1073741823"
          "  br i1 %limit, label %tooMany, label %resize"
          "tooMany:"
          "  %tooManyText = alloca [128 x i8], align 1"
          "  %tooManyLen = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %tooManyText, i64 128, ptr @rtAbi.tooMany, i32 %cap)"
          "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errLimit, ptr %tooManyText)"
          "  unreachable"
          "resize:"
          "  %empty = icmp eq i32 %cap, 0"
          "  %twice = shl i32 %cap, 1"
          "  %cap1 = select i1 %empty, i32 16, i32 %twice"
          "  %cap64 = sext i32 %cap1 to i64"
          "  %bytes = shl i64 %cap64, 3"
          "  %old = load ptr, ptr @rtAbi.slots"
          "  %grown = call ptr @realloc(ptr %old, i64 %bytes)"
          "  %oom = icmp eq ptr %grown, null"
          "  br i1 %oom, label %noMemory, label %grew"
          "noMemory:"
          "  %noMemoryText = alloca [128 x i8], align 1"
          "  %noMemoryLen = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %noMemoryText, i64 128, ptr @rtAbi.noMemory, i32 %cap1)"
          "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errOom, ptr %noMemoryText)"
          "  unreachable"
          "grew:"
          "  store ptr %grown, ptr @rtAbi.slots"
          "  store i32 %cap1, ptr @rtAbi.cap"
          "  br label %put"
          "put:"
          "  %table = load ptr, ptr @rtAbi.slots"
          "  %n64 = sext i32 %n to i64"
          "  %at = getelementptr inbounds ptr, ptr %table, i64 %n64"
          "  store ptr %slot, ptr %at"
          "  %n1 = add i32 %n, 1"
          "  store i32 %n1, ptr @rtAbi.count"
          "  ret void"
          "}")
    "\n")

fn rootsText -> String
  (stringJoin
    (list "define void @abiGcRoots(ptr %mark) {"
          "entry:"
          "  br label %loop"
          "loop:"
          "  %i = phi i32 [ 0, %entry ], [ %i1, %body ]"
          "  %n = load i32, ptr @rtAbi.count"
          "  %more = icmp slt i32 %i, %n"
          "  br i1 %more, label %body, label %out"
          "body:"
          "  %table = load ptr, ptr @rtAbi.slots"
          "  %i64 = sext i32 %i to i64"
          "  %at = getelementptr inbounds ptr, ptr %table, i64 %i64"
          "  %slot = load ptr, ptr %at"
          "  %v = load %Val, ptr %slot"
          "  call void %mark(%Val %v)"
          "  %i1 = add i32 %i, 1"
          "  br label %loop"
          "out:"
          "  ret void"
          "}"
          ""
          "define weak void @gcMutatorRoots(ptr %mark) {"
          "entry:"
          "  call void @abiGcRoots(ptr %mark)"
          "  ret void"
          "}")
    "\n")

fn fakeFrameText -> String
  (stringJoin
    (list "define internal void @rtAbi.scanFakeFrames(ptr %lo, ptr %hi) noinline {"
          "entry:"
          "  %beg = alloca ptr, align 8"
          "  %end = alloca ptr, align 8"
          "  %fake = call ptr @__asan_get_current_fake_stack()"
          "  %none = icmp eq ptr %fake, null"
          "  br i1 %none, label %out, label %start"
          "start:"
          "  %l = ptrtoint ptr %lo to i64"
          "  %h = ptrtoint ptr %hi to i64"
          "  %l7 = add i64 %l, 7"
          "  %a0 = and i64 %l7, -8"
          "  br label %loop"
          "loop:"
          "  %a = phi i64 [ %a0, %start ], [ %a1, %next ]"
          "  %a1 = add i64 %a, 8"
          "  %fits = icmp ule i64 %a1, %h"
          "  br i1 %fits, label %body, label %out"
          "body:"
          "  %ap = inttoptr i64 %a to ptr"
          "  %w = load ptr, ptr %ap"
          "  store ptr null, ptr %beg"
          "  store ptr null, ptr %end"
          "  %frame = call ptr @__asan_addr_is_in_fake_stack(ptr %fake, ptr %w, ptr %beg, ptr %end)"
          "  %miss = icmp eq ptr %frame, null"
          "  br i1 %miss, label %next, label %scan"
          "scan:"
          "  %b = load ptr, ptr %beg"
          "  %e = load ptr, ptr %end"
          "  call void @gcScanConservative(ptr %b, ptr %e)"
          "  br label %next"
          "next:"
          "  br label %loop"
          "out:"
          "  ret void"
          "}")
    "\n")

fn externalRootsText asan: Bool -> String
  (stringJoin
    (list "define internal void @rtAbi.externalRoots(ptr %mark) noinline {"
          "entry:"
          "  call void @llvm.eh.unwind.init()"
          "  %lo = call ptr @llvm.stacksave.p0()"
          "  %hi = load ptr, ptr @rtAbi.stackTop"
          "  notail call void @gcScanConservative(ptr %lo, ptr %hi)"
          (if asan "  notail call void @rtAbi.scanFakeFrames(ptr %lo, ptr %hi)" "")
          "  ret void"
          "}")
    "\n")

fn stackGuardWindowBytes -> Int64
  1048576

fn stackGuardAltStackBytes -> Int64
  65536

fn stackDepthMsg -> String
  (str "ERR_STACK_DEPTH: native call stack exceeded the " (mainStackBytes) "-byte body thread stack")

fn guardConst facts: libc/TripleFacts name: String -> (Result Int64 String)
  (match (libc/libcConst facts name)
    ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no " name " constant for " facts.triple)))
    ((some n) (ok n)))

fn guardField facts: libc/TripleFacts structName: String field: String -> (Result Int64 String)
  (match (libc/pairFind facts.structs structName)
    ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no " structName " layout for " facts.triple)))
    ((some sf)
      (match (libc/structFieldOffset sf field)
        ((none) (err (str "ERR_LLVM_RTABI: libc.asl " structName " has no " field " offset for " facts.triple)))
        ((some n) (ok n)))))

fn guardSize facts: libc/TripleFacts structName: String -> (Result Int64 String)
  (match (libc/structSize facts structName)
    ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no " structName " size for " facts.triple)))
    ((some n) (ok n)))

; (:m :ref NATIVE-STACK-GUARD-LINUX :do "the guard's constants and struct offsets come from the per-triple libc table, never inline: Darwin and glibc differ in SIGBUS, SA_ONSTACK, SA_SIGINFO, stack_t field order (sp size flags vs sp flags size), sigaction mask and flags offsets and the si_addr offset; a row missing from the table is an error naming it")
fn guardLayout facts: libc/TripleFacts -> (Result (List (Pair String Int64)) String)
  (fold (fn [(acc (Result (List (Pair String Int64)) String)) (p (Pair String (Result Int64 String)))] -> (Result (List (Pair String Int64)) String)
          (match acc
            ((err e) (err e))
            ((ok done)
              (match (pairSecond p)
                ((err e) (err e))
                ((ok n) (ok (cons (pair (pairFirst p) n) done)))))))
        (ok (list))
        (list (pair "segv" (guardConst facts "SIGSEGV"))
              (pair "bus" (guardConst facts "SIGBUS"))
              (pair "onStack" (guardConst facts "SA_ONSTACK"))
              (pair "sigInfo" (guardConst facts "SA_SIGINFO"))
              (pair "stackTSize" (guardSize facts "stack_t"))
              (pair "ssSp" (guardField facts "stack_t" "ss_sp"))
              (pair "ssSize" (guardField facts "stack_t" "ss_size"))
              (pair "ssFlags" (guardField facts "stack_t" "ss_flags"))
              (pair "actionSize" (guardSize facts "sigaction"))
              (pair "saHandler" (guardField facts "sigaction" "sa_handler"))
              (pair "saMask" (guardField facts "sigaction" "sa_mask"))
              (pair "saFlags" (guardField facts "sigaction" "sa_flags"))
              (pair "siAddr" (guardField facts "siginfo_t" "si_addr"))))

fn layoutOf layout: (List (Pair String Int64)) key: String -> Int64
  (optionOr (libc/pairFind layout key) 0)

; (:m :ref NATIVE-STACK-GUARD :do "a program body recursing past the 1 GiB thread stack (rtAbi mainText) used to SIGSEGV raw: no C stack depth counter exists (every ASL call is a real native call), so the cheapest sound catch is the stack pthread already refuses to extend past -- a guard-page fault -- turned into a loud, nonzero exit instead of a silent crash. rtAbi.locateStack records not just stackTop (for gcScanConservative) but stackBase (the lowest usable stack address) and installs a SIGSEGV/SIGBUS handler on its own sigaltstack (the faulting thread's own stack is exhausted, so the handler needs stack space that is not); the handler checks the fault address against a 1 MiB window just below stackBase -- where a real overflow lands, never a wild unrelated pointer -- reports ERR_STACK_DEPTH and _exit(1) on a match, else restores SIG_DFL and re-raises so a genuine unrelated fault still crashes exactly as before. One-time setup cost only (sigaltstack + two sigaction calls at thread start); no per-call probe, so steady-state recursion speed is unchanged. NATIVE-STACK-GUARD-LINUX: the same guard now installs on linux (glibc layouts from the libc table); before it only existed in the Darwin locateStack and a linux overflow died raw with SIGSEGV (exit 139)")
fn stackGuardText layout: (List (Pair String Int64)) -> (List String)
  (list "@rtAbi.stackBase = internal global ptr null, align 8"
        (str "@rtAbi.sigStackBuf = internal global [" (stackGuardAltStackBytes) " x i8] zeroinitializer, align 16")
        (str "@rtAbi.altStackBuf = internal global [" (layoutOf layout "stackTSize") " x i8] zeroinitializer, align 8")
        (str "@rtAbi.sigActionBuf = internal global [" (layoutOf layout "actionSize") " x i8] zeroinitializer, align 8")
        (cString "rtAbi.stackDepthMsg" (stackDepthMsg))
        ""
        "define internal void @rtAbi.installStackGuard() {"
        "entry:"
        (str "  %altSpAt = getelementptr i8, ptr @rtAbi.altStackBuf, i64 " (layoutOf layout "ssSp"))
        "  store ptr @rtAbi.sigStackBuf, ptr %altSpAt"
        (str "  %altSizeAt = getelementptr i8, ptr @rtAbi.altStackBuf, i64 " (layoutOf layout "ssSize"))
        (str "  store i64 " (stackGuardAltStackBytes) ", ptr %altSizeAt")
        (str "  %altFlagsAt = getelementptr i8, ptr @rtAbi.altStackBuf, i64 " (layoutOf layout "ssFlags"))
        "  store i32 0, ptr %altFlagsAt"
        "  %altSet = call i32 @sigaltstack(ptr @rtAbi.altStackBuf, ptr null)"
        (str "  %saHandlerAt = getelementptr i8, ptr @rtAbi.sigActionBuf, i64 " (layoutOf layout "saHandler"))
        "  store ptr @rtAbi.stackGuardHandler, ptr %saHandlerAt"
        (str "  %saMaskAt = getelementptr i8, ptr @rtAbi.sigActionBuf, i64 " (layoutOf layout "saMask"))
        "  %emptied = call i32 @sigemptyset(ptr %saMaskAt)"
        (str "  %saFlagsAt = getelementptr i8, ptr @rtAbi.sigActionBuf, i64 " (layoutOf layout "saFlags"))
        (str "  store i32 " (+ (layoutOf layout "sigInfo") (layoutOf layout "onStack")) ", ptr %saFlagsAt")
        (str "  %segvSet = call i32 @sigaction(i32 " (layoutOf layout "segv") ", ptr @rtAbi.sigActionBuf, ptr null)")
        (str "  %busSet = call i32 @sigaction(i32 " (layoutOf layout "bus") ", ptr @rtAbi.sigActionBuf, ptr null)")
        "  ret void"
        "}"
        ""
        "define internal void @rtAbi.stackGuardHandler(i32 %sig, ptr %info, ptr %uctx) {"
        "entry:"
        (str "  %addrAt = getelementptr i8, ptr %info, i64 " (layoutOf layout "siAddr"))
        "  %addr = load ptr, ptr %addrAt"
        "  %base = load ptr, ptr @rtAbi.stackBase"
        "  %belowBase = icmp ult ptr %addr, %base"
        (str "  %marginBase = getelementptr i8, ptr %base, i64 -" (stackGuardWindowBytes))
        "  %aboveMargin = icmp uge ptr %addr, %marginBase"
        "  %inGuard = and i1 %belowBase, %aboveMargin"
        "  br i1 %inGuard, label %report, label %chain"
        "report:"
        (str "  %msgWritten = call i64 @write(i32 2, ptr @rtAbi.stackDepthMsg, i64 " (stringLength (stackDepthMsg)) ")")
        "  call void @_exit(i32 1)"
        "  unreachable"
        "chain:"
        "  %restored = call ptr @signal(i32 %sig, ptr null)"
        "  %raised = call i32 @raise(i32 %sig)"
        "  unreachable"
        "}")

fn locateDarwinText layout: (List (Pair String Int64)) -> String
  (stringJoin
    (listAppend
      (stackGuardText layout)
      (list ""
            "define internal void @rtAbi.locateStack() {"
            "entry:"
            "  %self = call ptr @pthread_self()"
            "  %top = call ptr @pthread_get_stackaddr_np(ptr %self)"
            "  store ptr %top, ptr @rtAbi.stackTop"
            (str "  %base = getelementptr i8, ptr %top, i64 -" (mainStackBytes))
            "  store ptr %base, ptr @rtAbi.stackBase"
            "  call void @rtAbi.installStackGuard()"
            "  ret void"
            "}"))
    "\n")

fn locateLinuxText attrSize: Int64 layout: (List (Pair String Int64)) -> String
  (stringJoin
    (listAppend
      (stackGuardText layout)
      (list ""
            "define internal void @rtAbi.locateStack() {"
            "entry:"
            (str "  %at = alloca [" attrSize " x i8], align 16")
            "  %addr = alloca ptr, align 8"
            "  %size = alloca i64, align 8"
            "  %self = call i64 @pthread_self()"
            "  %got = call i32 @pthread_getattr_np(i64 %self, ptr %at)"
            "  %gotFail = icmp ne i32 %got, 0"
            "  br i1 %gotFail, label %fail, label %read"
            "read:"
            "  %rc = call i32 @pthread_attr_getstack(ptr %at, ptr %addr, ptr %size)"
            "  %destroyed = call i32 @pthread_attr_destroy(ptr %at)"
            "  %readFail = icmp ne i32 %rc, 0"
            "  br i1 %readFail, label %fail, label %done"
            "done:"
            "  %base = load ptr, ptr %addr"
            "  %bytes = load i64, ptr %size"
            "  %top = getelementptr i8, ptr %base, i64 %bytes"
            "  store ptr %top, ptr @rtAbi.stackTop"
            "  store ptr %base, ptr @rtAbi.stackBase"
            "  call void @rtAbi.installStackGuard()"
            "  ret void"
            "fail:"
            "  call void (ptr, ptr, ...) @gcFloorFail(ptr @rtAbi.errInternal, ptr @rtAbi.noStack)"
            "  unreachable"
            "}"))
    "\n")

fn declLines darwin: Bool asan: Bool -> (List String)
  (listAppend
    (list "@gcExternalRoots = external global ptr"
          "@KW_SOME = external global i32"
          "@KW_NONE = external global i32"
          "@KW_OK = external global i32"
          "@KW_ERR = external global i32"
          "@KW_PARTIAL = external global i32"
          "declare void @gcInit()"
          "declare void @gcScanConservative(ptr, ptr)"
          "declare i32 @aslInternShared(ptr, i64)"
          "declare void @gcFloorFail(ptr, ptr, ...) noreturn"
          "declare ptr @realloc(ptr, i64)"
          "declare i32 @snprintf(ptr, i64, ptr, ...)"
          "declare void @llvm.eh.unwind.init()"
          "declare ptr @llvm.stacksave.p0()"
          "declare ptr @signal(i32, ptr)"
          "declare i32 @fflush(ptr)"
          "declare i32 @sigemptyset(ptr)"
          "declare i32 @sigaction(i32, ptr, ptr)"
          "declare i32 @sigaltstack(ptr, ptr)"
          "declare i32 @raise(i32)"
          "declare i64 @write(i32, ptr, i64)"
          "declare void @_exit(i32) noreturn"
          "declare i32 @sigfillset(ptr)"
          "declare i32 @pthread_sigmask(i32, ptr, ptr)"
          "declare i32 @pthread_attr_init(ptr)"
          "declare i32 @pthread_attr_setstacksize(ptr, i64)"
          "declare i32 @pthread_create(ptr, ptr, ptr, ptr)"
          "declare void @exit(i32) noreturn")
    (listAppend
      (if darwin
        (list "declare ptr @pthread_self()" "declare ptr @pthread_get_stackaddr_np(ptr)" "declare i32 @pthread_attr_destroy(ptr)"
              "declare i32 @pthread_join(ptr, ptr)")
        (list "declare i64 @pthread_self()" "declare i32 @pthread_getattr_np(i64, ptr)" "declare i32 @pthread_attr_getstack(ptr, ptr, ptr)"
              "declare i32 @pthread_attr_destroy(ptr)" "declare i32 @pthread_join(i64, ptr)"))
      (if asan
        (list "declare ptr @__asan_get_current_fake_stack()" "declare ptr @__asan_addr_is_in_fake_stack(ptr, ptr, ptr, ptr)")
        (list))))

fn locateText facts: libc/TripleFacts -> (Result String String)
  (cond
    ((= facts.triple "darwin-arm64")
      (match (guardLayout facts)
        ((err e) (err e))
        ((ok layout) (ok (locateDarwinText layout)))))
    ((stringStartsWith? facts.triple "linux-")
      (match (libc/structSize facts "pthread_attr_t")
        ((none) (err (str "ERR_LLVM_RTABI: libc.asl has no pthread_attr_t size for " facts.triple)))
        ((some n)
          (match (guardLayout facts)
            ((err e) (err e))
            ((ok layout) (ok (locateLinuxText n layout)))))))
    (else (err (str "ERR_LLVM_RTABI: no native stack lookup for " facts.triple))))

fn abiText facts: libc/TripleFacts asan: Bool -> (Result String String)
  (match (locateText facts)
    ((err e) (err e))
    ((ok locate)
      (match (mainSizes facts)
        ((err e) (err e))
        ((ok sizes)
          (ok (str "source_filename = \"aslRtAbi\"\n\n"
                   (stringJoin
                     (list (stringJoin (dataLines) "\n") "" (initText) "" (mainText facts (pairFirst sizes) (pairSecond sizes)) "" (globalRootText) "" (rootsText) "" (externalRootsText asan) ""
                           (if asan (str (fakeFrameText) "\n") "") locate "" (stringJoin (declLines (= facts.triple "darwin-arm64") asan) "\n"))
                     "\n")
                   "\n"))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(chosen (gr/targetArgs! args))
        (triple (pairFirst chosen))
        (rest (pairSecond chosen))
        (asan (listContains? rest "asan"))]
    (match (libc/libcFacts triple)
      ((none) (err (str "ERR_LLVM_RTABI: libc.asl covers no triple '" triple "' (uname -s -m, else --target)")))
      ((some facts)
        (match (abiText facts asan)
          ((err e) (err e))
          ((ok text)
            (match (listHead (filter (fn [(a String)] -> Bool (!= a "asan")) rest))
              ((none) (do (print text) (ok 0)))
              ((some path) (match (fileWrite path text)
                             ((ok _) (ok 0))
                             ((err e) (err (str "ERR_LLVM_RTABI: cannot write " path ": " e)))))))))))
