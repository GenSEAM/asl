(module asl-gates/runnerMain
  :x [chooseBase! chooseBaseAt! parseFullGreen changedPaths! changedPathsAt parseDependencies packages! packagesAt affected! affectedAt! affectedPrefixesAt! isForceFull findPackageByName makePackageInfo makeRunArgs parseRunArgs baselineAsserts osError cmdGate cmdRun cmdGateTests cmdCapture main]
  :i [(asl-gates/suiteRunner :a sr) (asl-gates/runnerLedger :a rl)])

(schema PackageInfo
  (:f name String)
  (:f dir String)
  (:f deps (List String)))

fn makePackageInfo name: String dir: String deps: (List String) -> PackageInfo
  (PackageInfo :name name :dir dir :deps deps)

fn findPackageByName pkgs: (List PackageInfo) name: String -> (Option PackageInfo)
  (let [(matches (filter (fn [(p PackageInfo)] -> Bool (= p.name name)) pkgs))]
    (listHead matches))

fn skipComment chars: (List String) -> (List String)
  (if (listEmpty? chars)
    (list)
    (let [(c (optionOr (listHead chars) ""))
          (tail (optionOr (listTail chars) (list)))]
      (if (= c "\n")
        tail
        (skipComment tail))))

fn scanString chars: (List String) acc: (List String) -> (Pair String (List String))
  (if (listEmpty? chars)
    (pair (stringJoin (listReverse acc) "") (list))
    (let [(c (optionOr (listHead chars) ""))
          (tail (optionOr (listTail chars) (list)))]
      (cond
        ((= c "\\")
         (if (listEmpty? tail)
           (pair (stringJoin (listReverse (cons "\\" acc)) "") (list))
           (let [(c2 (optionOr (listHead tail) ""))
                 (tail2 (optionOr (listTail tail) (list)))]
             (scanString tail2 (cons c2 (cons "\\" acc))))))
        ((= c "\"")
         (pair (stringJoin (listReverse (cons "\"" acc)) "") tail))
        (else
          (scanString tail (cons c acc))))))

fn isDelim c: String -> Bool
  (or (= c "(") (or (= c ")") (or (= c "[") (or (= c "]") (or (= c "{") (or (= c "}") (or (= c "\"") (or (= c ";") (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))))))))))

fn scanAtom chars: (List String) acc: (List String) -> (Pair String (List String))
  (if (listEmpty? chars)
    (pair (stringJoin (listReverse acc) "") (list))
    (let [(c (optionOr (listHead chars) ""))]
      (if (isDelim c)
        (pair (stringJoin (listReverse acc) "") chars)
        (let [(tail (optionOr (listTail chars) (list)))]
          (scanAtom tail (cons c acc))))))

fn tokenizeLoop chars: (List String) acc: (List String) -> (List String)
  (if (listEmpty? chars)
    (listReverse acc)
    (let [(c (optionOr (listHead chars) ""))
          (tail (optionOr (listTail chars) (list)))]
      (cond
        ((or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))
         (tokenizeLoop tail acc))
        ((= c ";")
         (tokenizeLoop (skipComment tail) acc))
        ((or (= c "(") (or (= c ")") (or (= c "[") (or (= c "]") (or (= c "{") (= c "}"))))))
         (tokenizeLoop tail (cons c acc)))
        ((= c "\"")
         (let [(res (scanString tail (list "\"")))]
           (tokenizeLoop (pairSecond res) (cons (pairFirst res) acc))))
        (else
          (let [(res (scanAtom chars (list)))]
            (tokenizeLoop (pairSecond res) (cons (pairFirst res) acc)))))))

fn tokenizeAsn text: String -> (List String)
  (tokenizeLoop (stringChars text) (list))

fn collectDepStrings toks: (List String) closeTok: String acc: (List String) -> (Result (List String) String)
  (if (listEmpty? toks)
    (err ":dependencies list is not closed")
    (let [(tok (optionOr (listHead toks) ""))
          (tail (optionOr (listTail toks) (list)))]
      (if (= tok closeTok)
        (ok (listReverse acc))
        (if (not (stringStartsWith? tok "\""))
          (err (str ":dependencies holds a non-string item " tok))
          (let [(len (stringLength tok))
                (unquoted (optionOr (stringSlice tok 1 (- len 1)) ""))]
            (collectDepStrings tail closeTok (cons unquoted acc)))))))

fn parseDependenciesLoop toks: (List String) depth: Int64 -> (Result (List String) String)
  (if (listEmpty? toks)
    (err "no top-level :dependencies")
    (let [(tok (optionOr (listHead toks) ""))
          (tail (optionOr (listTail toks) (list)))]
      (cond
        ((or (= tok "(") (or (= tok "[") (= tok "{")))
         (parseDependenciesLoop tail (+ depth 1)))
        ((or (= tok ")") (or (= tok "]") (= tok "}")))
         (parseDependenciesLoop tail (- depth 1)))
        ((and (= depth 1) (= tok ":dependencies"))
         (if (listEmpty? tail)
           (err ":dependencies is not followed by a ( or [ list")
           (let [(openTok (optionOr (listHead tail) ""))
                 (itemsToks (optionOr (listTail tail) (list)))]
             (if (not (or (= openTok "(") (= openTok "[")))
               (err ":dependencies is not followed by a ( or [ list")
               (let [(closeTok (if (= openTok "(") ")" "]"))]
                 (collectDepStrings itemsToks closeTok (list)))))))
        (else
          (parseDependenciesLoop tail depth)))))

fn parseDependencies text: String -> (Result (List String) String)
  (parseDependenciesLoop (tokenizeAsn text) 0)

fn inRoot root: String p: String -> String
  (if (stringEmpty? root) p (str root "/" p))

fn ! packagesAt root: String -> (Pair (List PackageInfo) (List String))
  (mt (sr/gitOut! root (list "ls-files" "-z" "--" "asl/packages/*/manifest.asn"))
    ((err e) (pair (list) (list e)))
    ((ok text)
      (let [(lines (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit text "\x00")))
            (acc (fold (fn [(accPair (Pair (List PackageInfo) (List String))) (mLine String)] -> (Pair (List PackageInfo) (List String))
                         (let [(m mLine)
                               (pkgs (pairFirst accPair))
                               (errs (pairSecond accPair))
                               (segs (stringSplit m "/"))
                               (filePath (if (stringEmpty? root) m (str root "/" m)))]
                           (if (!= (listLength segs) 4)
                             accPair
                             (if (not (sr/isFile! filePath))
                               (pair pkgs (listAppend errs (list (str m " is tracked but missing from the worktree"))))
                               (let [(r (fileReadString filePath))]
                                 (mt r
                                   ((err _) (pair pkgs (listAppend errs (list (str m " cannot be read")))))
                                   ((ok content)
                                    (mt (parseDependencies content)
                                      ((err why) (pair pkgs (listAppend errs (list (str m ": " why)))))
                                      ((ok deps)
                                       (let [(d (sr/dirname m))
                                             (dSegs (stringSplit d "/"))
                                             (name (optionOr (listLast dSegs) ""))]
                                         (pair (listAppend pkgs (list (PackageInfo :name name :dir d :deps deps))) errs)))))))))))
                       (pair (list) (list))
                       lines))]
        acc)))

fn packages! -> (Pair (List PackageInfo) (List String))
  (packagesAt "")

fn dedupeSorted items: (List String) last: String acc: (List String) -> (List String)
  (if (listEmpty? items)
    (listReverse acc)
    (let [(cur (optionOr (listHead items) ""))
          (tail (optionOr (listTail items) (list)))]
      (if (= cur last)
        (dedupeSorted tail last acc)
        (dedupeSorted tail cur (cons cur acc)))))

fn listSortUnique items: (List String) -> (List String)
  (let [(sorted (listSort items))]
    (dedupeSorted sorted "" (list)))

fn ! changedPathsAt root: String base: String -> (List String)
  (let [(lines1 (resultOr (resultMap (sr/gitOut! root (list "diff" "--name-only" "--no-renames" base)) sr/pyLines) (list)))
        (lines2 (resultOr (resultMap (sr/gitOut! root (list "ls-files" "--others" "--exclude-standard")) sr/pyLines) (list)))
        (combined (listAppend lines1 lines2))
        (filtered (filter (fn [(p String)] -> Bool
                            (let [(trimmed (stringTrim p))]
                              (and (not (stringEmpty? trimmed))
                                   (not (stringStartsWith? trimmed ".asl/mem/benchmarks/fullGreen/")))))
                          combined))]
    (listSortUnique filtered))

fn changedPaths! base: String -> (List String)
  (changedPathsAt "" base)

(schema FullGreenRecord
  (:f path String)
  (:f sha String)
  (:f tree String))

fn ! gitLines root: String args: (List String) -> (Result (List String) String)
  (resultMap (sr/gitOut! root args) (fn [(t String)] -> (List String) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (sr/pyLines t))))

fn isLowerHex s: String width: Int64 -> Bool
  (and (= (stringLength s) width)
       (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789abcdef" c)) (stringChars s)))

fn digestAfter line: String from: Int64 -> (Option String)
  (let [(key ":receiptDigest \"")
        (at (stringIndexOf (optionOr (stringSlice line from (stringLength line)) "") key))]
    (mt at
      ((none) (none))
      ((some i)
       (let [(start (+ from (+ i (stringLength key))))
             (later (digestAfter line (+ from (+ i 1))))]
         (if (some? later)
           later
           (let [(hex (optionOr (stringSlice line start (+ start 64)) ""))
                 (close (optionOr (stringSlice line (+ start 64) (+ start 65)) ""))]
             (if (and (isLowerHex hex 64) (= close "\"")) (some hex) (none))))))))

fn parseFullGreen path: String data: String -> (Option FullGreenRecord)
  (let [(nl (stringIndexOf data "\n"))
        (first (mt nl ((some i) (optionOr (stringSlice data 0 i) "")) ((none) data)))
        (body (mt nl ((some i) (optionOr (stringSlice data (+ i 1) (stringLength data)) "")) ((none) "")))
        (head "(:fullGreen :v 1 :sha \"")
        (sha (optionOr (stringSlice first (stringLength head) (+ (stringLength head) 40)) ""))
        (treeKey (optionOr (stringSlice first (+ (stringLength head) 40) (+ (stringLength head) 49)) ""))
        (tree (optionOr (stringSlice first (+ (stringLength head) 49) (+ (stringLength head) 89)) ""))
        (afterTree (optionOr (stringSlice first (+ (stringLength head) 89) (+ (stringLength head) 91)) ""))
        (digest (digestAfter first (+ (stringLength head) 91)))]
    (if (and (stringStartsWith? first head)
             (isLowerHex sha 40)
             (= treeKey "\" :tree \"")
             (isLowerHex tree 40)
             (= afterTree "\" ")
             (some? digest)
             (= (optionOr digest "") (bytesSha256 (stringToBytes body))))
      (some (FullGreenRecord :path path :sha sha :tree tree))
      (none)))

fn readRecord! root: String path: String -> (Option FullGreenRecord)
  (mt (fileReadString (if (stringEmpty? root) path (str root "/" path)))
    ((err _) (none))
    ((ok data) (parseFullGreen path data)))

fn isAncestor! root: String a: String b: String -> Bool
  (mt (sr/gitRun! root (list "merge-base" "--is-ancestor" a b)) ((ok d) (= d.code 0)) ((err _) false))

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn surveyRecord! root: String acc: (Pair (List FullGreenRecord) (List String)) p: String -> (Pair (List FullGreenRecord) (List String))
  (let [(valid (pairFirst acc))
        (problems (pairSecond acc))]
    (mt (readRecord! root p)
      ((none) (pair valid (listAppend problems (list (str p " does not re-hash to its :receiptDigest")))))
      ((some rec)
       (if (!= (baseName p) (str rec.sha ".asn"))
         (pair valid (listAppend problems (list (str p " is not named for its :sha"))))
         (let [(treeRes (resultOr (sr/gitRun! root (list "rev-parse" (str rec.sha "^{tree}"))) (sr/Done :code 1 :out "" :errText "" :merged "" :startNs 0 :endNs 0)))]
           (if (or (!= treeRes.code 0) (!= (sr/pyStrip treeRes.out) rec.tree))
             (pair valid (listAppend problems (list (str p " :tree is not the tree of its :sha"))))
             (if (isAncestor! root rec.sha "HEAD")
               (pair (listAppend valid (list rec)) problems)
               acc)))))))

fn sinceBaseProblems! root: String base: FullGreenRecord -> (List String)
  (let [(short (optionOr (stringSlice base.sha 0 12) ""))
        (statusRes (gitLines root (list "diff" "--name-status" "--no-renames" base.sha "--" ".asl/mem/benchmarks/fullGreen/")))
        (statusProblems (mt statusRes
                          ((err e) (list e))
                          ((ok lines)
                           (fold (fn [(acc (List String)) (l String)] -> (List String)
                                   (let [(tab (optionOr (stringIndexOf l "\t") (stringLength l)))
                                         (st (optionOr (stringSlice l 0 tab) ""))
                                         (path (optionOr (stringSlice l (+ tab 1) (stringLength l)) ""))]
                                     (if (= st "A") acc (listAppend acc (list (str st " " path " since base " short))))))
                                 (list)
                                 lines))))
        (ledgerRes (gitLines root (list "diff" "-U0" base.sha "--" ".asl/mem/knownRed.asn")))]
    (mt ledgerRes
      ((err e) (listAppend statusProblems (list e)))
      ((ok lines)
       (let [(removed (filter (fn [(l String)] -> Bool
                                (and (stringStartsWith? l "-")
                                     (not (stringStartsWith? l "---"))
                                     (!= (stringTrim (optionOr (stringSlice l 1 (stringLength l)) "")) ")")))
                              lines))]
         (if (listEmpty? removed)
           statusProblems
           (listAppend statusProblems
                       (list (str ".asl/mem/knownRed.asn lost " (stringFromInt64 (listLength removed)) " line(s) since base " short))))))))

fn chooseBaseAt! root: String -> (Pair (Option FullGreenRecord) (List String))
  (mt (gitLines root (list "ls-files" "--" ".asl/mem/benchmarks/fullGreen/*.asn"))
    ((err e) (pair (none) (list e)))
    ((ok paths)
     (let [(survey (fold (fn [(acc (Pair (List FullGreenRecord) (List String))) (p String)] -> (Pair (List FullGreenRecord) (List String))
                           (surveyRecord! root acc p))
                         (pair (list) (list))
                         paths))
           (valid (pairFirst survey))
           (newest (filter (fn [(r FullGreenRecord)] -> Bool
                             (not (listAny? (fn [(o FullGreenRecord)] -> Bool
                                              (and (!= o.sha r.sha) (isAncestor! root r.sha o.sha)))
                                            valid)))
                           valid))
           (base (listHead newest))]
       (mt base
         ((none) (pair (none) (pairSecond survey)))
         ((some b) (pair base (listAppend (pairSecond survey) (sinceBaseProblems! root b))))))))

fn chooseBase! -> (Pair (Option FullGreenRecord) (List String))
  (chooseBaseAt! "")

fn forceFullPrefixes -> (List String)
  (list "asl/bin/" "bin/asl" "bin/asl-core" "asl/prelude/" "asl/grammar/" "scripts/runGateTests.sh" "scripts/audit/" ".asl/mem/knownRed.asn")

fn isForceFull p: String -> Bool
  (listAny? (fn [(f String)] -> Bool (stringStartsWith? p f)) (forceFullPrefixes))

fn findOwnerForPath pkgs: (List PackageInfo) path: String -> (Option String)
  (let [(matches (filter (fn [(pkg PackageInfo)] -> Bool
                           (stringStartsWith? path (str pkg.dir "/")))
                         pkgs))]
    (mt (listHead matches)
      ((none) (none))
      ((some pkg) (some pkg.name))))

fn findReverseDependents pkgs: (List PackageInfo) target: String -> (List String)
  (let [(matchingPkgs (filter (fn [(pkg PackageInfo)] -> Bool
                                (listContains? pkg.deps target))
                              pkgs))]
    (map (fn [(pkg PackageInfo)] -> String pkg.name) matchingPkgs))

fn traverseDepsLoop pkgs: (List PackageInfo) todo: (List String) seen: (List String) -> (List String)
  (if (listEmpty? todo)
    seen
    (let [(cur (optionOr (listHead todo) ""))
          (restTodo (optionOr (listTail todo) (list)))
          (revs (findReverseDependents pkgs cur))
          (newRevs (filter (fn [(n String)] -> Bool (not (listContains? seen n))) revs))
          (newSeen (listAppend seen newRevs))
          (newTodo (listAppend restTodo newRevs))]
      (traverseDepsLoop pkgs newTodo newSeen)))

fn fullReason pkgs: (List PackageInfo) changed: (List String) -> (Option String)
  (fold (fn [(acc (Option String)) (p String)] -> (Option String)
          (cond
            ((some? acc) acc)
            ((isForceFull p) (some (str "changed " p)))
            ((none? (findOwnerForPath pkgs p)) (some (str "no package manifest owns " p)))
            (else (none))))
        (none)
        changed)

fn ! affectedPrefixesAt! root: String base: String -> (Result (Pair (List String) String) String)
  (let [(changed (changedPathsAt root base))
        (pkgRes (packagesAt root))
        (pkgs (pairFirst pkgRes))
        (errors (pairSecond pkgRes))]
    (if (not (listEmpty? errors))
      (err (str "ERR_MANIFEST_PARSE " (stringJoin (listTake errors 4) "; ")))
      (mt (fullReason pkgs changed)
        ((some why) (err why))
        ((none)
         (let [(owners (fold (fn [(acc (List String)) (p String)] -> (List String)
                               (mt (findOwnerForPath pkgs p)
                                 ((none) acc)
                                 ((some n) (if (listContains? acc n) acc (listAppend acc (list n))))))
                             (list)
                             changed))
               (seenInitial (if (listContains? owners "asl-gates") owners (listAppend owners (list "asl-gates"))))
               (sortedSeen (listSortUnique (traverseDepsLoop pkgs owners seenInitial)))
               (prefixes (fold (fn [(acc (List String)) (name String)] -> (List String)
                                 (mt (findPackageByName pkgs name)
                                   ((none) acc)
                                   ((some pkg) (listAppend acc (list pkg.dir)))))
                               (list)
                               sortedSeen))]
           (ok (pair prefixes (str "packages " (stringJoin sortedSeen " ")))))))))

fn affectedAt! root: String base: String -> (Pair String (Pair (List String) String))
  (mt (affectedPrefixesAt! root base)
    ((err why) (pair ":full" (pair (list) why)))
    ((ok pr)
     (let [(prefixes (pairFirst pr))
           (reason (pairSecond pr))]
       (mt (sr/discover (if (stringEmpty? root) "." root) prefixes)
         ((err e) (pair ":full" (pair (list) (str "ERR_RUNNER " e))))
         ((ok suites) (pair ":affected" (pair suites reason)))))))

fn affected! base: String -> (Pair String (Pair (List String) String))
  (affectedAt! "" base)

(schema RunArgs
  (:f suites (List String))
  (:f paths (List String))
  (:f base (Option String))
  (:f telemetry (Option String)))

(schema ArgError
  (:f code Int64)
  (:f line String))

fn makeRunArgs suites: (List String) paths: (List String) base: (Option String) telemetry: (Option String) -> RunArgs
  (RunArgs :suites suites :paths paths :base base :telemetry telemetry)

fn usageError arg: String -> ArgError
  (ArgError :code 64 :line (str "(:runner :status :failed :err ERR_USAGE :ev \"" (sr/esc arg 400) "\")"))

fn missingValue -> ArgError
  (ArgError :code 2 :line "(:runner :status :failed :err ERR_RUNNER :ev \"\")")

fn withRunArg acc: RunArgs flag: String v: String -> RunArgs
  (cond
    ((= flag "--path") (with acc :paths (listAppend acc.paths (list v))))
    ((= flag "--suite") (with acc :suites (listAppend acc.suites (list v))))
    ((= flag "--base") (with acc :base (some v)))
    (else (with acc :telemetry (some v))))

fn parseRunArgs args: (List String) acc: RunArgs -> (Result RunArgs ArgError)
  (mt (listHead args)
    ((none) (ok acc))
    ((some a)
     (let [(tail (optionOr (listTail args) (list)))]
       (cond
         ((not (listContains? (list "--path" "--suite" "--base" "--telemetry") a)) (err (usageError a)))
         ((listEmpty? tail) (err (missingValue)))
         (else (parseRunArgs (optionOr (listTail tail) (list)) (withRunArg acc a (optionOr (listHead tail) ""))))))))

(schema Execution
  (:f results (List sr/SuiteResult))
  (:f checks (List rl/ReconcileCheck))
  (:f notEvaluated Int64)
  (:f held Int64)
  (:f deltaForm String)
  (:f wallMs Int64))

fn runnerFault e: String -> sr/Fault
  (sr/Fault :kind "runner" :msg e)

fn ! execute root: String suites: (List String) base: (Option String) workers: Int64 -> (Result Execution sr/Fault)
  (mt (sr/snapRun root suites workers 0)
    ((err f) (err f))
    ((ok run)
     (mt (rl/ledgerAt root (none))
       ((err e) (err (runnerFault e)))
       ((ok ledger)
        (mt (rl/ledgerAt root (some (optionOr base "HEAD")))
          ((err e) (err (runnerFault e)))
          ((ok baseLedger)
           (let [(results run.results)
                 (rec (rl/reconcile! results ledger root))
                 (gained run.gained)
                 (checks (if (listEmpty? gained)
                           rec.checks
                           (listAppend rec.checks (list (rl/makeReconcileCheck "ERR_TREE_DIRTIED" "snapshot" (str "suites wrote " (sr/gainedPaths gained))))))) ]
             (ok (Execution :results results :checks checks :notEvaluated rec.notEvaluated :held rec.held
                            :deltaForm (rl/delta baseLedger ledger) :wallMs run.wallMs)))))))))

fn sumBy results: (List sr/SuiteResult) pick: (fn [sr/SuiteResult] -> Int64) -> Int64
  (fold (fn [(acc Int64) (r sr/SuiteResult)] -> Int64 (+ acc (pick r))) 0 results)

fn causeCounts results: (List sr/SuiteResult) -> (List String)
  (let [(causes (listSortUnique (map (fn [(r sr/SuiteResult)] -> String r.cause)
                                     (filter (fn [(r sr/SuiteResult)] -> Bool (!= r.cause "OK")) results))))]
    (map (fn [(c String)] -> String
           (str "    (:cause \"" c "\" :count " (stringFromInt64 (listLength (filter (fn [(r sr/SuiteResult)] -> Bool (= r.cause c)) results))) ")\n"))
         causes))

fn ! today! -> (Result String String)
  (mt (sr/runOne! (sr/Job :input "" :argv (list "/bin/date" "+%Y-%m-%d") :cwd (none) :env (none) :timeoutMs 10000))
    ((err e) (err e))
    ((ok d) (if (= d.code 0) (ok (sr/pyStrip d.out)) (err (str "date: " (sr/pyStrip d.errText))))))

fn osError e: String path: String -> String
  (let [(codes (list (pair "No such file or directory" 2) (pair "Permission denied" 13) (pair "Is a directory" 21) (pair "Not a directory" 20) (pair "File exists" 17) (pair "Read-only file system" 30)))
        (hit (listHead (filter (fn [(c (Pair String Int64))] -> Bool (stringEndsWith? e (str ": " (pairFirst c)))) codes)))]
    (mt hit
      ((some c) (str "[Errno " (stringFromInt64 (pairSecond c)) "] " (pairFirst c) ": '" path "'"))
      ((none) e)))

fn ! writeFile! path: String text: String -> (Result Unit String)
  (mt (fileWrite path text) ((ok _) (ok ())) ((err e) (err (osError e path))))

fn ! writeTelemetry path: String results: (List sr/SuiteResult) wallMs: Int64 -> (Result Unit String)
  (let [(executed (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.asserts)))
        (refuted (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.refutes)))
        (declared (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.declared)))
        (passed (listLength (filter (fn [(r sr/SuiteResult)] -> Bool (= r.cause "OK")) results)))
        (failed (- (listLength results) passed))
        (n (fn [(i Int64)] -> String (stringFromInt64 i)))
        (digest (optionOr (stringSlice (bytesSha256 (stringToBytes (str (n executed) ":" (n refuted) ":" (n passed) ":" (n failed)))) 0 16) ""))]
    (mt (today!)
      ((err e) (err e))
      ((ok date)
       (mt (realPath ".")
         ((err e) (err e))
         ((ok cwd)
          (mt (dirCreate (sr/dirname (sr/normpath (sr/absPath cwd path))))
            ((err e) (err (osError e (sr/dirname (sr/normpath (sr/absPath cwd path))))))
            ((ok _)
             (writeFile! path
               (str "(:testTelemetry :v 3 :date \"" date "\" :method \"scripts/audit/runner.py: tracked suites run from a snapshot, per-suite cause and declared gap\"\n"
                    "  :runnerDigest \"" digest "\"\n"
                    "  :suites " (n (listLength results)) " :passedSuites " (n passed) " :failedSuites " (n failed) "\n"
                    "  :declaredAsserts " (n declared) " :executedAsserts " (n executed) " :executedRefutes " (n refuted)
                    " :verifiedTotal " (n (+ executed refuted)) " :declaredVerifiedGap " (n (- declared (+ executed refuted))) " :totalWallMs " (n wallMs) "\n"
                    "  :failureCauses [\n"
                    (stringJoin (causeCounts results) "")
                    "  ])\n")))))))))

fn ! maybeTelemetry tel: (Option String) x: Execution -> (Result Unit String)
  (mt tel
    ((none) (ok ()))
    ((some p) (writeTelemetry p x.results x.wallMs)))

fn faultExit! f: sr/Fault -> Int64
  (cond
    ((= f.kind "terminated") 143)
    ((= f.kind "busy") (do (println (str "(:runner :status :failed :err ERR_BUSY :ev \"" (sr/esc f.msg 400) "\")")) 1))
    (else (do (println (str "(:runner :status :failed :err ERR_RUNNER :ev \"" (sr/esc f.msg 400) "\")")) 2)))

fn ! receiptFor root: String x: Execution scope: String frozen: Int64 -> (Result (Pair String Bool) sr/Fault)
  (mt (sr/getExcludedForm root)
    ((err e) (err (runnerFault e)))
    ((ok excluded) (ok (rl/receipt x.results x.checks x.notEvaluated x.held x.deltaForm excluded scope frozen))))

fn ! runWith root: String parsed: RunArgs -> (Result Int64 sr/Fault)
  (let [(suites parsed.suites)
        (paths parsed.paths)
        (scope (if (and (listEmpty? paths) (listEmpty? suites)) ":full" ":affected"))
        (frozen (if (listEmpty? suites) (resultOr (sr/frozenCount root paths) 0) 0))
        (chosen (if (listEmpty? suites) (sr/discover root paths) (ok (listSortUnique suites))))]
    (mt chosen
      ((err e) (err (runnerFault e)))
      ((ok cs)
       (mt (execute root cs parsed.base (sr/workerCount (none)))
         ((err f) (err f))
         ((ok x)
          (mt (receiptFor root x scope frozen)
            ((err f) (err f))
            ((ok receiptRes)
             (mt (maybeTelemetry parsed.telemetry x)
               ((err e) (err (runnerFault e)))
               ((ok _)
                (do
                  (println (pairFirst receiptRes))
                  (eprintln (str "runner: " (stringFromInt64 (listLength x.results)) " suites, " (stringFromInt64 (listLength x.checks)) " red checks, " (if (pairSecond receiptRes) "passed" "failed")))
                  (ok (if (pairSecond receiptRes) 0 1))))))))))))

fn ! cmdRun root: String args: (List String) -> Int64
  (mt (parseRunArgs args (makeRunArgs (list) (list) (none) (none)))
    ((err e) (do (println e.line) e.code))
    ((ok parsed) (mt (runWith root parsed) ((err f) (faultExit! f)) ((ok code) code))))

(schema GateTestsArgs
  (:f telemetry (Option String))
  (:f baseline (Option String))
  (:f jobs (Option String))
  (:f positional (List String)))

fn afterEquals a: String -> String
  (let [(i (optionOr (stringIndexOf a "=") 0))]
    (optionOr (stringSlice a (+ i 1) (stringLength a)) ""))

fn setTelemetry g: GateTestsArgs v: String -> GateTestsArgs
  (with g :telemetry (some v))

fn setBaseline g: GateTestsArgs v: String -> GateTestsArgs
  (with g :baseline (some v))

fn setJobs g: GateTestsArgs v: String -> GateTestsArgs
  (with g :jobs (some v))

fn withValue args: (List String) g: GateTestsArgs setter: (fn [GateTestsArgs String] -> GateTestsArgs) -> (Result GateTestsArgs ArgError)
  (mt (listHead (optionOr (listTail args) (list)))
    ((none) (err (missingValue)))
    ((some v) (parseGateTestsArgs (optionOr (listTail (optionOr (listTail args) (list))) (list)) (setter g v))))

fn parseGateTestsArgs args: (List String) g: GateTestsArgs -> (Result GateTestsArgs ArgError)
  (mt (listHead args)
    ((none) (ok g))
    ((some a)
     (let [(rest (optionOr (listTail args) (list)))]
       (cond
         ((or (stringStartsWith? a "--telemetry=") (stringStartsWith? a "--telemetry-out=")) (parseGateTestsArgs rest (setTelemetry g (afterEquals a))))
         ((or (= a "--telemetry") (= a "--telemetry-out")) (withValue args g setTelemetry))
         ((or (stringStartsWith? a "--check-regression=") (stringStartsWith? a "--compare-baseline=")) (parseGateTestsArgs rest (setBaseline g (afterEquals a))))
         ((or (= a "--check-regression") (= a "--compare-baseline")) (withValue args g setBaseline))
         ((or (stringStartsWith? a "--jobs=") (stringStartsWith? a "-j=")) (parseGateTestsArgs rest (setJobs g (afterEquals a))))
         ((= a "-j") (withValue args g setJobs))
         (else (parseGateTestsArgs rest (with g :positional (listAppend g.positional (list a)))))))))

fn listTakeWhileDigits cs: (List String) acc: (List String) -> (List String)
  (mt (listHead cs)
    ((none) (listReverse acc))
    ((some c) (if (stringContains? "0123456789" c) (listTakeWhileDigits (optionOr (listTail cs) (list)) (cons c acc)) (listReverse acc))))

fn leadingDigits s: String -> String
  (stringJoin (listTakeWhileDigits (stringChars s) (list)) "")

fn afterKey text: String key: String -> (Option String)
  (mt (stringIndexOf text key)
    ((none) (none))
    ((some i) (stringSlice text (+ i (stringLength key)) (stringLength text))))

fn baselineAsserts text: String -> (Option Int64)
  (let [(digest (mt (afterKey text ":runnerDigest \"")
                  ((none) "")
                  ((some rest) (mt (stringIndexOf rest "\"") ((some j) (optionOr (stringSlice rest 0 j) "")) ((none) "")))))
        (executed (mt (afterKey text ":executedAsserts ")
                    ((none) 0)
                    ((some rest) (optionOr (stringToInt64 (leadingDigits rest)) 0))))]
    (if (and (>= (stringLength digest) 8) (> executed 0)) (some executed) (none)))

fn printChecks! checks: (List rl/ReconcileCheck) -> Unit
  (fold (fn [(u Unit) (c rl/ReconcileCheck)] -> Unit
          (println (str "    x " c.err " " c.suite ": " (optionOr (stringSlice c.ev 0 (min 300 (stringLength c.ev))) ""))))
        ()
        checks)

fn gateTestsVerdict! x: Execution receiptRes: (Pair String Bool) baseline: (Option Int64) tolerance: Int64 tel: (Option String) -> Int64
  (let [(results x.results)
        (n (fn [(i Int64)] -> String (stringFromInt64 i)))
        (executed (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.asserts)))
        (verified (+ executed (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.refutes))))
        (declared (sumBy results (fn [(r sr/SuiteResult)] -> Int64 r.declared)))
        (_ (mt tel ((some p) (println (str "Telemetry emitted to " p))) ((none) ())))
        (_ (if (pairSecond receiptRes) () (printChecks! x.checks)))
        (floor (optionOr baseline 400))
        (floorOk (if (< executed floor)
                   (do (eprintln (str "    x executed assertions " (n executed) " below " (if (some? baseline) "baseline" "floor") " " (n floor))) false)
                   true))
        (gap (- declared verified))
        (gapOk (if (> gap tolerance)
                 (do (eprintln (str "    x declared-vs-executed gap " (n gap) " > tolerance " (n tolerance) " (" (n declared) " declared, " (n verified) " verified)")) false)
                 (do (println (str "    Declared-vs-executed reconciliation passed: " (n declared) " declared, " (n verified) " verified, gap " (n gap) " (tolerance " (n tolerance) ")")) true)))]
    (do
      (println (pairFirst receiptRes))
      (if (and (pairSecond receiptRes) floorOk gapOk) 0 1)))

fn ! gateTestsWith root: String g: GateTestsArgs baseline: (Option Int64) -> (Result Int64 sr/Fault)
  (let [(scope (sr/normpath (optionOr (listGet g.positional 2) "asl/packages/asl-gates/tests")))
        (prefixes (if (= scope ".") (list) (list scope)))]
    (mt (sr/discover root prefixes)
      ((err e) (err (runnerFault e)))
      ((ok suites)
       (mt (execute root suites (none) (sr/workerCount g.jobs))
         ((err f) (err f))
         ((ok x)
          (mt (maybeTelemetry g.telemetry x)
            ((err e) (err (runnerFault e)))
            ((ok _)
             (mt (sr/envInt! "ASL_DECLARED_GAP_TOLERANCE" 0)
               ((err e) (err (runnerFault e)))
               ((ok tolerance)
                (mt (receiptFor root x (if (listEmpty? prefixes) ":full" ":affected") (resultOr (sr/frozenCount root prefixes) 0))
                  ((err f) (err f))
                  ((ok receiptRes) (ok (gateTestsVerdict! x receiptRes baseline tolerance g.telemetry)))))))))))))

fn ! cmdGateTests root: String args: (List String) -> Int64
  (mt (parseGateTestsArgs args (GateTestsArgs :telemetry (none) :baseline (none) :jobs (none) :positional (list)))
    ((err e) (do (println e.line) e.code))
    ((ok g)
     (let [(baselineRead (mt g.baseline
                           ((none) (ok (none)))
                           ((some b)
                            (mt (fileReadString b)
                              ((err _) (err (str "Error: baseline file not found: " b)))
                              ((ok text)
                               (mt (baselineAsserts text)
                                 ((none) (err (str "Error: baseline lacks a runner digest or positive :executedAsserts: " b)))
                                 ((some k) (ok (some k)))))))))]
       (mt baselineRead
         ((err why) (do (eprintln why) 1))
         ((ok baseline) (mt (gateTestsWith root g baseline) ((err f) (faultExit! f)) ((ok code) code)))))))

(schema CaptureArgs
  (:f out (Option String))
  (:f runs Int64)
  (:f paths (List String)))

fn parseCaptureArgs args: (List String) c: CaptureArgs -> (Result CaptureArgs ArgError)
  (mt (listHead args)
    ((none) (ok c))
    ((some a)
     (let [(tail (optionOr (listTail args) (list)))
           (v (optionOr (listHead tail) ""))
           (rest (optionOr (listTail tail) (list)))]
       (cond
         ((not (listContains? (list "--out" "--path" "--runs") a)) (err (ArgError :code 64 :line (str "capture: unknown argument " a))))
         ((listEmpty? tail) (err (missingValue)))
         ((= a "--out") (parseCaptureArgs rest (with c :out (some v))))
         ((= a "--path") (parseCaptureArgs rest (with c :paths (listAppend c.paths (list v)))))
         (else
          (mt (stringToInt64 v)
            ((none) (err (ArgError :code 1 :line (str "capture: invalid literal for int() with base 10: '" v "'"))))
            ((some k) (parseCaptureArgs rest (with c :runs k)))))))))

(schema Round
  (:f bySuite (Map String sr/SuiteResult)))

fn ! captureRounds! clone: String suites: (List String) runs: Int64 acc: (List Round) -> (Result (List Round) sr/Fault)
  (if (<= runs 0)
    (ok (listReverse acc))
    (mt (execute clone suites (none) (sr/workerCount (none)))
      ((err f) (err f))
      ((ok x) (captureRounds! clone suites (- runs 1) (cons (Round :bySuite (mapFromPairs (map (fn [(r sr/SuiteResult)] -> (Pair String sr/SuiteResult) (pair r.suite r)) x.results))) acc)))))

fn sigOf rd: Round s: String -> String
  (mt (mapGet rd.bySuite s) ((some r) (str r.cause "\n" r.digest)) ((none) ""))

fn ! captureIn root: String clone: String c: CaptureArgs out: String -> (Result Int64 sr/Fault)
  (mt (sr/gitOut! root (list "clone" "-q" root clone))
    ((err e) (err (runnerFault e)))
    ((ok _)
     (let [(_ (sr/gitRun! clone (list "remote" "remove" "origin")))]
       (mt (sr/gitOut! clone (list "rev-parse" "HEAD"))
         ((err e) (err (runnerFault e)))
         ((ok shaOut)
          (let [(sha (sr/pyStrip shaOut))]
            (mt (sr/discover clone c.paths)
              ((err e) (err (runnerFault e)))
              ((ok suites)
               (mt (captureRounds! clone suites c.runs (list))
                 ((err f) (err f))
                 ((ok rounds)
                  (let [(first (optionOr (listHead rounds) (Round :bySuite (mapEmpty))))
                        (flaky (filter (fn [(s String)] -> Bool (listAny? (fn [(rd Round)] -> Bool (!= (sigOf rd s) (sigOf first s))) rounds)) suites))
                        (entries (filter (fn [(s String)] -> Bool (and (not (listContains? flaky s)) (mt (mapGet first.bySuite s) ((some r) (!= r.cause "OK")) ((none) false)))) suites))]
                    (mt (today!)
                      ((err e) (err (runnerFault e)))
                      ((ok date)
                       (mt (writeFile! out
                             (str "(:knownRed :v 1 :capturedFrom \"" sha "\" :runs " (stringFromInt64 c.runs) " :scope \"" (sr/esc (if (listEmpty? c.paths) "full" (stringJoin c.paths " ")) 400) "\" :date \"" date "\" :confirmation :unverified\n"
                                  (stringJoin (map (fn [(s String)] -> String (str "  (:flaky \"" s "\")\n")) flaky) "")
                                  (stringJoin (map (fn [(s String)] -> String
                                                     (let [(r (optionOr (mapGet first.bySuite s) (sr/makeSuiteResult s "" "" "" 0 0 0 0)))]
                                                       (str "  (:suite \"" s "\" :cause \"" r.cause "\" :failedAssertDigest \"" r.digest "\" :since \"" sha "\")\n")))
                                                   entries) "")
                                  ")\n"))
                         ((err e) (err (runnerFault e)))
                         ((ok _)
                          (do
                            (println (str "(:capture :status :written :out \"" (sr/esc out 400) "\" :sha \"" sha "\" :suites " (stringFromInt64 (listLength suites))
                                          " :entries " (stringFromInt64 (listLength entries)) " :flaky " (stringFromInt64 (listLength flaky)) ")"))
                            (ok 0)))))))))))))))))

fn ! cmdCapture root: String args: (List String) -> Int64
  (mt (parseCaptureArgs args (CaptureArgs :out (none) :runs 2 :paths (list)))
    ((err e) (if (= e.code 2) (do (println e.line) 2) (do (eprintln e.line) e.code)))
    ((ok c)
     (mt c.out
       ((none) (do (eprintln "capture: --out FILE required and --runs must be at least 2") 64))
       ((some out)
        (if (< c.runs 2)
          (do (eprintln "capture: --out FILE required and --runs must be at least 2") 64)
          (do
            (sr/sweepStaleTemps!)
            (mt (sr/makeTempDir! "aslKnownRedCapture")
              ((err e) (faultExit! (runnerFault e)))
              ((ok clone)
               (let [(res (captureIn root clone c out))
                     (_ (pathRemove clone))]
                 (mt res ((err f) (faultExit! f)) ((ok code) code)))))))))))

fn strictFalsifyRejected -> String
  "ERR_UNSUPPORTED: --strict-falsify has no implementation: asl/host/out/asl-host test takes files only; refusing rather than running without it"

fn ! cmdGate root: String rest: (List String) -> Int64
  (if (or (!= (listLength rest) 1) (stringStartsWith? (optionOr (listHead rest) "") "-"))
    (do
      (println "(:runner :status :failed :err ERR_USAGE :ev \"usage: runner.py gate SUITE\")")
      64)
    (sr/gate root (optionOr (listHead rest) "")))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listHead args)
    ((none) (do (eprintln "usage: runner.py run|gateTests|capture|gate ...") (ok 64)))
    ((some cmd)
     (let [(rest (optionOr (listTail args) (list)))]
       (if (or (listContains? rest "--strict-falsify") (= (envGet "ASL_STRICT_FALSIFY") (some "1")))
         (do
           (println (str "(:runner :status :failed :err ERR_UNSUPPORTED :ev \"" (sr/esc (strictFalsifyRejected) 400) "\")"))
           (ok 2))
         (if (not (listContains? (list "run" "gateTests" "capture" "gate") cmd))
           (do (println (str "(:runner :status :failed :err ERR_USAGE :ev \"" (sr/esc cmd 400) "\")")) (ok 64))
           (mt (sr/gitRoot!)
             ((err e) (ok (faultExit! (runnerFault e))))
             ((ok root)
              (ok (cond
                    ((= cmd "run") (cmdRun root rest))
                    ((= cmd "gateTests") (cmdGateTests root rest))
                    ((= cmd "capture") (cmdCapture root rest))
                    (else (cmdGate root rest)))))))))))
