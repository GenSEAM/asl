(module asl-parser/tests/printHostValidLib
  :x [runShard! knownHostInvalidReason hostBinary!]
  :i [(ast :a a)
      (astPrinter :a ap)
      (asl-parser/tests/printReparseLib :a prl)
      (asl-parser/tests/printHostValidScope :a scope)])

fn knownHostInvalidReason path: String -> (Option String)
  (cond
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
    ((= path "asl/packages/asl-target-llvm/tests/nativeStringTest.asl")
     (some "astPrinter gap, confirmed on base 010f3a1bc (file and astPrinter.asl both byte-identical to base, matching printReparseLib.asl's knownMisparseReason entry for this file): one top form embeds a raw \\x00/\\xNN byte-escape string literal (a generated-fixture-text payload for native string/byte builtins), and the printed form's re-serialized escapes land in a field-name position the host rejects as ERR_BAD_CONSTRUCTOR"))
    (else (none)))

fn parentDir path: String -> String
  (let [(parts (stringSplit path "/"))]
    (if (<= (listLength parts) 1)
      ""
      (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn findHostFrom! dir: String -> (Result String String)
  (let [(candidate (str dir "/bin/asl"))]
    (if (fileExists? candidate)
      (ok candidate)
      (let [(up (parentDir dir))]
        (if (or (stringEmpty? up) (= up dir))
          (err "bin/asl not found in any ancestor of the working directory")
          (findHostFrom! up)))))

fn hostBinary! -> (Result String String)
  (match (envGet "ASL_HOST")
    ((some h) (if (stringEmpty? h) (err "ASL_HOST is set but empty") (ok h)))
    ((none)
     (match (realPath ".")
       ((err _) (err "cannot canonicalize the working directory"))
       ((ok cwd) (findHostFrom! cwd)))))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

; (:m :ref STRAY-CHK-PRINT :do "the printed copy must sit beside its source (a copy checked from a temp dir resolves package-relative imports differently and fails), so a run killed between create and remove cannot clean up after itself; each copy is named by its owner pid and every shard first removes the copies whose owner is dead, so a killed run's strays live only until the next shard starts")
fn tempPrefix -> String
  ".asl_chk_print_p"

fn ownerOf name: String -> (Option Int64)
  (if (stringStartsWith? name (tempPrefix))
    (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice name (stringLength (tempPrefix)) (stringLength name)) "") "_")) ""))
    (none))

fn ! staleTemp? dir: String name: String -> Bool
  (match (ownerOf name)
    ((some pid) (and (!= pid (procSelf)) (not (resultOr (procAlive? pid) true))))
    ((none) false))

fn ! sweepDir! dir: String -> Int64
  (listLength (filter (fn [(n String)] -> Bool (and (staleTemp? dir n) (ok? (pathRemove (str dir "/" n)))))
                      (resultOr (dirList dir) (list))))

fn ! sweepStrays! root: String files: (List String) -> Int64
  (let [(dirs (fold (fn [(acc (List String)) (p String)] -> (List String) (let [(d (parentDir (str root "/" p)))] (if (listContains? acc d) acc (cons d acc)))) (list) files))]
    (fold (fn [(n Int64) (d String)] -> Int64 (+ n (sweepDir! d))) 0 dirs))

fn createTemp! dir: String text: String attempt: Int64 -> (Result String String)
  (if (>= attempt 32)
    (err (str "no free temp name in " dir " after 32 attempts"))
    (let [(tmp (str dir "/" (tempPrefix) (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs)) "_" (stringFromInt64 attempt) ".asl"))]
      (match (fileCreateExclusive tmp text)
        ((ok _) (ok tmp))
        ((err e)
         (if (stringStartsWith? e "alreadyExists:")
           (createTemp! dir text (+ attempt 1))
           (err (str "create " tmp ": " e)))))))

fn firstHostError out: String -> String
  (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit out "\n")))
        (errLines (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) lines))]
    (match (listHead errLines)
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

; (:m :ref TEST-SPEED-PRINTHOSTVALID-BATCH :do "one bin/asl check per chunk instead of one per file: the receipt holds one line per path, ok PATH: or check failed: PATH:, and the error lines of a failed path start with PATH:; a path with no verdict line (the batch died early) is checked alone")
fn verdictIn lines: (List String) path: String -> (Option HostRun)
  (cond
    ((listAny? (fn [(l String)] -> Bool (stringStartsWith? l (str "ok " path ": "))) lines)
     (some (HostRun :valid true :detail "exit 0: ok in batch")))
    ((listAny? (fn [(l String)] -> Bool (stringStartsWith? l (str "check failed: " path ": "))) lines)
     (some (HostRun :valid false :detail (str "exit 1: " (firstHostError (stringJoin (filter (fn [(l String)] -> Bool (stringStartsWith? l (str path ":"))) lines) "\n"))))))
    (else (none)))

fn batchCheck! host: String paths: (List String) -> (Map String HostRun)
  (if (listEmpty? paths)
    (mapEmpty)
    (let [(res (processRun (str (shellQuote host) " check " (stringJoin (map shellQuote paths) " ") " 2>&1")))
          (lines (stringLines (str res.stdout res.stderr)))]
      (fold (fn [(m (Map String HostRun)) (p String)] -> (Map String HostRun)
              (mapSet m p (match (verdictIn lines p) ((some r) r) ((none) (runCheck! host p)))))
            (mapEmpty) paths)))

fn chunked xs: (List String) n: Int64 -> (List (List String))
  (if (listEmpty? xs)
    (list)
    (cons (listTake xs n) (chunked (listDrop xs n) n)))

fn runOf runs: (Map String HostRun) path: String -> HostRun
  (mapGetOr runs path (HostRun :valid false :detail (str "no check ran for " path)))

fn printForms forms: (List a/TopForm) -> String
  (match (listHead forms)
    ((some tf)
     (match tf
       ((a/topModule m) (ap/printAstModule m))
       (_ (stringJoin (map (fn [(t a/TopForm)] -> String (ap/printTopForm t)) forms) "\n\n"))))
    ((none) ""))

fn printedText! root: String path: String -> (Result String String)
  (match (fileReadString (str root "/" path))
    ((err _) (err (str path ": read failed")))
    ((ok src)
     (match (a/parse src)
       ((err e) (err (str path ": parse error " e.msg)))
       ((ok forms) (ok (printForms forms))))))

; (:m :ref TEST-SPEED-PRINTHOSTVALID-BATCH :do "printed copies and sources go in separate batches: a copy declares its source's module name, so the two in one checker process would share one module entry")
fn ! checkChunk! host: String root: String paths: (List String) -> (List FileResult)
  (let [(abs (map (fn [(p String)] -> String (str root "/" p)) paths))
        (temps (map (fn [(pa (Pair String String))] -> (Result String String)
                      (match (printedText! root (pairFirst pa))
                        ((err e) (err e))
                        ((ok text) (createTemp! (parentDir (pairSecond pa)) text 0))))
                    (zip paths abs)))
        (made (map (fn [(t (Result String String))] -> String (resultOr t "")) (filter ok? temps)))
        (printed (batchCheck! host made))
        (removed (fold (fn [(m (Map String String)) (t String)] -> (Map String String)
                         (mapSet m t (match (pathRemove t) ((ok _) "") ((err e) (str "remove " t ": " e)))))
                       (mapEmpty) made))
        (sources (batchCheck! host (map (fn [(x (Pair String (Result String String)))] -> String (pairFirst x))
                                        (filter (fn [(x (Pair String (Result String String)))] -> Bool (ok? (pairSecond x))) (zip abs temps)))))]
    (map (fn [(x (Pair (Pair String String) (Result String String)))] -> FileResult
           (FileResult
             :path (pairFirst (pairFirst x))
             :outcome (match (pairSecond x)
                        ((err e) (err e))
                        ((ok tmp)
                         (let [(why (mapGetOr removed tmp "not removed"))]
                           (ok (CheckOutcome
                                 :source (runOf sources (pairSecond (pairFirst x)))
                                 :printed (runOf printed tmp)
                                 :removed (stringEmpty? why)
                                 :removeDetail (if (stringEmpty? why) (str "removed " tmp) why))))))))
         (zip (zip paths abs) temps)))

(schema FileResult
  (:f path String)
  (:f outcome (Result CheckOutcome String)))

fn inScope? o: CheckOutcome -> Bool
  o.source.valid

fn fileFails? r: FileResult -> Bool
  (match r.outcome
    ((err _) true)
    ((ok o)
     (or (not o.removed)
         (match (knownHostInvalidReason r.path)
           ((some _) (or (not (inScope? o)) o.printed.valid))
           ((none) (if (inScope? o) (not o.printed.valid) (not (scope/knownSourceInvalid? r.path))))))))

fn assertFile r: FileResult -> Bool
  (let [(path r.path)]
    (match r.outcome
      ((err e) (do (assert false (str path " host check could not run: " e)) false))
      ((ok o)
       (do
         (assert o.removed (str path " temp cleanup: " o.removeDetail))
         (match (knownHostInvalidReason path)
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
  (match r.outcome ((ok o) o.source.valid) ((err _) false))

fn runShard! label: String n: Int64 k: Int64 -> Bool
  (match (prl/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok allFiles)
     (match (hostBinary!)
       ((err e) (do (assert false (str "host binary: " e)) false))
       ((ok host)
        (match (realPath ".")
          ((err _) (do (assert false "cannot canonicalize the repo root") false))
          ((ok root)
           (let [(swept (sweepStrays! root allFiles))
                 (shard (prl/shardFiles allFiles n k))
                 (expected (prl/expectedShardCount (listLength allFiles) n k))
                 (results (fold (fn [(acc (List FileResult)) (c (List String))] -> (List FileResult) (listAppend acc (checkChunk! host root c))) (list) (chunked shard 48)))
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
