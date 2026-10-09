(module asl-forms/tests/opsTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/ops :a ops) (asl-forms/delegate :a d) (asl-forms/gate :a g)])

fn wsRoot! -> String
  (resultOr (realPath "asl/packages/asl-forms/tests/fixtures/ws") "")

fn run! form: String -> ops/StepOutcome
  (ops/runStep! (wsRoot!) 1 form)

fn line! form: String -> String
  (optionOr (listHead (run! form).lines) "")

fn gatewayRun! form: String -> g/RunOut
  (let [(root (resultOr (realPath ".") "."))
        (host (k/joinPath root "asl/host/out/asl-host"))
        (mainPath (k/joinPath root "asl/packages/asl-forms/src/main.asl"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) "ASL_GATEWAY_PORT=1"))]
    (g/runArgv! (list host "run" mainPath form) (some root) (some env) 10000 0))

fn gatewayReplyRun! form: String reply: String -> g/RunOut
  (let [(root (resultOr (realPath ".") "."))
        (host (k/joinPath root "asl/host/out/asl-host"))
        (mainPath (k/joinPath root "asl/packages/asl-forms/src/main.asl"))
        (tmp (str (optionOr (envGet "TMPDIR") "/tmp/") "aslGatewayReply_" (stringFromInt64 (mod (nowNs) 1000000))))
        (bin (k/joinPath tmp "bin"))
        (curl (k/joinPath bin "curl"))
        (made (dirCreate bin))
        (written (fileWrite curl "#!/bin/sh\nprintf '%s\\n' \"$ASL_TEST_GATEWAY_REPLY\"\n"))
        (chmod (g/runArgv! (list "chmod" "+x" curl) (none) (none) 5000 0))
        (env (list (str "PATH=" bin ":" (optionOr (envGet "PATH") ""))
                   "ASL_GATEWAY_PORT=1"
                   (str "ASL_TEST_GATEWAY_REPLY=" reply)))
        (result (g/runArgv! (list host "run" mainPath form) (some root) (some env) 10000 0))
        (clean (g/runArgv! (list "rm" "-rf" tmp) (none) (none) 5000 0))]
    result)

fn testTree! -> Bool
  (let [(l (line! "(:tree)"))]
    (assert (stringContains? l ":path \".\" :totalFiles 15 :totalDirs 5 :depth 3") "every level counted, the directory symlink counted and not entered")
    (assert (stringContains? l "\"sub/deep/dup.txt\")") "entries stop at depth three")
    (assert (= (run! "(:tree :path \"../..\")").errCount 1) "a tree outside the root is refused")
    true)

fn testReadPaging! -> Bool
  (do
    (assert (stringContains? (line! "(:read :file \"unicode.md\" :maxBytes 256)") ":truncated true :limit 200 :maxBytes 256 :totalLines 4 :more (:start 3 :end 4)") ":maxBytes counts characters, not bytes")
    (assert (stringContains? (line! "(:read :file \"long.txt\" :limit \" 1_0\" :start 3)") ":start 3 :end 250 :truncated true :limit 10 :maxBytes 12000 :totalLines 248 :more (:start 13 :end 250)") ":limit parses as Python int")
    (assert (stringContains? (line! "(:read :file \"long.txt\" :start 20 :end 10)") ":error-code \":ERR_RANGE_OUT_OF_BOUNDS\" :file \"long.txt\" :start 20 :end 10 :lines 250") "an inverted range is out of bounds")
    true)

fn testReadLines! -> Bool
  (do
    (assert (stringContains? (line! "(:read :file \"crlf.txt\")") ":content \"one\\ntwo\\nthree\\n\"") "CRLF reads as LF")
    (assert (stringContains? (line! "(:read :file \"seps.txt\" :start 2 :end 3)") ":content \"b\x0bc \"") "vertical tab and line separator split lines")
    (assert (= (ops/splitLinesKeepEnds "a\x0cb\x0bc d\ne\r\nf") (list "a\x0c" "b\x0b" "c " "d\n" "e\r\n" "f")) "str.splitlines(keepends=True)")
    true)

fn ported? line: String -> Bool
  (not (stringContains? line "ERR_NOT_PORTED"))

fn testFallbacks! -> Bool
  (do
    (assert (= (line! "(:write)") "  (:step :id 1 :op \"write\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing file argument\")") "write emits the exact missing-path rejection")
    (assert (stringContains? (line! "(:read :file \"escape/../../../../../../scripts/observe.py\" :symbol \"x\")") "ERR_BOUNDARY_VIOLATION") "the path guard runs before any fallback")
    (assert (stringContains? (line! "(:job :status)") ":subop \"status\"") "a bare :status flag names the job subop")
    (assert (= (ops/pyInt " 1_000 ") (some 1000)) "int() accepts spaces and digit underscores")
    (assert (= (ops/pyInt "1__0") (none)) "int() refuses a double underscore")
    true)


fn testTarget! -> Bool
  (do
    (assert (stringContains? (line! "(:target)") "ERR_NOT_IMPLEMENTED") "target listing refuses an unverified registry")
    (assert (stringContains? (line! "(:target :name \"distrib\")") "ERR_NOT_IMPLEMENTED") "distribution refuses to claim generation without running its generator")
    (assert (stringContains? (line! "(:codegen :name \"sh\" :file \"missing-file.asl\")") "ERR_NOT_IMPLEMENTED") "codegen refuses to claim compilation without a compiler")
    (assert (stringContains? (line! "(:target :name \"bogus\")") ":error-code \":ERR_UNKNOWN_TARGET\" :message \"Unknown compilation target: bogus\"") "unknown target rejected")
    true)

fn testBrowserSession! -> Bool
  (do
    (assert (stringContains? (line! "(:browserSession :action \"bad act\")") ":error-code \":ERR_INVALID_ARG\" :message \"Fields must be identifiers: action\"") "bad action identifier rejected")
    (assert (stringContains? (line! "(:browserSession :action :step :mode \"bad mode!\")") ":error-code \":ERR_INVALID_ARG\" :message \"Fields must be identifiers: mode\"") "bad mode identifier rejected")
    true)

fn testBrowserGatewayFailure! -> Bool
  (do
    (assert (= (gatewayRun! "(:browserSession :action :spawn)").code 1) "gateway spawn failure exits nonzero against the selected closed port")
    (assert (= (gatewayRun! "(:browserSession :action :step)").code 1) "gateway step failure exits nonzero against the selected closed port")
    (assert (= (gatewayRun! "(:browserSession :action :snapshot)").code 1) "gateway snapshot failure exits nonzero against the selected closed port")
    (assert (= (gatewayRun! "(:browserSession :action :close)").code 1) "gateway close failure exits nonzero against the selected closed port")
    (assert (= (gatewayRun! "(:browserSession :action :list)").code 1) "gateway list failure exits nonzero against the selected closed port")
    (assert (stringContains? (gatewayRun! "(:browserSession :action :spawn)").out "ERR_GATEWAY_FAILED") "gateway failure has an explicit transport error")
    true)

fn testBrowserGatewayReplies! -> Bool
  (let [(spawn (gatewayReplyRun! "(:browserSession :action :spawn)" "(:status :ok :sessionId \"s1\")"))
        (rejected (gatewayReplyRun! "(:browserSession :action :spawn)" "(:status :rejected :message \"denied\")"))
        (unconfirmed (gatewayReplyRun! "(:browserSession :action :spawn)" "(:message \"no status\")"))
        (missingSessions (gatewayReplyRun! "(:browserSession :action :list)" "(:status :ok :message \"empty\")"))
        (unsupportedIdentifier (gatewayReplyRun! "(:browserSession :action :bogus)" "(:status :ok)"))]
    (do
      (assert (= spawn.code 0) "successful gateway response exits zero")
      (assert (stringContains? spawn.out ":action \"spawn\" :receipt") "successful spawn response is emitted as a receipt")
      (assert (stringContains? spawn.out ":status :ok :sessionId \"s1\"") "successful gateway payload is preserved")
      (assert (= rejected.code 1) "gateway rejection exits nonzero")
      (assert (stringContains? rejected.out "ERR_GATEWAY_REJECTED") "gateway rejection remains explicit")
      (assert (= unconfirmed.code 1) "unconfirmed gateway response exits nonzero")
      (assert (stringContains? unconfirmed.out "ERR_GATEWAY_RESPONSE") "unconfirmed gateway response remains explicit")
      (assert (= missingSessions.code 1) "list response without browserSessions exits nonzero")
      (assert (stringContains? missingSessions.out "Gateway list response has no sessions field") "list response must include browserSessions")
      (assert (= unsupportedIdentifier.code 1) "identifier-shaped unsupported action exits nonzero")
      (assert (stringContains? unsupportedIdentifier.out "ERR_INVALID_ARG") "unsupported action is rejected before gateway dispatch")
      true))

fn workspaceLine! form: String -> String
  (let [(root (resultOr (realPath ".") ""))
        (out (ops/runStep! root 1 form))]
    (optionOr (listHead out.lines) ""))

fn externalRootRun! root: String form: String -> g/RunOut
  (let [(repo (resultOr (realPath ".") ""))
        (host (k/joinPath repo "asl/host/out/asl-host"))
        (mainPath (k/joinPath repo "asl/packages/asl-forms/src/main.asl"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ASL_VFS_DIR=" (k/joinPath root ".asl/vfs"))))]
    (g/runArgv! (list host "run" mainPath "--root" root form) (some repo) (some env) 10000 0))

fn unknownSymbolCheck! -> (Pair String Bool)
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp/") "aslOpsCheck_" (stringFromInt64 (mod (nowNs) 1000000))))
        (content "(module temp/bad :x [run])\nfn run -> Int64\n  (unknownValue)\n")
        (made (dirCreate (k/joinPath tmp ".asl/vfs")))
        (result (externalRootRun! tmp (str "(:write :file \"bad.asl\" :content \"" (k/escapeAsnVal content) "\")")))
        (clean (g/runArgv! (list "rm" "-rf" tmp) (none) (none) 5000 0))]
    (pair result.out (and (ok? made) (= clean.code 0) (not (fileExists? tmp)))))

fn testTxnRouter! -> Bool
  (let [(root (scratchDir! "aslFormsTxnRouter"))
        (vfs (k/joinPath root ".asl/vfs"))
        (file (k/joinPath root "a.txt"))
        (repo (resultOr (realPath ".") ""))
        (host (k/joinPath repo "asl/host/out/asl-host"))
        (mainPath (k/joinPath repo "asl/packages/asl-forms/src/main.asl"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ASL_VFS_DIR=" vfs)))
        (payload "(:txn :owns (\"a.txt\") (:edit :file \"a.txt\" :old \"hello\" :new \"world\"))")]
    (do
      (assert (ok? (dirCreate vfs)) "create isolated transaction vfs")
      (assert (ok? (fileWrite file "hello")) "seed transaction target")
      (let [(out (g/runArgv! (list host "run" mainPath "--root" root payload) (some repo) (some env) 30000 0))
            (content (resultOr (fileReadString file) ""))]
        (do
          (assert (and (= out.code 0) (stringContains? out.out ":status \"ok\"")) "txn nested edit completes through runStep router")
          (assert (= content "world") "txn flushes nested router edit to isolated workspace")
          (assert (ok? (pathRemove root)) "remove isolated transaction workspace")
          true))))

fn testRoutedOperations! -> Bool
  (let [(foreignTools (externalRootRun! (wsRoot!) "(:tools)"))
        (unknownCheck (unknownSymbolCheck!))]
    (do
      (assert (stringContains? (line! "(:q)") "ERR_MISSING_ARG") "q reaches F3 query validation")
      (assert (ported? (line! "(:q)")) "q does not fall through to an unported route")
      (assert (stringContains? (line! "(:test)") "ERR_MISSING_ARG") "test reaches F2 gate validation")
      (assert (stringContains? (workspaceLine! "(:note :action :list)") ":action \"list\" :status \"ok\"") "note list reaches its native ledger route")
      (assert (not (stringContains? foreignTools.out "ERR_REGISTRY_MISSING")) "foreign workspace tools use the toolchain registry")
      (assert (stringContains? foreignTools.out ":op :read") "foreign workspace tools return the actual operation registry")
      (assert (stringContains? (line! "(:reed :file \"x\")") "ERR_UNIMPLEMENTED") "unknown operations preserve the legacy unimplemented error without a not-ported router path")
      (assert (pairSecond unknownCheck) "the foreign check workspace was created and removed")
      (assert (stringContains? (pairFirst unknownCheck) "ERR_CHECK_FAILED") "foreign workspace ASL checks use the toolchain host and reject unknown symbols")
      true))

fn routedReply? op: String out: String -> Bool
  (and (stringStartsWith? out (str "(:" op " "))
       (not (stringContains? out "ERR_UNIMPLEMENTED"))
       (not (stringContains? out "ERR_NOT_PORTED")))

fn testLegacyRoutes! -> Bool
  (let [(root (scratchDir! "aslOpsRouted"))
        (ops (list "echo" "eval" "read" "write" "edit" "diff" "preflush" "flush" "discard"
                   "consult" "chk" "gate" "check" "test" "fix" "txn" "note" "where" "search"
                   "research" "crawl" "tiktok" "automate" "inBrowserAgent" "browserSession" "tools"
                   "help" "manage" "proc" "engine" "lens" "agent" "ping" "doctor" "query" "q"
                   "tree" "observe" "job" "intel" "audit" "pack" "target" "codegen"))]
    (do
      (assert (ok? (dirCreate (k/joinPath root ".asl/vfs"))) "create isolated routing workspace")
      (assert (>= (listLength ops) 40) "the native routing inventory covers the legacy operation set")
      (let [(missed (filter (fn [(op String)] -> Bool
                              (not (routedReply? op (isolatedRun! root (str "(:" op ")")).out))) ops))]
        (do
          (if (listEmpty? missed) (print "") (println (str "(:unrouted " (stringJoin missed " ") ")")))
          (assert (listEmpty? missed) "each legacy operation routes to its own receipt without unimplemented or unported errors")
          (assert (ok? (pathRemove root)) "remove isolated routing workspace")
          true))))

fn scratchDir! tag: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp/") tag "_" (stringFromInt64 (mod (nowNs) 1000000000)))

fn isolatedRun! root: String form: String -> g/RunOut
  (let [(repo (resultOr (realPath ".") ""))
        (host (k/joinPath repo "asl/host/out/asl-host"))
        (mainPath (k/joinPath repo "asl/packages/asl-forms/src/main.asl"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ROOT_DIR=" root) (str "SCRIPT_DIR=" (k/joinPath root "bin"))
                   (str "HOME=" root) (str "ASL_VFS_DIR=" (k/joinPath root ".asl/vfs")) "ASL_GATEWAY_PORT=1"))]
    (g/runArgv! (list host "run" mainPath "--root" root form) (some repo) (some env) 60000 0))

fn routedAgentRun! root: String form: String -> g/RunOut
  (let [(repo (resultOr (realPath ".") ""))
        (host (k/joinPath repo "asl/host/out/asl-host"))
        (mainPath (k/joinPath repo "asl/packages/asl-forms/src/main.asl"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ROOT_DIR=" repo) (str "SCRIPT_DIR=" (k/joinPath repo "bin"))
                   (str "HOME=" root) (str "ASL_VFS_DIR=" (k/joinPath root ".asl/vfs")) "ASL_GATEWAY_PORT=1"))]
    (g/runArgv! (list host "run" mainPath "--root" root form) (some repo) (some env) 30000 0))

fn testAgentGetsRawForm! -> Bool
  (let [(root (scratchDir! "aslOpsAgent"))
        (made (dirCreate (k/joinPath root ".asl/vfs")))
        (repo (resultOr (realPath ".") ""))
        (mainPath (k/joinPath repo "asl/agentLoop/main.asl"))
        (out (routedAgentRun! root "(:agent :task \"route-test\" :role \"agent\" :wallBudget 5)"))
        (dry (routedAgentRun! root "(:agent :task \"route-test\" :wallBudget 5 :dryRun true :backend \"claude\")"))
        (badBudget (routedAgentRun! root "(:agent :task \"route-test\" :wallBudget 999999 :dryRun true)"))]
    (do
      (assert (ok? made) "create isolated agent workspace state")
      (assert (fileExists? mainPath) "agent routing targets the checked-in ASL loop entry")
      (assert (= out.code 1) "agent loop argument rejection propagates through the router")
      (assert (stringContains? out.out "ERR_ROLE_DEPRECATED") "the router passes the raw task form to ASL main validation")
      (assert (and (= dry.code 0) (stringContains? dry.out "(:dryRunReceipt") (stringContains? dry.out "route-test")) "a successful routed run: the loop receives the task text from the raw form and exits zero")
      (assert (and (= badBudget.code 1) (stringContains? badBudget.out "ERR_INVALID_ARG :key \"wallBudget\"")) "the loop receives the :wallBudget keyword from the raw form and validates it")
      (assert (ok? (pathRemove root)) "remove isolated agent workspace")
      true))

fn testDoctorProbesRouted! -> Bool
  (let [(root (scratchDir! "aslOpsDoctor"))
        (caps (str "(:capabilities\n"
                   "  (:cap :id echoWorks :use \"u\" :status :works :probe \"(:echo :message \\\"doctorProbeMarker\\\")\" :expect \"doctorProbeMarker\" :fallback \"\")\n"
                   "  (:cap :id echoMissing :use \"u\" :status :works :probe \"(:echo :message \\\"other\\\")\" :expect \"doctorProbeMarker\" :fallback \"\"))\n"))]
    (do
      (assert (ok? (dirCreate (k/joinPath root "asl/grammar"))) "create isolated capabilities dir")
      (assert (ok? (fileWrite (k/joinPath root "asl/grammar/capabilities.asn") caps)) "write probe capabilities")
      (let [(out (isolatedRun! root "(:doctor)").out)]
        (do
          (assert (stringContains? out "(:capability :id \"echoWorks\" :declared :works :measured :works)") "doctor runs a probe through the nested router and reads its receipt")
          (assert (stringContains? out "(:capability :id \"echoMissing\" :declared :works :measured :absent :mismatch true)") "a probe whose receipt lacks :expect measures absent")
          (assert (ok? (pathRemove root)) "remove isolated doctor workspace")
          true))))

fn engineExchange! mode: String form: String -> g/RunOut
  (let [(outcome
          (d/engineExchangeWith 1 "proc" form
            (fn [wire]
              (let [(reply (cond
                             ((= mode "ok") (str "(:engine :status :ok :got \"" (k/escapeAsnVal (stringTrim wire)) "\")"))
                             ((= mode "reject") "(:receipt :status :error :message \"refused\")")
                             ((= mode "cut") "(:engine :status :ok :partial true")
                             ((= mode "largeReply") (str "(:engine :status :ok :padding \"" (stringRepeat "x" 70000) "\")"))
                             ((= mode "slowRead") (str "(:engine :status :ok :gotBytes " (stringFromInt64 (stringLength wire)) ")"))
                             (else "(:engine :status :error)")))]
                (ok (pair (not (= mode "cut")) reply))))))]
    (g/RunOut :code outcome.errCount :out (str outcome.line "\n") :errText "" :timedOut false :failure ""))

fn doubled s: String times: Int64 -> String
  (if (<= times 0) s (doubled (stringConcat s s) (- times 1)))

fn testEngineExchange! -> Bool
  (let [(okRun (engineExchange! "ok" "(:proc :action :list)"))
        (rejectRun (engineExchange! "reject" "(:manage :action :status)"))
        (cutRun (engineExchange! "cut" "(:engine :action :status)"))
        (largeReply (engineExchange! "largeReply" "(:engine :action :status)"))]
    (do
      (assert (= okRun.code 0) "an ok engine frame exits zero")
      (assert (= okRun.out "  (:step :id 1 :op \"proc\" :status \"ok\" :receipt (:engine :status :ok :got \"(:proc :action :list)\"))\n") "the injected exchange receives the raw step form and its ok frame becomes the step receipt")
      (assert (= rejectRun.code 1) "an engine error frame exits nonzero")
      (assert (stringContains? rejectRun.out ":error-code \":ERR_ENGINE_REJECTED\"" ) "a frame without :status :ok is ERR_ENGINE_REJECTED")
      (assert (stringContains? rejectRun.out ":receipt (:receipt :status :error :message \"refused\")") "the rejected frame is preserved as the receipt")
      (assert (= cutRun.code 1) "a frame cut before its newline exits nonzero")
      (assert (stringContains? cutRun.out ":error-code \":ERR_TRUNCATED\" :truncated true :bytes 34") "an incomplete frame without newline is ERR_TRUNCATED with the byte count")
      (assert (= largeReply.code 0) "an injected successful response exits zero")
      (assert (stringContains? largeReply.out ":padding") "the injected full reply retains its large payload")
      (let [(bigForm (str "(:engine :action :probe :payload \"" (doubled "a" 19) "\")"))
            (partialSend (engineExchange! "slowRead" bigForm))]
        (do
          (assert (= partialSend.code 0) "the injected exchange accepts a large request")
          (assert (stringContains? partialSend.out (str ":gotBytes " (stringFromInt64 (+ (stringLength bigForm) 1)))) "the function-value exchange receives every request byte and its newline")))
      true))

fn testEngineFrames! -> Bool
  (let [(firstChunk (d/engineFrameData "" "(:engine :status "))
        (secondChunk (d/engineFrameData (pairSecond firstChunk) ":ok\nignored"))]
    (do
    (assert (not (pairFirst firstChunk)) "an unterminated chunk remains pending")
    (assert (pairFirst secondChunk) "a later chunk completes the frame at its newline")
    (assert (= (pairSecond secondChunk) "(:engine :status :ok") "bytes after a frame newline do not enter its receipt")
    (assert (d/engineOk? "(:engine :status :ok)") "an engine frame with :status :ok is accepted")
    (assert (d/engineOk? "(:engine :status :ok :receipt (:proc :list))") "an ok engine frame may carry a receipt")
    (assert (d/engineOk? "(:engine :status :ok :padding \"large\")") "an ok engine frame may carry payload fields")
    (assert (not (d/engineOk? "(:receipt :status :error :message \"refused\")")) "an error engine frame is rejected")
    (assert (not (d/engineOk? "(:engine :status :okay)")) "a status token extending ok is not accepted")
    (assert (not (d/engineOk? "(:engine :status :okish)")) "a status token beginning with ok is not accepted")
    (assert (not (d/engineOk? "(:engine :status :ok_extra)")) "an underscore continuation is not accepted as ok")
    (assert (not (d/engineOk? "(:engine :receipt :ok)")) "a receipt field named ok is not a status")
    (assert (not (d/engineOk? "(:status :ok :engine)")) "status in the wrong field position is rejected")
    (assert (not (d/engineOk? "prefix (:engine :status :ok)")) "non-frame text before the receipt is rejected")
    (assert (not (d/engineOk? "(:engine :status :error)")) "an engine status other than ok is rejected")
    true))

fn testManifestCoverage! -> Bool
  (let [(manifest (resultOr (fileReadString "asl/packages/asl-forms/manifest.asn") ""))]
    (and (stringContains? manifest "\"asl-forms/check\"")
         (stringContains? manifest "\"asl-forms/lens\"")
         (stringContains? manifest "\"asl-forms/query\"")
         (stringContains? manifest "\"asl-forms/repair\"")
         (stringContains? manifest "\"asl-forms/rewrite\"")
         (stringContains? manifest "\"asl-intel\"")
         (stringContains? manifest "\"asl-proc\"")
         (stringContains? manifest "\"asl-syntax\"")
         (stringContains? manifest "\"asl-coord\"")))

fn ! runTests -> Bool
  (do
    (assert (testManifestCoverage!) "manifest declares all forms modules and direct package dependencies")
    (assert (testLegacyRoutes!) "testLegacyRoutes")
    (assert (testEngineExchange!) "testEngineExchange")
    (assert (testEngineFrames!) "testEngineFrames")
    (assert (testAgentGetsRawForm!) "testAgentGetsRawForm")
    (assert (testDoctorProbesRouted!) "testDoctorProbesRouted")
    (assert (testTxnRouter!) "testTxnRouter")
    (assert (testRoutedOperations!) "testRoutedOperations")
    (assert (testTree!) "testTree")
    (assert (testReadPaging!) "testReadPaging")
    (assert (testReadLines!) "testReadLines")
    (assert (testFallbacks!) "testFallbacks")
    (assert (testTarget!) "testTarget")
    (assert (testBrowserSession!) "testBrowserSession")
    (assert (testBrowserGatewayFailure!) "testBrowserGatewayFailure")
    (assert (testBrowserGatewayReplies!) "testBrowserGatewayReplies")
    true)
