(module aslAgent/tuiTest :x [testTuiHeaderRendering testOrchestrationWindowHeader testTuiOrchestrationWindow testToolCallFolding testToolCallFoldingSummary testSpinnerFormatting testChatMsgFormatting testSessionSummary testReflectionChannel testMeshTelemetry testCockpitFrameCouplingIntegration! runTests] :i [(tui :a tui) (policy :a pol) (aslAgent/tuiWorkspaceRouter :a r) (asl-ui/terminalCanvas :a tc)])

fn testTuiHeaderRendering -> Bool
  (let [(h (tui/makeTuiHeader "gemma-4-31b-it" (pol/levelGuarded))) (rendered (tui/formatTuiHeader h))] (assert (stringContains? rendered "Addie TUI") "contains Addie TUI") (assert (stringContains? rendered "gemma-4-31b-it") "contains model") (assert (stringContains? rendered "L1:Guarded") "contains level") (assert (not (stringContains? rendered "L0:Autonomous")) "does not contain L0") true)

fn testOrchestrationWindowHeader -> Bool
  (let [(hdr (tui/makeTuiHeaderWithMode "gemma-4-31b-it" "fast" (pol/levelGuarded))) (rendered (tui/formatTuiHeader hdr))] (assert (= hdr.pipelineMode "fast") "pipeline mode is fast") (assert (stringContains? rendered "Model: gemma-4-31b-it") "contains model") (assert (stringContains? rendered "Mode: fast") "contains fast mode") (assert (not (stringContains? rendered "Mode: deep")) "does not contain deep mode") true)

fn testToolCallFolding -> Bool
  (let [(line (tui/formatToolCall "read_file" "src/agent.asl" "ok (120 lines)"))] (assert (stringContains? line "[>] [read_file]") "contains arrow and tool name") (assert (stringContains? line "src/agent.asl -> ok") "contains path and status") (assert (not (stringContains? line "write_file")) "does not contain write_file") true)

fn testToolCallFoldingSummary -> Bool
  (let [(folded (tui/formatToolCallFold "asl:test" "batch_test.asl" "passed" true "Detail omitted")) (unfolded (tui/formatToolCallFold "asl:test" "batch_test.asl" "passed" false "10 passed in 45ms"))] (assert (stringContains? folded "[>] [asl:test] batch_test.asl -> passed") "folded header matches") (assert (not (stringContains? folded "Detail omitted")) "folded detail omitted") (assert (stringContains? unfolded "[v] [asl:test] batch_test.asl -> passed") "unfolded header matches") (assert (stringContains? unfolded "10 passed in 45ms") "unfolded detail present") true)

fn testSpinnerFormatting -> Bool
  (let [(s (tui/formatSpinnerStatus "Executing verification gates"))] (assert (stringContains? s "[~] Executing verification gates...") "contains spinner message") (assert (not (stringContains? s "Idle")) "does not contain Idle") true)

fn testChatMsgFormatting -> Bool
  (let [(u (tui/formatChatMsg "user" "Refactor policy.asl")) (a (tui/formatChatMsg "assistant" "Policy updated. 0 syntax errors."))] (assert (stringStartsWith? u "\n> Refactor") "user message starts with prompt arrow") (assert (stringStartsWith? a "\n[*] Policy updated.") "assistant message starts with diamond") (assert (not (stringContains? u "Error")) "user message has no error") true)

fn testSessionSummary -> Bool
  (let [(h (tui/makeTuiHeader "qwen3:4b" (pol/levelAuto))) (s (tui/formatSessionSummary h 4))] (assert (stringContains? s "Session complete (4 turns)") "contains session complete") (assert (not (stringContains? s "Aborted")) "does not contain aborted") true)

fn testAgentBadge -> Bool
  (let [(b (tui/formatAgentBadge "planner" "fable" "claude-fable-5-1"))] (assert (stringContains? b "[Agent: planner]") "contains agent role") (assert (stringContains? b "alias :fable") "contains alias") (assert (not (stringContains? b "executor")) "does not contain executor") true)

fn testThinkingBlock -> Bool
  (let [(tb (tui/formatThinkingBlock "Reasoning about AST tree"))] (assert (stringContains? tb "[Quarantined Reasoning Channel]") "contains header") (assert (stringContains? tb "Reasoning about AST tree") "contains reasoning content") (assert (not (stringContains? tb "Unfiltered")) "does not contain unfiltered") true)

fn testContextBar -> Bool
  (let [(cb (tui/formatContextBar 4096 131072))] (assert (stringContains? cb "[Context:") "contains context header") (assert (stringContains? cb "4096 / 131072") "contains tokens count") (assert (not (stringContains? cb "Overflow")) "does not contain overflow") true)

fn testReflectionChannel -> Bool
  (let [(rc (tui/formatReflectionChannel "Epistemic calibration and fact reconciliation"))] (assert (stringContains? rc "[Quarantined Reflection Channel]") "contains reflection header") (assert (stringContains? rc "Epistemic calibration") "contains text") (assert (not (stringContains? rc "Hallucination")) "does not contain hallucination") true)

fn testMeshTelemetry -> Bool
  (let [(mt (tui/formatMeshTelemetry 120 450 85 45))] (assert (stringContains? mt "[Mesh Telemetry]") "contains mesh telemetry header") (assert (stringContains? mt ":scout: 120 tok") "contains scout tokens") (assert (stringContains? mt ":coder: 450 tok") "contains coder tokens") (assert (stringContains? mt ":reviewer: 85 tok") "contains reviewer tokens") true)

fn testDiffPreview -> Bool
  (let [(dp (tui/formatDiffPreview "src/main.asl" 12 3))] (assert (stringContains? dp "DELTA [src/main.asl]") "contains diff header") (assert (stringContains? dp "+12 -3 lines") "contains line counts") (assert (not (stringContains? dp "conflict")) "does not contain conflict") true)

fn testTuiOrchestrationWindow -> Bool
  (let [(hdr (tui/makeTuiHeaderWithMode "gemma-4-31b-it" "fast" (pol/levelGuarded))) (hStr (tui/formatTuiHeader hdr)) (rStr (tui/formatReflectionChannel "Epistemic anchor active")) (tStr (tui/formatToolCall "read" "gsa/src/tui.asl" "completed")) (cStr (tui/formatContextAndDiffBar 4096 131072 "gsa/src/tui.asl" 15 2))] (assert (stringContains? hStr "Addie TUI: Orchestration Window") "contains window header") (assert (stringContains? hStr "Autonomy: ") "contains autonomy label") (assert (stringContains? rStr "[Quarantined Reflection Channel]:") "contains reflection prefix") (assert (stringContains? tStr "[>] [read]") "contains tool call prefix") (assert (stringContains? cStr "[Context:") "contains context bar") (assert (stringContains? cStr "DELTA [") "contains diff indicator") true)

fn testCockpitFrameCouplingIntegration! -> Bool
  (let [(state (r/makeInitialRouterState!))
        (frameStandard (tui/composeCockpitFrame state))
        (frameIntel (tui/composeIntelCockpitFrame state))
        (renderedStd (tui/renderFullCockpitTui state))
        (renderedIntel (tui/renderIntelCockpitTui state))]
    (assert (= frameStandard.width 80) "Standard cockpit frame width is 80")
    (assert (= frameStandard.height 24) "Standard cockpit frame height is 24")
    (assert (= frameIntel.width 80) "Intel cockpit frame width is 80")
    (assert (= frameIntel.height 24) "Intel cockpit frame height is 24")
    (assert (= (tc/getCell frameStandard 2 1).ch "S") "Standard frame title starts with S")
    (assert (= (tc/getCell frameIntel 2 1).ch "S") "Intel frame title starts with S")
    (assert (stringContains? renderedStd "\x1b[") "Rendered standard TUI contains ANSI cursor codes")
    (assert (stringContains? renderedIntel "\x1b[") "Rendered Intel TUI contains ANSI cursor codes")
    (assert (not (stringEmpty? renderedStd)) "Standard TUI ANSI output is not empty")
    (assert (not (stringEmpty? renderedIntel)) "Intel TUI ANSI output is not empty")
    true)

fn ! runTests -> Bool
  (do (testTuiHeaderRendering) (testOrchestrationWindowHeader) (testToolCallFolding) (testToolCallFoldingSummary) (testSpinnerFormatting) (testChatMsgFormatting) (testSessionSummary) (testAgentBadge) (testThinkingBlock) (testReflectionChannel) (testMeshTelemetry) (testContextBar) (testDiffPreview) (testTuiOrchestrationWindow) (testCockpitFrameCouplingIntegration!) true)
