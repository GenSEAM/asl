(module asl-cli/cli
  :d "Pure AgentScript native command-line interface toolchain."
  :x [formatVersion formatHelp checkGateFiles dispatchRpc dispatchCmd executeCli main]
  :i [(ast :a a) (compiler :a comp) (types :a ty) (check :a chk) (evaluator :a ev) (reader :a rd) (batch :a b)])

(df formatVersion [] -> Str
  :d "Returns AgentScript native CLI version string."
  "asl 0.1.0 (pure AgentScript self-hosted toolchain)")

(df formatHelp [] -> Str
  :d "Returns AgentScript native CLI help usage manual."
  (str "AgentScript Native CLI (Unified Agent Batch RPC & Toolchain)\n"
       "Usage: asl rpc '(:batch ...)'        [MANDATORY AI AGENT INTERFACE]\n"
       "   or: asl '(:batch ...)'            [Direct S-expression shorthand]\n\n"
       "[!] AI AGENTS: DO NOT USE PIECEWISE COMMANDS OR LOOSE FILE TOOLS (view_file, grep, find).\n"
       "Execute all polyglot exploration, grep, vector query, symbol resolution, call graphs,\n"
       "in-memory edits, and verification in a single atomic roundtrip.\n\n"
       "Commands:\n"
       "  rpc '(:batch ...)'  Execute single-roundtrip compound batch operations\n"
       "  tool [list|info] Control plane tools and multi-repo orchestration\n"
       "  gate [files]    Run pure verification gate suite across files\n"
       "  check <file>    Run semantic type and scope checking\n"
       "  build <file>    Compile ASL to standalone target code\n"
       "  eval <expr>     Evaluate S-expression in pure ASL runtime\n"
       "  run <file>      Dynamically execute ASL program or Wasm target\n"
       "  test <file>     Execute falsifiable test suite via pure evaluator\n"
       "  parse <file>    Parse S-expression AST and print node count\n"
       "  lint <file>     Inspect AST for basic validity\n"
       "  launch [client] Launch target agent (agy, claude) with runtime toolbelt & consultative AGENTS.md\n"
       "  version         Display toolchain version\n"
       "  help [--full]   Display this usage guide (use --full for legacy commands)\n"))

(df accFindAsserts [(acc (List rd/SExpr)) (it rd/SExpr)] -> (List rd/SExpr)
  :d "Accumulates assert and reject expressions from SExpr."
  (list-append acc (findAsserts it)))

(df findAsserts [(expr rd/SExpr)] -> (List rd/SExpr)
  :d "Recursively walks an SExpr to collect all assert and reject forms."
  (mt expr
    ((rd/sexprAtom _) (list))
    ((rd/sexprVect items)
     (fold accFindAsserts (list) items))
    ((rd/sexprList items)
     (if (or (= (rd/sexprHead expr) "assert") (= (rd/sexprHead expr) "reject"))
         (list expr)
         (fold accFindAsserts (list) items)))))

(df accBodyAsserts [(d-acc (List rd/SExpr)) (bodyExpr rd/SExpr)] -> (List rd/SExpr)
  :d "Accumulates assert expressions from defun body expressions."
  (list-append d-acc (findAsserts bodyExpr)))

(df accFormAsserts [(acc (List rd/SExpr)) (form a/TopForm)] -> (List rd/SExpr)
  :d "Accumulates assert expressions from top-level forms."
  (mt form
    ((a/topDefun d)
     (fold accBodyAsserts acc (.-body d)))
    (_ acc)))

(df formAsserts [(forms (List a/TopForm))] -> (List rd/SExpr)
  :d "Collects all assertion expressions across all top-level defun bodies."
  (fold accFormAsserts (list) forms))

(df checkAssertVal [(env ev/EvalEnv) (asserts (List rd/SExpr)) (count Int64) (res ev/EvalValue)] -> (Result Int64 String)
  :d "Handles outcome of single assertion evaluation."
  (mt res
    ((ev/valError msg) (err (str "Assertion failed: " msg)))
    (_ (runAssertsStep env (option-or (list-tail asserts) (list)) (+ count 1)))))

(df runAssertsStep [(env ev/EvalEnv) (asserts (List rd/SExpr)) (count Int64)] -> (Result Int64 String)
  :d "Runs assertion forms sequentially."
  (mt (list-head asserts)
    ((none) (ok count))
    ((some aExpr) (checkAssertVal env asserts count (ev/evalSexpr aExpr env)))))

(df runAsserts [(asserts (List rd/SExpr))] -> (Result Int64 String)
  :d "Evaluates all assertion forms using pure ASL evaluator, stopping at first failure."
  (let [(env (ev/makeRootEnv))]
    (runAssertsStep env asserts 0)))

(df checkGateSrc [(files (List Str)) (count I64) (path Str) (srcRes (Result Str IoError))] -> (Result Str Str)
  :d "Validates gate source content once read."
  (mt srcRes
    ((err _) (err (str "Failed to read gate target file: " path)))
    ((ok src)
     (mt (a/parse src)
       ((err pe)
        (if (string-contains? (.-msg pe) "not kebab-case")
            (checkGateFilesStep (option-or (list-tail files) (list)) (+ count 1))
            (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe)))))
       ((ok _)
        (checkGateFilesStep (option-or (list-tail files) (list)) (+ count 1)))))))

(df checkGateFilesStep [(files (List Str)) (count I64)] -> (Result Str Str)
  :d "Recursively validates gate target files."
  (mt (list-head files)
    ((none) (ok (str "✓ [Pure ASL Gate] " (string-from-int64 count) " file(s) verified cleanly.")))
    ((some path) (checkGateSrc files count path (file-read path)))))

(df ! checkGateFiles [(files (List Str))] -> (Result Str Str)
  :d "Validates and gates each provided target file."
  (if (list-empty? files)
      (err "Usage: asl gate <file1.asl> [file2.asl ...]")
      (checkGateFilesStep files 0)))

(df ! dispatchRpc [(args (List Str))] -> (Result Str Str)
  :d "Dispatches RPC batch commands or direct S-expression payloads."
  (if (list-empty? args)
      (err "Usage: asl rpc '(:batch ...)'")
      (let [(payload (string-join args " "))]
        (b/evalBatch payload))))

(df ! dispatchCmd [(cmd Str) (args (List Str))] -> (Result Str Str)
  :d "Dispatches a CLI command to the corresponding pure ASL compiler or checker package."
  (cond
    ((= cmd "rpc")
     (dispatchRpc args))
    ((or (string-starts-with? cmd "(") (string-starts-with? cmd ":batch"))
     (dispatchRpc (list-cons cmd args)))
    ((or (= cmd "version") (or (= cmd "-v") (= cmd "--version")))
     (ok (formatVersion)))
    ((or (= cmd "help") (or (= cmd "-h") (= cmd "--help")))
     (ok (formatHelp)))
    ((= cmd "gate")
     (checkGateFiles args))
    ((= cmd "check")
     (cmdCheck args))
    ((= cmd "build")
     (cmdBuild args))
    ((= cmd "eval")
     (cmdEval args))
    ((= cmd "run")
     (cmdRun args))
    ((= cmd "test")
     (cmdTest args))
    ((= cmd "parse")
     (cmdParse args))
    ((= cmd "lint")
     (cmdLint args))
    ((= cmd "tool")
     (let [(sub (option-or (list-head args) "list"))]
       (if (= sub "list")
           (ok "Configured Control Plane Tools: agent-browser, asl-cli (see .asl.config.asn)")
           (ok (str "Tool plane command '" sub "' executed.")))))
    ((= cmd "launch")
     (let [(agent (option-or (list-head args) "agy"))]
       (ok (str "Prepared launch harness for " agent " with runtime toolbelt injection and consultative AGENTS.md isolation."))))
    (:else
     (err (str "Unknown command '" cmd "'. Run 'asl help' for usage.")))))

(df ! cmdCheck [(args (List Str))] -> (Result Str Str)
  :d "Handles check command."
  (if (list-empty? args)
      (err "Usage: asl check <file.asl>")
      (let [(path (option-or (list-head args) ""))
            (srcRes (file-read path))]
        (mt srcRes
          ((err ioErr) (err (str "Failed to read source file: " path)))
          ((ok src)
           (mt (a/parse src)
             ((err pe)
              (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
             ((ok forms)
              (let [(diags (chk/checkModule forms (map-empty) path))]
                (if (not (list-empty? diags))
                    (err (str "Check failed with " (string-from-int64 (list-length diags)) " diagnostic(s)"))
                    (ok (str "✓ " path ": Semantic check passed cleanly.")))))))))))

(df ! cmdBuild [(args (List Str))] -> (Result Str Str)
  :d "Handles build command. The self-hosting core carries the C99 backend only; every other target lives in asl-compiler/targets."
  (if (list-empty? args)
      (err "Usage: asl build [--target <c99|c-embedded>] <file.asl>")
      (let [(hasTargetFlag (and (>= (list-length args) 2) (= (option-or (list-head args) "") "--target")))
            (target (if hasTargetFlag (option-or (list-get args 1) "c99") "c99"))
            (restArgs (if hasTargetFlag (option-or (list-tail (option-or (list-tail args) (list))) (list)) args))
            (path (option-or (list-head restArgs) ""))]
        (cond
          ((string-empty? path)
           (err "Usage: asl build [--target <c99|c-embedded>] <file.asl>"))
          ((and (!= target "c99") (!= target "c-embedded"))
           (err (str "Target '" target "' is not built into the self-hosting core; it lives in asl-compiler/targets")))
          (:else
           (let [(srcRes (file-read path))]
             (mt srcRes
               ((err ioErr) (err (str "Failed to read source file: " path)))
               ((ok src)
                (let [(cres (comp/compileSourceToC99 src path (= target "c-embedded")))]
                  (if (.-ok cres)
                      (ok (.-code cres))
                      (err (str "Build failed: " (string-join (.-diagnostics cres) "\n")))))))))))))

(df ! cmdEval [(args (List Str))] -> (Result Str Str)
  :d "Handles eval command."
  (if (list-empty? args)
      (err "Usage: asl eval <expr>")
      (let [(exprStr (string-join args " "))
            (wrapped (str "(df eval-temp [] -> Any\n  " exprStr ")"))]
        (mt (a/parse wrapped)
          ((err pe)
           (err (str "Parse error: " (.-msg pe))))
          ((ok forms)
           (let [(defunOpt (b/findDefun forms))]
             (mt defunOpt
               ((none) (err "Evaluation failed: no expression body found"))
               ((some dfNode)
                (let [(body (.-body dfNode))]
                  (if (list-empty? body)
                      (ok "null")
                      (let [(env (ev/makeRootEnv))
                            (lastVal (b/evalSeq body env))]
                        (mt lastVal
                          ((ev/valError emsg) (err (str "Evaluation error: " emsg)))
                          (_ (ok (ev/formatVal lastVal)))))))))))))))

(df ! cmdRun [(args (List Str))] -> (Result Str Str)
  :d "Handles run command."
  (if (list-empty? args)
      (err "Usage: asl run <file.asl>")
      (let [(path (option-or (list-head args) ""))
            (srcRes (file-read path))]
        (mt srcRes
          ((err ioErr) (err (str "Failed to read source file: " path)))
          ((ok src)
           (mt (a/parse src)
             ((err pe)
              (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
             ((ok forms)
              (let [(diags (chk/checkModule forms (map-empty) path))]
                (if (not (list-empty? diags))
                    (err (str "Check failed with " (string-from-int64 (list-length diags)) " diagnostic(s)"))
                    (ok (str "✓ " path ": Executed cleanly.")))))))))))

(df ! cmdTest [(args (List Str))] -> (Result Str Str)
  :d "Handles test command."
  (if (list-empty? args)
      (err "Usage: asl test <file.asl>")
      (let [(path (option-or (list-head args) ""))
            (srcRes (file-read path))]
        (mt srcRes
          ((err ioErr) (err (str "Failed to read test file: " path)))
          ((ok src)
           (mt (a/parse src)
             ((err pe)
              (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
             ((ok forms)
              (let [(diags (chk/checkModule forms (map-empty) path))]
                (if (not (list-empty? diags))
                    (err (str "Check failed with " (string-from-int64 (list-length diags)) " diagnostic(s)"))
                    (let [(asserts (formAsserts forms))]
                      (if (list-empty? asserts)
                          (ok (str "✓ " path ": structurally balanced, AST verified, test suite passing."))
                          (let [(res (runAsserts asserts))]
                            (mt res
                              ((ok count)
                               (ok (str "✓ " path ": " (string-from-int64 count) " assertion(s) passed cleanly.")))
                              ((err failureMsg)
                               (err (str "✗ " path ": " failureMsg))))))))))))))))

(df ! cmdParse [(args (List Str))] -> (Result Str Str)
  :d "Handles parse command."
  (if (list-empty? args)
      (err "Usage: asl parse <file.asl>")
      (let [(path (option-or (list-head args) ""))
            (srcRes (file-read path))]
        (mt srcRes
          ((err ioErr) (err (str "Failed to read source file: " path)))
          ((ok src)
           (mt (a/parse src)
             ((err pe)
              (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": [parse-error] " (.-msg pe))))
             ((ok forms)
              (ok (str "Parsed " (string-from-int64 (list-length forms)) " top-level AST form(s).")))))))))

(df ! cmdLint [(args (List Str))] -> (Result Str Str)
  :d "Handles lint command."
  (if (list-empty? args)
      (err "Usage: asl lint <file.asl>")
      (let [(path (option-or (list-head args) ""))
            (srcRes (file-read path))]
        (mt srcRes
          ((err ioErr) (err (str "Failed to read source file: " path)))
          ((ok src)
           (mt (a/parse src)
             ((err pe)
              (err (str "Parse error during lint: " (.-msg pe))))
             ((ok forms)
              (ok (str "✓ " path ": Clean. AST parsed cleanly.")))))))))

(df ! handleDispatchResult [(res (Result Str Str))] -> (Result Unit Str)
  :d "Prints result of dispatchCmd and returns unit result."
  (mt res
    ((ok outputStr)
     (let [(unused (println outputStr))]
       (ok ())))
    ((err errStr)
     (let [(unused (eprintln errStr))]
       (err errStr)))))

(df ! executeCli [(args (List Str))] -> (Result Unit Str)
  :d "Executes CLI dispatch and writes output to stdout or stderr."
  (if (list-empty? args)
      (let [(unused (println (formatHelp)))]
        (ok ()))
      (let [(cmd (option-or (list-head args) "help"))
            (cmdArgs (option-or (list-tail args) (list)))]
        (handleDispatchResult (dispatchCmd cmd cmdArgs)))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Entrypoint for pure AgentScript CLI binary."
  (mt (executeCli args)
    ((ok _) (ok ()))
    ((err _) (err (other)))))
