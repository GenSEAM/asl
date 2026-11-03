(module asl-target-llvm/tests/llvmToolsTest
  :x [runTests]
  :i [(asl-target-llvm/tests/llvmTools :a lt)])

; (:m :ref LLVM-NODE2-REDS :do "the shared tool lookup finds a tool that is on PATH, answers empty for one that is nowhere, and never answers a path that is not an executable file")
fn ! runTests -> Bool
  (let [(sh (lt/toolPath! "sh" "sh"))
        (none (lt/toolPath! "zzNoSuchLlvmTool" "zzNoSuchLlvmTool"))
        (llc (lt/llcPath!))]
    (do (assert (not (stringEmpty? sh)) "sh is found on PATH")
        (assert (stringEmpty? none) "a tool that exists nowhere is the empty answer")
        (assert (or (stringEmpty? llc) (stringEndsWith? llc "llc") (stringContains? llc "llc-")) (str "llc answer names an llc: " llc))
        (assert (or (stringEmpty? llc) (lt/usable? llc)) (str "llc answer is an executable file: " llc))
        true))
