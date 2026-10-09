(module aslHarnessTests/benchTest
  :x [runTests]
  :i [(aslHarness/bench :a b)
      (aslHarness/chatBench :a cb)])

fn testLoadTasks! -> Bool
  (let [(loaded (b/loadTasks! "tests/harnessBench/cases"))]
    (mt loaded
      ((err e) (do (assert false "loadTasks parses task ASN fixtures") true))
      ((ok tasks)
        (let [(matches (filter (fn [(task b/Task)] -> Bool (= task.id "fund-spec-coverage")) tasks))
              (scoutMatches (filter (fn [(task b/Task)] -> Bool (= task.id "scout-off-by-one")) tasks))
              (distillMatches (filter (fn [(task b/Task)] -> Bool (= task.id "distill-research")) tasks))]
          (mt (listHead matches)
            ((none) (do (assert false "fund-spec-coverage task is present") true))
            ((some task)
              (let [(distillTask (optionOr (listHead distillMatches) task))
                    (idSpec (optionOr task.check.idSet (b/IdSetSpec :ids (list) :done (list))))]
                (do
                  (assert (stringContains? task.prompt "requirements in SPEC.md") "task prompt parsed")
                  (assert (= task.mode "scout") "read-only mode derives from check")
                  (assert (some? task.observe) "observe form parsed")
                  (assert (= (listLength idSpec.done) 3) "idSet done values parsed")
                  (assert (and (some? (listHead scoutMatches)) (= (optionOr (listHead scoutMatches) task).mode "scout")) "scout directory mode derives from case name")
                  (assert (> (listLength distillTask.check.preserve) 0) "preserve requirements are parsed")
                  (assert (= (listLength distillTask.check.conflicts) 1) "conflict requirements are parsed")
                  true))))))))

fn testLoadForbid -> Bool
  (let [(okRes (b/loadForbid (list "needle1" "needle2")))
        (emptyRes (b/loadForbid (list)))
        (blankRes (b/loadForbid (list "valid" "")))]
    (do
      (assert (ok? okRes) "valid forbid list passes")
      (assert (err? emptyRes) "empty forbid list returns err")
      (assert (err? blankRes) "forbid list with blank item returns err")
      true))

fn testLoadAnswerInt -> Bool
  (let [(validSpec (b/loadAnswerInt 4 "function" (list 2 5 6 7)))
        (emptyNoun (b/loadAnswerInt 4 "" (list 2 5 6 7)))
        (selfForbid (b/loadAnswerInt 4 "function" (list 2 4 6 7)))]
    (do
      (assert (ok? validSpec) "valid answerInt spec passes")
      (assert (= (resultOr validSpec (b/AnswerIntSpec :value 0 :noun "" :forbid (list))).value 4) "value matches 4")
      (assert (err? emptyNoun) "empty noun returns err")
      (assert (err? selfForbid) "forbid holding target value returns err")
      true))

fn testLoadFileLineSet -> Bool
  (let [(p1 (b/FileLinePair :path "src/export.py" :line 6))
        (p2 (b/FileLinePair :path "src/lockfile.py" :line 8))
        (pBad (b/FileLinePair :path "src/bad.py" :line 0))
        (okRes (b/loadFileLineSet (list p1 p2)))
        (emptyRes (b/loadFileLineSet (list)))
        (badRes (b/loadFileLineSet (list p1 pBad)))]
    (do
      (assert (ok? okRes) "valid file line set passes")
      (assert (err? emptyRes) "empty file line set returns err")
      (assert (err? badRes) "line 0 returns err")
      true))

fn testLoadFileLineAlt -> Bool
  (let [(a1 (b/FileLineAltSpec :path "kiosk/app/invoices.asl" :line 8 :alts (list 7)))
        (okRes (b/loadFileLineAlt (list a1)))
        (emptyRes (b/loadFileLineAlt (list)))]
    (do
      (assert (ok? okRes) "valid file line alt passes")
      (assert (err? emptyRes) "empty file line alt returns err")
      true))

fn testLoadQuoteExists -> Bool
  (let [(okRes (b/loadQuoteExists "src/config.py" "return dict(DEFAULTS, source=\"defaults\")" "return"))
        (noMarkerRes (b/loadQuoteExists "src/config.py" "return dict(DEFAULTS)" "missingMarker"))
        (emptyFileRes (b/loadQuoteExists "" "line text" "marker"))]
    (do
      (assert (ok? okRes) "valid quote exists passes")
      (assert (err? noMarkerRes) "marker not in line returns err")
      (assert (err? emptyFileRes) "empty file returns err")
      true))

fn testLoadIdSet -> Bool
  (let [(ids (list "R1" "R2" "R3"))
        (done (list "R1" "R3"))
        (badDone (list "R1" "R99"))
        (okRes (b/loadIdSet ids done))
        (badRes (b/loadIdSet ids badDone))
        (emptyRes (b/loadIdSet (list) (list)))]
    (do
      (assert (ok? okRes) "valid idSet passes")
      (assert (err? badRes) "unknown done ID returns err")
      (assert (err? emptyRes) "empty ids returns err")
      true))

fn testLoadTrueAndSourcesAndRatio -> Bool
  (let [(tOk (b/loadTrue true))
        (tErr (b/loadTrue false))
        (sOk (b/loadSources (list "services/core.yaml" "services/edge.yaml")))
        (sErrAbs (b/loadSources (list "/etc/passwd")))
        (sErrEmpty (b/loadSources (list)))
        (rOk (b/loadMaxRatio 0.4))
        (rErr0 (b/loadMaxRatio 0.0))
        (rErrHigh (b/loadMaxRatio 1.5))
        (nOk (b/loadNoNewFacts true))
        (nErr (b/loadNoNewFacts false))]
    (do
      (assert (ok? tOk) "loadTrue true passes")
      (assert (err? tErr) "loadTrue false returns err")
      (assert (ok? sOk) "relative sources pass")
      (assert (err? sErrAbs) "absolute sources return err")
      (assert (err? sErrEmpty) "empty sources return err")
      (assert (ok? rOk) "ratio 0.4 passes")
      (assert (err? rErr0) "ratio 0.0 returns err")
      (assert (err? rErrHigh) "ratio 1.5 returns err")
      (assert (ok? nOk) "loadNoNewFacts true passes")
      (assert (err? nErr) "loadNoNewFacts false returns err")
      true))

fn testLoadPreserveAndConflicts -> Bool
  (let [(pf (b/PreserveFact :id "F1" :tokens (list (list "tok1"))))
        (pOk (b/loadPreserve (list pf)))
        (pErr (b/loadPreserve (list)))
        (cs (b/ConflictSide :values (list "v1") :sources (list "s1")))
        (cr (b/ConflictRow :id "C1" :sides (list cs)))
        (cOk (b/loadConflicts (list cr)))
        (cErr (b/loadConflicts (list)))]
    (do
      (assert (ok? pOk) "valid preserve facts pass")
      (assert (err? pErr) "empty preserve facts return err")
      (assert (ok? cOk) "valid conflicts pass")
      (assert (err? cErr) "empty conflicts return err")
      true))

fn testJudgeGate! -> Bool
  (let [(passRes (b/judgeGate "true" "." "/tmp"))
        (failRes (b/judgeGate "exit 1" "." "/tmp"))]
    (do
      (assert (listEmpty? passRes) "true exit 0 passes gate")
      (assert (= (listLength failRes) 1) "exit 1 reports one failure")
      (assert (= (optionOr (listHead failRes) "") "gate exit 1") "failure message is gate exit 1")
      true))

fn testJudgeMentions -> Bool
  (let [(needles (list (list "bus.py") (list "make_queue") (list "mutable default" "default argument")))
        (replyPass "In bus.py, make_queue uses a mutable default handlers=[] list.")
        (replyFail "In bus.py, make_queue has a bug.")
        (passRes (b/judgeMentions needles replyPass))
        (failRes (b/judgeMentions needles replyFail))]
    (do
      (assert (listEmpty? passRes) "all needles mentioned passes")
      (assert (= (listLength failRes) 1) "missing needle reports failure")
      (assert (stringContains? (optionOr (listHead failRes) "") "missing mention") "failure message format matches")
      true))

fn testJudgeAnswerInt -> Bool
  (let [(spec (b/AnswerIntSpec :value 4 :noun "function" :forbid (list 2 5 6 7)))
        (replyPass "There are 4 unused functions in src/.")
        (replyFail "There are 5 unused functions in src/.")
        (substringFail (b/judgeAnswerInt spec "14 functions are defined here."))
        (nounFail (b/judgeAnswerInt spec "There are 4 lines in this file."))
        (forbidFail (b/judgeAnswerInt spec "There are 5 functions."))
        (decoyFail (b/judgeAnswerInt spec "There are 4 files and 3 functions."))
        (unrelatedForbid (b/judgeAnswerInt spec "There are 5 lines and 4 functions."))
        (targetWithForbidden (b/judgeAnswerInt spec "There are 4 functions and also 5 functions."))
        (passRes (b/judgeAnswerInt spec replyPass))
        (failRes (b/judgeAnswerInt spec replyFail))]
    (do
      (assert (listEmpty? passRes) "reply with 4 passes")
      (assert (= (listLength failRes) 1) "reply without 4 reports failure")
      (assert (= (listLength substringFail) 1) "substring 14 is not the count 4")
      (assert (= (listLength nounFail) 1) "count must be attached to noun")
      (assert (= (listLength forbidFail) 1) "forbidden count must be rejected")
      (assert (= (listLength targetWithForbidden) 1) "forbidden count must be rejected even when the target is also present")
      (assert (= (listLength decoyFail) 1) "unrelated target number does not satisfy count noun")
      (assert (listEmpty? unrelatedForbid) "forbidden count unrelated to noun does not reject")
      true))

fn testJudgeQuoteExists! -> Bool
  (let [(spec (b/QuoteExistsSpec :file "src/config.py" :line "return dict(DEFAULTS, source=\"defaults\")" :marker "return"))
        (replyPass "The code does `return dict(DEFAULTS, source=\"defaults\")`")
        (replyFail "The code yields the defaults directly.")
        (fabricated "A separate helper uses return; parse_config returns None.")
        (unquoted (b/judgeQuoteExists! spec "tests/harnessBench/cases/honest-quote" "The source line is return dict(DEFAULTS, source=\"defaults\")"))
        (passRes (b/judgeQuoteExists! spec "tests/harnessBench/cases/honest-quote" replyPass))
        (failRes (b/judgeQuoteExists! spec "tests/harnessBench/cases/honest-quote" replyFail))
        (fabricatedRes (b/judgeQuoteExists! spec "tests/harnessBench/cases/honest-quote" fabricated))
        (wrongFileSpec (b/QuoteExistsSpec :file "src/missing.py" :line "return dict(DEFAULTS, source=\"defaults\")" :marker "return"))
        (wrongFileRes (b/judgeQuoteExists! wrongFileSpec "tests/harnessBench/cases/honest-quote" replyPass))]
    (do
      (assert (listEmpty? passRes) "reply with marker passes")
      (assert (= (listLength failRes) 1) "reply missing marker reports failure")
      (assert (stringContains? (optionOr (listHead failRes) "") "quote missing") "quote error format")
      (assert (= (listLength fabricatedRes) 1) "marker elsewhere does not satisfy exact quote")
      (assert (= (listLength unquoted) 1) "unquoted source text is not a verbatim quote")
      (assert (= (listLength wrongFileRes) 1) "quote must come from declared source file")
      true))

fn testJudgeIdSet -> Bool
  (let [(spec (b/IdSetSpec :ids (list "R1" "R2" "R3") :done (list "R1" "R3")))
        (replyPass "Checked R1: pass, R3: pass, R2: skipped.")
        (replyFail "Checked R1: pass, all other requirements untested.")
        (passRes (b/judgeIdSet spec replyPass))
        (failRes (b/judgeIdSet spec replyFail))]
    (do
      (assert (listEmpty? passRes) "reply mentioning both done ids passes")
      (assert (= (listLength failRes) 1) "reply missing R3 reports missing R3")
      (assert (= (optionOr (listHead failRes) "") "idSet missing R3") "missing ID reported exactly")
      true))

fn testJudgeFileLineAlt -> Bool
  (let [(w1 (b/FileLinePair :path "kiosk/app/invoices.asl" :line 8))
        (w2 (b/FileLinePair :path "kiosk/app/payouts.asl" :line 8))
        (a1 (b/FileLineAltSpec :path "kiosk/app/invoices.asl" :line 8 :alts (list 7)))
        (aBad (b/FileLineAltSpec :path "kiosk/app/missing.asl" :line 99 :alts (list 1)))
        (passRes (b/judgeFileLineAlt (list a1) (list (b/FileLinePair :path "kiosk/app/invoices.asl" :line 7))))
        (badAltRes (b/judgeFileLineAlt (list a1) (list (b/FileLinePair :path "kiosk/app/invoices.asl" :line 6))))
        (replyPass (b/judgeFileLineReply (list w1) (list a1) "kiosk/app/invoices.asl:7"))
        (replyFail (b/judgeFileLineReply (list w1) (list a1) "kiosk/app/invoices.asl:6"))
        (replyLongLine (b/judgeFileLineReply (list w1) (list a1) "kiosk/app/invoices.asl:70"))
        (failRes (b/judgeFileLineAlt (list aBad) (list w1 w2)))]
    (do
      (assert (listEmpty? passRes) "declared alternative line matches")
      (assert (= (listLength badAltRes) 1) "undeclared alternative line fails")
      (assert (= (listLength failRes) 1) "alt not in want fails")
      (assert (stringContains? (optionOr (listHead failRes) "") "no allowed call line") "diagnostic format")
      (assert (listEmpty? replyPass) "actual reply citation accepts declared alternative")
      (assert (= (listLength replyFail) 1) "actual reply citation rejects undeclared line")
      (assert (= (listLength replyLongLine) 1) "line 70 does not satisfy line 7")
      true))

fn testFormatting -> Bool
  (let [(esc1 (b/formatAsnStr "simple string"))
        (esc2 (b/formatAsnStr "string\nwith\nnewlines"))
        (esc3 (b/formatAsnStr "string with \"quotes\" and \\backslash"))
        (linePass (b/formatRescoreLine "case-a" "client-x" "cond-y" "rep123" true ""))
        (lineFail (b/formatRescoreLine "case-a" "client-x" "cond-y" "rep123" false "error message"))
        (sumLine (b/formatRescoreSumLine "case-a" "client-x" "cond-y" 3 5))]
    (do
      (assert (= esc1 "\"simple string\"") "format simple string")
      (assert (= esc2 "\"string with newlines\"") "newlines converted to space")
      (assert (stringContains? esc3 (str "\\" "\"")) "quotes escaped")
      (assert (stringContains? esc3 "\\\\") "backslashes escaped")
      (assert (= linePass "(:rescore :case \"case-a\" :client \"client-x\" :condition \"cond-y\" :reply \"rep123\" :pass true)") "rescore pass format")
      (assert (= lineFail "(:rescore :case \"case-a\" :client \"client-x\" :condition \"cond-y\" :reply \"rep123\" :pass false :why \"error message\")") "rescore fail format")
      (assert (= sumLine "(:rescoreSum :case \"case-a\" :client \"client-x\" :condition \"cond-y\" :pass 3 :runs 5)") "rescore sum format")
      true))

fn testVerdict! -> Bool
  (let [(vFail (b/verdict "fund-readiness" "tests/harnessBench/cases/fund-readiness" "The readiness check reports pass."))
        (vErr (b/verdict "unknown-nonexistent-case" "." "reply"))]
    (do
      (assert (> (listLength vFail) 0) "fund-readiness on bad reply returns failures")
      (assert (= (listLength vErr) 1) "unknown case returns 1 error")
      (assert (= (optionOr (listHead vErr) "") "unknown case unknown-nonexistent-case") "unknown case is surfaced")
      true))

fn testChatBenchProvider -> Bool
  (let [(pGroq (cb/provider "groq/llama-3.3-70b-versatile"))
        (pGai (cb/provider "gai/gemini-2.5-flash"))
        (pOpen (cb/provider "anthropic/claude-3.5-sonnet"))]
    (do
      (assert (= pGroq.name "groq") "groq name matches")
      (assert (= pGroq.envVar "GROQ_API_KEY") "groq env var matches")
      (assert (= pGroq.modelId "llama-3.3-70b-versatile") "groq model id stripped")
      (assert (= pGai.name "gai") "gai name matches")
      (assert (= pGai.envVar "GEMINI_API_KEY") "gai env var matches")
      (assert (= pGai.modelId "gemini-2.5-flash") "gai model id stripped")
      (assert (= pOpen.name "openrouter") "openrouter default name")
      (assert (= pOpen.envVar "OPENROUTER_API_KEY") "openrouter env var matches")
      (assert (= pOpen.modelId "anthropic/claude-3.5-sonnet") "openrouter keeps full model")
      true))

fn testChatBenchCurlConfig -> Bool
  (let [(cfg (cb/curlConfig "https://api.groq.com/openai/v1/chat/completions" "test_key_123" "{\"model\":\"llama\"}" 240))]
    (do
      (assert (stringContains? cfg "url = \"https://api.groq.com/openai/v1/chat/completions\"") "curl url config")
      (assert (stringContains? cfg "header = \"Authorization: Bearer test_key_123\"") "curl auth header")
      (assert (stringContains? cfg "header = \"User-Agent: asl-chatBench/1\"") "curl user agent")
      (assert (stringContains? cfg "header = \"Content-Type: application/json\"") "curl content type")
      (assert (stringContains? cfg "max-time = \"240\"") "curl max time")
      (assert (stringContains? cfg "silent\nshow-error") "curl silent and show-error")
      true))

fn testChatBenchSystemFor! -> Bool
  (let [(sNone (cb/systemFor "none" "scout"))
        (sCore (cb/systemFor "core" "scout"))
        (unsupported (cb/systemFor "unknown" "scout"))
        (corePrompt (resultOr sCore ""))]
    (do
      (assert (= (resultOr sNone "nonempty") "") "system prompt for none is empty")
      (assert (> (stringLength corePrompt) 0) "system prompt for core is non-empty")
      (assert (stringContains? corePrompt "tools") "system prompt contains ASL instructions")
      (assert (mt unsupported ((err message) true) ((ok prompt) false)) "unsupported system condition returns an error")
      true))

fn repeatParts n: Int64 part: String acc: (List String) -> (List String)
  (if (<= n 0) acc (repeatParts (- n 1) part (cons part acc)))

fn testChatBenchCurlStdin! -> Bool
  (let [(base (str "/tmp/aslChatBenchCurl." (stringFromInt64 (procSelf))))
        (script (str base ".sh"))
        (failScript (str base ".fail.sh"))
        (inputPath (str base ".stdin"))
        (argvPath (str base ".argv"))
        (largeConfig (cb/curlConfig "https://example.invalid/chat" "large_secret_key" (str "{\"body\":\"" (stringJoin (repeatParts 1200 (stringRepeat "x" 1000) (list)) "") "\"}") 240))
        (source (str "#!/bin/sh\nprintf '%s\\n' \"$@\" > " argvPath "\ncat > " inputPath "\nawk 'BEGIN { for (i=0; i<70000; i++) printf \"x\" }'\n"))
        (failSource "#!/bin/sh\ncat >/dev/null\nprintf 'bad' >&2\nexit 22\n")
        (written (fileWrite script source))
        (failWritten (fileWrite failScript failSource))
        (chmod (processRun (str "chmod +x " script " " failScript)))
        (response (cb/curlRequestWith largeConfig script))
        (failedResponse (cb/curlRequestWith largeConfig failScript))
        (captured (resultOr (fileReadString inputPath) ""))
        (args (resultOr (fileReadString argvPath) ""))
        (removed1 (pathRemove script))
        (removed2 (pathRemove failScript))
        (removed3 (pathRemove inputPath))
        (removed4 (pathRemove argvPath))]
    (do
      (assert (ok? written) "curl fake executable is written")
      (assert (ok? failWritten) "curl failing executable is written")
      (assert (= chmod.exitCode 0) "curl fake executables are runnable")
      (assert (> (stringLength largeConfig) 131072) "curl request exceeds Linux per-argument limit")
      (assert (ok? response) "curl request returns a response larger than the pipe buffer")
      (assert (= (stringLength (resultOr response "")) 70000) "curl response is read through EOF without truncation")
      (assert (err? failedResponse) "curl non-zero exit remains an error")
      (assert (mt failedResponse ((err e) (stringContains? e "bad")) ((ok _) false)) "curl non-zero exit preserves stderr")
      (assert (= captured largeConfig) "curl stdin receives the exact config bytes")
      (assert (not (stringContains? args "large_secret_key")) "curl argv excludes the API key")
      (assert (stringContains? args "--config\n-\n") "curl argv requests config from stdin")
      (assert (stringContains? args "--fail") "curl argv preserves HTTP failure handling")
      (assert (and (ok? removed1) (and (ok? removed2) (and (ok? removed3) (ok? removed4)))) "curl probe files are removed")
      true))

fn testChatBenchPartialWrite! -> Bool
  (let [(data (stringJoin (repeatParts 40 "0123456789" (list)) ""))
        (spawned (procSpawnv (list "/bin/cat") (none) (none)))]
    (mt spawned
      ((err e) (do (assert false (str "cat spawns: " e)) false))
      ((ok sp)
        (let [(short (fn [(fd Int64) (text String)] -> (Result Int64 String) (fdWrite fd (optionOr (stringSlice text 0 (min 3 (stringLength text))) ""))))
              (sent (cb/curlWriteAllWith short sp.stdin data))
              (closed (fdClose sp.stdin))
              (echoed (cb/curlCollect sp.pid sp.stdout sp.stderr))]
          (do
            (assert (ok? sent) "short writes complete")
            (assert (ok? closed) "cat stdin closes")
            (assert (= (resultOr echoed "") data) "every byte arrives through 3-byte writes")
            true)))))

fn openFdCount! -> Int64
  (let [(res (processRun (str "lsof -p " (stringFromInt64 (procSelf)) " | wc -l")))]
    (optionOr (stringToInt64 (stringTrim res.stdout)) -1))

fn testChatBenchStdinFailureClosesPipes! -> Bool
  (let [(script (str "/tmp/aslChatBenchNoStdin." (stringFromInt64 (procSelf)) ".sh"))
        (written (fileWrite script "#!/bin/sh\nexec 0<&-\nsleep 1\n"))
        (chmod (processRun (str "chmod +x " script)))
        (config (stringRepeat "x" 200000))
        (before (openFdCount!))
        (r1 (cb/curlRequestWith config script))
        (r2 (cb/curlRequestWith config script))
        (r3 (cb/curlRequestWith config script))
        (after (openFdCount!))
        (removed (pathRemove script))]
    (do
      (assert (and (ok? written) (= chmod.exitCode 0)) "stdin-closing fake curl is runnable")
      (assert (and (err? r1) (and (err? r2) (err? r3))) "a failed stdin write is an error")
      (assert (> before 0) "open descriptors are counted")
      (assert (= after before) (str "no pipe leaks after three stdin failures: " (stringFromInt64 before) " -> " (stringFromInt64 after)))
      (assert (ok? removed) "stdin-closing fake curl is removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testLoadTasks!) "testLoadTasks must pass")
    (assert (testLoadForbid) "testLoadForbid must pass")
    (assert (testLoadAnswerInt) "testLoadAnswerInt must pass")
    (assert (testLoadFileLineSet) "testLoadFileLineSet must pass")
    (assert (testLoadFileLineAlt) "testLoadFileLineAlt must pass")
    (assert (testLoadQuoteExists) "testLoadQuoteExists must pass")
    (assert (testLoadIdSet) "testLoadIdSet must pass")
    (assert (testLoadTrueAndSourcesAndRatio) "testLoadTrueAndSourcesAndRatio must pass")
    (assert (testLoadPreserveAndConflicts) "testLoadPreserveAndConflicts must pass")
    (assert (testJudgeGate!) "testJudgeGate must pass")
    (assert (testJudgeMentions) "testJudgeMentions must pass")
    (assert (testJudgeAnswerInt) "testJudgeAnswerInt must pass")
    (assert (testJudgeQuoteExists!) "testJudgeQuoteExists must pass")
    (assert (testJudgeIdSet) "testJudgeIdSet must pass")
    (assert (testJudgeFileLineAlt) "testJudgeFileLineAlt must pass")
    (assert (testFormatting) "testFormatting must pass")
    (assert (testVerdict!) "testVerdict must pass")
    (assert (testChatBenchProvider) "testChatBenchProvider must pass")
    (assert (testChatBenchCurlConfig) "testChatBenchCurlConfig must pass")
    (assert (testChatBenchCurlStdin!) "testChatBenchCurlStdin must pass")
    (assert (testChatBenchSystemFor!) "testChatBenchSystemFor! must pass")
    (assert (testChatBenchPartialWrite!) "testChatBenchPartialWrite must pass")
    (assert (testChatBenchStdinFailureClosesPipes!) "testChatBenchStdinFailureClosesPipes must pass")
      true)
