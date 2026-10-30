(module asl-target-llvm/tests/cEntryShimTest
  :x [runTests]
  :i [(asl-ir/lower :a low) (asl-target-llvm/ssa :a ssa)])

; (:m :ref C-EXPORT-ABI :do "tailcc is not the C convention on x86_64 (callee pops, ret $8), so a C caller needs a ccc entry: the default IR keeps the tailcc definitions only, the opt-in IR adds define ... @c.<name> with the same registers that calls the tailcc body")
fn source -> String
  (stringJoin (list
    "(module cEntryMod :x [getY twice] :i [])"
    ""
    "(schema Point (:f x Int64) (:f y Int64))"
    ""
    "fn getY p: Point -> Int64"
    "  p.y"
    ""
    "fn twice n: Int64 -> Int64"
    "  (+ n n)") "\n")

fn ! runTests -> Bool
  (match (low/lowerSource (source))
    ((err ds) (do (assert false "the source lowers") false))
    ((ok m) (match (pair (ssa/emitLlvmModule m) (ssa/emitLlvmModuleCEntries m))
              ((pair (ok plain) (ok shimmed))
                (do (assert (stringContains? plain "define tailcc i64 @getY(") "default IR defines getY as tailcc")
                    (refute (stringContains? plain "@c.getY") "default IR has no C entry")
                    (assert (stringContains? shimmed "define tailcc i64 @getY(") "opt-in IR keeps the tailcc body")
                    (assert (stringContains? shimmed "define i64 @c.getY(%Val %p) {") "opt-in IR defines the ccc entry @c.getY with the same registers")
                    (assert (stringContains? shimmed "call tailcc i64 @getY(") "the C entry calls the tailcc body")
                    (assert (stringContains? shimmed "define i64 @c.twice(i64 %n) {") "an Int64 function gets its own ccc entry")
                    (assert (stringStartsWith? shimmed plain) "the opt-in IR is the default IR plus the entries")
                    true))
              (_ (do (assert false "both emit") false)))))
