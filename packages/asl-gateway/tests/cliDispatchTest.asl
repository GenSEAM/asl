(module aslGateway/tests/cliDispatchTest
  :x [testMessageTextParity
      testAgyToolsParity!
      testWritePromptDirParity!
      testJsonObjectParity
      testParseResultParity
      testResolveCliBinParity!
      testBuildCmdParity!
      testDispatchAgainstStubs!
      testTimeoutAndSetsidKill!
      testFixtureCorpusVerification!
      testPromptDirFailures!
      runTests]
  :i [(cliDispatch :a cli)
      (asl-json/json :a j)])

fn parseJsonUnsafe s: String -> j/Json
  (resultOr (j/jsonParse s) (j/jnull))

fn testMessageTextParity -> Bool
  (do
    (assert (= (cli/cliMessageText (j/jarr (list))) "") "msg_list_empty parity")
    (let [(texts (list (j/jobj (list (pair "text" (j/jstr "hello"))))
                       (j/jobj (list (pair "text" (j/jstr "world"))))))]
      (assert (= (cli/cliMessageText (j/jarr texts)) "hello\nworld") "msg_list_texts parity"))
    (let [(mixed (list (j/jobj (list (pair "text" (j/jstr "first"))))
                       (j/jobj (list (pair "other" (j/jint 1))))
                       (j/jobj (list (pair "text" (j/jstr ""))))
                       (j/jobj (list (pair "text" (j/jstr "second"))))))]
      (assert (= (cli/cliMessageText (j/jarr mixed)) "first\nsecond") "msg_list_mixed parity"))
    (let [(nonDicts (list (j/jobj (list (pair "text" (j/jstr "part1"))))
                          (j/jint 42)
                          (j/jstr "ignored")
                          (j/jnull)
                          (j/jobj (list (pair "text" (j/jstr "part2"))))))]
      (assert (= (cli/cliMessageText (j/jarr nonDicts)) "part1\npart2") "msg_list_non_dicts parity"))
    (assert (= (cli/cliMessageText (j/jnull)) "") "msg_none parity")
    (assert (= (cli/cliMessageText (j/jstr "hello plain text")) "hello plain text") "msg_str parity")
    (assert (= (cli/cliMessageText (j/jint 42)) "42") "msg_int parity")
    (assert (= (cli/cliMessageText (j/jbool true)) "True") "msg_bool_true parity")
    (assert (= (cli/cliMessageText (j/jbool false)) "False") "msg_bool_false parity")
    (assert (= (cli/cli_message_text (j/jstr "alias test")) "alias test") "cli_message_text alias parity")
    true)

fn testAgyToolsParity! -> Bool
  (let [(toolsRes (cli/cliAgyTools!))]
    (do
      (assert (ok? toolsRes) "cliAgyTools must succeed")
      (let [(tools (resultOr toolsRes (list)))]
        (assert (= (listLength tools) 5) "tools list length must be 5")
        (assert (= (optionOr (listHead tools) "") "run_command") "first tool is run_command")
        (assert (= (optionOr (listHead (optionOr (listTail tools) (list))) "") "invoke_subagent") "second tool is invoke_subagent")
        (assert (= (resultOr (cli/cli_agy_tools!) (list)) tools) "cli_agy_tools alias parity"))
      true))

fn testWritePromptDirParity! -> Bool
  (let [(tools (list "run_command" "invoke_subagent" "send_message" "manage_subagents" "wait"))
        (sysPrompt "System prompt for agy")
        (agyMd (cli/agyAgentMarkdown sysPrompt tools false))
        (agyMdNoTools (cli/agyAgentMarkdown "System prompt no tools" tools true))]
    (do
      (assert (stringContains? agyMd "name: aslGateway") "agy md contains name")
      (assert (stringContains? agyMd "  - run_command") "agy md contains tools")
      (assert (stringContains? agyMd "System prompt for agy") "agy md contains prompt")
      (assert (stringContains? agyMdNoTools "tools: []") "agy no tools md contains empty tools")
      (assert (stringContains? agyMdNoTools "excludeDefaultComponents: true") "agy no tools excludes defaults")
      (let [(claudeDirRes (cli/cliWritePromptDir! "claude" "Claude prompt test" false))]
        (assert (ok? claudeDirRes) "cliWritePromptDir for claude succeeds")
        (let [(pdir (resultOr claudeDirRes (cli/CliPromptDir :tmpDir "" :promptPath "")))]
          (assert (fileExists? pdir.promptPath) "promptPath file exists")
          (assert (= (resultOr (fileReadString pdir.promptPath) "") "Claude prompt test") "prompt content matches")
          (let [(_ignore (pathRemove pdir.tmpDir))] true)))
      true))

fn testJsonObjectParity -> Bool
  (do
    (let [(res1 (cli/cliJsonObject "{\"status\": \"ok\", \"code\": 200}"))]
      (assert (ok? res1) "json_obj_simple must parse")
      (let [(obj1 (resultOr res1 (j/jnull)))]
        (assert (= (cli/jsonIntField obj1 "code") 200) "code field is 200")))
    (let [(res2 (cli/cliJsonObject "Some logs before\n{\"valid\": true}\nTrailing logs after"))]
      (assert (ok? res2) "json_obj_surrounded must parse")
      (let [(obj2 (resultOr res2 (j/jnull)))]
        (assert (some? (j/jsonGet obj2 "valid")) "valid field exists in surrounded json")))
    (let [(res3 (cli/cliJsonObject "{\"text\": \"line1\\nline2 \\\"quoted\\\"\"}"))]
      (assert (ok? res3) "json_obj_escaped must parse"))
    (let [(res4 (cli/cliJsonObject "{}"))]
      (assert (ok? res4) "json_obj_empty must parse"))
    (assert (err? (cli/cliJsonObject "error: something went wrong without json")) "json_obj_no_json must err")
    (assert (err? (cli/cliJsonObject "[1, 2, 3]")) "json_obj_array_only must err")
    (assert (err? (cli/cliJsonObject "{\"unclosed\": 1")) "json_obj_malformed must err")
    (assert (= (resultOr (cli/cli_json_object "{\"a\": 1}") (j/jnull))
               (resultOr (cli/cliJsonObject "{\"a\": 1}") (j/jnull))) "cli_json_object alias parity")
    true)

fn testParseResultParity -> Bool
  (do
    (let [(claudeMu "{\"result\": \"Answer from Claude MU\", \"modelUsage\": {\"claude-3-5\": {\"inputTokens\": 100, \"cacheCreationInputTokens\": 20, \"cacheReadInputTokens\": 10, \"outputTokens\": 50}}}")
          (res (cli/cliParseResult "claude" claudeMu))]
      (assert (= res.text "Answer from Claude MU") "claude mu text parity")
      (assert (some? res.usage) "claude mu usage exists")
      (let [(u (optionOr res.usage (cli/CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))]
        (assert (= u.inputTokens 130) "claude mu inputTokens parity")
        (assert (= u.cachedTokens 10) "claude mu cachedTokens parity")
        (assert (= u.outputTokens 50) "claude mu outputTokens parity"))
      (refute res.dedup "claude mu dedup is false"))

    (let [(claudeU "{\"result\": \"Answer from Claude standard\", \"usage\": {\"input_tokens\": 80, \"cache_creation_input_tokens\": 15, \"cache_read_input_tokens\": 5, \"output_tokens\": 30}}")
          (res (cli/cliParseResult "claude" claudeU))]
      (assert (= res.text "Answer from Claude standard") "claude u text parity")
      (let [(u (optionOr res.usage (cli/CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))]
        (assert (= u.inputTokens 100) "claude u inputTokens parity")
        (assert (= u.cachedTokens 5) "claude u cachedTokens parity")
        (assert (= u.outputTokens 30) "claude u outputTokens parity")))

    (let [(claudeInv "Error: server disconnected")
          (res (cli/cliParseResult "claude" claudeInv))]
      (assert (= res.text "Error: server disconnected") "claude inv text parity")
      (assert (none? res.usage) "claude inv usage is none"))

    (let [(codexStd "{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 200, \"cached_input_tokens\": 50, \"output_tokens\": 75}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"Codex answer 1\"}}")
          (res (cli/cliParseResult "codex" codexStd))]
      (assert (= res.text "Codex answer 1") "codex std text parity")
      (let [(u (optionOr res.usage (cli/CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))]
        (assert (= u.inputTokens 200) "codex std inputTokens parity")
        (assert (= u.cachedTokens 50) "codex std cachedTokens parity")
        (assert (= u.outputTokens 75) "codex std outputTokens parity")))

    (let [(codexMulti "{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 100, \"cached_input_tokens\": 20, \"output_tokens\": 40}}\n{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 50, \"cached_input_tokens\": 10, \"output_tokens\": 20}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"Multi turn answer\"}}")
          (res (cli/cliParseResult "codex" codexMulti))]
      (assert (= res.text "Multi turn answer") "codex multi text parity")
      (let [(u (optionOr res.usage (cli/CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))]
        (assert (= u.inputTokens 150) "codex multi inputTokens parity")
        (assert (= u.cachedTokens 30) "codex multi cachedTokens parity")
        (assert (= u.outputTokens 60) "codex multi outputTokens parity")))

    (let [(agyStd "{\"response\": \"Agy answer 1\", \"usage\": {\"input_tokens\": 300, \"cache_read_tokens\": 40, \"output_tokens\": 100, \"thinking_tokens\": 20}}")
          (res (cli/cliParseResult "agy" agyStd))]
      (assert (= res.text "Agy answer 1") "agy std text parity")
      (let [(u (optionOr res.usage (cli/CliUsage :inputTokens 0 :cachedTokens 0 :outputTokens 0)))]
        (assert (= u.inputTokens 300) "agy std inputTokens parity")
        (assert (= u.cachedTokens 40) "agy std cachedTokens parity")
        (assert (= u.outputTokens 120) "agy std outputTokens parity (+ thinking)"))
      (refute res.dedup "agy std dedup is false"))

    (let [(agyDedup "{\"response\": \"Repeated response\\nRepeated response\", \"usage\": {\"input_tokens\": 50, \"cache_read_tokens\": 0, \"output_tokens\": 20, \"thinking_tokens\": 0}}")
          (res (cli/cliParseResult "agy" agyDedup))]
      (assert (= res.text "Repeated response") "agy dedup text parity")
      (assert res.dedup "agy dedup flag parity"))

    (let [(agyEven "{\"response\": \"Even length text! Even length text!\", \"usage\": {\"input_tokens\": 10, \"cache_read_tokens\": 0, \"output_tokens\": 10, \"thinking_tokens\": 0}}")
          (res (cli/cliParseResult "agy" agyEven))]
      (assert (= res.text "Even length text! Even length text!") "agy even text parity")
      (refute res.dedup "agy even dedup is false"))
    true)

fn testResolveCliBinParity! -> Bool
  (let [(homeBin "/tmp/asl-gw-resolver-home/.local/bin/conflict_cli")
        (pathBin "/tmp/asl-gw-resolver-path/conflict_cli")
        (_homeDir (dirCreate "/tmp/asl-gw-resolver-home/.local/bin"))
        (_pathDir (dirCreate "/tmp/asl-gw-resolver-path"))
        (_homeWrite (fileWrite homeBin "home"))
        (_pathWrite (fileWrite pathBin "path"))
        (rHome (cli/resolveCliBinFromLocations! "conflict_cli" "/tmp/fallback/legacy" "/tmp/asl-gw-resolver-home" "/tmp/asl-gw-resolver-path:/usr/bin:/bin"))
        (_cleanup (pathRemove "/tmp/asl-gw-resolver-home"))
        (_cleanup2 (pathRemove "/tmp/asl-gw-resolver-path"))]
    (do
      (assert (= rHome homeBin) "home local bin wins over a conflicting PATH candidate")
      (let [(r1 (cli/resolveCliBin! "PATH" "sh" "/bin/legacy_fallback"))]
        (assert (stringEndsWith? r1 "sh") "resolveCliBin finds sh on PATH"))
      (let [(r2 (cli/resolveCliBin! "NONEXISTENT_VAR_XYZ" "nonexistent_bin_123" "/tmp/fallback/legacy"))]
        (assert (= r2 "/tmp/fallback/legacy") "resolveCliBin falls back to legacy path"))
      true))

fn testBuildCmdParity! -> Bool
  (do
    (let [(codexCmd (cli/codexBuildCmd "codex" "/tmp/ws" "/tmp/prompt.txt" true (some "high") (some "luna")))]
      (assert (= (optionOr (listHead codexCmd) "") "codex") "codex cmd starts with binary")
      (assert (listContains? codexCmd "exec") "codex cmd has exec")
      (assert (listContains? codexCmd "-C") "codex cmd has -C")
      (assert (listContains? codexCmd "/tmp/ws") "codex cmd has workspace")
      (assert (listContains? codexCmd "project_doc_max_bytes=0") "codex cmd has noTools flag")
      (assert (listContains? codexCmd "model_reasoning_effort=\"high\"") "codex cmd has effort")
      (assert (listContains? codexCmd "gpt-5.6-luna") "codex cmd mapped luna to gpt-5.6-luna"))

    (let [(claudeCmd (cli/claudeBuildCmd! "claude" "/tmp/prompt.txt" false (some "claude-3-5") (some "high")))]
      (assert (= (optionOr (listHead claudeCmd) "") "claude") "claude cmd starts with binary")
      (assert (listContains? claudeCmd "-p") "claude cmd has -p")
      (assert (listContains? claudeCmd "Bash,Read,Edit,Write,Grep,Glob") "claude cmd has lean tools")
      (assert (listContains? claudeCmd "plan") "claude cmd has plan permission mode")
      (assert (listContains? claudeCmd "claude-3-5") "claude cmd has model")
      (assert (listContains? claudeCmd "high") "claude cmd has effort"))

    (let [(agyCmd (cli/agyBuildCmd! "agy" "/tmp/ws" "/tmp/tmpDir" "/tmp/root" 120 (some "opus-high") (some "low") none (list) "Prompt" false))]
      (assert (= (optionOr (listHead agyCmd) "") "agy") "agy cmd starts with binary")
      (assert (listContains? agyCmd "--output-format") "agy cmd has --output-format")
      (assert (listContains? agyCmd "claude-opus-4-6-thinking") "agy cmd mapped opus to thinking")
      (assert (listContains? agyCmd "aslGateway") "agy cmd has default agent")
      (assert (listContains? agyCmd "/tmp/ws") "agy cmd has --add-dir ws"))
    true)

fn setupStubScripts! stubDir: String logDir: String -> Bool
  (let [(_d1 (dirCreate stubDir))
        (_d2 (dirCreate logDir))
        (stubScript (str "#!/bin/sh\n"
                         "echo \"$@\" > " logDir "/last_argv.txt\n"
                         "pwd > " logDir "/last_cwd.txt\n"
                         "cat > " logDir "/last_stdin.txt\n"
                         "env | grep -E '_API_KEY' > " logDir "/last_env.txt || true\n"
                         "case \"$0\" in\n"
                         "  *codex*) printf '{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 10, \"cached_input_tokens\": 0, \"output_tokens\": 5}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"stub codex reply\"}}\n' ;;\n"
                         "  *claude*) printf '{\"result\": \"stub claude reply\", \"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}}\n' ;;\n"
                         "  *agy*) printf '{\"response\": \"stub agy reply\", \"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}}\n' ;;\n"
                         "  *) printf '{\"error\": \"unknown stub\"}\n' ;;\n"
                         "esac\n"))
        (_w1 (fileWrite (str stubDir "/codex") stubScript))
        (_w2 (fileWrite (str stubDir "/claude") stubScript))
        (_w3 (fileWrite (str stubDir "/agy") stubScript))
        (_c1 (processRun (str "chmod +x " stubDir "/codex " stubDir "/claude " stubDir "/agy")))]
    true)

fn cleanupStubScripts! stubDir: String logDir: String -> Bool
  (let [(_r1 (pathRemove stubDir))
        (_r2 (pathRemove logDir))]
    true)

fn testDispatchAgainstStubs! -> Bool
  (let [(stubDir "/tmp/asl_test_gw_stubs")
        (logDir "/tmp/asl_test_gw_logs")
        (_setup (setupStubScripts! stubDir logDir))
        (testWs "/tmp")
        (testPrompt "Test dispatch prompt content")
        (baseOpts (cli/DispatchOptions
                    :model (some "test-model")
                    :effort (some "low")
                    :timeout 10
                    :workspace (some testWs)
                    :systemPrompt (some "Test system")
                    :noTools true
                    :agent none
                    :addDirs (list)
                    :cliBin none))]
    (do
      (assert (fileExists? (str stubDir "/codex")) "stub scripts created in isolated test dir")
      (let [(codexOpts (cli/DispatchOptions
                         :model baseOpts.model
                         :effort baseOpts.effort
                         :timeout baseOpts.timeout
                         :workspace baseOpts.workspace
                         :systemPrompt baseOpts.systemPrompt
                         :noTools baseOpts.noTools
                         :agent baseOpts.agent
                         :addDirs baseOpts.addDirs
                         :cliBin (some (str stubDir "/codex"))))
            (res (cli/dispatchCodexFallback! testPrompt codexOpts))]
        (assert (ok? res) (str "dispatchCodexFallback failed: " (mt res ((ok _) "OK") ((err msg) msg))))
        (let [(parsed (resultOr res (cli/CliParseResult :text "" :usage none :dedup false)))]
          (assert (= parsed.text "stub codex reply") "stub codex parsed text"))
        (let [(recordedStdin (stringTrim (resultOr (fileReadString (str logDir "/last_stdin.txt")) "")))]
          (assert (= recordedStdin testPrompt) "codex stdin equals prompt"))
        (let [(recordedCwd (stringTrim (resultOr (fileReadString (str logDir "/last_cwd.txt")) "")))]
          (assert (stringContains? recordedCwd "tmp") "codex cwd equals workspace"))
        (let [(recordedArgv (resultOr (fileReadString (str logDir "/last_argv.txt")) ""))]
          (assert (stringContains? recordedArgv "exec") "codex argv contains exec")
          (assert (stringContains? recordedArgv "--json") "codex argv contains --json"))
        (let [(recordedEnv (resultOr (fileReadString (str logDir "/last_env.txt")) ""))]
          (refute (stringContains? recordedEnv "GEMINI_API_KEY=") "codex env must NOT leak GEMINI_API_KEY")
          (refute (stringContains? recordedEnv "DEEPGRAM_API_KEY=") "codex env must NOT leak DEEPGRAM_API_KEY")
          (refute (stringContains? recordedEnv "GROQ_API_KEY=") "codex env must NOT leak GROQ_API_KEY")
          (refute (stringContains? recordedEnv "ANTHROPIC_API_KEY=") "codex env must NOT leak ANTHROPIC_API_KEY")))

      (let [(claudeOpts (cli/DispatchOptions
                          :model baseOpts.model
                          :effort baseOpts.effort
                          :timeout baseOpts.timeout
                          :workspace baseOpts.workspace
                          :systemPrompt baseOpts.systemPrompt
                          :noTools baseOpts.noTools
                          :agent baseOpts.agent
                          :addDirs baseOpts.addDirs
                          :cliBin (some (str stubDir "/claude"))))
            (resClaude (cli/dispatchClaudeFallback! testPrompt claudeOpts))]
        (assert (ok? resClaude) (str "dispatchClaudeFallback failed: " (mt resClaude ((ok _) "OK") ((err msg) msg))))
        (let [(parsed (resultOr resClaude (cli/CliParseResult :text "" :usage none :dedup false)))]
          (assert (= parsed.text "stub claude reply") "stub claude parsed text"))
        (let [(recordedStdin (stringTrim (resultOr (fileReadString (str logDir "/last_stdin.txt")) "")))]
          (assert (= recordedStdin testPrompt) "claude stdin equals prompt"))
        (let [(recordedArgv (resultOr (fileReadString (str logDir "/last_argv.txt")) ""))]
          (assert (stringContains? recordedArgv "-p") "claude argv contains -p")
          (assert (stringContains? recordedArgv "--output-format") "claude argv contains --output-format"))
        (let [(recordedEnv (resultOr (fileReadString (str logDir "/last_env.txt")) ""))]
          (refute (stringContains? recordedEnv "GEMINI_API_KEY=") "claude env must NOT leak GEMINI_API_KEY")
          (refute (stringContains? recordedEnv "DEEPGRAM_API_KEY=") "claude env must NOT leak DEEPGRAM_API_KEY")
          (refute (stringContains? recordedEnv "GROQ_API_KEY=") "claude env must NOT leak GROQ_API_KEY")
          (refute (stringContains? recordedEnv "OPENAI_API_KEY=") "claude env must NOT leak OPENAI_API_KEY")))

      (let [(agyOpts (cli/DispatchOptions
                       :model baseOpts.model
                       :effort baseOpts.effort
                       :timeout baseOpts.timeout
                       :workspace baseOpts.workspace
                       :systemPrompt baseOpts.systemPrompt
                       :noTools baseOpts.noTools
                       :agent baseOpts.agent
                       :addDirs baseOpts.addDirs
                       :cliBin (some (str stubDir "/agy"))))
            (resAgy (cli/dispatchAgyFallback! testPrompt agyOpts))]
        (assert (ok? resAgy) (str "dispatchAgyFallback failed: " (mt resAgy ((ok _) "OK") ((err msg) msg))))
        (let [(parsed (resultOr resAgy (cli/CliParseResult :text "" :usage none :dedup false)))]
          (assert (= parsed.text "stub agy reply") "stub agy parsed text"))
        (let [(recordedArgv (resultOr (fileReadString (str logDir "/last_argv.txt")) ""))]
          (assert (stringContains? recordedArgv "--output-format") "agy argv contains --output-format")
          (assert (stringContains? recordedArgv "aslGateway") "agy argv contains aslGateway agent"))
        (let [(recordedEnv (resultOr (fileReadString (str logDir "/last_env.txt")) ""))
              (hasKey (or (some? (envGet "GEMINI_API_KEY")) (or (some? (envGet "GOOGLE_API_KEY")) (some? (envGet "AGY_API_KEY")))))]
          (assert (if hasKey (or (stringContains? recordedEnv "GEMINI_API_KEY=") (or (stringContains? recordedEnv "GOOGLE_API_KEY=") (stringContains? recordedEnv "AGY_API_KEY="))) (= recordedEnv "")) "agy env passes an allowed api key when one is configured and none otherwise")
          (refute (stringContains? recordedEnv "DEEPGRAM_API_KEY=") "agy env must NOT leak DEEPGRAM_API_KEY")
          (refute (stringContains? recordedEnv "GROQ_API_KEY=") "agy env must NOT leak GROQ_API_KEY")
          (refute (stringContains? recordedEnv "OPENAI_API_KEY=") "agy env must NOT leak OPENAI_API_KEY")
          (refute (stringContains? recordedEnv "ANTHROPIC_API_KEY=") "agy env must NOT leak ANTHROPIC_API_KEY")))

      (let [(_clean (cleanupStubScripts! stubDir logDir))] true)
      true))

fn testTimeoutAndSetsidKill! -> Bool
  (let [(timeoutDir "/tmp/asl_test_gw_timeout")
        (_d (dirCreate timeoutDir))
        (pidFile (str timeoutDir "/child_pid.txt"))
        (stubPath (str timeoutDir "/stub_sleep"))
        (stubSh (str "#!/bin/sh\n"
                     "sleep 30 &\n"
                     "echo $! > '" pidFile "'\n"
                     "exec sleep 15\n"))
        (_w (fileWrite stubPath stubSh))
        (_c (processRun (str "chmod +x " stubPath)))
        (envStr "PATH=/usr/bin:/bin")
        (cmd (list stubPath))
        (tmpDir (str timeoutDir "/scratch"))
        (_mkTmp (dirCreate tmpDir))
        (childPidFile (str tmpDir "/child.pid"))
        (dispRes (cli/runSpawnDispatch! cmd "/tmp" envStr none childPidFile tmpDir 1 "agy"))]
    (do
      (assert (err? dispRes) "dispatch must time out and return err")
      (let [(childPidStr (stringTrim (resultOr (fileReadString pidFile) "")))]
        (assert (not (stringEmpty? childPidStr)) "child written pid must not be empty")
        (let [(_s (sleepMs 100))
              (psRes (processRun (str "kill -0 " childPidStr " 2>/dev/null")))]
          (refute (= psRes.exitCode 0) "stub process calling setsid must be killed on timeout")))
      (let [(_rm (pathRemove timeoutDir))] true)
      true))

fn fixtureCaseIncludes content: String id: String expected: String -> Bool
  (if (stringEmpty? content) false
    (let [(lines (stringSplit content "\n"))]
      (if (listEmpty? lines) false
        (let [(line (optionOr (listHead lines) ""))]
          (if (and (stringContains? line (str ":id \"" id "\"")) (stringContains? line expected)) true
            (fixtureCaseIncludes (stringJoin (optionOr (listTail lines) (list)) "\n") id expected))))))

fn fixtureFieldMatches content: String id: String field: String actual: String -> Bool
  (let [(escapedSlashes (stringReplace actual "\\" "\\\\"))
        (escapedQuotes (stringReplace escapedSlashes "\"" "\\\""))
        (encoded (stringReplace escapedQuotes "\n" "\\n"))]
    (fixtureCaseIncludes content id (str field " \"" encoded "\"")))

fn testFixtureCorpusVerification! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-gateway/tests/cliParityFixture.asn"))]
    (do
      (assert (ok? readRes) "cliParityFixture.asn must exist and be readable")
      (let [(content (resultOr readRes ""))
            (lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringSplit content "\n")))
            (n (listLength lines))]
        (assert (>= n 30) "Corpus must have at least 30 fixtures")
        (assert (= n 41) "Corpus holds exactly 41 recorded fixtures from Python")
        (assert (fixtureFieldMatches content "msg_list_empty" ":want" (cli/cliMessageText (j/jarr (list)))) "msg_list_empty fixture expectation matches actual output")
        (assert (fixtureFieldMatches content "msg_none" ":want" (cli/cliMessageText (j/jnull))) "msg_none fixture expectation matches actual output")
        (assert (fixtureFieldMatches content "msg_str" ":want" (cli/cliMessageText (j/jstr "hello plain text"))) "msg_str fixture expectation matches actual output")
        (assert (fixtureFieldMatches content "msg_int" ":want" (cli/cliMessageText (j/jint 42))) "msg_int fixture expectation matches actual output")
        (assert (fixtureFieldMatches content "msg_bool_true" ":want" (cli/cliMessageText (j/jbool true))) "msg_bool_true fixture expectation matches actual output")
        (assert (fixtureFieldMatches content "msg_bool_false" ":want" (cli/cliMessageText (j/jbool false))) "msg_bool_false fixture expectation matches actual output")
        (let [(toolsRes (cli/cliAgyTools!))
              (tools (resultOr toolsRes (list)))]
          (assert (and (ok? toolsRes) (= tools (list "run_command" "invoke_subagent" "send_message" "manage_subagents" "wait")) (fixtureCaseIncludes content "agy_tools" "[\"run_command\" \"invoke_subagent\" \"send_message\" \"manage_subagents\" \"wait\"]")) "agy_tools fixture expected list matches the executed CLI tool list"))
        (assert (fixtureFieldMatches content "resolve_env_override" ":want" (cli/resolveCliBinFromLocations! "sh" "" "" "/bin")) "resolve_env_override fixture want matches executed resolver")
        (assert (fixtureFieldMatches content "resolve_legacy_fallback" ":want" (cli/resolveCliBinFromLocations! "fixture_missing_cli_1379" "/tmp/fallback/bin" "" "")) "resolve_legacy_fallback fixture want matches executed resolver")
        (let [(texts (j/jarr (list (j/jobj (list (pair "text" (j/jstr "hello")))) (j/jobj (list (pair "text" (j/jstr "world")))))))]
          (assert (fixtureFieldMatches content "msg_list_texts" ":want" (cli/cliMessageText texts)) "msg_list_texts fixture expectation matches actual output"))
        (let [(mixed (j/jarr (list (j/jobj (list (pair "text" (j/jstr "first")))) (j/jobj (list (pair "other" (j/jint 1)))) (j/jobj (list (pair "text" (j/jstr "")))) (j/jobj (list (pair "text" (j/jstr "second")))))))]
          (assert (fixtureFieldMatches content "msg_list_mixed" ":want" (cli/cliMessageText mixed)) "msg_list_mixed fixture expectation matches actual output"))
        (let [(nonDicts (j/jarr (list (j/jobj (list (pair "text" (j/jstr "part1")))) (j/jint 42) (j/jstr "ignored") (j/jnull) (j/jobj (list (pair "text" (j/jstr "part2")))))))]
          (assert (fixtureFieldMatches content "msg_list_non_dicts" ":want" (cli/cliMessageText nonDicts)) "msg_list_non_dicts fixture expectation matches actual output"))
        true)))

fn fixtureLineById lines: (List String) id: String -> String
  (mt (listHead lines)
    ((none) "")
    ((some line)
     (if (stringContains? line (str ":id \"" id "\""))
       line
       (fixtureLineById (optionOr (listTail lines) (list)) id))))

fn fixtureQuotedEnd line: String start: Int64 pos: Int64 escaped: Bool -> Int64
  (if (>= pos (stringLength line)) pos
    (let [(ch (optionOr (stringSlice line pos (+ pos 1)) ""))]
      (if (and (> pos start) (and (= ch "\"") (not escaped))) pos
        (if escaped
          (fixtureQuotedEnd line start (+ pos 1) false)
          (if (= ch "\\")
            (fixtureQuotedEnd line start (+ pos 1) true)
            (fixtureQuotedEnd line start (+ pos 1) false))))))

fn fixtureStringField content: String id: String field: String -> String
  (let [(line (fixtureLineById (stringSplit content "\n") id))
        (marker (str field " "))
        (markerPos (stringIndexOf line marker))]
    (mt markerPos
      ((none) "")
      ((some pos)
       (let [(start (+ pos (stringLength marker)))
             (end (fixtureQuotedEnd line (+ pos (stringLength marker)) (+ pos (stringLength marker)) false))]
         (let [(raw (optionOr (stringSlice line start (+ end 1)) "\"\\\""))]
           (mt (j/jsonParse raw)
             ((ok parsed) (mt parsed ((j/jstr value) value) (_ "")))
             ((err _) "")))))))

fn fixtureExpectedJson content: String id: String -> j/Json
  (resultOr (j/jsonParse (fixtureStringField content id ":want")) (j/jnull))

fn fixtureJsonPairsMatch expected: (List (Pair String j/Json)) actual: j/Json -> Bool
  (mt (listHead expected)
    ((none) true)
    ((some entry)
     (mt (j/jsonGet actual (pairFirst entry))
       ((none) false)
       ((some value)
        (and (fixtureJsonEquivalent (pairSecond entry) value)
             (fixtureJsonPairsMatch (optionOr (listTail expected) (list)) actual))))))

fn fixtureJsonListsMatch expected: (List j/Json) actual: (List j/Json) -> Bool
  (mt (listHead expected)
    ((none) (listEmpty? actual))
    ((some value)
     (mt (listHead actual)
       ((none) false)
       ((some actualValue)
        (and (fixtureJsonEquivalent value actualValue)
             (fixtureJsonListsMatch (optionOr (listTail expected) (list)) (optionOr (listTail actual) (list))))))))

fn fixtureJsonEquivalent expected: j/Json actual: j/Json -> Bool
  (mt expected
    ((j/jobj expectedPairs)
     (mt actual
       ((j/jobj actualPairs)
        (and (= (listLength expectedPairs) (listLength actualPairs))
             (fixtureJsonPairsMatch expectedPairs actual)))
       (_ false)))
    ((j/jarr expectedValues)
     (mt actual
       ((j/jarr actualValues) (fixtureJsonListsMatch expectedValues actualValues))
       (_ false)))
    (_ (= expected actual)))

fn fixtureJsonOutputMatches content: String id: String result: (Result j/Json String) -> Bool
  (mt result
    ((ok value) (fixtureJsonEquivalent (fixtureExpectedJson content id) value))
    ((err _) false))

fn testFixtureJsonRows! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-gateway/tests/cliParityFixture.asn"))
        (content (resultOr readRes ""))
        (simple (cli/cliJsonObject "{\"status\": \"ok\", \"code\": 200}"))
        (nested (cli/cliJsonObject "{\"model\": \"test\", \"details\": {\"input\": 1, \"output\": 2}}"))
        (surrounded (cli/cliJsonObject "Some logs before\n{\"valid\": true}\nTrailing logs after"))
        (escaped (cli/cliJsonObject "{\"text\": \"line1\\nline2 \\\"quoted\\\"\"}"))
        (empty (cli/cliJsonObject "{}"))
        (noJson (cli/cliJsonObject "error: something went wrong without json"))
        (arrayOnly (cli/cliJsonObject "[1, 2, 3]"))
        (malformed (cli/cliJsonObject "{\"unclosed\": 1"))]
    (do
      (assert (and (ok? readRes) (ok? simple) (fixtureCaseIncludes content "json_obj_simple" ":status :ok") (fixtureJsonOutputMatches content "json_obj_simple" simple)) "json_obj_simple fixture expected JSON equals actual parsed object")
      (assert (and (ok? nested) (fixtureCaseIncludes content "json_obj_nested" ":status :ok") (fixtureJsonOutputMatches content "json_obj_nested" nested)) "json_obj_nested fixture expected JSON equals actual parsed object")
      (assert (and (ok? surrounded) (fixtureCaseIncludes content "json_obj_surrounded" ":status :ok") (fixtureJsonOutputMatches content "json_obj_surrounded" surrounded)) "json_obj_surrounded fixture expected JSON equals actual parsed object")
      (assert (and (ok? escaped) (fixtureCaseIncludes content "json_obj_escaped" ":status :ok") (fixtureJsonOutputMatches content "json_obj_escaped" escaped)) "json_obj_escaped fixture expected JSON equals actual parsed object")
      (assert (and (ok? empty) (fixtureCaseIncludes content "json_obj_empty" ":status :ok") (fixtureJsonOutputMatches content "json_obj_empty" empty)) "json_obj_empty fixture expected JSON equals actual parsed object")
      (assert (and (err? noJson) (fixtureCaseIncludes content "json_obj_no_json" ":status :err") (fixtureCaseIncludes content "json_obj_no_json" "no JSON object in output") (= (mt noJson ((err e) e) ((ok _) "")) "no JSON object in output")) "json_obj_no_json fixture error output")
      (assert (and (err? arrayOnly) (fixtureCaseIncludes content "json_obj_array_only" ":status :err") (fixtureCaseIncludes content "json_obj_array_only" "no JSON object in output") (= (mt arrayOnly ((err e) e) ((ok _) "")) "no JSON object in output")) "json_obj_array_only fixture error output")
      (assert (and (err? malformed) (fixtureCaseIncludes content "json_obj_malformed" ":status :err") (= (mt malformed ((err e) e) ((ok _) "")) (fixtureStringField content "json_obj_malformed" ":want"))) (str "json_obj_malformed expected " (fixtureStringField content "json_obj_malformed" ":want") " but got " (mt malformed ((err e) e) ((ok _) ""))))
      true))

fn fixtureUsageMatches content: String id: String usage: (Option cli/CliUsage) -> Bool
  (mt usage
    ((none) (fixtureCaseIncludes content id ":usage :none"))
    ((some u)
     (and
       (fixtureCaseIncludes content id (str ":input " (stringFromInt64 u.inputTokens)))
       (fixtureCaseIncludes content id (str ":cached " (stringFromInt64 u.cachedTokens)))
       (fixtureCaseIncludes content id (str ":output " (stringFromInt64 u.outputTokens))))))

fn fixtureParseMatches content: String id: String result: cli/CliParseResult -> Bool
  (and
    (fixtureFieldMatches content id ":text" result.text)
    (fixtureUsageMatches content id result.usage)
    (fixtureCaseIncludes content id (str ":dedup " (if result.dedup "true" "false"))))

fn testFixtureExistingParseRows! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-gateway/tests/cliParityFixture.asn"))
        (content (resultOr readRes ""))
        (claudeMu "{\"result\": \"Answer from Claude MU\", \"modelUsage\": {\"claude-3-5\": {\"inputTokens\": 100, \"cacheCreationInputTokens\": 20, \"cacheReadInputTokens\": 10, \"outputTokens\": 50}}}")
        (claudeStandard "{\"result\": \"Answer from Claude standard\", \"usage\": {\"input_tokens\": 80, \"cache_creation_input_tokens\": 15, \"cache_read_input_tokens\": 5, \"output_tokens\": 30}}")
        (claudeNoUsage "{\"result\": \"Answer no usage\"}")
        (claudeExtra "Init line\n{\"result\": \"Clean answer\", \"usage\": {\"input_tokens\": 5, \"output_tokens\": 5}}\nEnd line")
        (claudeInvalid "Error: server disconnected")
        (codexStandard "{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 200, \"cached_input_tokens\": 50, \"output_tokens\": 75}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"Codex answer 1\"}}")
        (codexMulti "{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 100, \"cached_input_tokens\": 20, \"output_tokens\": 40}}\n{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 50, \"cached_input_tokens\": 10, \"output_tokens\": 20}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"Multi turn answer\"}}")
        (codexNoMsg "{\"type\": \"turn.completed\", \"usage\": {\"input_tokens\": 10, \"cached_input_tokens\": 0, \"output_tokens\": 5}}")
        (codexNoUsage "{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"Only message\"}}")
        (codexNoise "{\"type\": \"init\"}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"other\"}}\n{\"type\": \"item.completed\", \"item\": {\"type\": \"agent_message\", \"text\": \"After noise\"}}")
        (codexInvalid "Codex error: internal failure")
        (agyStandard "{\"response\": \"Agy answer 1\", \"usage\": {\"input_tokens\": 300, \"cache_read_tokens\": 40, \"output_tokens\": 100, \"thinking_tokens\": 20}}")
        (agyDedup "{\"response\": \"Repeated response\\nRepeated response\", \"usage\": {\"input_tokens\": 50, \"cache_read_tokens\": 0, \"output_tokens\": 20, \"thinking_tokens\": 0}}")
        (agyEven "{\"response\": \"Even length text! Even length text!\", \"usage\": {\"input_tokens\": 10, \"cache_read_tokens\": 0, \"output_tokens\": 10, \"thinking_tokens\": 0}}")
        (agyNoUsage "{\"response\": \"Agy no usage\"}")
        (agyInvalid "Agy crashed with signal 11")
        (claudeMuRes (cli/cliParseResult "claude" claudeMu))
        (claudeStandardRes (cli/cliParseResult "claude" claudeStandard))
        (claudeNoUsageRes (cli/cliParseResult "claude" claudeNoUsage))
        (claudeExtraRes (cli/cliParseResult "claude" claudeExtra))
        (claudeInvalidRes (cli/cliParseResult "claude" claudeInvalid))
        (codexStandardRes (cli/cliParseResult "codex" codexStandard))
        (codexMultiRes (cli/cliParseResult "codex" codexMulti))
        (codexNoMsgRes (cli/cliParseResult "codex" codexNoMsg))
        (codexNoUsageRes (cli/cliParseResult "codex" codexNoUsage))
        (codexNoiseRes (cli/cliParseResult "codex" codexNoise))
        (codexInvalidRes (cli/cliParseResult "codex" codexInvalid))
        (agyStandardRes (cli/cliParseResult "agy" agyStandard))
        (agyDedupRes (cli/cliParseResult "agy" agyDedup))
        (agyEvenRes (cli/cliParseResult "agy" agyEven))
        (agyNoUsageRes (cli/cliParseResult "agy" agyNoUsage))
        (agyInvalidRes (cli/cliParseResult "agy" agyInvalid))]
    (do
      (assert (and (ok? readRes) (fixtureParseMatches content "parse_claude_model_usage" claudeMuRes)) "parse_claude_model_usage fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_claude_usage" claudeStandardRes) "parse_claude_usage fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_claude_no_usage" claudeNoUsageRes) "parse_claude_no_usage fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_claude_extra_logs" claudeExtraRes) "parse_claude_extra_logs fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_claude_invalid" claudeInvalidRes) "parse_claude_invalid fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_standard" codexStandardRes) "parse_codex_standard fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_multi_turn" codexMultiRes) "parse_codex_multi_turn fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_no_msg" codexNoMsgRes) "parse_codex_no_msg fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_no_usage" codexNoUsageRes) "parse_codex_no_usage fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_other_events" codexNoiseRes) "parse_codex_other_events fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_codex_invalid" codexInvalidRes) "parse_codex_invalid fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_agy_standard" agyStandardRes) "parse_agy_standard fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_agy_dedup" agyDedupRes) "parse_agy_dedup fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_agy_no_dedup_even" agyEvenRes) "parse_agy_no_dedup_even fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_agy_no_usage" agyNoUsageRes) "parse_agy_no_usage fixture fields match actual parser")
      (assert (fixtureParseMatches content "parse_agy_invalid" agyInvalidRes) "parse_agy_invalid fixture fields match actual parser")
      true))

fn testPromptFixtureRows! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-gateway/tests/cliParityFixture.asn"))
        (content (resultOr readRes ""))
        (suffix (stringFromInt64 (nowNs)))
        (agyRoot (str "/tmp/asl-gw-fixture-agy-" suffix))
        (agyNoToolsRoot (str "/tmp/asl-gw-fixture-agy-no-tools-" suffix))
        (claudeRoot (str "/tmp/asl-gw-fixture-claude-" suffix))
        (codexRoot (str "/tmp/asl-gw-fixture-codex-" suffix))
        (agySetup (dirCreate agyRoot))
        (agyNoToolsSetup (dirCreate agyNoToolsRoot))
        (claudeSetup (dirCreate claudeRoot))
        (codexSetup (dirCreate codexRoot))]
    (do
      (assert (and (ok? readRes) (ok? agySetup) (ok? agyNoToolsSetup) (ok? claudeSetup) (ok? codexSetup)) "prompt fixture inputs and output roots are available")
      (let [(agyRes (cli/cliWritePromptDirAt! "agy" "System prompt for agy" false agyRoot))
            (agyNoToolsRes (cli/cliWritePromptDirAt! "agy" "System prompt no tools" true agyNoToolsRoot))
            (claudeRes (cli/cliWritePromptDirAt! "claude" "Claude system prompt" false claudeRoot))
            (codexRes (cli/cliWritePromptDirAt! "codex" "Codex system prompt" false codexRoot))]
        (assert (and (ok? agyRes) (fixtureFieldMatches content "prompt_dir_agy_default_md" ":want" (resultOr (fileReadString (resultOr agyRes (cli/CliPromptDir :tmpDir "" :promptPath "")).promptPath) ""))) "agy default prompt fixture want matches written Markdown")
        (assert (and (ok? (fileReadString (str agyRoot "/.agents/plugins/aslGateway/plugin.json"))) (fixtureFieldMatches content "prompt_dir_agy_plugin_json" ":want" (resultOr (fileReadString (str agyRoot "/.agents/plugins/aslGateway/plugin.json")) ""))) "agy plugin fixture want matches written plugin metadata")
        (assert (and (ok? agyNoToolsRes) (fixtureFieldMatches content "prompt_dir_agy_no_tools_md" ":want" (resultOr (fileReadString (resultOr agyNoToolsRes (cli/CliPromptDir :tmpDir "" :promptPath "")).promptPath) ""))) "agy no-tools prompt fixture want matches written Markdown")
        (assert (and (ok? claudeRes) (fixtureFieldMatches content "prompt_dir_claude" ":want" (resultOr (fileReadString (resultOr claudeRes (cli/CliPromptDir :tmpDir "" :promptPath "")).promptPath) ""))) "Claude prompt fixture want matches written file")
        (assert (and (ok? codexRes) (fixtureFieldMatches content "prompt_dir_codex" ":want" (resultOr (fileReadString (resultOr codexRes (cli/CliPromptDir :tmpDir "" :promptPath "")).promptPath) ""))) "Codex prompt fixture want matches written file"))
      (pathRemove agyRoot)
      (pathRemove agyNoToolsRoot)
      (pathRemove claudeRoot)
      (pathRemove codexRoot)
      true))

fn testPromptDirFailures! -> Bool
  (let [(root (str "/tmp/asl-gw-write-fail-" (stringFromInt64 (nowNs))))
        (obstruction (str root "-file"))
        (writePluginRoot (str root "-plugin"))
        (writePromptRoot (str root "-prompt"))
        (setupObstruction (fileWrite obstruction "not a directory"))
        (setupPluginDir (dirCreate (str writePluginRoot "/.agents/plugins/aslGateway/plugin.json")))
        (setupPromptDir (dirCreate (str writePromptRoot "/.agents/plugins/aslGateway/agents/aslGateway.md")))]
    (do
      (assert (ok? setupObstruction) "directory failure fixture file is created")
      (assert (ok? setupPluginDir) "plugin write failure fixture directory is created")
      (assert (ok? setupPromptDir) "prompt write failure fixture directory is created")
      (let [(dirRes (cli/cliWritePromptDirAt! "agy" "directory error prompt" false obstruction))
            (pluginRes (cli/cliWritePromptDirAt! "agy" "plugin write error prompt" false writePluginRoot))
            (promptRes (cli/cliWritePromptDirAt! "agy" "prompt write error prompt" false writePromptRoot))]
        (assert (and (err? dirRes) (stringStartsWith? (mt dirRes ((err e) e) ((ok _) "")) "failed to create agents dir:")) "prompt setup propagates directory creation failure")
        (assert (and (err? pluginRes) (stringStartsWith? (mt pluginRes ((err e) e) ((ok _) "")) "failed to write plugin.json:")) "prompt setup propagates plugin.json write failure")
        (assert (and (err? promptRes) (stringStartsWith? (mt promptRes ((err e) e) ((ok _) "")) "failed to write aslGateway.md:")) "prompt setup propagates agent markdown write failure"))
      true))

fn ! runTests -> Bool
  (and (testMessageTextParity)
  (and (testAgyToolsParity!)
  (and (testWritePromptDirParity!)
  (and (testJsonObjectParity)
  (and (testParseResultParity)
  (and (testResolveCliBinParity!)
  (and (testBuildCmdParity!)
  (and (testDispatchAgainstStubs!)
  (and (testTimeoutAndSetsidKill!)
       (and (testFixtureCorpusVerification!)
       (and (testFixtureJsonRows!)
       (and (testFixtureExistingParseRows!)
       (and (testPromptFixtureRows!)
            (testPromptDirFailures!))))))))))))))
