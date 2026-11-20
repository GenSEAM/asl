(module asl-target-llvm/tests/nativeForEntryTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

; (:m :ref LLVM-FOR-ENTRY-TESTS :do "emitLlvmProgramNativeFor! emits a linked module for a named target and RC mode: a Linux target and the host target route differently, the With entry is the host target, an RC mode adds its runtime calls, and an unknown mode is ERR_LLVM_RC_MODE")
fn mainSource -> String
  "(module p1/main :x [main])\n\nfn ! main -> Int64\n  (match (fileReadString \"/nonexistent/nativeForEntry\") ((ok s) (stringLength s)) ((err _) 3))\n"

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn textOf r: (Result String (List irTy/IrDiag)) -> String
  (match r ((ok t) t) ((err ds) (str "diag: " (formatDiags ds))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/nativeForEntryTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))
        (made (and (ok? (dirCreate dir)) (ok? (fileWrite (str dir "/main.asl") (mainSource)))))
        (linked (lk/linkEntry! (str dir "/main.asl")))
        (cleaned (pathRemove dir))]
    (match linked
      ((err ds) (do (assert false (str "the fixture links: " (formatDiags ds))) false))
      ((ok m)
        (let [(entry (str m.name ".main"))
              (host (textOf (llvm/emitLlvmProgramNativeFor! m entry "0" "")))
              (linux (textOf (llvm/emitLlvmProgramNativeFor! m entry "0" "linux-x86_64")))
              (viaWith (textOf (llvm/emitLlvmProgramNativeWith! m entry "0")))
              (rc (textOf (llvm/emitLlvmProgramNativeFor! m entry "1" "")))
              (bad (textOf (llvm/emitLlvmProgramNativeFor! m entry "bogus" "")))]
          (do
            (assert made "the fixture is written")
            (assert (ok? cleaned) "the fixture is removed")
            (assert (stringContains? host "define") (str "the host target emits LLVM functions: " (optionOr (stringSlice host 0 300) "")))
            (assert (stringContains? linux "define") (str "a Linux target emits LLVM functions: " (optionOr (stringSlice linux 0 300) "")))
            (assert (!= host linux) "the target reaches the routes: Linux and host text differ")
            (assert (= viaWith host) "emitLlvmProgramNativeWith! is the For entry with the host target")
            (assert (and (stringContains? rc "define") (!= rc host)) "RC mode 1 emits a different, still valid program")
            (assert (stringContains? bad "ERR_LLVM_RC_MODE") (str "an unknown RC mode is a diagnostic: " bad))
            true)))))
