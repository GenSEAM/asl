(module asl-compiler/llvmForEntryTest :x [runTests] :i [(asl-compiler/compiler :a comp)])

; (:m :ref LLVM-FOR-ENTRY-TESTS :do "compilePackageToLlvmFor! compiles an entry file for a named target and RC mode: the target reaches the emitter (a Linux target and the host target give different LLVM text), a bad RC mode is a diagnostic, not a crash, and a missing entry is an error")
fn mainSource -> String
  "(module p1/main :x [main])\n\nfn ! main -> Int64\n  (match (fileReadString \"/nonexistent/llvmForEntry\") ((ok s) (stringLength s)) ((err _) 3))\n"

fn ! writeEntry! dir: String -> Bool
  (and (ok? (dirCreate dir))
       (ok? (dirCreate (str dir "/p1")))
       (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n"))
       (ok? (fileWrite (str dir "/p1/manifest.asn") "(:package p1)\n"))
       (ok? (fileWrite (str dir "/p1/main.asl") (mainSource))))

fn codeOf r: (Result comp/CompileResult String) -> String
  (match r ((ok cr) (if cr.ok cr.code (str "diag: " (stringJoin cr.diagnostics "; ")))) ((err e) (str "err: " e)))

fn diagsOf r: (Result comp/CompileResult String) -> String
  (match r ((ok cr) (if cr.ok "compiled" (stringJoin cr.diagnostics "; "))) ((err e) (str "err: " e)))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/llvmForEntryTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))
        (made (writeEntry! dir))
        (entry (str dir "/p1/main.asl"))
        (host (comp/compilePackageToLlvmFor! entry (list dir) "0" ""))
        (linux (comp/compilePackageToLlvmFor! entry (list dir) "0" "linux-x86_64"))
        (viaWith (comp/compilePackageToLlvmWith! entry (list dir) "0"))
        (badMode (comp/compilePackageToLlvmFor! entry (list dir) "bogus" ""))
        (missing (comp/compilePackageToLlvmFor! (str dir "/p1/absent.asl") (list dir) "0" ""))
        (cleaned (pathRemove dir))]
    (do
      (assert made "the entry workspace is written")
      (assert (stringContains? (codeOf host) "define") (str "the host target compiles to LLVM functions: " (optionOr (stringSlice (codeOf host) 0 300) "")))
      (assert (stringContains? (codeOf linux) "define") (str "a Linux target compiles to LLVM functions: " (optionOr (stringSlice (codeOf linux) 0 300) "")))
      (assert (!= (codeOf host) (codeOf linux)) "the target reaches the emitter: Linux and host text differ")
      (assert (= (codeOf viaWith) (codeOf host)) "compilePackageToLlvmWith! is the For entry with the host target")
      (assert (stringContains? (diagsOf badMode) "ERR_LLVM_RC_MODE") (str "a bad RC mode is a diagnostic: " (diagsOf badMode)))
      (assert (= (codeOf missing) (str "err: Failed to read entry file: " dir "/p1/absent.asl")) (str "a missing entry is an error: " (codeOf missing)))
      (assert (ok? cleaned) "the workspace is removed")
      true))
