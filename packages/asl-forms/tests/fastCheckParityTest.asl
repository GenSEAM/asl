(module asl-forms/tests/fastCheckParityTest
  :x [runTests]
  :i [(asl-forms/gate :a g)])

; (:m :ref FORMS-FASTPATH :do "the in-process check of a staged .asl file accepts only what asl check accepts: a stray paren after a ; (:m ...) comment form, which the checker's reader accepts, is rejected by asl check's balance pass and so by the fast path, an unresolved import keeps its checker code and never reads as ERR_IO, a clean file passes")
fn verdict! env: g/GateEnv name: String text: String -> (List String)
  (g/validateStaged! env (str env.root "/asl/packages/asl-forms/tests/" name ".asl") (none) text false)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (env (g/GateEnv :root root :rootDir root :binDir (str root "/bin") :host (str root "/bin/asl") :staged (list)))
        (clean (verdict! env "zzFastClean" "(module asl-forms/tests/zzFastClean :x [one])\n\nfn one -> Int64\n  1\n"))
        (commentParen (verdict! env "zzFastComment" "(module asl-forms/tests/zzFastComment :x [one])\n\n; (:m :ref X :do \"a\") (\nfn one -> Int64\n  1\n"))
        (badImport (verdict! env "zzFastImport" "(module asl-forms/tests/zzFastImport :x [one] :i [(asl-forms/noSuchModuleAnywhere :a z)])\n\nfn one -> Int64\n  1\n"))]
    (do (assert (= (optionOr (listGet clean 0) "x") "") (str "a clean file passes: " (stringJoin clean " | ")))
        (assert (= (optionOr (listGet commentParen 0) "") ":ERR_CHECK_FAILED") (str "a stray paren after a meta comment fails as asl check's balance pass does: " (stringJoin commentParen " | ")))
        (assert (stringContains? (optionOr (listGet commentParen 1) "") "ERR_UNBALANCED") "the balance failure names ERR_UNBALANCED")
        (assert (= (optionOr (listGet badImport 0) "") ":ERR_CHECK_FAILED") "an unresolved import fails")
        (assert (not (stringContains? (optionOr (listGet badImport 1) "") "ERR_IO")) (str "a resolver error keeps its own code, not ERR_IO: " (optionOr (listGet badImport 1) "")))
        true))
