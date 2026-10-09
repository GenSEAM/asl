(module asl-cli/tests/argvParityTest
  :x [runTests]
  :i [(cli :a c) (asl-cli/lensCmd :a lens) (asl-cli/consiliumCmd :a cons) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-parser/reader :a rd)])

fn atomValue expr: rd/SExpr -> String
  (mt expr ((rd/sexprAtom raw) raw) ((rd/sexprList _) "") ((rd/sexprVect _) ""))

fn unquoteFixtureString raw: String -> String
  (if (>= (stringLength raw) 2)
    (let [(inner (optionOr (stringSlice raw 1 (- (stringLength raw) 1)) ""))]
      (let [(decoded (stringReplace inner "\\n" "\n"))]
        (stringReplace decoded "\\\"" "\"")))
    raw)

fn fieldValue fields: (List rd/SExpr) key: String -> rd/SExpr
  (if (listEmpty? fields)
    (rd/sexprAtom "")
    (let [(head (optionOr (listHead fields) (rd/sexprAtom "")))
          (rest (optionOr (listTail fields) (list)))]
      (if (= (atomValue head) key)
        (optionOr (listHead rest) (rd/sexprAtom ""))
        (fieldValue (optionOr (listTail rest) (list)) key))))

fn fixtureString fields: (List rd/SExpr) key: String -> String
  (unquoteFixtureString (atomValue (fieldValue fields key)))

fn fixtureArgs expr: rd/SExpr -> (List String)
  (map unquoteFixtureString (map atomValue (ast/sexprItems expr)))

fn shellQuote value: String -> String
  (str "'" (stringReplace value "'" "'\\''") "'")

fn runFixtureProcess! cmd: String args: (List String) -> ProcessOutput
  (let [(quotedArgs (map shellQuote (cons cmd args)))
        (root (mt (realPath ".") ((ok path) path) ((err _) ".")))
        (host (str root "/asl/host/out/asl-host"))
        (main (str root "/asl/packages/asl-cli/src/main.asl"))
        (command (str (shellQuote host) " run " (shellQuote main) " " (stringJoin quotedArgs " ")))]
    (processRun command))

fn processOutput process: ProcessOutput -> String
  (str process.stdout process.stderr)

fn emittedBytes value: String -> String
  (if (stringEndsWith? value "\n") value (str value "\n"))

fn normalizeCheckoutPath! value: String -> String
  (mt (realPath ".")
    ((err _) value)
    ((ok root) (stringReplace value (str root "/") "")))

fn fixtureCaseId caseExpr: rd/SExpr -> String
  (fixtureString (optionOr (listTail (ast/sexprItems caseExpr)) (list)) ":id")

fn caseMatchesFixture! caseExpr: rd/SExpr -> Bool
  (let [(fields (optionOr (listTail (ast/sexprItems caseExpr)) (list)))
        (cmd (fixtureString fields ":cmd"))
        (args (fixtureArgs (fieldValue fields ":args")))
        (expectedExit (optionOr (stringToInt64 (atomValue (fieldValue fields ":exit"))) -1))
        (expectedStdout (fixtureString fields ":stdout"))
        (expectedStderr (fixtureString fields ":stderr"))
        (actual (c/dispatchCmd cmd args))
        (process (runFixtureProcess! cmd args))]
    (and (= process.exitCode expectedExit)
      (and (= (normalizeCheckoutPath! process.stdout) expectedStdout)
        (and (or (stringEmpty? expectedStderr) (stringContains? (normalizeCheckoutPath! process.stderr) expectedStderr))
          (if (= expectedExit 0)
            true
            (mt actual
              ((ok _) false)
              ((err output)
               (if (and (= cmd "lens")
                        (and (= (optionOr (listHead args) "") "info") (listEmpty? (optionOr (listTail args) (list)))))
                 (and (= (emittedBytes output) expectedStdout) (stringEmpty? expectedStderr))
                 (and (stringEmpty? expectedStdout) (= (normalizeCheckoutPath! (emittedBytes output)) expectedStderr))))))))))

fn fixtureCasesMatch! cases: (List rd/SExpr) -> Bool
  (if (listEmpty? cases)
    true
    (let [(current (optionOr (listHead cases) (rd/sexprAtom "")))]
      (do
        (assert (caseMatchesFixture! current) (str "recorded argv result must match fixture status and text: " (fixtureCaseId current)))
        (fixtureCasesMatch! (optionOr (listTail cases) (list))))))

fn testConsiliumSecondSuiteFailure! -> Bool
  (let [(first (processRun "printf first-suite"))
        (second (processRun "printf second-suite >&2; exit 7"))
        (result (cons/consiliumTestResults first second))]
    (mt result
      ((err message) (do (assert (= message "second-suite") "consilium --test propagates the second suite failure") true))
      ((ok _) (do (assert false "consilium --test must fail when its second suite fails") false))))

fn testToolchainRootWithoutLauncherEnvironment! -> Bool
  (let [(lensTest (c/dispatchCmd "lens" (list "--test")))
        (consiliumTest (c/dispatchCmd "consilium" (list "--test")))]
    (do
      (assert (ok? lensTest) "lens test resolves the repository root without launcher environment")
      (assert (ok? consiliumTest) "consilium test resolves the repository root without launcher environment")
      true))

fn testLegacyDelegation! -> Bool
  (do
    (assert (= (lens/lensTargetKind! "README.md") "file") "existing file routes through lens file input")
    (assert (= (lens/lensTargetKind! "WR1 route probe") "text") "non-file target routes through lens text input")
    (assert (= (lens/formatLensPayload "file" (list "README.md")) "(:lens :file \"README.md\")") "file input constructs a file payload")
    (assert (= (lens/formatLensPayload "text" (list "WR1" "route" "probe")) "(:lens :text \"WR1 route probe\")") "text input constructs a joined text payload")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "README.md"))) "lensAudit") "lens file target executes the lens operation")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "run" "README.md"))) "lensAudit") "lens run forwards only its target to the lens operation")
    (assert (not (stringContains? (processOutput (runFixtureProcess! "lens" (list "run" "README.md"))) "run README.md")) "lens run subcommand is not included in its payload target")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "discover" "README.md"))) "README.md") "lens discover forwards its rest arguments")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "some" "text"))) "some text") "bare lens text targets preserve joined arguments")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "describe"))) "Usage: lens info") "lens describe usage is written to stdout by the process")
    (assert (!= (runFixtureProcess! "consilium" (list "run" "README.md")).exitCode 0) "consilium run cannot report success without executing a council")
    (assert (stringContains? (runFixtureProcess! "consilium" (list "run" "README.md")).stderr "ERR_UNIMPLEMENTED") "consilium run preserves the unimplemented action diagnostic")
    (assert (!= (runFixtureProcess! "consilium" (list "audit" "README.md")).exitCode 0) "consilium audit cannot report success without executing a council")
    (assert (stringContains? (runFixtureProcess! "consilium" (list "audit" "README.md")).stderr "ERR_UNIMPLEMENTED") "consilium audit preserves the unimplemented action diagnostic")
    (assert (ok? (c/dispatchCmd "lens" (list "--setup"))) "lens --setup is dispatched as a successful option")
    (assert (ok? (c/dispatchCmd "lens" (list "--rules"))) "lens --rules is dispatched as a successful option")
    (assert (ok? (c/dispatchCmd "lens" (list "--test"))) "lens --test runs its suite successfully")
    (assert (ok? (c/dispatchCmd "consilium" (list "--test"))) "consilium --test runs its suites successfully")
    (assert (stringContains? (runFixtureProcess! "lens" (list "describe")).stdout "Usage: lens info") "lens describe usage must remain on stdout")
    (assert (!= (runFixtureProcess! "lens" (list "info" "unknown-lens")).exitCode 0) "unknown lens info error is checked through the process")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "info" "unknown-lens"))) "Unknown lens") "unknown lens info error text comes from the process")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "help"))) "ERR_TARGET_NOT_FOUND") "bare lens help remains a legacy target")
    (assert (stringContains? (processOutput (runFixtureProcess! "lens" (list "version"))) "ERR_TARGET_NOT_FOUND") "bare lens version remains a legacy target")
    (assert (stringContains? (processOutput (runFixtureProcess! "consilium" (list "help"))) "ERR_UNIMPLEMENTED") "bare consilium help cannot claim a prepared audit")
    (assert (stringContains? (processOutput (runFixtureProcess! "consilium" (list "version"))) "ERR_UNIMPLEMENTED") "bare consilium version cannot claim a prepared audit")
    (let [(runError (runFixtureProcess! "consilium" (list "run" "README.md")))
          (auditError (runFixtureProcess! "consilium" (list "audit" "README.md")))]
      (do
        (assert (!= runError.exitCode 0) "consilium run must fail without an actual council provider")
        (assert (stringContains? runError.stderr "ERR_UNIMPLEMENTED") "consilium run reports absent council provider instead of prepared success")
        (assert (stringContains? runError.stderr "ERR_UNIMPLEMENTED") "consilium run preserves the unimplemented action diagnostic")
        (assert (!= auditError.exitCode 0) "consilium audit must fail without an actual council provider")
        (assert (stringContains? auditError.stderr "ERR_UNIMPLEMENTED") "consilium audit preserves the unimplemented action diagnostic")) )
    true)

fn testPayloadAndFailureContracts! -> Bool
  (let [(runProbe (processOutput (runFixtureProcess! "lens" (list "run" "WR1" "route" "probe"))))
        (quoted (processOutput (runFixtureProcess! "lens" (list "say \"hi\""))))
        (failed (lens/lensTestResult (processRun "printf lens-suite-failed >&2; exit 3")))]
    (do
      (assert (stringContains? runProbe "Target not found: WR1 route probe") "lens run sends its whole rest as one text target")
      (assert (= (lens/formatLensPayload "text" (list "say" "\"hi\"")) "(:lens :text \"say \\\"hi\\\"\")") "a text payload escapes the quotes of its target")
      (assert (stringContains? quoted "Target not found: say \\\"hi\\\"") "a quoted target reaches the lens operation intact")
      (assert (stringContains? (lens/formatLensPayload "text" (list "a\\b")) "\\\\") "a text payload escapes backslashes before the reader sees them")
      (mt failed
        ((err message) (do (assert (= message "lens-suite-failed") "lens --test propagates its suite failure") true))
        ((ok _) (do (assert false "lens --test must fail when its suite fails") false)))))

fn ! runTests -> Bool
  (mt (fileRead "tests/parity/cli/argvFixture.asn")
    ((err e) (do (assert false (str "could not read argv fixture: " e)) false))
    ((ok src)
     (mt (ast/readForms (lx/tokenize src))
       ((err e) (do (assert false (str "could not parse argv fixture: " e.msg)) false))
       ((ok forms)
        (mt (listHead forms)
          ((none) (do (assert false "argv fixture has no top-level form") false))
          ((some form)
           (let [(root form.expr)
                 (cases (ast/sexprItems (fieldValue (optionOr (listTail (ast/sexprItems root)) (list)) ":cases")))]
             (assert (> (listLength cases) 0) "argv fixture must contain cases")
             (and (testToolchainRootWithoutLauncherEnvironment!) (and (testPayloadAndFailureContracts!) (and (testConsiliumSecondSuiteFailure!) (and (testLegacyDelegation!) (fixtureCasesMatch! cases))))))))))))
