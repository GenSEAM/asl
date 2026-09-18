(module asl-cli/bootstrap
  :d "Sovereign bootstrap entrypoint for native ISO C99 self-hosting binary."
  :x [dispatch main formatVersion formatHelp]
  :i [])

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

(df ! dispatch [(args (List Str))] -> (Result Unit Str)
  :d "Dispatches command-line arguments to the pure AgentScript bootstrap CLI."
  (if (list-empty? args)
      (let [(unused (println (formatHelp)))]
        (ok ()))
      (let [(cmd (option-or (list-head args) "help"))]
        (cond
          ((or (= cmd "help") (or (= cmd "-h") (= cmd "--help")))
           (let [(unused (println (formatHelp)))]
             (ok ())))
          ((or (= cmd "version") (or (= cmd "-v") (= cmd "--version")))
           (let [(unused (println (formatVersion)))]
             (ok ())))
          (:else
           (err (str "Unknown command '" cmd "'. Run 'asl help' for usage.")))))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Top-level main entrypoint for compiled pure ASL bootstrap CLI."
  (mt (dispatch args)
    ((ok _) (ok ()))
    ((err msg)
     (let [(unused (eprintln msg))]
       (err (other))))))

