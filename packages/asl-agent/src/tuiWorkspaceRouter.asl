(module aslAgent/tuiWorkspaceRouter :x [TuiFocusTarget focusWorkspace focusProject focusTasks focusObservatory focusOmniPrompt focusTargetToString WorkspaceItem makeWorkspaceItem ProjectItem makeProjectItem TaskItem makeTaskItem TuiRouterState makeInitialRouterState! cycleFocusForward cycleFocusBackward selectNextItem selectPrevItem formatOmniIntentPayload setPromptBuffer clearPromptBuffer] :i [])

(enum TuiFocusTarget
  (:c focusWorkspace [] "Focus on active workspace list")
  (:c focusProject [] "Focus on project explorer")
  (:c focusTasks [] "Focus on task collection and status list")
  (:c focusObservatory [] "Focus on audit observatory tiles")
  (:c focusOmniPrompt [] "Focus on bottom natural language command bar"))

(schema WorkspaceItem
  (:f id String)
  (:f uri String)
  (:f isCurrent Bool)
  (:f projectCount Int64))

(schema ProjectItem
  (:f id String)
  (:f name String)
  (:f path String)
  (:f isCurrent Bool))

(schema TaskItem
  (:f id String)
  (:f title String)
  (:f status String)
  (:f isCurrent Bool))

(schema TuiRouterState
  (:f focus TuiFocusTarget)
  (:f workspaces (List WorkspaceItem))
  (:f selectedWorkspaceIdx Int64)
  (:f projects (List ProjectItem))
  (:f selectedProjectIdx Int64)
  (:f tasks (List TaskItem))
  (:f selectedTaskIdx Int64)
  (:f promptBuffer String)
  (:f statusMessage String))

fn focusTargetToString f: TuiFocusTarget -> String
  (mt f
    ((focusWorkspace) "workspace")
    ((focusProject) "project")
    ((focusTasks) "tasks")
    ((focusObservatory) "observatory")
    ((focusOmniPrompt) "omniPrompt"))

fn makeWorkspaceItem id: String uri: String isCurrent: Bool count: Int64 -> WorkspaceItem
  (WorkspaceItem :id id :uri uri :isCurrent isCurrent :projectCount count)

fn makeProjectItem id: String name: String path: String isCurrent: Bool -> ProjectItem
  (ProjectItem :id id :name name :path path :isCurrent isCurrent)

fn makeTaskItem id: String title: String status: String isCurrent: Bool -> TaskItem
  (TaskItem :id id :title title :status status :isCurrent isCurrent)

fn makeInitialRouterState! -> TuiRouterState
  (let [(workspaceUri (optionOr (envGet "PWD") "."))
        (w1 (makeWorkspaceItem "ws-asex" workspaceUri true 4))
        (p1 (makeProjectItem "proj-asl-core" "asl-core" "asl/packages/asl-core" true))
        (p2 (makeProjectItem "proj-asl-ui" "asl-ui" "asl/packages/asl-ui" false))
        (p3 (makeProjectItem "proj-asl-gw" "asl-gateway" "asl/packages/asl-gateway" false))
        (p4 (makeProjectItem "proj-agent" "agent" "agent" false))
        (t1 (makeTaskItem "TASK-612-01" "Terminal Canvas" "[OK] Verified" true))
        (t2 (makeTaskItem "TASK-612-02" "Terminal Observatory" "[OK] Verified" false))
        (t3 (makeTaskItem "TASK-612-03" "Workspace Router" "[RUN] In Progress" false))
        (t4 (makeTaskItem "TASK-612-04" "Cockpit TUI Entry" "[IDLE] Pending" false))]
    (TuiRouterState
      :focus (focusWorkspace)
      :workspaces (list w1)
      :selectedWorkspaceIdx 0
      :projects (list p1 p2 p3 p4)
      :selectedProjectIdx 0
      :tasks (list t1 t2 t3 t4)
      :selectedTaskIdx 0
      :promptBuffer ""
      :statusMessage "Ready"))

fn cycleFocusForward state: TuiRouterState -> TuiRouterState
  (let [(nextFocus (mt state.focus
                     ((focusWorkspace) (focusProject))
                     ((focusProject) (focusTasks))
                     ((focusTasks) (focusObservatory))
                     ((focusObservatory) (focusOmniPrompt))
                     ((focusOmniPrompt) (focusWorkspace))))]
    (with state :focus nextFocus))

fn cycleFocusBackward state: TuiRouterState -> TuiRouterState
  (let [(prevFocus (mt state.focus
                     ((focusWorkspace) (focusOmniPrompt))
                     ((focusProject) (focusWorkspace))
                     ((focusTasks) (focusProject))
                     ((focusObservatory) (focusTasks))
                     ((focusOmniPrompt) (focusObservatory))))]
    (with state :focus prevFocus))

fn selectNextItem state: TuiRouterState -> TuiRouterState
  (mt state.focus
    ((focusWorkspace)
      (let [(len (listLength state.workspaces))
            (nextIdx (if (< (+ state.selectedWorkspaceIdx 1) len) (+ state.selectedWorkspaceIdx 1) state.selectedWorkspaceIdx))]
        (with state :selectedWorkspaceIdx nextIdx)))
    ((focusProject)
      (let [(len (listLength state.projects))
            (nextIdx (if (< (+ state.selectedProjectIdx 1) len) (+ state.selectedProjectIdx 1) state.selectedProjectIdx))]
        (with state :selectedProjectIdx nextIdx)))
    ((focusTasks)
      (let [(len (listLength state.tasks))
            (nextIdx (if (< (+ state.selectedTaskIdx 1) len) (+ state.selectedTaskIdx 1) state.selectedTaskIdx))]
        (with state :selectedTaskIdx nextIdx)))
    (_ state))

fn selectPrevItem state: TuiRouterState -> TuiRouterState
  (mt state.focus
    ((focusWorkspace)
      (let [(prevIdx (if (> state.selectedWorkspaceIdx 0) (- state.selectedWorkspaceIdx 1) 0))]
        (with state :selectedWorkspaceIdx prevIdx)))
    ((focusProject)
      (let [(prevIdx (if (> state.selectedProjectIdx 0) (- state.selectedProjectIdx 1) 0))]
        (with state :selectedProjectIdx prevIdx)))
    ((focusTasks)
      (let [(prevIdx (if (> state.selectedTaskIdx 0) (- state.selectedTaskIdx 1) 0))]
        (with state :selectedTaskIdx prevIdx)))
    (_ state))

fn setPromptBuffer state: TuiRouterState prompt: String -> TuiRouterState
  (with state :promptBuffer prompt)

fn clearPromptBuffer state: TuiRouterState -> TuiRouterState
  (with state :promptBuffer "")

fn formatOmniIntentPayload state: TuiRouterState -> String
  (let [(ws (optionOr (listGet state.workspaces state.selectedWorkspaceIdx) (makeWorkspaceItem "" "" false 0)))
        (proj (optionOr (listGet state.projects state.selectedProjectIdx) (makeProjectItem "" "" "" false)))
        (task (optionOr (listGet state.tasks state.selectedTaskIdx) (makeTaskItem "" "" "" false)))]
    (str "(:omniIntentPayload\n"
         "  :workspace \"" ws.uri "\"\n"
         "  :project \"" proj.path "\"\n"
         "  :taskId \"" task.id "\"\n"
         "  :prompt \"" state.promptBuffer "\"\n"
         "  :status :routed)"))
