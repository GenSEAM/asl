(module asl-forms/tests/effectMarkOnWriteTest
  :x [runTests]
  :i [(asl-forms/vfs :a v) (asl-forms/edit :a e) (asl-checker/check :a c) (asl-checker/types :a ty) (asl-proc/jobPool :a jp)])

; (:m :ref "lead amend 2026-10-16" :do "the agent write path (stage then flush) runs effectMark on every .asl flush, on by default, so an LLM adding an effectful call to an unmarked function never has to write the ! itself: the gate the lead asked for, in a :pure package where an unmarked effect would otherwise be ERR_EFFECT_UNMARKED")

fn before -> String
  "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n"

fn after -> String
  "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (do (println \"hi\") (+ n 1))\n"

fn ! writePureManifest! dir: String -> Bool
  (ok? (fileWrite (str dir "/manifest.asn") "(:package effectwrite :pure true)\n"))

fn ! checkedDiagnostics! path: String dir: String -> (List ty/Diagnostic)
  (resultOr (c/checkFile! path (list dir)) (list (ty/Diagnostic :code "ERR_IO" :message "checkFile! failed" :msg "checkFile! failed" :line 0 :col 0 :path path)))

fn ! verifyFlush! vs: v/Vfs target: String dir: String -> Bool
  (let [(out (e/flushStep! vs (list) 1 (mapSet (mapEmpty) "file" target) (list)))
        (lines (stringJoin out.lines "\n"))]
    (do (assert (= out.errCount 0) (str "flush writes the file without an error: " lines))
        (refute (stringContains? lines "ERR_") (str "no error code in the flush receipt: " lines))
        (let [(written (resultOr (fileReadString target) ""))
              (checked (checkedDiagnostics! target dir))]
          (do (assert (stringContains? written "fn ! f") (str "effectMark wrote the ! for f on flush, an LLM did not have to: " written))
              (assert (listEmpty? checked) (str "the checker reports the inferred effect without an error once written: " (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code ":" d.message)) checked) "; ")))
              true))))

fn ! runTests -> Bool
  (let [(made (jp/runOne (jp/job (list "mktemp" "-d") "." (jp/childEnv (list))))) (rawDir (stringReplace made.out "\n" ""))
        (dir (match (realPath rawDir) ((ok r) r) ((err _) rawDir)))
        (vdir (str dir "/.asl/vfs"))
        (target (str dir "/m.asl"))]
    (do (assert (= made.exit 0) "mktemp -d makes a workspace directory")
        (assert (writePureManifest! dir) "pure manifest written")
        (assert (ok? (dirCreate vdir)) "vfs dir created")
        (assert (ok? (fileWrite target (before))) "initial pure file written")
        (let [(vs (v/vfsAt dir vdir "effectMarkOnWriteTest"))
              (staged (v/stage! vs target (after)))]
          (do (assert (ok? staged) (str "stage the edit that adds an unmarked effectful call: " staged))
              (verifyFlush! vs target dir)))
        (assert (= (jp/runOne (jp/job (list "rm" "-rf" dir) "." (jp/childEnv (list)))).exit 0) "workspace removed")
        true))
