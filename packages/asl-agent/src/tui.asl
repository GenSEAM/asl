(module aslAgent/tui :x [TuiHeader MeshNodeStats makeTuiHeader makeTuiHeaderWithMode formatTuiHeader formatToolCall formatToolCallFold formatSpinnerStatus formatChatMsg formatAgentBadge formatThinkingBlock formatReflectionChannel formatMeshTelemetry formatContextBar formatDiffPreview formatContextAndDiffBar formatSessionSummary parseCliArgs composeCockpitFrame composeIntelCockpitFrame renderFullCockpitTui renderIntelCockpitTui main] :i [(policy :a pol) (cli :a cli) (asl-ui/terminalCanvas :a tc) (asl-ui/terminalObservatory :a to) (asl-ui/radarCard :a rc) (asl-ui/blastRadiusHeatmap :a hm) (asl-ui/sessionTile :a sess) (aslAgent/tuiWorkspaceRouter :a r)])

(schema TuiHeader (:f modelName Str) (:f pipelineMode Str) (:f autonomy pol/AutonomyLevel) (:f promptTokens I64) (:f completionTokens I64) (:f sessionCost F64))

fn makeTuiHeader modelName: Str autonomy: pol/AutonomyLevel -> TuiHeader
  (TuiHeader :modelName modelName :pipelineMode "standard" :autonomy autonomy :promptTokens 0 :completionTokens 0 :sessionCost 0.0)

fn makeTuiHeaderWithMode modelName: Str mode: Str autonomy: pol/AutonomyLevel -> TuiHeader
  (TuiHeader :modelName modelName :pipelineMode mode :autonomy autonomy :promptTokens 0 :completionTokens 0 :sessionCost 0.0)

fn formatTuiHeader header: TuiHeader -> Str
  (let [(totalTokens (+ header.promptTokens header.completionTokens)) (lvlStr (pol/autonomyLevelToString header.autonomy))] (str "+-- [Addie TUI: Orchestration Window] Model: " header.modelName " | Mode: " header.pipelineMode " | Autonomy: " lvlStr " | Tokens: " (stringFromInt64 totalTokens) " | Cost: $" (stringSlice (stringFromFloat64 header.sessionCost) 0 6) " --+"))

fn formatAgentBadge role: Str alias: Str model: Str -> Str
  (str "  [Agent: " role "] routed to alias :" alias " (" model ")")

(schema MeshNodeStats (:f alias Str) (:f role Str) (:f tokens I64) (:f latencyMs I64))

fn formatMeshTelemetry scoutTok: I64 coderTok: I64 reviewerTok: I64 latencyMs: I64 -> Str
  (str "  [Mesh Telemetry] :scout: " (stringFromInt64 scoutTok) " tok" " | :coder: " (stringFromInt64 coderTok) " tok" " | :reviewer: " (stringFromInt64 reviewerTok) " tok" " | Latency: " (stringFromInt64 latencyMs) "ms")

fn formatThinkingBlock think: Str -> Str
  (str "  [Quarantined Reasoning Channel]\n     | " (stringTrim think))

fn formatReflectionChannel thought: Str -> Str
  (str "  [Quarantined Reflection Channel]: " (stringTrim thought))

fn formatContextBar current: I64 limit: I64 -> Str
  (let [(pct (if (> limit 0) (/ (* current 100) limit) 0))] (str "  [Context: " (stringFromInt64 current) " / " (stringFromInt64 limit) " tok (" (stringFromInt64 pct) "%)]"))

fn formatDiffPreview path: Str added: I64 removed: I64 -> Str
  (str "  DELTA [" path "] +" (stringFromInt64 added) " -" (stringFromInt64 removed) " lines")

fn formatContextAndDiffBar current: I64 limit: I64 path: Str added: I64 removed: I64 -> Str
  (str (formatContextBar current limit) " " (formatDiffPreview path added removed))

fn formatToolCall tool: Str target: Str status: Str -> Str
  (str "  [>] [" tool "] " target " -> " status)

fn formatToolCallFold tool: Str target: Str status: Str isFolded: Bool detail: Str -> Str
  (if isFolded (str "  [>] [" tool "] " target " -> " status) (str "  [v] [" tool "] " target " -> " status "\n     " detail))

fn formatSpinnerStatus action: Str -> Str
  (str "  [~] " action "...")

fn formatChatMsg role: Str content: Str -> Str
  (if (= role "user") (str "\n> " content) (str "\n[*] " (stringTrim content)))

fn formatSessionSummary header: TuiHeader turns: I64 -> Str
  (let [(totalToks (+ header.promptTokens header.completionTokens))] (str "\n[OK] Session complete (" (stringFromInt64 turns) " turns). Total tokens: " (stringFromInt64 totalToks) " ($" (stringSlice (stringFromFloat64 header.sessionCost) 0 6) ")"))

fn parseCliArgs args: (List Str) -> (Result cli/CliOptions Str)
  (cli/parseCliArgs args)

fn renderProjectListLoop buf: tc/TerminalBuffer projects: (List r/ProjectItem) idx: Int64 len: Int64 selectedIdx: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(p (optionOr (listGet projects idx) (r/makeProjectItem "" "" "" false)))
          (prefix (if (= idx selectedIdx) "> " "  "))
          (lineText (str prefix p.name))
          (col (if (= idx selectedIdx) "cyan" "default"))
          (nextBuf (tc/drawText buf x (+ y idx) lineText col "default" (= idx selectedIdx)))]
      (renderProjectListLoop nextBuf projects (+ idx 1) len selectedIdx x y)))

fn renderTaskListLoop buf: tc/TerminalBuffer tasks: (List r/TaskItem) idx: Int64 len: Int64 selectedIdx: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(t (optionOr (listGet tasks idx) (r/makeTaskItem "" "" "" false)))
          (prefix (if (= idx selectedIdx) "> " "  "))
          (lineText (str prefix t.id " " t.status))
          (col (if (= idx selectedIdx) "yellow" "default"))
          (nextBuf (tc/drawText buf x (+ y idx) lineText col "default" (= idx selectedIdx)))]
      (renderTaskListLoop nextBuf tasks (+ idx 1) len selectedIdx x y)))

fn composeIntelCockpitFrame state: r/TuiRouterState -> tc/TerminalBuffer
  (let [(w 80)
        (h 24)
        (buf0 (tc/makeTerminalBuffer w h))
        (hdrText "Sovereign Cockpit TUI | Focus: [asl-intel DAG] | Autonomous Mesh v0")
        (buf1 (tc/drawBorder buf0 0 0 w 3 "" "double" "cyan" "default"))
        (buf2 (tc/drawText buf1 2 1 hdrText "cyan" "default" true))
        (pkg1 (to/makePackageCouplingItem "asl-parser" 21 0 0.0 "foundation" "verified"))
        (pkg2 (to/makePackageCouplingItem "asl-checker" 12 1 0.077 "foundation" "verified"))
        (pkg3 (to/makePackageCouplingItem "asl-ir" 11 1 0.083 "foundation" "verified"))
        (pkg4 (to/makePackageCouplingItem "asl-compiler" 4 8 0.667 "bridge" "verified"))
        (pkg5 (to/makePackageCouplingItem "asl-ui" 1 2 0.667 "bridge" "verified"))
        (pkg6 (to/makePackageCouplingItem "asl-intel" 0 3 1.0 "orchestrator" "verified"))
        (buf3 (to/renderTerminalCouplingMatrix buf2 0 3 48 10 (list pkg1 pkg2 pkg3 pkg4 pkg5 pkg6)))
        (buf4 (to/renderTerminalIntelTile buf3 48 3 32 10 46 327 0 0))
        (node1 (hm/makeBlastRadiusNode "asl-parser" 21 false false))
        (node2 (hm/makeBlastRadiusNode "asl-checker" 12 false false))
        (node3 (hm/makeBlastRadiusNode "asl-compiler" 8 false false))
        (node4 (hm/makeBlastRadiusNode "asl-intel" 3 false false))
        (buf5 (to/renderTerminalHeatmap buf4 0 13 48 7 (list node1 node2 node3 node4)))
        (snap (rc/makeRadarSnapshot 98 96 95 94 96 97 "c0ckp1t0"))
        (buf6 (to/renderTerminalRadarCard buf5 48 13 32 7 snap))
        (promptTitle "Intel Command (Enter: Analyze Impact | :q Exit)")
        (buf7 (tc/drawBorder buf6 0 20 w 4 promptTitle "single" "cyan" "default"))
        (pText (str "> " state.promptBuffer "_"))
        (buf8 (tc/drawText buf7 2 22 pText "cyan" "default" true))]
    buf8)

fn renderIntelCockpitTui state: r/TuiRouterState -> Str
  (let [(frameBuf (composeIntelCockpitFrame state))
        (canvas (tc/TerminalCanvas :width 80 :height 24 :frontBuffer (tc/makeTerminalBuffer 80 24) :backBuffer frameBuf))]
    (tc/renderAnsiDiff canvas))

fn composeCockpitFrame state: r/TuiRouterState -> tc/TerminalBuffer
  (let [(focusStr (r/focusTargetToString state.focus))]
    (if (= focusStr "observatory")
      (composeIntelCockpitFrame state)
      (let [(w 80)
            (h 24)
            (buf0 (tc/makeTerminalBuffer w h))
            (hdrText (str "Sovereign Cockpit TUI | Focus: [" focusStr "] | Autonomous Mesh v0"))
            (buf1 (tc/drawBorder buf0 0 0 w 3 "" "single" "cyan" "default"))
            (buf2 (tc/drawText buf1 2 1 hdrText "cyan" "default" true))
            (isWsFocus (or (= focusStr "workspace") (= focusStr "project")))
            (wsStyle (if isWsFocus "double" "single"))
            (wsCol (if isWsFocus "cyan" "default"))
            (buf3 (tc/drawBorder buf2 0 3 26 10 "Projects" wsStyle wsCol "default"))
            (buf4 (renderProjectListLoop buf3 state.projects 0 (listLength state.projects) state.selectedProjectIdx 2 5))
            (isTaskFocus (= focusStr "tasks"))
            (taskStyle (if isTaskFocus "double" "single"))
            (taskCol (if isTaskFocus "yellow" "default"))
            (buf5 (tc/drawBorder buf4 26 3 28 10 "Tasks" taskStyle taskCol "default"))
            (buf6 (renderTaskListLoop buf5 state.tasks 0 (listLength state.tasks) state.selectedTaskIdx 28 5))
            (snap (rc/makeRadarSnapshot 94 90 92 88 95 86 "19f19b4f"))
            (buf7 (to/renderTerminalRadarCard buf6 54 3 26 10 snap))
            (node1 (hm/makeBlastRadiusNode "asl-parser" 21 false false))
            (node2 (hm/makeBlastRadiusNode "asl-core" 12 false false))
            (node3 (hm/makeBlastRadiusNode "asl-intel" 3 false false))
            (node4 (hm/makeBlastRadiusNode "asl-ui" 2 false false))
            (buf8 (to/renderTerminalHeatmap buf7 0 13 40 7 (list node1 node2 node3 node4)))
            (sess1 (sess/makeSessionCardItem "steel-01" "Steel Crawler" 1 false (sess/statusRunning) "Crawling Docs"))
            (sess2 (sess/makeSessionCardItem "chrome-01" "Chrome SaaS" 3 true (sess/statusActive) "PR Review"))
            (buf9 (to/renderTerminalSessionTile buf8 40 13 40 7 (list sess1 sess2)))
            (isPromptFocus (= focusStr "omniPrompt"))
            (promptStyle (if isPromptFocus "double" "single"))
            (promptCol (if isPromptFocus "magenta" "default"))
            (promptTitle "OmniPrompt (Tab: Cycle Focus | Enter: Dispatch)")
            (buf10 (tc/drawBorder buf9 0 20 w 4 promptTitle promptStyle promptCol "default"))
            (pText (str "> " state.promptBuffer "_"))
            (buf11 (tc/drawText buf10 2 22 pText promptCol "default" true))]
        buf11)))

fn renderFullCockpitTui state: r/TuiRouterState -> Str
  (let [(frameBuf (composeCockpitFrame state))
        (canvas (tc/TerminalCanvas :width 80 :height 24 :frontBuffer (tc/makeTerminalBuffer 80 24) :backBuffer frameBuf))]
    (tc/renderAnsiDiff canvas))

fn ! main args: (List Str) -> (Result Unit Str)
  (if (or (listEmpty? args) (or (= (optionOr (listHead args) "") "--cockpit") (or (= (optionOr (listHead args) "") "--tui") (or (= (optionOr (listHead args) "") "--intel") (= (optionOr (listHead args) "") "--coupling")))))
    (let [(state (r/makeInitialRouterState!))
          (isIntel (or (= (optionOr (listHead args) "") "--intel") (= (optionOr (listHead args) "") "--coupling")))
          (frame (if isIntel (renderIntelCockpitTui state) (renderFullCockpitTui state)))]
      (print frame)
      (ok ()))
    (cli/main args))
