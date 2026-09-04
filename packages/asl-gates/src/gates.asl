(module asl-gates/gates
  :d "Pure AgentScript verification gate runners and continuous audit engine."
  :x [verify-source-syntax verify-file-semantic run-suite main]
  :i [(ast :a a) (compiler :a comp) (types :a ty) (check :a chk)])

(df verify-source-syntax [(src Str)] -> Bool
  :d "Verifies that source parses cleanly into well-formed AST under pure ASL parser."
  (mt (a/parse src)
    ((ok _) true)
    ((err _) false)))

(df ! verify-file-semantic [(path Str)] -> (Result Unit Str)
  :d "Verifies that an AgentScript file passes pure ASL semantic and type checks."
  (mt (file-read path)
    ((err _) (err (str "Failed to read file: " path)))
    ((ok src)
     (mt (a/parse src)
       ((err pe)
        (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": " (.-msg pe))))
       ((ok forms)
        (let [(diags (chk/check-module forms (map-empty) path))]
          (if (list-empty? diags)
              (ok ())
              (err (str path ": " (string-from-int64 (list-length diags)) " semantic error(s)")))))))))

(df ! run-suite [(paths (List Str))] -> (Result I64 Str)
  :d "Executes semantic verification gate across a collection of ASL source paths."
  (fold (fn ! [(acc (Result I64 Str)) (p Str)] -> (Result I64 Str)
          (mt acc
            ((err e) (err e))
            ((ok count)
             (mt (verify-file-semantic p)
               ((ok _) (ok (+ count 1)))
               ((err msg) (err msg))))))
        (ok 0)
        paths))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Entrypoint for pure AgentScript gate verification binary."
  (if (list-empty? args)
      (let [(u1 (println "AgentScript Gate Runner: 0 files specified. Verification clean."))]
        (ok ()))
      (mt (run-suite args)
        ((ok count)
         (let [(u2 (println (str "=== [Pure ASL Gate] ALL " (string-from-int64 count) " FILE(S) VERIFIED CLEANLY ===")))]
           (ok ())))
        ((err msg)
         (let [(u3 (eprintln (str "=== [Pure ASL Gate] FAILED: " msg " ===")))]
           (err (other)))))))
