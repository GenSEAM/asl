(module asl-parser/tests/printHostValidLib
  :x [runShard! knownHostInvalidReason hostBinary!]
  :i [(ast :a a)
      (astPrinter :a ap)
      (asl-parser/tests/printReparseLib :a prl)
      (asl-parser/tests/printHostValidScope :a scope)])

fn knownHostInvalidReason path: String -> (Option String)
  (cond
    ((= path "asl/packages/asl-hypergraph/src/main.asl")
     (some "a/parse splits the parameter type asl-parser/reader:SExpr at its colon into the type text asl-parser/reader :SExpr: Any, so the printed signature is rejected: ERR_UNKNOWN_SYMBOL Any"))
    ((= path "tests/acceptance/r1Host/sem/hostSubjectTest.asl")
     (some "compile.c's D152 constant-assert exemption keys off a ; (:m :tags (hostSubject)) line comment textually adjacent to the fn; DefunNode carries no field for it, so astPrinter cannot reproduce the comment and the printed form's otherwise-constant assert is rejected: ERR_CONSTANT_ASSERT"))
    ((= path "tests/acceptance/r1Host/sem/intDivModTest.asl")
     (some "compile.c's D152 constant-assert exemption keys off a ; (:m :tags (hostSubject)) line comment textually adjacent to the fn; DefunNode carries no field for it, so astPrinter cannot reproduce the comment and the printed form's otherwise-constant assert is rejected: ERR_CONSTANT_ASSERT"))
    ((= path "tests/acceptance/vtbotDataPlane/floatLiteralParseTest.asl")
     (some "compile.c's D152 constant-assert exemption keys off a ; (:m :tags (hostSubject)) line comment textually adjacent to the fn; DefunNode carries no field for it, so astPrinter cannot reproduce the comment and the printed form's otherwise-constant assert is rejected: ERR_CONSTANT_ASSERT"))
    ((= path "tests/acceptance/r1Host/float/reprTableTest.asl")
     (some "compile.c's D152 constant-assert exemption keys off a ; (:m :tags (hostSubject)) line comment textually adjacent to the fn; DefunNode carries no field for it, so astPrinter cannot reproduce the comment and the printed form's otherwise-constant assert is rejected: ERR_CONSTANT_ASSERT"))
    ((= path "tests/acceptance/r1Host/reader/expLiteralTest.asl")
     (some "compile.c's D152 constant-assert exemption keys off a ; (:m :tags (hostSubject)) line comment textually adjacent to the fn; DefunNode carries no field for it, so astPrinter cannot reproduce the comment and the printed form's otherwise-constant assert is rejected: ERR_CONSTANT_ASSERT"))
    (else (none)))

fn parentDir path: String -> String
  (let [(parts (stringSplit path "/"))]
    (if (<= (listLength parts) 1)
      ""
      (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn findHostFrom! dir: String -> (Result String String)
  (let [(candidate (str dir "/asl/host/out/asl-host"))]
    (if (fileExists? candidate)
      (ok candidate)
      (let [(up (parentDir dir))]
        (if (or (stringEmpty? up) (= up dir))
          (err "asl/host/out/asl-host not found in any ancestor of the working directory")
          (findHostFrom! up)))))

fn hostBinary! -> (Result String String)
  (mt (envGet "ASL_HOST")
    ((some h) (if (stringEmpty? h) (err "ASL_HOST is set but empty") (ok h)))
    ((none)
     (mt (pathCanonicalize ".")
       ((err _) (err "cannot canonicalize the working directory"))
       ((ok cwd) (findHostFrom! cwd)))))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn createTemp! dir: String text: String attempt: Int64 -> (Result String String)
  (if (>= attempt 32)
    (err (str "no free temp name in " dir " after 32 attempts"))
    (let [(tmp (str dir "/.asl_chk_print_" (stringFromInt64 (monotonicNs)) "_" (stringFromInt64 attempt) ".asl"))]
      (mt (fileCreateExclusive tmp text)
        ((ok _) (ok tmp))
        ((err e)
         (if (stringStartsWith? e "alreadyExists:")
           (createTemp! dir text (+ attempt 1))
           (err (str "create " tmp ": " e)))))))

fn firstHostError out: String -> String
  (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit out "\n")))
        (errLines (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) lines))]
    (mt (listHead errLines)
      ((some l) l)
      ((none) (optionOr (listHead lines) "(no output)"))))

(schema HostRun
  (:f valid Bool)
  (:f detail String))

fn runCheck! host: String path: String -> HostRun
  (let [(res (processRun (str (shellQuote host) " check " (shellQuote path) " 2>&1")))
        (out (str res.stdout res.stderr))]
    (HostRun
      :valid (= res.exitCode 0)
      :detail (str "exit " (stringFromInt64 res.exitCode) ": " (firstHostError out))))

(schema CheckOutcome
  (:f source HostRun)
  (:f printed HostRun)
  (:f removed Bool)
  (:f removeDetail String))

fn hostCheck! host: String srcPath: String text: String -> (Result CheckOutcome String)
  (mt (createTemp! (parentDir srcPath) text 0)
    ((err e) (err e))
    ((ok tmp)
     (let [(printed (runCheck! host tmp))
           (removed (pathRemove tmp))
           (source (runCheck! host srcPath))]
       (ok (CheckOutcome
             :source source
             :printed printed
             :removed (ok? removed)
             :removeDetail (mt removed ((ok _) (str "removed " tmp)) ((err e) (str "remove " tmp ": " e))))))))

fn printForms forms: (List a/TopForm) -> String
  (mt (listHead forms)
    ((some tf)
     (mt tf
       ((a/topModule m) (ap/printAstModule m))
       (_ (stringJoin (map (fn [(t a/TopForm)] -> String (ap/printTopForm t)) forms) "\n\n"))))
    ((none) ""))

fn checkFile! host: String root: String path: String -> (Result CheckOutcome String)
  (let [(abs (str root "/" path))]
    (mt (fileRead abs)
      ((err _) (err (str path ": read failed")))
      ((ok src)
       (mt (a/parse src)
         ((err e) (err (str path ": parse error " e.msg)))
         ((ok forms) (hostCheck! host abs (printForms forms)))))))

(schema FileResult
  (:f path String)
  (:f outcome (Result CheckOutcome String)))

fn inScope? o: CheckOutcome -> Bool
  o.source.valid

fn fileFails? r: FileResult -> Bool
  (mt r.outcome
    ((err _) true)
    ((ok o)
     (or (not o.removed)
         (mt (knownHostInvalidReason r.path)
           ((some _) (or (not (inScope? o)) o.printed.valid))
           ((none) (if (inScope? o) (not o.printed.valid) (not (scope/knownSourceInvalid? r.path))))))))

fn assertFile r: FileResult -> Bool
  (let [(path r.path)]
    (mt r.outcome
      ((err e) (do (assert false (str path " host check could not run: " e)) false))
      ((ok o)
       (do
         (assert o.removed (str path " temp cleanup: " o.removeDetail))
         (mt (knownHostInvalidReason path)
           ((some why)
            (do
              (assert (and (inScope? o) (not o.printed.valid)) (str path " is listed host-invalid (" why "): its source must pass and its printed output fail asl-host check, source " o.source.detail ", printed " o.printed.detail))
              true))
           ((none)
            (if (inScope? o)
              (do
                (assert o.printed.valid (str path " printed output passes asl-host check like its source: " o.printed.detail))
                true)
              (do
                (assert (scope/knownSourceInvalid? path) (str path " source newly fails asl-host check and is not in the shrink-only printHostValidScope list: " o.source.detail))
                true))))))))

fn sourceValid? r: FileResult -> Bool
  (mt r.outcome ((ok o) o.source.valid) ((err _) false))

fn runShard! label: String n: Int64 k: Int64 -> Bool
  (mt (prl/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok allFiles)
     (mt (hostBinary!)
       ((err e) (do (assert false (str "host binary: " e)) false))
       ((ok host)
        (mt (pathCanonicalize ".")
          ((err _) (do (assert false "cannot canonicalize the repo root") false))
          ((ok root)
           (let [(shard (prl/shardFiles allFiles n k))
                 (expected (prl/expectedShardCount (listLength allFiles) n k))
                 (results (map (fn [(p String)] -> FileResult (FileResult :path p :outcome (checkFile! host root p))) shard))
                 (failing (filter fileFails? results))
                 (sourceValid (filter sourceValid? results))
                 (excluded (filter (fn [(r FileResult)] -> Bool (some? (knownHostInvalidReason r.path))) results))]
             (do
               (print (str "(:printHostValid :suite " label " :checked " (stringFromInt64 (listLength results))
                           " :sourceValid " (stringFromInt64 (listLength sourceValid))
                           " :failed " (stringFromInt64 (listLength failing))
                           " :excluded " (stringFromInt64 (listLength excluded))
                           " :failing (" (stringJoin (map (fn [(r FileResult)] -> String r.path) failing) " ") "))\n"))
               (assert (= (listLength shard) expected) (str label " holds its exact share " (stringFromInt64 expected)))
               (map assertFile results)
               (listEmpty? failing)))))))))
