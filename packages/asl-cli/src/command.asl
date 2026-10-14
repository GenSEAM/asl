(module asl-cli/command
  :x [main dispatch! route! asnEcho testFiles!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/lensCmd :a lens) (asl/packages/asl-cli/src/consiliumCmd :a consilium) (asl/packages/asl-cli/src/verify :a verify) (asl/packages/asl-cli/src/pack :a pack) (asl/packages/asl-cli/src/target :a target) (asl/packages/asl-cli/src/build :a build) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-gates/src/suiteRunner :a runner)])

(schema Open
  (:f closer String)
  (:f pos Int64)
  (:f opener String))

fn helpText -> String
  (str "AgentSlang (ASL) Unified Toolchain & Runtime\n"
       "\n"
       "Human CLI Usage:\n"
       "  asl <command> [args...]\n"
       "\n"
       "Commands:\n"
       "  check <file>        Balance, then asl-host check for .asl (names, arity, enums); bare: every tracked file\n"
       "  test <file|dir>     Run suites; --changed [BASE] selects impacts (default main), --dry-run lists without execution\n"
       "  parse <file>        Count top-level forms on asl-host\n"
       "  eval [--native] <expr> Host evaluates expressions and echoes (:keyword ...) as ASN data; --native evaluates a single Int64 expression only\n"
       "  build <file>        Not implemented until R1 (ERR_UNIMPLEMENTED)\n"
       "  pack [options]      Assemble, package and compile target distribution bundles\n"
       "  intel <subcmd>      Unified Code Intelligence: coupling, impact, outline, query, deadcode, vacuity, graph, complexity\n"
       "  graph [opts]        Alias to 'intel graph' (whole-repo call graph, connectivity, architectural hotspots)\n"
       "  complexity [target] Alias to 'intel complexity' (cyclomatic complexity, expressions, purity)\n"
       "  coupling [opts]     Alias to 'intel coupling' (short-range cohesion, inter-package DAG, fictions)\n"
       "  audit <subcmd>      Run workspace audit (gates, consistency, coupling, foreign, steps, naming, closure)\n"
       "  engine [cmd]        Resident ASL engine runtime, supervisor, and process management (start, stop, status, ping)\n"
       "  version             Display toolchain version\n"
       "  help                Display this usage guide\n"
       "\n"
       "Agent Plane Usage:\n"
       "  Agents interact exclusively via pure Dyck-1 ASN S-expressions:\n"
       "    asl '(:tools)'                      Introspect machine-readable tool schema\n"
       "    asl '(:intel :op <op> ...)'         Unified Code Intelligence query (:coupling :impact :outline :query)\n"
       "    asl '(:op ...)'                     Execute single pure-ASN operation\n"
       "    asl '(:op1 ...) (:op2 ...)'         Compound multi-operation batch\n"
       "    asl -f FILE                         Run the forms in FILE, as asl '<forms>' would\n"
       "    asl - <<'ASN'                       Run forms from stdin; a quoted heredoc keeps single quotes")

fn ! preludeEnv -> (List String)
  (let [(prelude (optionOr (envGet "ASL_CLI_USER_PRELUDE") ""))]
    (if (stringEmpty? prelude) (list) (list (str "ASL_PRELUDE=" prelude))))

fn rest args: (List String) -> (List String)
  (optionOr (listTail args) (list))

fn first args: (List String) -> String
  (optionOr (listHead args) "")

fn ! version! ctx: sys/Context -> Int64
  (do (sys/say! "asl 0.1.0 (bin/asl)")
      (if (sys/executable? ctx.hostBin)
        (sys/run! (list ctx.hostBin "--version"))
        (do (sys/say! "asl-host absent: build it with sh asl/host/build.sh or set ASL_HOST") 0)))

fn retired! cmd: String pointer: String -> Int64
  (do (sys/say! (str "(:" cmd " :status :failed :error ERR_RETIRED :message \"asl " cmd " ran bin/asl-core, which is retired; " pointer "\")")) 2)

fn ! forms! ctx: sys/Context args: (List String) -> Int64
  (let [(entry (str ctx.root "/asl/packages/asl-forms/src/main.asl"))]
    (if (and (sys/executable? ctx.hostBin) (sys/isFile? entry))
      (mt (sys/captureWith! (cons ctx.hostBin (cons "run" (cons entry args))) (none)
                            (list (str "SCRIPT_DIR=" ctx.scriptDir) (str "ROOT_DIR=" ctx.root)))
        ((err e) (do (sys/sayErr! e) 1))
        ((ok out)
          (let [(text (sys/stripTrailingNewlines out.stdout))]
            (do
              (sys/say! text)
              (if (stringEmpty? out.stderr) true (sys/sayErr! (sys/stripTrailingNewlines out.stderr)))
              out.exitCode))))
      (do (sys/sayErr! "Error: ASL host or asl-forms package entry not found") 1)))

fn ! delegate! ctx: sys/Context name: String args: (List String) missing: String -> Int64
  (mt (sys/findCommand! ctx name)
    ((some path) (sys/execv! (cons path args) (list)))
    ((none) (do (sys/sayErr! missing) 1)))

fn ! tool! ctx: sys/Context name: String args: (List String) -> Int64
  (delegate! ctx name args (str "Error: " name " binary or tool not found"))

fn ! intel! ctx: sys/Context args: (List String) -> Int64
  (let [(entry (str ctx.root "/asl/packages/asl-intel/src/main.asl"))]
    (if (and (sys/executable? ctx.hostBin) (sys/isFile? entry))
      (sys/runWith! (cons ctx.hostBin (cons "run" (cons entry args))) (list (str "ASL_INTEL_WORKSPACE=" ctx.root)))
      (do (sys/sayErr! "Error: ASL host or intel package entry not found") 1)))

fn pySpace? c: String -> Bool
  (listContains? (list " " "\t" "\n" "\r" "\u{b}" "\u{c}" "\u{1c}" "\u{1d}" "\u{1e}" "\u{1f}" "\u{85}" "\u{a0}") c)

fn dropSpace chars: (List String) -> (List String)
  (mt (listHead chars) ((some c) (if (pySpace? c) (dropSpace (rest chars)) chars)) ((none) chars))

fn pyStrip chars: (List String) -> (List String)
  (listReverse (dropSpace (listReverse (dropSpace chars))))

fn closerOf c: String -> String
  (cond ((= c "(") ")") ((= c "[") "]") ((= c "{") "}") (else ""))

fn scan chars: (List String) i: Int64 stack: (List Open) inStr: Bool escaped: Bool -> (Pair String (Pair Bool (List Open)))
  (mt (listHead chars)
    ((none) (pair "" (pair inStr stack)))
    ((some c)
      (let [(more (rest chars))]
        (cond
          (inStr
            (cond
              (escaped (scan more (+ i 1) stack true false))
              ((= c "\\") (scan more (+ i 1) stack true true))
              ((= c "\"") (scan more (+ i 1) stack false false))
              (else (scan more (+ i 1) stack true false))))
          ((= c "\"") (scan more (+ i 1) stack true false))
          ((not (stringEmpty? (closerOf c))) (scan more (+ i 1) (cons (Open :closer (closerOf c) :pos i :opener c) stack) false false))
          ((or (= c ")") (or (= c "]") (= c "}")))
            (mt (listHead stack)
              ((none) (pair (str "unexpected " c " at byte " (stringFromInt64 i)) (pair false stack)))
              ((some top)
                (if (!= top.closer c)
                  (pair (str "unexpected " c " at byte " (stringFromInt64 i)) (pair false stack))
                  (let [(popped (optionOr (listTail stack) (list)))]
                    (if (and (listEmpty? popped) (not (listEmpty? (pyStrip more))))
                      (pair (str "text after the form at byte " (stringFromInt64 (+ i 1))) (pair false popped))
                      (scan more (+ i 1) popped false false)))))))
          (else (scan more (+ i 1) stack false false))))))

fn letter? c: String -> Bool
  (let [(b (stringToBytes c))] (and (= (bytesLength b) 1) (or (and (>= (bytesGet b 0) 65) (<= (bytesGet b 0) 90)) (and (>= (bytesGet b 0) 97) (<= (bytesGet b 0) 122)))))

fn nameChar? c: String -> Bool
  (or (letter? c) (listContains? (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "_" "." "-") c))

fn afterName chars: (List String) -> (List String)
  (mt (listHead chars) ((some c) (if (nameChar? c) (afterName (rest chars)) chars)) ((none) chars))

fn keywordHead? chars: (List String) -> Bool
  (and (= (first chars) "(")
       (and (= (first (rest chars)) ":")
            (and (letter? (first (rest (rest chars))))
                 (let [(next (first (afterName (rest (rest (rest chars))))))]
                   (or (= next ")") (pySpace? next))))))

fn asnEcho text: String -> (Pair String Int64)
  (let [(chars (pyStrip (stringChars text)))
        (result (scan chars 0 (list) false false))
        (found (pairFirst result))
        (openString (pairFirst (pairSecond result)))
        (stack (pairSecond (pairSecond result)))
        (problem (cond
                   ((not (stringEmpty? found)) found)
                   (openString "unterminated string")
                   ((not (listEmpty? stack)) (mt (listHead stack) ((some top) (str "unclosed " top.opener " at byte " (stringFromInt64 top.pos))) ((none) "")))
                   ((not (keywordHead? chars)) "the head is not a keyword")
                   (else "")))]
    (if (stringEmpty? problem)
      (pair (stringJoin chars "") 0)
      (pair (str "(:eval :status :failed :error ERR_ASN_SYNTAX :message \"" problem "\")") 2)))

fn ! crawler! ctx: sys/Context args: (List String) -> Int64
  (let [(entry (str ctx.root "/asl/packages/asl-crawler/src/crawler.asl"))]
    (if (and (sys/executable? ctx.hostBin) (sys/isFile? entry))
      (sys/execv! (cons ctx.hostBin (cons "run" (cons entry args))) (list))
      (do (sys/sayErr! "Error: ASL host or crawler package entry not found") 1)))

fn outputLine value: String -> String
  (if (stringEndsWith? value "\n") (optionOr (stringSlice value 0 (- (stringLength value) 1)) "") value)

fn ! cliResult! cmd: String args: (List String) res: (Result String String) -> Int64
  (mt res
    ((ok out) (do (sys/say! (outputLine out)) 0))
    ((err e)
     (let [(sub (optionOr (listHead args) ""))
           (usageOnStdout (and (= cmd "lens") (and (or (= sub "info") (= sub "describe")) (listEmpty? (optionOr (listTail args) (list))))))]
       (do (if usageOnStdout (sys/say! (outputLine e)) (sys/sayErr! (outputLine e))) 1))))

fn ! engine! ctx: sys/Context args: (List String) -> Int64
  (let [(entry (str ctx.root "/asl/packages/asl-engine/src/cli.asl"))]
    (if (and (sys/executable? ctx.hostBin) (sys/isFile? entry))
      (sys/execv! (cons ctx.hostBin (cons "run" (cons entry args))) (list (str "ASL_ENGINE_ENTRY=" entry) (str "ASL_HOST=" ctx.hostBin)))
      (do (sys/sayErr! "Error: ASL host or asl-engine package entry not found") 1)))

fn ! mesh! ctx: sys/Context args: (List String) -> Int64
  (let [(entry (str ctx.root "/asl/tools/mesh/cmd.asl"))]
    (if (and (sys/executable? ctx.hostBin) (sys/isFile? entry))
      (sys/execv! (cons ctx.hostBin (cons "run" (cons entry args))) (list (str "ROOT_DIR=" ctx.root)))
      (do (sys/sayErr! "Error: ASL host or mesh tool entry not found") 1)))

fn ! eval! ctx: sys/Context args: (List String) -> Int64
  (if (= (first args) "--native")
    (let [(cwdReal (resultOr (realPath ".") "."))
          (rootReal (resultOr (realPath ctx.root) ctx.root))]
      (if (or (listEmpty? (rest args)) (not (sys/executable? ctx.hostBin)) (!= cwdReal rootReal))
        (do (sys/sayErr! (str "usage: asl eval --native EXPR (requires asl-host and the workspace root " ctx.root ")")) 2)
        (sys/execv! (list ctx.hostBin "run" (str ctx.root "/tools/nativeTest.asl") "eval" (stringJoin (rest args) " ")) (list))))
  (let [(expr (stringJoin args " "))]
    (if (not (sys/executable? ctx.hostBin))
      (do (sys/say! (sys/hostAbsent "eval")) 2)
      (let [(trimmed (sys/trimLeft expr))]
        (if (stringStartsWith? trimmed "(:")
          (let [(r (asnEcho trimmed))] (do (sys/say! (pairFirst r)) (pairSecond r)))
          (sys/execv! (list ctx.hostBin "eval" expr) (list)))))))

fn ! browserUrl -> String
  (str "http://127.0.0.1:" (optionOr (envGet "ASL_GATEWAY_PORT") "8765") "/api/asl/browser")

fn ! curl! argv: (List String) -> Int64
  (mt (sys/onPath! "curl")
    ((none) (do (sys/say! "(:browser :status :failed :error ERR_TOOL_ABSENT :message \"curl is not on PATH; asl browser reaches the gateway through curl\")") 1))
    ((some path)
      (let [(rc (sys/run! (cons path argv)))]
        (if (!= rc 0) rc (do (sys/say! "") 0)))))

fn browserArgs args: (List String) target: String browser: String payload: String -> (Result (Pair String (Pair String String)) Int64)
  (mt (listHead args)
    ((none) (ok (pair target (pair browser payload))))
    ((some a)
      (cond
        ((= a "--target") (if (< (listLength args) 2) (err 1) (browserArgs (rest (rest args)) (first (rest args)) browser payload)))
        ((= a "--browser") (if (< (listLength args) 2) (err 1) (browserArgs (rest (rest args)) target (first (rest args)) payload)))
        (else (browserArgs (rest args) target browser (if (stringEmpty? payload) a (str payload " " a)))))))

fn ! browser! args: (List String) -> Int64
  (let [(sub (first args))]
    (cond
      ((or (= sub "targets") (or (= sub "list") (= sub "")))
        (curl! (list "-s" "--noproxy" "*" "-H" "Accept: application/asn+sexpr" (str (browserUrl) "/target/list"))))
      ((= sub "exec")
        (mt (browserArgs (rest args) "" "" "")
          ((err code) code)
          ((ok parsed)
            (let [(target (pairFirst parsed)) (browserName (pairFirst (pairSecond parsed))) (payload (pairSecond (pairSecond parsed)))]
              (if (stringEmpty? payload)
                (do (sys/sayErr! "Error: missing action payload for asl browser exec") 1)
                (curl! (list "-s" "--noproxy" "*" "-X" "POST" "-H" "Content-Type: application/asn+sexpr" "-d" payload
                             (str (browserUrl) "/exec" (cond ((not (stringEmpty? target)) (str "?target=" target)) ((not (stringEmpty? browserName)) (str "?browser=" browserName)) (else ""))))))))))
      (else (do (sys/sayErr! "Usage: asl browser <targets|exec> [options]") 1))))

fn ! cockpit! ctx: sys/Context args: (List String) -> Int64
  (if (listContains? args "--tui")
    (do (sys/say! "[Cockpit] Launching Terminal UI Observatory...")
        (let [(tui (str ctx.root "/asl/packages/asl-agent/src/tui.asl"))]
          (if (sys/isFile? tui)
            (dispatch! ctx "run" (cons tui args))
            (do (sys/sayErr! "[Cockpit] TUI component not found.") 1))))
    (do (sys/say! "[Cockpit] Opening Sovereign Cockpit at http://127.0.0.1:8765/cockpit")
        (mt (sys/onPath! "open")
          ((some path) (sys/run! (list path "http://127.0.0.1:8765/cockpit")))
          ((none) 0))))

fn intelAudit? sub: String -> Bool
  (listContains? (list "coupling" "deadcode" "vacuity" "sweep" "graph" "complexity" "stubs" "vitality" "trace" "full" "all" "system") sub)

fn ! audit! ctx: sys/Context args: (List String) -> Int64
  (let [(given (first args))
        (sub (if (stringEmpty? given) "consistency" given))]
    (if (intelAudit? sub)
      (intel! ctx (cons sub (rest args)))
      (sys/execv! (cons "/usr/bin/python3" (cons (str ctx.root "/scripts/audit/audit.py") (cons sub (rest args)))) (list))))

fn asnQuote v: String -> String
  (str "\"" (stringReplace (stringReplace v "\\" "\\\\") "\"" "\\\"") "\"")

fn blank? s: String -> Bool
  (let [(b (stringToBytes s))] (= (bytesLength b) (fold (fn [(n Int64) (i Int64)] -> Int64 (if (or (= (bytesGet b i) 32) (and (>= (bytesGet b i) 9) (<= (bytesGet b i) 13))) (+ n 1) n)) 0 (range 0 (bytesLength b)))))

fn ! webDelegate! ctx: sys/Context op: String field: String args: (List String) -> Int64
  (forms! ctx (list (str "(:" op " :" field " " (asnQuote (stringJoin args " ")) ")")))

fn ! docCmd! ctx: sys/Context args: (List String) -> Int64
  (let [(arg (first args))]
    (if (blank? arg)
      (do (sys/say! "(:receipt :doc :rejected :error-code \":ERR_MISSING_ARG\" :message \"doc requires SYMBOL (path#name) or FILE\")") 1)
      (webDelegate! ctx "doc" (if (stringContains? arg "#") "symbol" "file") (list arg))))

fn afterEquals a: String -> String
  (mt (stringIndexOf a "=") ((some i) (optionOr (stringSlice a (+ i 1) (stringLength a)) "")) ((none) a))

fn eqFlag? a: String names: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringStartsWith? a (str n "="))) names)

fn noteFields args: (List String) prev: String fields: (List String) -> (List String)
  (mt (listHead args)
    ((none) fields)
    ((some a)
      (let [(claim (optionOr (listGet fields 0) "")) (kind (optionOr (listGet fields 1) "")) (scope (optionOr (listGet fields 2) "")) (date (optionOr (listGet fields 3) ""))
            (byPrev (cond
                      ((listContains? (list "--claim" "--fact" "--text") prev) (list a kind scope date))
                      ((listContains? (list "--kind" "--topic") prev) (list claim a scope date))
                      ((= prev "--scope") (list claim kind a date))
                      ((= prev "--date") (list claim kind scope a))
                      (else fields)))
            (c2 (optionOr (listGet byPrev 0) "")) (k2 (optionOr (listGet byPrev 1) "")) (s2 (optionOr (listGet byPrev 2) "")) (d2 (optionOr (listGet byPrev 3) ""))
            (byArg (cond
                     ((eqFlag? a (list "--claim" "--fact" "--text")) (list (afterEquals a) k2 s2 d2))
                     ((eqFlag? a (list "--kind" "--topic")) (list c2 (afterEquals a) s2 d2))
                     ((eqFlag? a (list "--scope")) (list c2 k2 (afterEquals a) d2))
                     ((eqFlag? a (list "--date")) (list c2 k2 s2 (afterEquals a)))
                     (else byPrev)))]
        (noteFields (rest args) a byArg))))

fn ! note! ctx: sys/Context args: (List String) -> Int64
  (let [(sub (first args))]
    (cond
      ((= sub "write")
        (let [(f (noteFields (rest args) "" (list "" "observation" "workspace" "")))
              (claim (optionOr (listGet f 0) "")) (date (optionOr (listGet f 3) ""))]
          (if (blank? claim)
            (do (sys/say! "(:receipt :note :rejected :error-code \":ERR_MISSING_ARG\" :message \"note write requires a non-empty --claim\")") 1)
            (forms! ctx (list (str "(:note :action :write :kind " (asnQuote (optionOr (listGet f 1) "")) " :scope " (asnQuote (optionOr (listGet f 2) "")) " :claim " (asnQuote claim)
                                   (if (stringEmpty? date) "" (str " :date " (asnQuote date))) ")"))))))
      ((= sub "list") (forms! ctx (list "(:note :action :list)")))
      ((and (= sub "query") (not (stringEmpty? (first (rest args)))))
        (forms! ctx (list (str "(:note :action :query :query " (asnQuote (first (rest args))) ")"))))
      ((stringEmpty? sub) (forms! ctx (list "(:note :action :list)")))
      (else (retired! "note" "use asl note list, asl note query TEXT or asl note write --claim TEXT"))))

fn suiteName? n: String -> Bool
  (or (stringEndsWith? n "Test.asl") (stringEndsWith? n "_test.asl"))

fn aslName? n: String -> Bool
  (stringEndsWith? n ".asl")

fn ! walk! dir: String dirReal: String suites: Bool acc: (List String) -> (List String)
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (fold (fn [(found (List String)) (n String)] -> (List String)
              (let [(p (str dir "/" n))]
                (mt (realPath p)
                  ((err _) found)
                  ((ok real)
                    (cond
                      ((!= real (str dirReal "/" n)) found)
                      ((sys/isDir? p) (walk! p real suites found))
                      ((and (sys/isFile? p) (if suites (suiteName? n) (aslName? n))) (cons p found))
                      (else found))))))
            acc names)))

fn ! findFiles! dir: String suites: Bool -> (List String)
  (mt (realPath dir)
    ((err _) (list))
    ((ok real) (listSort (walk! (if (stringEndsWith? dir "/") (optionOr (stringSlice dir 0 (- (stringLength dir) 1)) dir) dir) real suites (list)))))

fn ! testFiles! args: (List String) acc: (List String) -> (Result (List String) Int64)
  (mt (listHead args)
    ((none) (ok acc))
    ((some a)
      (cond
        ((stringEmpty? a)
          (do (sys/say! "(:test :status :failed :error ERR_EMPTY_PATH :message \"asl test: empty path argument\")") (err 2)))
        ((stringStartsWith? a "-")
          (do (sys/say! (str "(:test :status :failed :error ERR_UNKNOWN_ARG :message \"asl test takes files and directories; unknown option " a "\")")) (err 2)))
        ((sys/isDir? a)
          (let [(suites (findFiles! a true))
                (found (if (and (listEmpty? suites) (sys/isDir? (str a "/tests"))) (findFiles! (str a "/tests") false) suites))]
            (if (listEmpty? found)
              (do (sys/say! (str "(:test :status :failed :error ERR_NO_TESTS :message \"no test files under " a "\")")) (err 1))
              (testFiles! (rest args) (listAppend acc found)))))
        (else (testFiles! (rest args) (listAppend acc (list a)))))))

fn ! trace! ctx: sys/Context extra: (List String) code: Int64 -> Int64
  (let [(rc (intel! ctx (cons "trace" (cons "--summary" extra))))]
    (if (!= rc 0) rc code))

fn ! changedTest! ctx: sys/Context args: (List String) -> Int64
  (let [(restArgs (filter (fn [(a String)] -> Bool (and (!= a "--changed") (!= a "--dry-run"))) (optionOr (listTail args) (list))))
        (dryRun (listContains? args "--dry-run"))]
    (if (> (listLength restArgs) 1)
      (do (sys/say! "(:changed :status :failed :error ERR_USAGE :message \"asl test --changed [BASE] [--dry-run]\")") 2)
      (let [(base (optionOr (listHead restArgs) "main"))
            (argv (listAppend (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/sweep.asl") "changed" ctx.hostBin base) (if dryRun (list "--dry-run") (list))))]
        (sys/run! argv))))

fn ! test! ctx: sys/Context args: (List String) -> Int64
  (if (listContains? args "--changed")
    (changedTest! ctx args)
    (if (= (optionOr (listHead args) "") "--native")
    (let [(suites (optionOr (listTail args) (list)))
          (cwdReal (resultOr (realPath ".") "."))
          (rootReal (resultOr (realPath ctx.root) ctx.root))]
      (if (or (listEmpty? suites) (!= cwdReal rootReal))
        (do (sys/say! (str "(:test :status :failed :error ERR_USAGE :message \"asl test --native SUITE... runs from the workspace root " ctx.root "\")")) 2)
        (sys/execv! (cons ctx.hostBin (cons "run" (cons (str ctx.root "/tools/nativeTest.asl") suites)))
                    (list))))
    (let [(files (filter (fn [(a String)] -> Bool (!= a "--trace")) args))
          (tracing (or (listContains? args "--trace") (= (optionOr (envGet "ASL_TRACE") "0") "1")))
          (host ctx.hostBin)]
      (cond
        ((not (sys/executable? host)) (do (sys/say! (sys/hostAbsent "test")) 2))
        ((listEmpty? files)
          (let [(rc (sys/run! (list host "run" (str ctx.root "/asl/packages/asl-cli/src/sweep.asl") "test" host)))]
            (if tracing (trace! ctx (list) rc) rc)))
        (else
          (mt (testFiles! files (list))
            ((err code) code)
            ((ok paths)
              (let [(dirs (filter (fn [(a String)] -> Bool (sys/isDir? a)) files))
                    (selection (runner/selectDirectorySuites! ctx.root paths dirs))
                    (frozen (pairSecond selection))
                    (selected (pairFirst selection))
                    (note (if (listEmpty? dirs) true (sys/say! (str "(:test :frozen " (stringFromInt64 (listLength frozen)) ")"))))]
                (if (listEmpty? selected)
                  0
                  (if tracing
                    (trace! ctx (list "--target" (first files))
                            (sys/runWith! (cons host (cons "test" selected)) (preludeEnv)))
                    (sys/execv! (cons host (cons "test" selected))
                                (preludeEnv))))))))))))

fn ! runFile! ctx: sys/Context args: (List String) -> Int64
  (cond
    ((listEmpty? args) (do (sys/say! "usage: asl run FILE [ARGS]   load FILE and call its main; exit 0 iff main returns (ok ...)") 2))
    ((or (= (first args) "--help") (= (first args) "-h")) (do (sys/say! "usage: asl run FILE [ARGS]   load FILE and call its main; exit 0 iff main returns (ok ...)") 0))
    ((not (sys/executable? ctx.hostBin)) (do (sys/say! (sys/hostAbsent "run")) 2))
    (else
      (let [(argv (runArgv ctx args))]
        (sys/execv! argv (if (listContains? argv (str ctx.root "/tools/nativeTest.asl")) (list) (preludeEnv))))))

fn ! runArgv ctx: sys/Context args: (List String) -> (List String)
  (let [(file (first args))
        (host ctx.hostBin)
        (native (str ctx.root "/tools/nativeTest.asl"))
        (rootPrefix (str ctx.root "/"))
        (cwdReal (resultOr (realPath ".") "."))
        (rootReal (resultOr (realPath ctx.root) ctx.root))]
    (cond
      ((not (sys/isFile? native)) (cons host (cons "run" args)))
      ((stringStartsWith? file rootPrefix)
        (listAppend (list "/bin/sh" "-c" "cd -- \"$0\" && exec \"$@\"" ctx.root host "run" native "run" (optionOr (stringSlice file (stringLength rootPrefix) (stringLength file)) "")) (rest args)))
      ((and (= cwdReal rootReal) (not (stringStartsWith? file "/")))
        (cons host (cons "run" (cons native (cons "run" args)))))
      (else
        (mt (if (stringStartsWith? file "/") (workspaceOf! (parentDir file)) (none))
          ((some ws)
            (listAppend (list "/bin/sh" "-c" "cd -- \"$0\" && ASL_ROOT=\"$1\" && export ASL_ROOT && shift && exec \"$@\"" ws ctx.root host "run" native "run" (optionOr (stringSlice file (+ (stringLength ws) 1) (stringLength file)) "")) (rest args)))
          ((none)
            (do (sys/sayErr! (str "NATIVE-BYPASS " file " :reason " (if (stringStartsWith? file "/") "absolute-path-outside-workspace" "relative-path-from-non-root-cwd")))
                (cons host (cons "run" args))))))))

fn parentDir path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (optionOr (listSlice parts 0 (- (listLength parts) 1)) (list)) "/"))

fn ! workspaceOf! dir: String -> (Option String)
  (cond
    ((stringEmpty? dir) (none))
    ((sys/isFile? (str dir "/.asl.config.asn")) (some dir))
    (else (workspaceOf! (parentDir dir))))

fn ! check! ctx: sys/Context args: (List String) -> Int64
  (if (listEmpty? args)
    (if (not (sys/executable? ctx.hostBin))
      (do (sys/say! (sys/hostAbsent "check")) 2)
      (sys/execv! (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/sweep.asl") "check" ctx.hostBin) (list)))
    (let [(preludeEnv (preludeEnv))]
      (if (listEmpty? preludeEnv)
        (verify/checkFiles! ctx args)
        (let [(aslArgs (filter (fn [(a String)] -> Bool (stringEndsWith? a ".asl")) args))
              (otherArgs (filter (fn [(a String)] -> Bool (not (stringEndsWith? a ".asl"))) args))
              (otherRc (verify/checkFiles! ctx otherArgs))]
          (if (!= otherRc 0)
            otherRc
            (if (listEmpty? aslArgs)
              0
              (sys/runWith! (cons ctx.hostBin (cons "check" aslArgs)) preludeEnv)))))))

fn ! parse! ctx: sys/Context args: (List String) -> Int64
  (if (not (sys/executable? ctx.hostBin))
    (do (sys/say! "(:parse :status :failed :error ERR_HOST_ABSENT :message \"asl parse needs the stage-0 host; build it with sh asl/host/build.sh or set ASL_HOST\")") 2)
    (sys/execv! (cons ctx.hostBin (cons "parse" args)) (list)))

fn ! dispatch! ctx: sys/Context cmd: String args: (List String) -> Int64
  (cond
    ((or (= cmd "") (or (= cmd "-h") (or (= cmd "--help") (= cmd "help")))) (do (sys/say! (helpText)) 0))
    ((or (= cmd "-v") (or (= cmd "--version") (= cmd "version"))) (version! ctx))
    ((= cmd "eval") (eval! ctx args))
    ((= cmd "browser") (browser! args))
    ((= cmd "cockpit") (cockpit! ctx args))
    ((= cmd "intel") (intel! ctx args))
    ((= cmd "lens") (cliResult! "lens" args (lens/runLensCommand args)))
    ((= cmd "consilium") (cliResult! "consilium" args (consilium/runConsiliumCommand args)))
    ((= cmd "mesh") (mesh! ctx args))
    ((or (= cmd "relay") (or (= cmd "rla") (= cmd "gateway"))) (tool! ctx "asl-gateway" args))
    ((or (= cmd "web") (= cmd "search")) (webDelegate! ctx "search" "query" args))
    ((= cmd "research") (webDelegate! ctx "research" "topic" args))
    ((or (= cmd "crawler") (= cmd "crawl")) (crawler! ctx args))
    ((= cmd "coupling") (intel! ctx (cons "coupling" args)))
    ((= cmd "graph") (intel! ctx (cons "graph" args)))
    ((= cmd "complexity") (intel! ctx (cons "complexity" args)))
    ((or (= cmd "vitality") (= cmd "full")) (intel! ctx (cons "vitality" args)))
    ((= cmd "stubs") (intel! ctx (cons "stubs" args)))
    ((= cmd "trace") (intel! ctx (cons "trace" args)))
    ((or (= cmd "target") (= cmd "codegen")) (target/targetCommand! ctx args))
    ((= cmd "launch") (sys/execv! (listAppend (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-harness/src/launch.asl")) args) (list (str "ASL_ROOT=" ctx.root))))
    ((= cmd "audit") (audit! ctx args))
    ((= cmd "pack") (pack/packCommand! ctx args))
    ((= cmd "engine") (engine! ctx args))
    ((= cmd "note") (note! ctx args))
    ((= cmd "test") (test! ctx args))
    ((or (stringStartsWith? cmd "(") (stringStartsWith? cmd ":")) (forms! ctx (cons cmd args)))
    ((= cmd "rpc") (forms! ctx args))
    ((= cmd "run") (runFile! ctx args))
    ((= cmd "check") (check! ctx args))
    ((= cmd "build") (build/buildCommand! ctx args))
    ((= cmd "parse") (parse! ctx args))
    ((= cmd "lint") (retired! "lint" "asl check FILE runs balance and asl-host check"))
    ((= cmd "gate") (retired! "gate" "asl audit gates runs the gate suites"))
    ((= cmd "mem") (retired! "mem" "asl '(:observe :dim memory)' reports the ledgers"))
    ((= cmd "tool") (retired! "tool" "asl '(:tools)' lists the operations"))
    ((= cmd "doc") (docCmd! ctx args))
    (else (do (sys/say! (str "(:asl :status :failed :error ERR_UNKNOWN_COMMAND :message \"unknown command " cmd "; see asl help\")")) 2)))

fn ! readStdin! acc: (List String) -> (Result String String)
  (mt (fdRead 0 65536)
    ((err e) (err e))
    ((ok chunk) (if (stringEmpty? chunk) (ok (stringJoin (listReverse acc) "")) (readStdin! (cons chunk acc)))))

fn batchUsage! text: String -> Int64
  (do (sys/say! (str "(:batch :status :failed :error ERR_MISSING_ARG :message \"" text "\")")) 2)

fn ! entry! ctx: sys/Context args: (List String) -> Int64
  (let [(cmd (first args))]
    (cond
      ((= cmd "-f")
        (if (or (!= (listLength args) 2) (not (sys/isFile? (first (rest args)))))
          (batchUsage! "usage: asl -f FILE, one readable file of forms and no other argument")
          (mt (fileRead (first (rest args)))
            ((err _) (batchUsage! "usage: asl -f FILE, one readable file of forms and no other argument"))
            ((ok text) (dispatch! ctx "rpc" (list (sys/stripTrailingNewlines text)))))))
      ((= cmd "-")
        (if (!= (listLength args) 1)
          (batchUsage! "usage: asl - reads forms from stdin and takes no other argument")
          (mt (readStdin! (list))
            ((err e) (do (sys/sayErr! (str "asl -: stdin: " e)) 2))
            ((ok text) (dispatch! ctx "rpc" (list (sys/stripTrailingNewlines text)))))))
      (else
        (let [(r (route! ctx args))]
          (dispatch! ctx (pairFirst r) (pairSecond r))))))

fn ! route! ctx: sys/Context args: (List String) -> (Pair String (List String))
  (let [(cmd (first args))
        (trimmed (sys/trimLeft cmd))
        (lead (if (and (or (stringStartsWith? trimmed "(") (stringStartsWith? trimmed ":")) (!= trimmed cmd)) trimmed cmd))
        (asTest (and (sys/isFile? lead) (or (= (sys/baseName ctx.argv0) "asl-eval") (stringEndsWith? lead ".asl"))))]
    (if asTest
      (pair "test" (cons lead (rest args)))
      (pair lead (rest args))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (sys/context!)
    ((err e) (do (sys/sayErr! (str "(:asl :status :failed :error ERR_NO_WORKSPACE :message \"" e "\")")) (ok 2)))
    ((ok ctx) (do (nc/hostEntry! ctx args) (ok (entry! ctx args)))))
