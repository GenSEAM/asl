(module asl-cli/cli
  :d "Pure AgentScript native command-line interface toolchain."
  :x [format-version format-help dispatch-cmd execute-cli main]
  :i [(ast :a a) (compiler :a comp) (types :a ty) (check :a chk)])

(df format-version [] -> Str
  :d "Returns AgentScript native CLI version string."
  "asl 0.3.0 (pure AgentScript self-hosted toolchain)")

(df format-help [] -> Str
  :d "Returns AgentScript native CLI help usage manual."
  (str "AgentScript Native CLI (100% Pure Self-Hosted ASL)\n"
       "Usage: asl <command> [arguments]\n\n"
       "Commands:\n"
       "  check <file>    Run semantic type and scope checking\n"
       "  build <file>    Compile ASL to standalone target code\n"
       "  parse <file>    Parse S-expression AST and print node count\n"
       "  lint <file>     Inspect AST for basic validity\n"
       "  version         Display toolchain version\n"
       "  help            Display this usage guide\n"))

(df ! dispatch-cmd [(cmd Str) (args (List Str))] -> (Result Str Str)
  :d "Dispatches a CLI command to the corresponding pure ASL compiler or checker package."
  (cond
    ((or (= cmd "version") (or (= cmd "-v") (= cmd "--version")))
     (ok (format-version)))
    ((or (= cmd "help") (or (= cmd "-h") (= cmd "--help")))
     (ok (format-help)))
    ((= cmd "check")
     (if (list-empty? args)
         (err "Usage: asl check <file.asl>")
         (let [(path (option-or (list-head args) ""))
               (src-res (file-read path))]
           (mt src-res
             ((err io-err) (err (str "Failed to read source file: " path)))
             ((ok src)
              (mt (a/parse src)
                ((err pe)
                 (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
                ((ok forms)
                 (let [(diags (chk/check-module forms (map-empty) path))]
                   (if (not (list-empty? diags))
                       (err (str "Check failed with " (string-from-int64 (list-length diags)) " diagnostic(s)"))
                       (ok (str "✓ " path ": Semantic check passed cleanly.")))))))))))
    ((= cmd "build")
     (if (list-empty? args)
         (err "Usage: asl build <file.asl>")
         (let [(path (option-or (list-head args) ""))
               (src-res (file-read path))]
           (mt src-res
             ((err io-err) (err (str "Failed to read source file: " path)))
             ((ok src)
              (let [(cres (comp/compile-standalone-source src path))]
                (if (.-ok cres)
                    (ok (.-code cres))
                    (err (str "Build failed: " (string-join (.-diagnostics cres) "\n"))))))))))
    ((= cmd "parse")
     (if (list-empty? args)
         (err "Usage: asl parse <file.asl>")
         (let [(path (option-or (list-head args) ""))
               (src-res (file-read path))]
           (mt src-res
             ((err io-err) (err (str "Failed to read source file: " path)))
             ((ok src)
              (mt (a/parse src)
                ((err pe)
                 (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": " (.-msg pe))))
                ((ok forms)
                 (ok (str "Parsed " (string-from-int64 (list-length forms)) " top-level AST form(s).")))))))))
    ((= cmd "lint")
     (if (list-empty? args)
         (err "Usage: asl lint <file.asl>")
         (let [(path (option-or (list-head args) ""))
               (src-res (file-read path))]
           (mt src-res
             ((err io-err) (err (str "Failed to read source file: " path)))
             ((ok src)
              (mt (a/parse src)
                ((err pe)
                 (err (str "Parse error during lint: " (.-msg pe))))
                ((ok forms)
                 (ok (str "✓ " path ": Clean. AST parsed cleanly.")))))))))
    (:else
     (err (str "Unknown command '" cmd "'. Run 'asl help' for usage.")))))

(df ! execute-cli [(args (List Str))] -> (Result Unit Str)
  :d "Executes CLI dispatch and writes output to stdout or stderr."
  (if (list-empty? args)
      (let [(unused (println (format-help)))]
        (ok ()))
      (let [(cmd (option-or (list-head args) "help"))
            (cmd-args (option-or (list-tail args) (list)))
            (res (dispatch-cmd cmd cmd-args))]
        (mt res
          ((ok output-str)
           (let [(unused (println output-str))]
             (ok ())))
          ((err err-str)
           (let [(unused (eprintln err-str))]
             (err err-str)))))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Entrypoint for pure AgentScript CLI binary."
  (mt (execute-cli args)
    ((ok _) (ok ()))
    ((err _) (err (other)))))
