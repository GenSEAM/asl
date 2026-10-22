(module asl-cli/cli :x [formatVersion formatHelp checkGateFiles dispatchRpc dispatchCmd executeCli main] :i [(ast :a a) (compiler :a comp) (asl-checker/types :a ty) (asl-checker/check :a chk) (reader :a rd) (batch :a b) (migrate :a mig) (asl-cli/patch :a patchCli) (asl-cli/impact :a impactCli) (asl-cli/check :a checkCli) (asl-cli/watch :a watchCli) (asl-cli/heal :a healCli) (asl-cli/digest :a digestCli) (asl-cli/auditCmd :a auditCli) (asl-cli/lensCmd :a lensCmd) (asl-cli/consiliumCmd :a consiliumCmd)])

fn formatVersion -> Str
  "asl 0.1.0 (pure AgentSlang self-hosted toolchain)"

fn formatHelp -> Str
  (str "AgentSlang Native CLI (Unified Full S-Expression Toolchain)\n"
       "Usage: asl '(:query ...) (:read ...)'   [Implicit parallel batch execution]\n"
       "   or: asl <command> [args...]          [First-class toolchain subcommands]\n"
       "   or: asl rpc '(:batch ...)'           [Explicit batch RPC evaluation]\n"
       "   or: asl check <file>                 [Semantic check module]\n"
       "   or: asl build <file>                 [Compile module to C99]\n"
       "   or: asl run <file>                   [Execute main function of module]\n"
       "   or: asl test <file>                  [Run module test assertions]\n"
       "   or: asl migrate [--dry-run|--check] <file> [Syntax migration utility]\n"
       "   or: asl '(:tools)'                   [Introspect self-describing tool catalog]\n"
       "   or: asl '(:where)'                   [Situational guidance & active invariants]\n\n"
       "First-Class Unified Ecosystem Capabilities:\n"
       "  lens [cmd|opt]     Sovereign multi-lens discovery & multi-agent Popperian audit\n"
       "  consilium [cmd]    Multi-LLM Frontier Council (Astra, DeepSeek, GLM >=75% consensus)\n"
       "  mesh [cmd]         24/7 Autonomous agent mesh daemon & shard intent sweeps\n"
       "  relay, rla [cmd]   Sovereign proxy relay & multi-model orchestration gateway\n"
       "  gateway [cmd]      Universal L7 cognitive gateway & hallucination interception proxy\n\n"
       "Agent Operations (Pure S-Expressions):\n"
       "  (:tools)                                Introspect authoritative runtime tool registry\n"
       "  (:manage :action <a> ...)               Resident daemon process supervision & logs\n"
       "  (:lens :file <f> [:lenses (<l> ...)])   Sovereign multi-lens analytical verification\n"
       "  (:query <text> [:scope <s>] [:limit <n>]) Bounded AST & symbol semantic search\n"
       "  (:read :file <f> [:symbol <s>] [:anchor <a>] [:limit <n>]) Bounded AST slice retrieval\n"
       "  (:edit :file <f> :old <target> :new <replacement>) Virtual RAM buffer staging\n"
       "  (:diff [:file <f>])                     Inspect staged RAM diffs before flush\n"
       "  (:flush)                                Atomically persist staged edits to disk\n"
       "  (:discard)                              Clear pending RAM modifications\n"
       "  (:check [:file <f>])                    Verify Dyck-1 delimiter balance & syntax\n"
       "  (:test [:file <f>])                     Execute assertions under verification\n"
       "  (:doctor)                               Audit measured capabilities & invariants\n"
       "  (:note <subcmd> ...)                    Working memory recorder and query surface\n\n"
       "Use 'asl help --full' for host environment administration.\n")

fn formatDiagnostic d: ty/Diagnostic -> Str
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message)

fn formatDiagnostics diags: (List ty/Diagnostic) -> Str
  (stringJoin (map (fn [(d ty/Diagnostic)] -> Str (formatDiagnostic d)) diags) "\n")

fn shellQuote s: Str -> Str
  (str "'" (stringReplace s "'" "'\\''") "'")

fn checkGateSrc! files: (List Str) count: I64 path: Str srcRes: (Result Str Str) -> (Result Str Str)
  (match srcRes ((err _) (err (str "Failed to read gate target file: " path))) ((ok src) (match (a/parse src) ((err pe) (if (stringContains? pe.msg "not kebab-case") (checkGateFilesStep! (optionOr (listTail files) (list)) (+ count 1)) (err (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg)))) ((ok _) (checkGateFilesStep! (optionOr (listTail files) (list)) (+ count 1))))))

fn checkGateFilesStep! files: (List Str) count: I64 -> (Result Str Str)
  (match (listHead files) ((none) (ok (str "✓ [Pure ASL Gate] " (stringFromInt64 count) " file(s) verified cleanly."))) ((some path) (checkGateSrc! files count path (fileReadString path))))

fn ! checkGateFiles files: (List Str) -> (Result Str Str)
  (if (listEmpty? files) (err "Usage: asl gate <file1.asl> [file2.asl ...]") (checkGateFilesStep! files 0))

fn ! dispatchRpc args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl rpc '(:batch ...)'") (let [(payload (stringJoin args " "))] (b/evalBatch! payload)))

fn ! cmdSysDelegate targetBin: Str args: (List Str) -> (Result Str Str)
  (let [(quotedArgs (map (fn [(a Str)] -> Str (shellQuote a)) args))
        (cmdStr (str targetBin (if (listEmpty? quotedArgs) "" (str " " (stringJoin quotedArgs " ")))))
        (res (processRun cmdStr))]
    (if (= res.exitCode 0)
      (ok res.stdout)
      (err (if (stringEmpty? res.stderr) res.stdout res.stderr))))

fn ! dispatchCmd cmd: Str args: (List Str) -> (Result Str Str)
  (cond ((= cmd "rpc") (dispatchRpc args))
        ((or (stringStartsWith? cmd "(") (stringStartsWith? cmd ":batch")) (dispatchRpc (cons cmd args)))
        ((or (= cmd "version") (or (= cmd "-v") (= cmd "--version"))) (ok (formatVersion)))
        ((or (= cmd "help") (or (= cmd "-h") (= cmd "--help"))) (ok (formatHelp)))
        ((= cmd "lens") (lensCmd/runLensCommand args))
        ((= cmd "consilium") (consiliumCmd/runConsiliumCommand args))
        ((= cmd "mesh") (cmdSysDelegate "bin/asl mesh" args))
        ((or (= cmd "relay") (= cmd "rla")) (cmdSysDelegate "bin/asl-gateway" args))
        ((= cmd "gateway") (cmdSysDelegate "bin/asl-gateway" args))
        ((= cmd "full") (if (listEmpty? args) (ok (formatHelp)) (dispatchCmd (optionOr (listHead args) "help") (optionOr (listTail args) (list)))))
        ((= cmd "gate") (checkGateFiles args))
        ((= cmd "check") (cmdCheck args))
        ((= cmd "migrate") (mig/runMigrate args))
        ((= cmd "build") (cmdBuild args))
        ((= cmd "eval") (cmdEval args))
        ((= cmd "run") (cmdRun args))
        ((= cmd "test") (cmdTest args))
        ((= cmd "parse") (cmdParse args))
        ((= cmd "lint") (cmdLint args))
        ((= cmd "tool") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "launch") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "chk") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "where") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "conform") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "ir") (err "ERR_NOT_IMPLEMENTED"))
        ((= cmd "impact") (impactCli/runImpactCommand! args))
        ((= cmd "audit") (auditCli/runAuditCommand args))
        ((= cmd "patch") (patchCli/runPatchCommand! args))
        ((= cmd "watch") (watchCli/runWatchCommand! args))
        ((= cmd "heal") (healCli/runHealCommand! args))
        ((= cmd "outline") (digestCli/runOutlineCommand! args))
        (else (err (str "Unknown command '" cmd "'. Run 'asl help' for usage."))))

fn ! cmdCheck args: (List Str) -> (Result Str Str)
  (checkCli/runCheckCommand! args)

fn ! cmdBuild args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl build [--target <c99|c-embedded>] <file.asl>") (let [(hasTargetFlag (and (>= (listLength args) 2) (= (optionOr (listHead args) "") "--target"))) (target (if hasTargetFlag (optionOr (listGet args 1) "c99") "c99")) (restArgs (if hasTargetFlag (optionOr (listTail (optionOr (listTail args) (list))) (list)) args)) (path (optionOr (listHead restArgs) ""))] (cond ((stringEmpty? path) (err "Usage: asl build [--target <c99|c-embedded>] <file.asl>")) ((and (!= target "c99") (!= target "c-embedded")) (err (str "Target '" target "' is not built into the self-hosting core; it lives in asl-compiler/targets"))) (else (let [(srcRes (fileReadString path))] (match srcRes ((err ioErr) (err (str "Failed to read source file: " path))) ((ok src) (let [(cres (comp/compileSourceToC99 src path (= target "c-embedded")))] (if cres.ok (ok cres.code) (err (str "Build failed: " (stringJoin cres.diagnostics "\n"))))))))))))

; (:m :ref NATIVE-LOWER-GAPS :do "with no ASL_HOST, run, test and eval go to the native CLI of the toolchain bin/asl names in ASL_CLI_ROOT for every child, not to a guessed path")
fn resolveHostBinary! -> (Result Str Str)
  (let [(envHost (optionOr (envGet "ASL_HOST") ""))
        (cliRoot (optionOr (envGet "ASL_CLI_ROOT") ""))
        (native (str cliRoot "/bin/asl"))]
    (if (stringEmpty? envHost)
      (if (and (not (stringEmpty? cliRoot)) (ok? (fileStat native)))
        (ok native)
        (err "neither ASL_HOST nor ASL_CLI_ROOT names a runner (asl/host/src was retired by HL-DELETE) -- run through bin/asl, which sets ASL_CLI_ROOT, or set ASL_HOST to a real interpreter binary"))
      (match (fileStat envHost)
        ((ok _) (ok envHost))
        ((err _) (err (str "ASL_HOST binary not found: " envHost))))))

fn ! cmdEval args: (List Str) -> (Result Str Str)
  (if (listEmpty? args)
    (err "Usage: asl eval <expr>")
    (let [(hostRes (resolveHostBinary!))]
      (match hostRes
        ((err e) (err e))
        ((ok hostBin)
         (let [(exprStr (stringJoin args " "))
               (evalCmd (str (shellQuote hostBin) " eval " (shellQuote exprStr)))
               (procRes (processRun evalCmd))]
           (if (= procRes.exitCode 0)
             (ok (stringTrim procRes.stdout))
             (err (stringTrim (if (stringEmpty? procRes.stderr) procRes.stdout procRes.stderr)))))))))

fn ! cmdRun args: (List Str) -> (Result Str Str)
  (if (listEmpty? args)
    (err "Usage: asl run <file.asl>")
    (let [(hostRes (resolveHostBinary!))]
      (match hostRes
        ((err e) (err e))
        ((ok hostBin)
         (let [(path (optionOr (listHead args) ""))
               (srcRes (fileReadString path))]
           (match srcRes
             ((err ioErr) (err (str "Failed to read source file: " path)))
             ((ok src)
              (match (a/parse src)
                ((err pe) (err (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg)))
                ((ok forms)
                 (let [(diags (chk/checkModule forms (mapEmpty) path))]
                   (if (not (listEmpty? diags))
                     (err (formatDiagnostics diags))
                     (let [(quotedArgs (map (fn [(a Str)] -> Str (shellQuote a)) args))
                           (runCmd (str (shellQuote hostBin) " run " (stringJoin quotedArgs " ")))
                           (procRes (processRun runCmd))]
                       (if (= procRes.exitCode 0)
                         (ok procRes.stdout)
                         (err (if (stringEmpty? procRes.stderr) procRes.stdout procRes.stderr)))))))))))))))

fn ! cmdTest args: (List Str) -> (Result Str Str)
  (cond
    ((listEmpty? args) (err "Usage: asl test <file.asl>"))
    ((listAny? stringEmpty? args) (err "ERR_EMPTY_PATH: asl test takes one or more non-empty file paths"))
    (else
    (let [(hostRes (resolveHostBinary!))]
      (match hostRes
        ((err e) (err e))
        ((ok hostBin)
         (let [(quotedArgs (map (fn [(a Str)] -> Str (shellQuote a)) args))
               (testCmd (str (shellQuote hostBin) " test " (stringJoin quotedArgs " ")))
               (procRes (processRun testCmd))]
           (if (= procRes.exitCode 0)
             (ok (stringTrim procRes.stdout))
             (err (stringTrim (if (stringEmpty? procRes.stderr) procRes.stdout procRes.stderr))))))))))

fn ! cmdParse args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl parse <file.asl>") (let [(path (optionOr (listHead args) "")) (srcRes (fileReadString path))] (match srcRes ((err ioErr) (err (str "Failed to read source file: " path))) ((ok src) (match (a/parse src) ((err pe) (err (str path ":" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": [parse-error] " pe.msg))) ((ok forms) (ok (str "Parsed " (stringFromInt64 (listLength forms)) " top-level AST form(s)."))))))))

fn ! cmdLint args: (List Str) -> (Result Str Str)
  (if (listEmpty? args) (err "Usage: asl lint <file.asl>") (let [(path (optionOr (listHead args) "")) (srcRes (fileReadString path))] (match srcRes ((err ioErr) (err (str "Failed to read source file: " path))) ((ok src) (match (a/parse src) ((err pe) (err (str "Parse error during lint: " pe.msg))) ((ok forms) (ok (str "✓ " path ": Clean. AST parsed cleanly."))))))))

fn outputLine value: Str -> Str
  (if (stringEndsWith? value "\n")
    (optionOr (stringSlice value 0 (- (stringLength value) 1)) "")
    value)

fn ! handleDispatchResult cmd: Str args: (List Str) res: (Result Str Str) -> (Result Unit Str)
  (match res
    ((ok outputStr) (let [(unused (println (outputLine outputStr)))] (ok ())))
    ((err errStr)
     (if (and (= cmd "lens")
              (and (or (= (optionOr (listHead args) "") "info") (= (optionOr (listHead args) "") "describe"))
                   (listEmpty? (optionOr (listTail args) (list)))))
       (let [(unused (println (outputLine errStr)))] (err errStr))
       (let [(unused (eprintln (outputLine errStr)))] (err errStr)))))

fn ! executeCli args: (List Str) -> (Result Unit Str)
  (if (listEmpty? args) (let [(unused (println (formatHelp)))] (ok ())) (let [(cmd (optionOr (listHead args) "help")) (cmdArgs (optionOr (listTail args) (list)))] (handleDispatchResult cmd cmdArgs (dispatchCmd cmd cmdArgs))))

fn ! main args: (List Str) -> Int64
  (match (executeCli args) ((ok _) 0) ((err _) 1))
