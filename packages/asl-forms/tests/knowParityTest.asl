(module asl-forms/tests/knowParityTest
  :x [runTests FileSpec CaseSpec CaseDirs parseFiles parseCases prepareCase! runForm! ledgerState! removeTree! caseDirName]
  :i [(asl-forms/kernel :a k) (asl-forms/wire :a w) (asl-forms/search :a s) (asl-forms/tools :a t) (asl-proc/coreProcess :a cp)])


(schema FileSpec (:f tree String) (:f path String) (:f kind String) (:f body String) (:f times Int64))

(schema CaseSpec (:f id Int64) (:f ws String) (:f tc String) (:f extra String) (:f git String) (:f bin String) (:f tools String) (:f form String) (:f stdout String) (:f exit Int64) (:f ledger String) (:f files String) (:f mask String) (:f wantLedger Bool))

(schema CaseDirs (:f dir String) (:f ws String) (:f tc String) (:f bin String) (:f toolsFile String))

(schema Tally (:f cases Int64) (:f failures Int64))


fn kwText kw: (Map String String) key: String -> String
  (optionOr (mapGet kw key) "")

fn fixtureLines text: String head: String -> (List k/ParsedStep)
  (map k/parseStep (filter (fn [(l String)] -> Bool (stringStartsWith? l head)) (stringSplit text "\n")))

fn parseFiles text: String -> (List FileSpec)
  (map (fn [(p k/ParsedStep)] -> FileSpec
         (let [(kw p.kwargs)]
           (cond
             ((mapHas? kw "base64") (FileSpec :tree (kwText kw "tree") :path (kwText kw "path") :kind "base64" :body (kwText kw "base64") :times 1))
             ((mapHas? kw "repeat") (FileSpec :tree (kwText kw "tree") :path (kwText kw "path") :kind "repeat" :body (kwText kw "repeat") :times (optionOr (stringToInt64 (kwText kw "times")) 0)))
             (else (FileSpec :tree (kwText kw "tree") :path (kwText kw "path") :kind "text" :body (kwText kw "text") :times 1)))))
       (fixtureLines text "(:file "))

fn parseCases text: String -> (List CaseSpec)
  (map (fn [(p k/ParsedStep)] -> CaseSpec
         (let [(kw p.kwargs)]
           (CaseSpec :id (optionOr (stringToInt64 (kwText kw "id")) 0) :ws (kwText kw "ws") :tc (kwText kw "tc") :extra (kwText kw "extra")
                     :git (kwText kw "git") :bin (kwText kw "bin") :tools (kwText kw "tools") :form (kwText kw "form")
                     :stdout (kwText kw "stdout") :exit (optionOr (stringToInt64 (kwText kw "exit")) -1)
                     :ledger (kwText kw "ledger") :files (kwText kw "files") :mask (kwText kw "mask") :wantLedger (mapHas? kw "ledger"))))
       (fixtureLines text "(:case "))

fn mkdirs! p: String -> Bool
  (cond
    ((k/isDir! p) true)
    ((= (k/dirName p) p) false)
    (else (and (mkdirs! (k/dirName p)) (or (k/isDir! p) (ok? (dirCreate p))))))

fn writeSpec! dir: String f: FileSpec -> Bool
  (let [(path (k/joinPath dir f.path))]
    (and (mkdirs! (k/dirName path))
         (cond
           ((= f.kind "base64") (mt (bytesFromBase64 f.body) ((ok b) (ok? (fileWrite path b))) ((err _) false)))
           ((= f.kind "repeat") (ok? (fileWrite path (stringRepeat f.body f.times))))
           (else (ok? (fileWrite path f.body))))))

fn materializeTree! files: (List FileSpec) tree: String dir: String -> Bool
  (and (mkdirs! dir) (listAll? (fn [(f FileSpec)] -> Bool (writeSpec! dir f)) (filter (fn [(f FileSpec)] -> Bool (= f.tree tree)) files)))

fn runGit! ws: String args: (List String) -> Bool
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" args) ws) 60000))
    ((ok out) (= out.exitCode 0))
    ((err _) false))

fn currentHost! repo: String -> (Option String)
  (mt (envGet "ASL_HOST")
    ((some h) (if (fileExists? h)
                (some (resultOr (realPath h) h))
                (do (println (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (assert false (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (none))))
    ((none) (let [(p (k/joinPath repo "asl/host/out/asl-host"))]
              (if (fileExists? p)
                (some (resultOr (realPath p) p))
                (do (println (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (none))))))

fn caseDirName id: Int64 -> String
  (str "c" (stringFromInt64 id))

fn prepareCase! repo: String base: String files: (List FileSpec) c: CaseSpec -> CaseDirs
  (let [(dir (k/joinPath base (caseDirName c.id)))
        (tc (k/joinPath dir "tc"))
        (ws (if (= c.ws "@tc") tc (k/joinPath dir "knowWs")))
        (made (and (materializeTree! files c.tc tc)
                   (or (= c.ws "@tc") (materializeTree! files c.ws ws))
                   (or (stringEmpty? c.extra) (materializeTree! files c.extra (k/joinPath dir c.extra)))))
        (gitOk (cond
                 ((= c.git "init") (runGit! ws (list "init" "-q")))
                 ((= c.git "add") (and (runGit! ws (list "init" "-q")) (runGit! ws (list "add" "-A"))))
                 (else true)))
        (stubs (k/joinPath repo "asl/packages/asl-forms/tests/fixtures/recorded/knowStubs"))
        (hostOpt (currentHost! repo))
        (hostDir (k/joinPath tc "asl/host/out"))
        (hostLinked (and (some? hostOpt)
                         (mkdirs! hostDir)
                         (mt (cp/exec! (cp/withTimeout (cp/cmd "ln" (list "-s" (optionOr hostOpt "") (k/joinPath hostDir "asl-host"))) 60000))
                           ((ok out) (= out.exitCode 0))
                           ((err _) false))))
        (bin (cond
               ((= c.bin "echo") (k/joinPath stubs "echo"))
               ((= c.bin "false") (k/joinPath stubs (if (fileExists? "/usr/bin/false") "false" "binFalse")))
               ((= c.bin "sh") (k/joinPath stubs "sh"))
               ((= c.bin "plain") (k/joinPath tc "bin"))
               (else (k/joinPath dir "nobin"))))]
    (if (and made gitOk hostLinked)
      (CaseDirs :dir dir :ws ws :tc tc :bin bin :toolsFile (if (stringEmpty? c.tools) "" (k/joinPath dir c.tools)))
      (CaseDirs :dir "" :ws ws :tc tc :bin bin :toolsFile "")))

fn uniqueRoots items: (List String) acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listSortBy (fn [(r String)] -> Int64 (- 0 (stringLength r))) (listReverse acc)))
    ((some r) (uniqueRoots (optionOr (listTail items) (list)) (if (or (stringEmpty? r) (= r "/") (listContains? acc r)) acc (cons r acc)))))

fn dispatch! ctx: s/KnowCtx id: Int64 raw: String p: k/ParsedStep -> s/KnowOutcome
  (let [(op p.op) (kw p.kwargs) (args p.args)]
    (cond
      ((or (= op "query") (= op "q")) (s/queryStep! ctx id kw args))
      ((= op "note") (s/noteStep! ctx id kw args))
      ((= op "where") (s/whereStep! ctx id kw args))
      ((= op "observe") (s/observeStep! ctx id kw args (s/kwOrder raw)))
      ((= op "tools") (t/toolsStep! ctx id kw args))
      ((= op "help") (t/helpStep! ctx id kw args))
      (else (s/badLine (str (s/stepHead id op) " :status \"rejected\" :error-code \":ERR_NOT_PORTED\" :message \"not a know op\")")))))

fn runForm! dirs: CaseDirs form: String -> (Pair String Int64)
  (let [(realWs (resultOr (realPath dirs.ws) dirs.ws))
        (ctx (s/KnowCtx :ws realWs :toolRoot dirs.tc :binDir dirs.bin :vfsDir "" :toolsFile dirs.toolsFile :home (optionOr (envGet "HOME") "")))
        (wsRec (w/Workspace :root realWs
                            :roots (uniqueRoots (list dirs.tc (resultOr (realPath dirs.tc) "") realWs) (list))
                            :ops (w/toolOps (resultOr (fileReadString (k/joinPath dirs.tc "asl/grammar/tools.asn")) ""))))
        (raws (k/extractSteps (stringTrim form)))
        (outs (map (fn [(ip (Pair Int64 String))] -> (Pair String s/KnowOutcome)
                     (let [(p (k/parseStep (pairSecond ip)))] (pair p.op (dispatch! ctx (+ (pairFirst ip) 1) (pairSecond ip) p))))
                   (enumerate raws)))
        (wired (fold (fn [(acc (List String)) (o (Pair String s/KnowOutcome))] -> (List String)
                       (listAppend acc (map (fn [(l String)] -> String (w/wireReceipt! wsRec l (> (pairSecond o).errCount 0) (pairFirst o))) (pairSecond o).lines)))
                     (list) outs))
        (errs (listSum (map (fn [(o (Pair String s/KnowOutcome))] -> Int64 (pairSecond o).errCount) outs)))]
    (pair (if (= (listLength wired) 1) (optionOr (listHead wired) "") (str "(:batch " (stringJoin wired " ") ")")) (if (> errs 0) 1 0)))

fn walkFiles! dir: String rel: String acc: (List String) -> (List String)
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (fold (fn [(a (List String)) (nm String)] -> (List String)
              (let [(p (k/joinPath dir nm)) (r (if (stringEmpty? rel) nm (str rel "/" nm)))]
                (cond
                  ((= nm ".git") a)
                  ((k/isDir! p) (walkFiles! p r a))
                  (else (cons r a)))))
            acc (listSort names))))

fn ledgerState! ws: String -> (Pair String String)
  (pair (resultOr (fileReadString (k/joinPath ws ".asl/mem/notes.asn")) "")
        (stringJoin (listSort (walkFiles! ws "" (list))) "|"))

fn maskDigitsAfter s: String key: String -> String
  (let [(parts (stringSplit s key))]
    (stringJoin (cons (optionOr (listHead parts) "") (map (fn [(p String)] -> String (str "T" (dropDigits p))) (optionOr (listTail parts) (list)))) key))

fn dropDigits p: String -> String
  (if (and (not (stringEmpty? p)) (let [(c (charCode (k/charAt p 0)))] (and (>= c 48) (<= c 57)))) (dropDigits (optionOr (stringSlice p 1 (stringLength p)) "")) p)

fn removeTree! p: String -> Bool
  (cond
    ((not (or (fileExists? p) (k/isDir! p))) true)
    ((and (k/isDir! p) (k/realChild? (k/dirName p) (k/baseName p)))
      (and (mt (dirList p) ((ok names) (listAll? (fn [(nm String)] -> Bool (removeTree! (k/joinPath p nm))) names)) ((err _) false))
           (ok? (pathRemove p))))
    (else (ok? (pathRemove p))))

fn around s: String at: Int64 -> String
  (optionOr (stringSlice s (max 0 (- at 50)) (min (stringLength s) (+ at 70))) "")

fn firstDiff a: String b: String i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (!= (stringSlice a i (+ i 1)) (stringSlice b i (+ i 1)))) i (firstDiff a b (+ i 1) n))

fn checkCase! repo: String base: String files: (List FileSpec) today: String c: CaseSpec tally: Tally -> Tally
  (let [(dirs (prepareCase! repo base files c))
        (got (if (stringEmpty? dirs.dir) (pair "(:prepareFailed)" -1) (runForm! dirs c.form)))
        (state (ledgerState! dirs.ws))
        (norm (fn [(x String)] -> String (let [(m (maskDigitsAfter x ":timestamp "))] (if (= c.mask "date") (maskRecordedDate m) m))))
        (sameOut (and (= (pairFirst got) c.stdout) (= (pairSecond got) c.exit)))
        (dateOk (or (!= c.mask "date") (stringContains? (pairFirst state) (str ":date \"" today "\""))))
        (sameLedger (or (not c.wantLedger) (and dateOk (= (norm (pairFirst state)) (norm c.ledger)) (= (pairSecond state) c.files))))
        (at (firstDiff c.stdout (pairFirst got) 0 (max (stringLength c.stdout) (stringLength (pairFirst got)))))]
    (do
      (if (and sameOut sameLedger)
        (print "")
        (println (str "(:knowDiff :case " (stringFromInt64 c.id) " :form " (s/quoted c.form) " :exit " (stringFromInt64 c.exit) " :got " (stringFromInt64 (pairSecond got))
                      " :byte " (stringFromInt64 at) " :want " (s/quoted (around c.stdout at)) " :have " (s/quoted (around (pairFirst got) at))
                      (if sameLedger "" (str " :ledgerWant " (s/quoted c.ledger) " :ledgerHave " (s/quoted (pairFirst state)) " :filesWant " (s/quoted c.files) " :filesHave " (s/quoted (pairSecond state)))) ")")))
      (Tally :cases (+ tally.cases 1) :failures (+ tally.failures (if (and sameOut sameLedger) 0 1)))))

fn maskRecordedDate s: String -> String
  (let [(marker ":author \"agent\"\n      :date \"")
        (at (k/findFrom s (stringToBytes s) marker (maxNoteAt s marker)))]
    (if (< at 0) s (str (optionOr (stringSlice s 0 (+ at (stringLength marker))) "") "D" (optionOr (stringSlice s (+ at (stringLength marker) 10) (stringLength s)) ""))))

fn maxNoteAt s: String marker: String -> Int64
  (lastFind s (stringToBytes s) marker 0 -1)

fn lastFind s: String b: Bytes marker: String from: Int64 best: Int64 -> Int64
  (let [(at (k/findFrom s b marker from))] (if (< at 0) (max best 0) (lastFind s b marker (+ at 1) at)))

fn ! runTests -> Bool
  (let [(repo (resultOr (realPath ".") "."))]
    (mt (currentHost! repo)
      ((none) false)
      ((some _)
       (let [(text (resultOr (fileReadString (k/joinPath repo "asl/packages/asl-forms/tests/fixtures/recorded/know.asn")) ""))
        (files (parseFiles text))
        (registries (filter (fn [(f FileSpec)] -> Bool (and (= f.tree "tc1") (listContains? (list "asl/grammar/tools.asn" "asl/prelude/prelude.asn") f.path))) files))
        (cases (parseCases text))
        (base (k/joinPath (optionOr (envGet "TMPDIR") "/tmp") (str "knowParity" (stringFromInt64 (procSelf)))))
        (probeWs (str base "Observe"))
        (probeReady (dirCreate probeWs))
        (probeGit (cp/exec! (cp/withCwd (cp/cmd "git" (list "init" "-q")) probeWs)))
        (today (s/localDate! (/ (nowNs) 1000000000)))
        (execFailure (s/observeResult 94 3 "observe: garbage" ""))
        (plainFailure (s/observeResult 95 4 "plain stdout only" ""))
        (emptyFailure (s/observeResult 96 0 "" ""))
        (receiptNoStatus (s/observeResult 97 0 "(:observe :dim nostatus)" ""))
        (observeProbe (s/observeStep! (s/KnowCtx :ws probeWs :toolRoot repo :binDir "" :vfsDir "" :toolsFile "" :home "") 98 (mapEmpty) (list "tokenCost") (list)))
        (tally (fold (fn [(tl Tally) (c CaseSpec)] -> Tally (checkCase! repo base files today c tl)) (Tally :cases 0 :failures 0) cases))
        (cleaned (and (removeTree! base) (removeTree! probeWs)))]
    (println (str "(:knowParity :cases " (stringFromInt64 tally.cases) " :failures " (stringFromInt64 tally.failures) " :files " (stringFromInt64 (listLength files)) ")"))
    (assert (>= (listLength cases) 90) "the know shard holds at least 90 recorded cases")
    (assert (>= (listLength files) 35) "the know shard embeds its workspace and toolchain trees")
    (assert (and (= (listLength registries) 2) (listAll? (fn [(f FileSpec)] -> Bool (> (stringLength f.body) 10000)) registries)) "tc1 includes both source registries, not empty placeholders")
    (assert (= tally.cases (listLength cases)) "every recorded case ran")
    (assert (= tally.failures 0) "every case gives the recorded stdout, exit code and ledger")
    (assert (and (= execFailure.errCount 1) (stringContains? (optionOr (listHead execFailure.lines) "") "exitCode 3") (stringContains? (optionOr (listHead execFailure.lines) "") "observe: garbage")) "non-zero observe execution failure is rejected with its message")
    (assert (and (= plainFailure.errCount 1) (stringContains? (optionOr (listHead plainFailure.lines) "") "exitCode 4") (stringContains? (optionOr (listHead plainFailure.lines) "") "plain stdout only")) "plain stdout without a receipt is rejected")
    (assert (and (= emptyFailure.errCount 1) (stringContains? (optionOr (listHead emptyFailure.lines) "") "exitCode 0") (stringContains? (optionOr (listHead emptyFailure.lines) "") "observe produced no receipt")) "empty successful subprocess output is rejected")
    (assert (and (= receiptNoStatus.errCount 0) (stringContains? (optionOr (listHead receiptNoStatus.lines) "") ":dim nostatus")) "a valid observe receipt without status is accepted")
    (assert (and (= observeProbe.errCount 0) (stringContains? (optionOr (listHead observeProbe.lines) "") ":dim tokenCost")) (str "observe dispatch reaches tokenCost with its configured tool root: " (optionOr (listHead observeProbe.lines) "none")))
    (assert cleaned "the case directories are removed")
    (assert (= (s/localDateAt! (some "Europe/Kiev") 1782941400) "2026-07-02") "local date follows the zone offset (python zoneinfo, 2026-09-27)")
    (assert (= (s/localDateAt! (some "America/New_York") 1773540000) "2026-03-14") "local date before a DST switch")
    (assert (= (s/localDateAt! (some "America/New_York") 2240000000) "2040-12-24") "local date past the TZif table uses the footer rule")
    (assert (= (s/localDateAt! (some "EST5EDT,M3.2.0,M11.1.0") 1782941400) "2026-07-01") "a POSIX TZ string is evaluated")
    (assert (= (s/localDateAt! (some "") 1782941400) "2026-07-01") "an empty TZ is UTC")
    (assert (= (s/localDateAt! (some "America/Sao_Paulo") 0) "1969-12-31") "a negative local time keeps its day (python time.localtime)")
    (assert (= (s/localDateAt! (some "Asia/Kolkata") -315619200) "1960-01-01") "a pre-1970 half-hour zone keeps its day (python time.localtime)")
    true))))
