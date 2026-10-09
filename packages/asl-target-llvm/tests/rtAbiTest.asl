(module asl-target-llvm/tests/rtAbiTest
  :x [runTests]
  :i [(asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/rtAbi :a abi)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn lib -> String
  "asl/host/out/libaslrt.a"

fn hideMask -> String
  "6148914691236517205"

fn armZero holder: String -> String
  (stringJoin
    (map (fn [(r String)] -> String (str "mov " r ", xzr"))
         (filter (fn [(r String)] -> Bool (!= r holder))
                 (list "x0" "x1" "x2" "x3" "x4" "x5" "x6" "x7" "x8" "x10" "x11" "x12" "x13" "x14" "x15" "x16" "x17"
                       "x19" "x20" "x21" "x22" "x23" "x24" "x25" "x26" "x27" "x28")))
    "\\0A")

fn armHold kind: String -> (Pair String String)
  (cond
    ((= kind "slot") (pair "str x9, [sp, #-16]!" "ldr x9, [sp], #16"))
    ((= kind "gpr") (pair "mov x28, x9" "mov x9, x28"))
    (else (pair "fmov d8, x9" "fmov x9, d8")))

fn armAsm kind: String prefix: String -> String
  (let [(hold (armHold kind))]
    (stringJoin
      (list (pairFirst hold) "mov x9, xzr" (str "bl " prefix "rtAbiProbeScrub") (armZero (if (= kind "gpr") "x28" ""))
            (str "bl " prefix "asl_gc_collect") (pairSecond hold))
      "\\0A"))

fn armConstraints -> String
  (str "={x9},{x9},"
       (stringJoin
         (map (fn [(r String)] -> String (str "~{" r "}"))
              (list "x0" "x1" "x2" "x3" "x4" "x5" "x6" "x7" "x8" "x10" "x11" "x12" "x13" "x14" "x15" "x16" "x17"
                    "x19" "x20" "x21" "x22" "x23" "x24" "x25" "x26" "x27" "x28" "x30"
                    "q0" "q1" "q2" "q3" "q4" "q5" "q6" "q7" "d8" "d9" "d10" "d11" "d12" "d13" "d14" "d15"
                    "q16" "q17" "q18" "q19" "q20" "q21" "q22" "q23" "q24" "q25" "q26" "q27" "q28" "q29" "q30" "q31"
                    "cc" "memory"))
         ","))

fn x86Zero holder: String -> String
  (stringJoin
    (map (fn [(r String)] -> String (str "xorq %" r ", %" r))
         (filter (fn [(r String)] -> Bool (!= r holder))
                 (list "rax" "rcx" "rdx" "rsi" "r8" "r9" "r10" "r11" "rbx" "r12" "r13" "r14" "r15")))
    "\\0A")

fn x86Hold kind: String -> (Pair String String)
  (if (= kind "slot")
    (pair "subq $$16, %rsp\\0Amovq %rdi, (%rsp)" "movq (%rsp), %rdi\\0Aaddq $$16, %rsp")
    (pair "movq %rdi, %r15" "movq %r15, %rdi"))

fn x86Asm kind: String -> String
  (let [(hold (x86Hold kind))]
    (stringJoin
      (list (pairFirst hold) "xorq %rdi, %rdi" "call rtAbiProbeScrub" (x86Zero (if (= kind "gpr") "r15" ""))
            "call asl_gc_collect" (pairSecond hold))
      "\\0A"))

fn x86Constraints -> String
  (str "={rdi},{rdi},"
       (stringJoin
         (map (fn [(r String)] -> String (str "~{" r "}"))
              (list "rax" "rcx" "rdx" "rsi" "r8" "r9" "r10" "r11" "rbx" "r12" "r13" "r14" "r15"
                    "xmm0" "xmm1" "xmm2" "xmm3" "xmm4" "xmm5" "xmm6" "xmm7" "xmm8" "xmm9" "xmm10" "xmm11" "xmm12" "xmm13" "xmm14" "xmm15"
                    "dirflag" "fpsr" "flags" "memory"))
         ","))

fn probeKinds triple: String -> (List String)
  (if (= triple "linux-x86_64") (list "slot" "gpr") (list "slot" "gpr" "fpr"))

fn probeText triple: String kind: String hidden: Bool -> String
  (let [(arm (!= triple "linux-x86_64"))
        (prefix (if (= triple "darwin-arm64") "_" ""))
        (key (if hidden (hideMask) "0"))
        (body (if arm (armAsm kind prefix) (x86Asm kind)))
        (constraintText (if arm (armConstraints) (x86Constraints)))]
    (stringJoin
      (list
        "declare void @asl_rt_init()"
        "declare ptr @asl_alloc(i32, i64)"
        "declare void @asl_gc_collect()"
        "declare ptr @gcFindObj(i64)"
        "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)"
        ""
        "define void @rtAbiProbeScrub() noinline {"
        "  %b = alloca [65536 x i8], align 16"
        "  call void @llvm.memset.p0.i64(ptr %b, i8 0, i64 65536, i1 true)"
        "  ret void"
        "}"
        ""
        "define i32 @main() {"
        "entry:"
        "  call void @asl_rt_init()"
        "  %p = call ptr @asl_alloc(i32 0, i64 32)"
        "  %pi = ptrtoint ptr %p to i64"
        (str "  %h = xor i64 %pi, " key)
        "  %hp = inttoptr i64 %h to ptr"
        (str "  %back = call ptr asm sideeffect \"" body "\", \"" constraintText "\"(ptr %hp)")
        "  %bi = ptrtoint ptr %back to i64"
        (str "  %qi = xor i64 %bi, " key)
        "  %f = call ptr @gcFindObj(i64 %qi)"
        "  %fi = ptrtoint ptr %f to i64"
        "  %live = icmp eq i64 %fi, %qi"
        "  %r = select i1 %live, i32 0, i32 3"
        "  ret i32 %r"
        "}"
        "")
      "\n"))

fn ! hostTriple -> String
  (let [(os (stringReplace (sh "uname -s").stdout "\n" ""))
        (machine (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= os "Darwin") (= machine "arm64")) "darwin-arm64")
      ((and (= os "Linux") (= machine "x86_64")) "linux-x86_64")
      ((and (= os "Linux") (or (= machine "aarch64") (= machine "arm64"))) "linux-aarch64")
      (else "")))

fn ! runProbe work: String triple: String kind: String hidden: Bool -> Bool
  (let [(name (str "probe-" kind (if hidden "-hidden" "-kept")))
        (ll (str work "/" name ".ll"))
        (bin (str work "/" name))
        (written (fileWrite ll (probeText triple kind hidden)))
        (floor (str work "/floor.ll"))
        (floorWritten (fileWrite floor (ssa/cRuntimeModule)))
        (linked (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " " floor " -x none " (lib) " -lm -o " bin)))
        (run (sh (str "ASL_GC_STRESS=1 ASL_GC_VERIFY=1 " bin)))
        (want (if hidden 3 0))]
    (do (assert (ok? written) (str name ": .ll written"))
        (assert (ok? floorWritten) (str name ": the runtime floor IR written"))
        (assert (= linked.exitCode 0) (str name ": links against libaslrt.a; " linked.stderr))
        (assert (= run.exitCode want)
          (str name ": the object " (if hidden "whose only reference is hidden is freed" "held only in a native stack slot or register survives")
               " a collection under ASL_GC_STRESS=1 ASL_GC_VERIFY=1; exit " run.exitCode ", want " want "; stderr " run.stderr))
        true))

fn ! testStackScan work: String -> Bool
  (let [(triple (hostTriple))]
    (do (assert (!= triple "") "the host is a triple libc.asl covers")
        (map (fn [(kind String)] -> Bool (and (runProbe work triple kind false) (runProbe work triple kind true))) (probeKinds triple))
        true))

fn layoutRows -> (List (Pair String Int64))
  (list (pair "sizeof(Val)" 16) (pair "offsetof(Val, tag)" 0) (pair "offsetof(Val, aux)" 4) (pair "offsetof(Val, u)" 8)
        (pair "__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__" 1) (pair "sizeof(double)" 8) (pair "sizeof(void *)" 8) (pair "sizeof(int)" 4)
        (pair "T_UNIT" 0) (pair "T_BOOL" 1) (pair "T_INT" 2) (pair "T_FLOAT" 3) (pair "T_STR" 5) (pair "T_REC" 7) (pair "T_CTOR" 8) (pair "T_FN" 9) (pair "T_BUILTIN" 10)
        (pair "offsetof(Ctor, ctor)" 8) (pair "offsetof(Ctor, n)" 12) (pair "offsetof(Ctor, f)" 16)
        (pair "offsetof(Rec, schema)" 8) (pair "offsetof(Rec, n)" 12) (pair "offsetof(Rec, keys)" 16) (pair "offsetof(Rec, v)" 24)
        (pair "offsetof(Closure, p)" 8) (pair "offsetof(Closure, n)" 16) (pair "offsetof(Closure, up)" 24)
        (pair "O_STR" 0) (pair "O_REC" 2) (pair "O_CTOR" 3) (pair "O_CLOSURE" 4) (pair "offsetof(Str, len)" 8) (pair "offsetof(Str, s)" 16)
        (pair "sizeof(Proto)" 64) (pair "offsetof(Proto, name)" 0) (pair "offsetof(Proto, file)" 8) (pair "offsetof(Proto, nparams)" 16)
        (pair "offsetof(Proto, maxstack)" 20) (pair "offsetof(Proto, code)" 24) (pair "offsetof(Proto, ncode)" 32) (pair "offsetof(Proto, capcode)" 36)
        (pair "offsetof(Proto, consts)" 40) (pair "offsetof(Proto, nconsts)" 48) (pair "offsetof(Proto, capconsts)" 52) (pair "offsetof(Proto, native)" 56))

fn layoutProbeText -> String
  (stringJoin
    (listAppend
      (list "#include \"value.h\"" "int main(void) {")
      (listAppend
        (map (fn [(r (Pair String Int64))] -> String (str "  printf(\"%s=%lld\\n\", \"" (pairFirst r) "\", (long long)(" (pairFirst r) "));")) (layoutRows))
        (list "  return 0;" "}" "")))
    "\n")

fn layoutValue lines: (List String) name: String -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (l String)] -> (Option Int64)
          (if (stringStartsWith? l (str name "=")) (stringToInt64 (optionOr (stringSlice l (+ (stringLength name) 1) (stringLength l)) "")) acc))
        (none) lines)

fn ! testLayout work: String -> Bool
  (let [(src (str work "/layout.c"))
        (bin (str work "/layout"))
        (written (fileWrite src (layoutProbeText)))
        (built (sh (str "/usr/bin/cc -std=c11 -D_DEFAULT_SOURCE -I asl/host/src " src " -o " bin)))
        (run (sh bin))
        (lines (stringLines run.stdout))]
    (do (assert (ok? written) "layout probe written")
        (assert (= built.exitCode 0) (str "layout probe compiles against value.h; " built.stderr))
        (assert (= run.exitCode 0) (str "layout probe runs; " run.stderr))
        (map (fn [(r (Pair String Int64))] -> Bool
               (let [(got (layoutValue lines (pairFirst r)))]
                 (do (assert (= got (some (pairSecond r)))
                       (str (pairFirst r) " is " (pairSecond r) " in the layout the emitted IR assumes; value.h gives " (optionOr got -1)))
                     true)))
             (layoutRows))
        true))

fn ! testAbiModule work: String -> Bool
  (let [(triple (hostTriple))
        (facts (libc/libcFacts triple))]
    (mt facts
      ((none) (assert false (str "libc.asl has facts for " triple)))
      ((some f)
        (let [(plain (abi/abiText f false))
              (asan (abi/abiText f true))
              (text (mt plain ((ok t) t) ((err e) e)))
              (asanText (mt asan ((ok t) t) ((err e) e)))
              (externalRoots (optionOr (stringSlice text (optionOr (stringIndexOf text "define internal void @rtAbi.externalRoots") 0) (stringLength text)) ""))
              (ll (str work "/rtAbiAsan.ll"))
              (written (fileWrite ll asanText))
              (compiled (sh (str "/usr/bin/clang -O2 -Wno-override-module -c -x ir " ll " -o " work "/rtAbiAsan.o")))]
          (do (assert (ok? plain) (str "abiText emits the runtime ABI module for " triple "; " text))
              (assert (ok? asan) (str "abiText emits the ASan runtime ABI module for " triple "; " asanText))
              (assert (stringContains? externalRoots "call void @llvm.eh.unwind.init()") "externalRoots spills every callee-saved register (llvm.eh.unwind.init)")
              (assert (stringContains? externalRoots "notail call void @gcScanConservative(ptr %lo, ptr %hi)") "externalRoots scans from its own stack pointer in a call that cannot become a tail call")
              (refute (stringContains? text "__asan_") "the plain module calls no ASan interface")
              (assert (stringContains? asanText "@__asan_addr_is_in_fake_stack(") "the ASan module scans fake frames")
              (assert (stringContains? text (str "@asl_rt_spill = global [" (abi/spillSlots) " x %Val]")) "asl_rt_spill holds spillSlots Vals")
              (assert (ok? written) "the ASan module written")
              (assert (= compiled.exitCode 0) (str "clang compiles the ASan module; " compiled.stderr))
              (mt (libc/libcFacts "linux-x86_64")
                ((none) (assert false "libc.asl has linux-x86_64 facts"))
                ((some lf) (assert (stringContains? (mt (abi/abiText lf false) ((ok t) t) ((err e) e)) "call i32 @pthread_getattr_np(")
                             "linux-x86_64 locates the stack through pthread_getattr_np")))
              (mt (libc/libcFacts "wasm32-unknown-unknown")
                ((none) (assert false "libc.asl has wasm32 facts"))
                ((some wf) (refute (ok? (abi/abiText wf false)) "wasm32 has no native stack lookup, so abiText refuses it")))
              true)))))

fn ! testArchive work: String -> Bool
  (let [(members (sh (str "ar t " (lib))))
        (names (stringLines members.stdout))
        (here (stringReplace (sh "pwd").stdout "\n" ""))
        (extracted (sh (str "cd " work " && ar x " here "/" (lib) " rtAbi.o")))
        (listed (sh (str "nm -gP " work "/rtAbi.o")))
        (defined (map (fn [(l String)] -> String (let [(n (optionOr (listHead (stringSplit l " ")) ""))] (if (stringStartsWith? n "_") (optionOr (stringSlice n 1 (stringLength n)) n) n)))
                      (filter (fn [(l String)] -> Bool (not (stringContains? l " U "))) (stringLines listed.stdout))))]
    (do (assert (= members.exitCode 0) (str "ar t lists libaslrt.a; " members.stderr))
        (assert (listContains? names "rtAbi.o") (str "libaslrt.a has the IR-built rtAbi.o; members " members.stdout))
        (refute (listContains? names "abi.o") (str "libaslrt.a has no abi.o; members " members.stdout))
        (assert (= extracted.exitCode 0) (str "rtAbi.o extracted; " extracted.stderr))
        (assert (= listed.exitCode 0) (str "nm lists rtAbi.o; " listed.stderr))
        (map (fn [(n String)] -> Bool (do (assert (listContains? defined n) (str "rtAbi.o defines " n "; defines " (stringJoin defined " "))) true)) (abi/entryNames))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testLayout work)
        (testAbiModule work)
        (testArchive work)
        (testStackScan work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
