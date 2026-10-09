(module asl-gates/vacuity
  :x [VacuityConfig VacuityTally parseArgv parseAssertions classify escapeStr isTapPlan isTapVersion isAllDigits statusRecords copyFilesLoop! copyUncommittedTestFiles! copyFileTo! runAt! VacuityProcessOutput main]
  :i [(asl-proc/coreProcess :a cp)])

(schema VacuityConfig
  (:f baseRef String)
  (:f failOnVacuous Bool)
  (:f testCmd String))

(schema VacuityTally
  (:f vacuous (List String))
  (:f realGreen Int64)
  (:f stillRed Int64)
  (:f baseOnly Int64))

(schema VacuityProcessOutput
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn escapeStr s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn isDigit c: Int64 -> Bool
  (and (>= c 48) (<= c 57))

fn isAllDigitsLoop bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    true
    (if (not (isDigit (bytesGet bs i)))
      false
      (isAllDigitsLoop bs n (+ i 1))))

fn isAllDigits s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0)
      false
      (let [(b (stringToBytes s))]
        (isAllDigitsLoop b (bytesLength b) 0))))

fn isTapPlan line: String -> Bool
  (let [(clean (let [(hashIdx (optionOr (stringIndexOf line "#") -1))]
                 (if (>= hashIdx 0) (stringTrim (optionOr (stringSlice line 0 hashIdx) "")) (stringTrim line))))]
    (let [(dotIdx (optionOr (stringIndexOf clean "..") -1))]
      (if (< dotIdx 1)
        false
        (let [(part1 (optionOr (stringSlice clean 0 dotIdx) ""))
              (part2 (optionOr (stringSlice clean (+ dotIdx 2) (stringLength clean)) ""))]
          (and (isAllDigits part1) (isAllDigits part2))))))

fn isTapVersion line: String -> Bool
  (stringStartsWith? (stringLower line) "tap version ")

fn parseArgvLoop args: (List String) baseRef: String failOnVacuous: Bool testTokens: (List String) testSeen: Bool inTest: Bool -> (Result VacuityConfig String)
  (if (listEmpty? args)
    (let [(testCmd (stringTrim (stringJoin (listReverse testTokens) " ")))]
      (if (or (not testSeen) (stringEmpty? testCmd))
        (err "(:vacuity :error ERR_ARGS :hint \"missing required --test argument\")")
        (ok (VacuityConfig :baseRef baseRef :failOnVacuous failOnVacuous :testCmd testCmd))))
    (let [(arg (optionOr (listHead args) ""))
          (tail (optionOr (listTail args) (list)))]
      (cond
        ((or (= arg "--help") (= arg "-h"))
          (err "HELP"))
        ((= arg "--fail-on-vacuous")
          (parseArgvLoop tail baseRef true testTokens testSeen false))
        ((= arg "--base")
          (if (listEmpty? tail)
            (err "(:vacuity :error ERR_ARGS :hint \"missing argument after --base\")")
            (let [(baseVal (optionOr (listHead tail) ""))
                  (nextTail (optionOr (listTail tail) (list)))]
              (parseArgvLoop nextTail baseVal failOnVacuous testTokens testSeen false))))
        ((stringStartsWith? arg "--base=")
          (let [(baseVal (optionOr (stringSlice arg 7 (stringLength arg)) ""))]
            (parseArgvLoop tail baseVal failOnVacuous testTokens testSeen false)))
        ((= arg "--test")
          (parseArgvLoop tail baseRef failOnVacuous testTokens true true))
        ((stringStartsWith? arg "--test=")
          (let [(tok (optionOr (stringSlice arg 7 (stringLength arg)) ""))]
            (parseArgvLoop tail baseRef failOnVacuous (cons tok testTokens) true false)))
        (inTest
          (parseArgvLoop tail baseRef failOnVacuous (cons arg testTokens) testSeen true))
        (else
          (err (str "(:vacuity :error ERR_ARGS :hint \"unexpected argument '" (escapeStr arg) "' before --test\")"))))))

fn parseArgv args: (List String) -> (Result VacuityConfig String)
  (parseArgvLoop args "HEAD" false (list) false false)

fn parseLine line: String -> (Option (Option (Pair String Bool)))
  (cond
    ((stringEmpty? line) (some (none)))
    ((stringStartsWith? line "#") (some (none)))
    ((and (stringStartsWith? line "(:") (stringEndsWith? line ")")) (some (none)))
    ((isTapPlan line) (some (none)))
    ((isTapVersion line) (some (none)))
    ((stringStartsWith? line "not ok")
      (let [(clean (let [(h (optionOr (stringIndexOf line "#") -1))]
                     (if (>= h 0) (stringTrim (optionOr (stringSlice line 0 h) "")) line)))]
        (let [(rest (stringTrim (optionOr (stringSlice clean 6 (stringLength clean)) "")))]
          (if (stringEmpty? rest)
            (none)
            (if (stringStartsWith? rest "-")
              (let [(desc (stringTrim (optionOr (stringSlice rest 1 (stringLength rest)) "")))]
                (if (stringEmpty? desc) (none) (some (some (pair desc false)))))
              (let [(words (stringSplit rest " "))
                    (w0 (optionOr (listHead words) ""))]
                (if (isAllDigits w0)
                  (let [(rest2 (stringTrim (optionOr (stringSlice rest (stringLength w0) (stringLength rest)) "")))]
                    (let [(desc (if (stringStartsWith? rest2 "-")
                                  (stringTrim (optionOr (stringSlice rest2 1 (stringLength rest2)) ""))
                                  rest2))]
                      (let [(aid (if (stringEmpty? desc) w0 desc))]
                        (some (some (pair aid false))))))
                  (none))))))))
    ((stringStartsWith? line "ok")
      (let [(rest (stringTrim (optionOr (stringSlice line 2 (stringLength line)) "")))]
        (if (stringStartsWith? rest "-")
          (let [(clean (let [(h (optionOr (stringIndexOf rest "#") -1))]
                         (if (>= h 0) (stringTrim (optionOr (stringSlice rest 0 h) "")) rest)))]
            (let [(desc (stringTrim (optionOr (stringSlice clean 1 (stringLength clean)) "")))]
              (if (stringEmpty? desc) (none) (some (some (pair desc true))))))
          (let [(clean (let [(h (optionOr (stringIndexOf rest "#") -1))]
                         (if (>= h 0) (stringTrim (optionOr (stringSlice rest 0 h) "")) rest)))]
            (let [(words (stringSplit clean " "))
                  (w0 (optionOr (listHead words) ""))]
              (if (isAllDigits w0)
                (let [(rest2 (stringTrim (optionOr (stringSlice clean (stringLength w0) (stringLength clean)) "")))]
                  (let [(desc (if (stringStartsWith? rest2 "-")
                                (stringTrim (optionOr (stringSlice rest2 1 (stringLength rest2)) ""))
                                rest2))]
                    (let [(aid (if (stringEmpty? desc) w0 desc))]
                      (some (some (pair aid true))))))
                (let [(wordsOrig (stringSplit rest " "))
                      (grp (optionOr (listHead wordsOrig) ""))]
                  (if (stringEmpty? grp)
                    (none)
                    (let [(nm (stringTrim (optionOr (stringSlice rest (stringLength grp) (stringLength rest)) "")))]
                      (let [(aid (if (stringEmpty? nm) grp (str grp " " nm)))]
                        (some (some (pair aid true)))))))))))))
    ((stringStartsWith? line "FAIL")
      (let [(rest (stringTrim (optionOr (stringSlice line 4 (stringLength line)) "")))]
        (let [(colonIdx (optionOr (stringIndexOf rest ":") -1))]
          (let [(beforeColon (if (>= colonIdx 0) (stringTrim (optionOr (stringSlice rest 0 colonIdx) "")) rest))]
            (let [(words (stringSplit beforeColon " "))
                  (grp (optionOr (listHead words) ""))]
              (if (stringEmpty? grp)
                (none)
                (let [(nm (stringTrim (optionOr (stringSlice beforeColon (stringLength grp) (stringLength beforeColon)) "")))]
                  (let [(aid (if (stringEmpty? nm) grp (str grp " " nm)))]
                    (some (some (pair aid false)))))))))))
    (else (none)))

fn parseLinesLoop lines: (List String) acc: (Map String Bool) keys: (List String) count: Int64 stderr: String -> (Result (Map String Bool) String)
  (if (listEmpty? lines)
    (if (= count 0)
      (let [(errTrim (stringTrim stderr))]
        (if (stringEmpty? errTrim)
          (err "no assertion lines found in output")
          (let [(lim (if (> (stringLength errTrim) 200) 200 (stringLength errTrim)))]
            (err (str "no assertion lines found in output; stderr: " (optionOr (stringSlice errTrim 0 lim) ""))))))
      (ok acc))
    (let [(raw (optionOr (listHead lines) ""))
          (tail (optionOr (listTail lines) (list)))
          (line (stringTrim raw))]
      (mt (parseLine line)
        ((none)
          (err (str "unrecognized output line: " line)))
        ((some optPair)
          (mt optPair
            ((none)
              (parseLinesLoop tail acc keys count stderr))
            ((some p)
              (let [(aid (pairFirst p))
                    (val (pairSecond p))
                    (newAcc (mapSet acc aid val))
                    (newKeys (if (mapHas? acc aid) keys (cons aid keys)))]
                (parseLinesLoop tail newAcc newKeys (+ count 1) stderr))))))))

fn parseAssertions stdout: String stderr: String -> (Result (Map String Bool) String)
  (let [(lines (stringLines stdout))]
    (parseLinesLoop lines (mapEmpty) (list) 0 stderr))

fn classifyBaseOnly baseKeys: (List String) baseMap: (Map String Bool) workMap: (Map String Bool) bo: Int64 vacAcc: (List String) rg: Int64 sr: Int64 -> VacuityTally
  (if (listEmpty? baseKeys)
    (VacuityTally :vacuous (listReverse vacAcc) :realGreen rg :stillRed sr :baseOnly bo)
    (let [(aid (optionOr (listHead baseKeys) ""))
          (tail (optionOr (listTail baseKeys) (list)))
          (okBase (optionOr (mapGet baseMap aid) false))]
      (if (and (not (mapHas? workMap aid)) okBase)
        (classifyBaseOnly tail baseMap workMap (+ bo 1) vacAcc rg sr)
        (classifyBaseOnly tail baseMap workMap bo vacAcc rg sr))))

fn classifyLoop workKeys: (List String) baseMap: (Map String Bool) workMap: (Map String Bool) vacAcc: (List String) rg: Int64 sr: Int64 bo: Int64 -> VacuityTally
  (if (listEmpty? workKeys)
    (let [(baseKeys (mapKeys baseMap))]
      (classifyBaseOnly baseKeys baseMap workMap bo vacAcc rg sr))
    (let [(aid (optionOr (listHead workKeys) ""))
          (tail (optionOr (listTail workKeys) (list)))
          (okWork (optionOr (mapGet workMap aid) false))
          (hasBase (mapHas? baseMap aid))
          (okBase (if hasBase (optionOr (mapGet baseMap aid) false) false))]
      (if okWork
        (if (and hasBase okBase)
          (classifyLoop tail baseMap workMap (cons aid vacAcc) rg sr bo)
          (classifyLoop tail baseMap workMap vacAcc (+ rg 1) sr bo))
        (if (or (not hasBase) (not okBase))
          (classifyLoop tail baseMap workMap vacAcc rg (+ sr 1) bo)
          (classifyLoop tail baseMap workMap vacAcc rg sr (+ bo 1))))))

fn classify base: (Map String Bool) work: (Map String Bool) -> VacuityTally
  (classifyLoop (mapKeys work) base work (list) 0 0 0)

fn copyFilesLoop! repoRoot: String wtDir: String lines: (List String) -> Unit
  (if (listEmpty? lines)
    ()
    (let [(raw (optionOr (listHead lines) ""))
          (tail (optionOr (listTail lines) (list)))]
      (do
        (if (>= (stringLength raw) 3)
          (let [(status (optionOr (stringSlice raw 0 2) ""))
                (pathClean (optionOr (stringSlice raw 3 (stringLength raw)) ""))]
            (do
              (let [(lower (stringLower pathClean))]
                (if (or (stringContains? lower "test") (or (stringContains? lower "fixture") (stringContains? lower "fixtures")))
                  (if (stringContains? status "D")
                    (mt (pathRemove (str wtDir "/" pathClean))
                      ((err e) (eprintln (str "vacuity: cannot remove " wtDir "/" pathClean ": " e)))
                      ((ok _) ()))
                    (let [(src (str repoRoot "/" pathClean))
                          (dst (str wtDir "/" pathClean))]
                      (let [(_ (copyFileTo! src dst))] ())))
                  ()))))
          ())
        (copyFilesLoop! repoRoot wtDir tail))))

fn copyTokenFiles! repoRoot: String wtDir: String tokens: (List String) -> Unit
  (if (listEmpty? tokens)
    ()
    (let [(tok (optionOr (listHead tokens) ""))
          (tail (optionOr (listTail tokens) (list)))]
      (do
        (if (and (not (stringEmpty? tok)) (not (stringStartsWith? tok "-")))
          (let [(cand (str repoRoot "/" tok))]
            (if (fileExists? cand)
              (let [(dst (str wtDir "/" tok))]
                (let [(_ (copyFileTo! cand dst))] ()))
              ()))
          ())
        (copyTokenFiles! repoRoot wtDir tail))))

fn nulLoop s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (if (< start n) (cons (optionOr (stringSlice s start n) "") acc) acc)))
    ((= (bytesGet bs i) 0) (nulLoop s bs (+ i 1) (+ i 1) n (cons (optionOr (stringSlice s start i) "") acc)))
    (else (nulLoop s bs (+ i 1) start n acc)))

fn renameOrigins records: (List String) acc: (List String) -> (List String)
  (mt (listHead records)
    ((none) (listReverse acc))
    ((some rec)
      (let [(rest (optionOr (listTail records) (list)))
            (x (optionOr (stringSlice rec 0 1) ""))]
        (renameOrigins (if (or (= x "R") (= x "C")) (optionOr (listTail rest) (list)) rest) (cons rec acc)))))

fn statusRecords text: String -> (List String)
  (let [(bs (stringToBytes text))]
    (renameOrigins (nulLoop text bs 0 0 (bytesLength bs) (list)) (list)))

fn copyUncommittedTestFiles! repoRoot: String wtDir: String testCmd: String -> Unit
  (let [(statusRes (runAt! (list "git" "-C" repoRoot "status" "--porcelain" "-z" "-uall") (none)))]
    (do
      (if (= statusRes.exitCode 0)
        (copyFilesLoop! repoRoot wtDir (statusRecords statusRes.stdout))
        (eprintln (str "vacuity: git status failed in " repoRoot ": " (stringTrim statusRes.stderr))))
      (copyTokenFiles! repoRoot wtDir (stringSplit testCmd " "))
      ()))

fn copyFileTo! src: String dst: String -> Bool
  (let [(parts (stringSplit dst "/"))
        (parentParts (listReverse (optionOr (listTail (listReverse parts)) (list))))
        (parent (stringJoin parentParts "/"))
        (made (dirCreate parent))]
    (mt made
      ((err e) (do (eprintln (str "cannot create copy directory " parent ": " e)) false))
      ((ok _)
        (mt (fileStat src)
          ((err e) (do (eprintln (str "cannot copy " src " to " dst ": " e)) false))
          ((ok stat)
            (let [(isDir stat.isDir)
                  (prepared (if isDir (dirCreate dst) (ok ())))]
              (mt prepared
                ((err e) (do (eprintln (str "cannot create copy directory " dst ": " e)) false))
                ((ok _)
                  (let [(source (if isDir (str src "/.") src))
                        (copied (runAt! (list "cp" "-R" "-p" source dst) (none)))]
                    (if (!= copied.exitCode 0)
                      (do (eprintln (str "cannot copy " src " to " dst ": " (stringTrim copied.stderr))) false)
                      true))))))))))

fn ! removeTemp! dir: String -> Unit
  (mt (pathRemove dir)
    ((err e) (eprintln (str "vacuity: cannot remove " dir ": " e)))
    ((ok _) ()))

fn ! reportFailed! what: String out: VacuityProcessOutput -> Unit
  (if (= out.exitCode 0) () (eprintln (str "vacuity: " what " failed (exit " (stringFromInt64 out.exitCode) "): " (stringTrim out.stderr))))

fn ! cleanup! repoRoot: String wtDir: String tmpParent: String -> Unit
  (do
    (reportFailed! "git worktree remove" (runAt! (list "git" "-C" repoRoot "worktree" "remove" "--force" wtDir) (none)))
    (removeTemp! tmpParent)
    (reportFailed! "git worktree prune" (runAt! (list "git" "-C" repoRoot "worktree" "prune") (none))))

fn ! runAt! argv: (List String) cwd: (Option String) -> VacuityProcessOutput
  (let [(bin (optionOr (listHead argv) ""))
        (args (optionOr (listTail argv) (list)))
        (base (cp/withTimeout (cp/cmd bin args) 1800000))
        (configured (mt cwd ((some dir) (cp/withCwd base dir)) ((none) base)))]
    (mt (cp/execRaw! configured)
      ((err e) (VacuityProcessOutput :exitCode 127 :stdout "" :stderr (str e)))
      ((ok out) (VacuityProcessOutput :exitCode out.exitCode :stdout out.stdout :stderr out.stderr))))

fn ! main argv: (List String) -> (Result Int64 String)
  (mt (parseArgv argv)
    ((err msg)
      (if (= msg "HELP")
        (do
          (println "Usage: python3 scripts/audit/vacuity.py --test <cmd...> [--base <ref>] [--fail-on-vacuous]")
          (ok 0))
        (do
          (println msg)
          (ok 2))))
    ((ok cfg)
      (let [(revProc (runAt! (list "git" "rev-parse" "--show-toplevel") (none)))]
        (if (!= revProc.exitCode 0)
          (do
            (println "(:vacuity :error ERR_GIT_REPO :hint \"not inside a git repository\")")
            (ok 2))
          (let [(repoRoot (stringTrim revProc.stdout))]
            (let [(shaProc (runAt! (list "git" "-C" repoRoot "rev-parse" cfg.baseRef) (none)))]
              (if (!= shaProc.exitCode 0)
                (do
                  (println (str "(:vacuity :error ERR_BASE_REF :hint \"cannot resolve base git ref '" (escapeStr cfg.baseRef) "'\")"))
                  (ok 2))
                (let [(baseSha (stringTrim shaProc.stdout))
                      (tmpProc (runAt! (list "mktemp" "-d" "/tmp/asl_vacuity_XXXXXX") (none)))]
                  (if (or (!= tmpProc.exitCode 0) (stringEmpty? (stringTrim tmpProc.stdout)))
                    (do
                      (println (str "(:vacuity :error ERR_TMP :hint \"mktemp failed: " (escapeStr (stringTrim tmpProc.stderr)) "\")"))
                      (ok 2))
                  (let [(tmpParent (stringTrim tmpProc.stdout))
                        (wtDir (str (stringTrim tmpProc.stdout) "/wt"))]
                    (let [(wtAddProc (runAt! (list "git" "-C" repoRoot "worktree" "add" "--detach" "-q" wtDir baseSha) (none)))]
                      (if (!= wtAddProc.exitCode 0)
                        (do
                          (removeTemp! tmpParent)
                          (let [(hint (stringTrim wtAddProc.stderr))]
                            (let [(lim (if (> (stringLength hint) 200) 200 (stringLength hint)))]
                              (println (str "(:vacuity :error ERR_WORKTREE :hint \"" (escapeStr (optionOr (stringSlice hint 0 lim) "")) "\")"))
                              (ok 2))))
                        (let [(_ (copyUncommittedTestFiles! repoRoot wtDir cfg.testCmd))
                              (pwdProc (runAt! (list "pwd") (none)))
                              (curCwd (stringTrim pwdProc.stdout))]
                          (let [(wtCwd (if (= curCwd repoRoot)
                                         wtDir
                                         (if (stringStartsWith? curCwd (str repoRoot "/"))
                                           (str wtDir "/" (optionOr (stringSlice curCwd (+ (stringLength repoRoot) 1) (stringLength curCwd)) ""))
                                           wtDir)))
                                (workCwd curCwd)]
                            (mt (dirCreate wtCwd)
                              ((err e)
                                (do
                                  (cleanup! repoRoot wtDir tmpParent)
                                  (println (str "(:vacuity :error ERR_WORKTREE :hint \"cannot create " (escapeStr wtCwd) ": " (escapeStr e) "\")"))
                                  (ok 2)))
                              ((ok _)
                              (let [(procBase (runAt! (list "/bin/sh" "-c" cfg.testCmd) (some wtCwd)))
                                    (procWork (runAt! (list "/bin/sh" "-c" cfg.testCmd) (some workCwd)))]
                                (do
                                  (cleanup! repoRoot wtDir tmpParent)
                                  (mt (parseAssertions procBase.stdout procBase.stderr)
                                    ((err baseErr)
                                      (do
                                        (println (str "(:vacuity :error ERR_UNPARSED :hint \"base run: " (escapeStr baseErr) "\")"))
                                        (ok 2)))
                                    ((ok baseResults)
                                      (mt (parseAssertions procWork.stdout procWork.stderr)
                                        ((err workErr)
                                          (do
                                            (println (str "(:vacuity :error ERR_UNPARSED :hint \"working tree run: " (escapeStr workErr) "\")"))
                                            (ok 2)))
                                        ((ok workResults)
                                          (let [(tally (classify baseResults workResults))]
                                            (let [(vacList tally.vacuous)]
                                              (let [(vacExpr (if (listEmpty? vacList)
                                                               "()"
                                                               (str "(" (stringJoin (map (fn [v] (str "\"" (escapeStr v) "\"")) vacList) " ") ")")))]
                                                (let [(receipt (str "(:vacuity :test \"" (escapeStr cfg.testCmd) "\" "
                                                                    ":base \"" (escapeStr baseSha) "\" "
                                                                    ":vacuous " vacExpr " "
                                                                    ":realGreen " (stringFromInt64 tally.realGreen) " "
                                                                    ":stillRed " (stringFromInt64 tally.stillRed) " "
                                                                    ":baseOnly " (stringFromInt64 tally.baseOnly) ")"))]
                                                  (do
                                                    (println receipt)
                                                    (if (and cfg.failOnVacuous (> (listLength vacList) 0))
                                                      (ok 1)
                                                      (ok 0)))))))))))))))))))))))))))))
