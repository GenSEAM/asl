(module aslAgent/liveAppTest :x [testLiveGameSpecification testLiveGameExecutionLoop! testLiveGameTuiTelemetry runTests] :i [(policy :a pol) (agent :a ag) (feedback :a fb) (tui :a tui) (eddie :a ed)])

"run: (run-tests)"

fn testLiveGameSpecification -> Bool
  (let [(rawPrompt "Please build a terminal snake game with collision detection and unit tests.") (req (fb/refineUserPrompt rawPrompt (list "asl/packages/asl-agent/tests/fixtures/test-app/src/snake.asl" "asl/packages/asl-agent/tests/fixtures/test-app/tests/snake-test.asl")))] (assert (not req.isAmbiguous) "game specification is unambiguous") (assert (= (listLength req.targetFiles) 2) "two target files") (assert (stringContains? req.clarifiedGoal "terminal snake game") "contains goal text") true)

fn testLiveGameExecutionLoop! -> Bool
  (let [(ws "asl/packages/asl-agent/tests/fixtures/test-app") (m (pol/makeManifest ws (list) "/tmp" false)) (sess (ag/makeAutonomySession "build snake game" m (pol/levelAuto))) (s1 (ag/stepAgent! sess "read" (str ws "/src/snake.asl") "")) (s2 (ag/stepAgentWithHostCall! s1.session "test" (str ws "/tests/snake-test.asl") "" (fn [(cap Str) (act Str) (target Str)] -> (Result Str Str) (if (and (= cap "exec") (and (= act "exec") (= target (str ws "/tests/snake-test.asl")))) (ok "fake runner: snake-test 5/5 assertions passed") (err "unexpected runner request"))))) (s3 (ag/stepAgent! s2.session "finish" "" "Snake game engine and tests verified passing"))] (assert s1.success "step 1 read succeeded") (assert s2.success "step 2 test succeeded against the fake runner") (assert (= s2.actionTaken "executed:test") "test capability was dispatched") (assert (= s2.observation "fake runner: snake-test 5/5 assertions passed") "step 2 preserves the runner observation") (assert s3.success "step 3 finish succeeded") (assert s3.session.state.isTerminal "terminal state reached") true)

fn testLiveGameTuiTelemetry -> Bool
  (let [(h (tui/makeTuiHeader "gemma-4-31b-it" (pol/levelAuto))) (folding1 (tui/formatToolCall "read" "src/snake.asl" "ok (60 lines)")) (folding2 (tui/formatToolCall "test" "tests/snake-test.asl" "passing (5/5 assertions)")) (summary (tui/formatSessionSummary h 3))] (assert (stringContains? (tui/formatTuiHeader h) "Addie TUI") "header contains Addie TUI") (assert (stringContains? folding1 "[>] [read]") "folding contains read tool") (assert (stringContains? folding2 "[>] [test]") "folding contains test tool") (assert (stringContains? summary "[OK] Session complete") "summary contains Session complete") true)

fn ! runTests -> Bool
  (do (testLiveGameSpecification) (testLiveGameExecutionLoop!) (testLiveGameTuiTelemetry) true)
