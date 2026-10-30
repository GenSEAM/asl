(module asl-target-llvm/tests/stackGuardTextTest
  :x [runTests]
  :i [(asl-target-llvm/libc :a libc) (asl-target-llvm/rtAbi :a abi)])

; (:m :ref NATIVE-STACK-GUARD-LINUX :do "the stack-overflow guard is installed by locateStack on every native triple, with that triple's own sigaction, stack_t and siginfo layouts from the libc table; before, only Darwin installed it and a linux overflow died raw (exit 139)")
fn runtimeText triple: String -> String
  (match (libc/libcFacts triple)
    ((none) (do (assert false (str "libc table covers " triple)) ""))
    ((some facts)
      (match (abi/abiText facts false)
        ((err e) (do (assert false (str "abiText " triple ": " e)) ""))
        ((ok text) text))))

fn ! checkGuard triple: String sigbus: String flags: String -> Bool
  (let [(text (runtimeText triple))]
    (do (assert (stringContains? text "call void @rtAbi.installStackGuard()") (str triple ": locateStack installs the guard"))
        (assert (stringContains? text "store ptr %base, ptr @rtAbi.stackBase") (str triple ": locateStack records stackBase"))
        (assert (stringContains? text (str "call i32 @sigaction(i32 11,")) (str triple ": SIGSEGV handler"))
        (assert (stringContains? text (str "call i32 @sigaction(i32 " sigbus ",")) (str triple ": SIGBUS handler uses the triple's number"))
        (assert (stringContains? text (str "store i32 " flags ", ptr %saFlagsAt")) (str triple ": SA_SIGINFO|SA_ONSTACK from the table"))
        true))

fn ! runTests -> Bool
  (do (checkGuard "darwin-arm64" "10" "65")
      (checkGuard "linux-x86_64" "7" "134217732")
      (checkGuard "linux-aarch64" "7" "134217732")
      (let [(linux (runtimeText "linux-x86_64"))
            (darwin (runtimeText "darwin-arm64"))]
        (do (assert (stringContains? linux "%saFlagsAt = getelementptr i8, ptr @rtAbi.sigActionBuf, i64 136") "glibc sa_flags offset 136")
            (assert (stringContains? linux "%altSizeAt = getelementptr i8, ptr @rtAbi.altStackBuf, i64 16") "glibc stack_t ss_size offset 16")
            (assert (stringContains? linux "%addrAt = getelementptr i8, ptr %info, i64 16") "glibc si_addr offset 16")
            (assert (stringContains? darwin "%saFlagsAt = getelementptr i8, ptr @rtAbi.sigActionBuf, i64 12") "darwin sa_flags offset 12 unchanged")
            (assert (stringContains? darwin "%altSizeAt = getelementptr i8, ptr @rtAbi.altStackBuf, i64 8") "darwin stack_t ss_size offset 8 unchanged")
            (assert (stringContains? darwin "%addrAt = getelementptr i8, ptr %info, i64 24") "darwin si_addr offset 24 unchanged")
            true)))
