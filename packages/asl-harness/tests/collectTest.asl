(module asl-harness/tests/collectTest
  :x [runTests]
  :i [(asl-harness/collect :a c)])

fn home -> String
  "asl/packages/asl-harness/tests/fixtures/collect/home"

fn started -> Int64
  1792663198

fn mapN m: (Map String Int64) k: String -> Int64
  (optionOr (mapGet m k) 0)

fn readOr path: String -> String
  (match (fileReadString path) ((ok t) t) ((err _) ""))

fn ! scanOf client: String rel: String -> c/Scan
  (let [(text (readOr (str (home) "/" rel)))]
    (cond
      ((= client "claude") (c/scanClaude text))
      ((= client "codex") (c/scanCodex text))
      (else (c/scanAgy text))))

fn ! checkTime -> Bool
  (let [(a (= (c/isoEpoch "2026-10-22T10:00:00.000Z") 1792663200))
        (b (= (c/isoEpoch "1970-01-01T00:00:00Z") 0))
        (d (= (c/isoEpoch "2024-02-29T23:59:59Z") 1709251199))
        (e (= (c/epochDays 1792663200) "2026/10/22"))
        (f (= (c/epochDays 1709251199) "2024/02/29"))
        (g (= (c/slugOf "/Users/x/a.b_c") "-Users-x-a-b-c"))]
    (do (assert a "isoEpoch fixture time")
        (assert b "isoEpoch epoch")
        (assert d "isoEpoch leap day")
        (assert e "epochDays fixture day")
        (assert f "epochDays leap day")
        (assert g "slugOf keeps alphanumerics")
        (and a (and b (and d (and e (and f g)))))))

fn ! checkClaude -> Bool
  (let [(s (scanOf "claude" ".claude/projects/-work-proj/a.jsonl"))
        (turns (= s.turns 2))
        (tin (= s.tokIn 155))
        (tout (= s.tokOut 27))
        (tcached (= s.tokCached 2200))
        (tools (and (= (mapN s.tools "Read") 1) (= (mapN s.tools "Bash") 1)))
        (errs (and (= (mapN s.errors "toolError") 1) (= (listLength (mapKeys s.errors)) 1)))]
    (do (assert turns "claude turns dedupe by message id")
        (assert tin "claude in = input + cache creation, last record per id")
        (assert tout "claude out takes the final usage per message")
        (assert tcached "claude cached = cache reads")
        (assert tools "claude tool_use counts by name")
        (assert errs "claude is_error tool_result counted once")
        (and turns (and tin (and tout (and tcached (and tools errs)))))))

fn ! checkCodex -> Bool
  (let [(s (scanOf "codex" ".codex/sessions/2026/10/22/rollout-2026-10-22T13-00-00-aaa.jsonl"))
        (turns (= s.turns 2))
        (tin (= s.tokIn 100))
        (tout (= s.tokOut 30))
        (tcached (= s.tokCached 200))
        (tools (and (= (mapN s.tools "exec") 2) (and (= (mapN s.tools "apply_patch") 1) (= (listLength (mapKeys s.tools)) 2))))
        (errs (and (= (mapN s.errors "stream_error") 1) (= (listLength (mapKeys s.errors)) 1)))]
    (do (assert turns "codex turns = token_usage_record count")
        (assert tin "codex in = last total input minus cached")
        (assert tout "codex out = last total output")
        (assert tcached "codex cached = last total cached")
        (assert tools "codex function_call and custom_tool_call by name, outputs not counted")
        (assert errs "codex stream_error counted")
        (and turns (and tin (and tout (and tcached (and tools errs)))))))

fn ! checkAgy -> Bool
  (let [(s (scanOf "agy" ".gemini/antigravity-cli/brain/newrun/.system_generated/logs/transcript.jsonl"))
        (turns (= s.turns 2))
        (tin (= s.tokIn 650))
        (tout (= s.tokOut 105))
        (tcached (= s.tokCached 700))
        (tools (and (= (mapN s.tools "run_command") 2) (= (mapN s.tools "view_file") 1)))
        (errs (and (= (mapN s.errors "stepRUNNING") 1) (= (listLength (mapKeys s.errors)) 1)))]
    (do (assert turns "agy turns = PLANNER_RESPONSE steps")
        (assert tin "agy in sums input_tokens")
        (assert tout "agy out sums output_tokens")
        (assert tcached "agy cached sums cache_read_tokens")
        (assert tools "agy tool_calls by name")
        (assert errs "agy non-DONE step status counted")
        (and turns (and tin (and tout (and tcached (and tools errs)))))))

fn ! checkPick -> Bool
  (let [(claude (= (c/pickTranscript! "claude" (home) (started) "/work/proj") (ok (str (home) "/.claude/projects/-work-proj/a.jsonl"))))
        (codex (= (c/pickTranscript! "codex" (home) (started) "/work/proj") (ok (str (home) "/.codex/sessions/2026/10/22/rollout-2026-10-22T13-00-00-aaa.jsonl"))))
        (agy (= (c/pickTranscript! "agy" (home) (started) "/work/proj") (ok (str (home) "/.gemini/antigravity-cli/brain/newrun/.system_generated/logs/transcript.jsonl"))))
        (amb (match (c/pickTranscript! "claude" (home) (started) "/work/amb") ((err w) (stringStartsWith? w "ambiguous: 2")) ((ok _) false)))
        (missing (match (c/pickTranscript! "claude" (home) (started) "/work/missing") ((err _) true) ((ok _) false)))
        (late (match (c/pickTranscript! "claude" (home) 1893456000 "/work/proj") ((err _) true) ((ok _) false)))
        (unknown (match (c/pickTranscript! "vim" (home) (started) "/work/proj") ((err _) true) ((ok _) false)))]
    (do (assert claude "claude picks the session of the cwd")
        (assert codex "codex picks the rollout whose cwd matches, not the other cwd")
        (assert agy "agy picks the transcript inside the window, not the older run")
        (assert amb "two sessions in the window are ambiguous")
        (assert missing "no session dir gives none")
        (assert late "a transcript older than the launch is not picked")
        (assert unknown "unknown client is an error")
        (and claude (and codex (and agy (and amb (and missing (and late unknown))))))))

fn ! runDirFor base: String name: String -> String
  (let [(d (str base "/" name))] (do (dirCreate d) d))

fn ! checkReceipt base: String -> Bool
  (let [(d (runDirFor base "claude-4242"))
        (r (c/collect! "claude" (home) d (started) "/work/proj" 3 "abc123"))
        (want (str "(:launchRun :client claude :run claude-4242 :promptDigest \"abc123\" :startedAt 1792663198 :exit 3"
                   " :transcript \"" (home) "/.claude/projects/-work-proj/a.jsonl\" :turns 2"
                   " :tokens (:in 155 :out 27 :cached 2200) :tools (Bash 1 Read 1) :errors (toolError 1))\n"))
        (got (readOr (str d "/run.asn")))
        (wrote (= r (ok (str d "/run.asn"))))
        (same (= got want))
        (d2 (runDirFor base "agy-7"))
        (r2 (c/collect! "agy" (home) d2 (started) "/work/proj" 0 "dd"))
        (got2 (readOr (str d2 "/run.asn")))
        (agyOk (and (stringContains? got2 ":turns 2") (and (stringContains? got2 ":tokens (:in 650 :out 105 :cached 700)") (and (stringContains? got2 ":tools (run_command 2 view_file 1)") (stringContains? got2 ":errors (stepRUNNING 1)")))))
        (d3 (runDirFor base "claude-9/"))
        (r3 (c/collect! "claude" (home) d3 (started) "/work/amb" 1 "ee"))
        (got3 (readOr (str d3 "run.asn")))
        (noneOk (and (stringContains? got3 ":run claude-9 ") (and (stringContains? got3 ":transcript :none :why \"ambiguous: 2") (not (stringContains? got3 ":turns")))))
        (d4 (str base "/missing/claude-1"))
        (r4 (c/collect! "claude" (home) d4 (started) "/work/proj" 0 "ff"))
        (unwritable (match r4 ((err e) (stringStartsWith? e "collect: cannot write")) ((ok _) false)))]
    (do (assert wrote "collect! returns the run.asn path")
        (assert same (str "claude receipt text: " got))
        (assert agyOk (str "agy receipt: " got2))
        (assert noneOk (str "ambiguous receipt names why and carries no counts: " got3))
        (assert unwritable "an unwritable run dir is an error, not a silent success")
        (and wrote (and same (and agyOk (and noneOk unwritable))))))

fn ! runTests -> Bool
  (let [(base (str "/tmp/aslCollectTest-" (stringFromInt64 (procSelf))))
        (mk (dirCreate base))
        (time (checkTime))
        (claude (checkClaude))
        (codex (checkCodex))
        (agy (checkAgy))
        (pick (checkPick))
        (receipt (checkReceipt base))]
    (and time (and claude (and codex (and agy (and pick receipt))))))
