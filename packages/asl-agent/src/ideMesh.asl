(module aslAgent/ideMesh :x [IdeRuntime WorktreeSlot MeshHubConfig IdeTaskEnvelope IdeExecutionReceipt IdeMeshCoordinator ideClaudeCode ideAntigravity ideNativeAd ideCursorBridge runtimeToStr strToRuntime makeWorktreeSlot formatGitWorktreeAdd formatGitWorktreeRemove hasWorktreeCollision? makeDefaultHubConfig makeIdeTask formatClaudeCliDispatch formatAntigravityCliDispatch formatHubEnvelopeAsn makeExecutionReceipt isReceiptFalsifiedAndGreen? formatReceiptAloud makeMeshCoordinator allocateTaskWorktree releaseTaskWorktree dispatchTaskToMesh recordTaskSettlement renderMeshStatusAsn] :i [(asl-text/string :a s)])

(enum IdeRuntime (:c ideClaudeCode [] "Claude Code CLI headless runner") (:c ideAntigravity [] "Google Antigravity IDE headless CLI runner") (:c ideNativeAd [] "Native AgentScript autonomous session") (:c ideCursorBridge [] "Cursor or Windsurf external tool bridge"))

(schema WorktreeSlot (:f taskId Str) (:f branchName Str) (:f worktreePath Str) (:f repoRoot Str) (:f isActive Bool) (:f allocatedAt Int64))

(schema MeshHubConfig (:f socketPath Str) (:f defaultTimeoutSec Int64) (:f maxConcurrentWorkers Int64))

(schema IdeTaskEnvelope (:f taskId Str) (:f runtime IdeRuntime) (:f intentKind Str) (:f prompt Str) (:f worktreePath Str) (:f timeoutSec Int64) (:f enqueuedAt Int64))

(schema IdeExecutionReceipt (:f taskId Str) (:f runtime IdeRuntime) (:f exitCode Int64) (:f assertionsPassed Int64) (:f filesModified Int64) (:f durationMs Int64) (:f digest Str))

(schema IdeMeshCoordinator (:f config MeshHubConfig) (:f worktrees (List WorktreeSlot)) (:f dispatchedTasks (List IdeTaskEnvelope)) (:f receipts (List IdeExecutionReceipt)))

fn runtimeToStr runtime: IdeRuntime -> Str
  (mt runtime ((ideClaudeCode) "claude-code") ((ideAntigravity) "antigravity") ((ideNativeAd) "native-ad") ((ideCursorBridge) "cursor-bridge"))

fn strToRuntime name: Str -> IdeRuntime
  (cond ((= name "claude-code") (ideClaudeCode)) ((= name "antigravity") (ideAntigravity)) ((= name "native-ad") (ideNativeAd)) (else (ideCursorBridge)))

fn makeWorktreeSlot taskId: Str repoRoot: Str now: Int64 -> WorktreeSlot
  (WorktreeSlot :taskId taskId :branchName (str "eddie/" taskId) :worktreePath (str repoRoot "/.worktrees/" taskId) :repoRoot repoRoot :isActive true :allocatedAt now)

fn formatGitWorktreeAdd slot: WorktreeSlot -> Str
  (str "git worktree add -b " slot.branchName " " slot.worktreePath)

fn formatGitWorktreeRemove slot: WorktreeSlot -> Str
  (str "git worktree remove --force " slot.worktreePath)

fn hasWorktreeCollision? slots: (List WorktreeSlot) taskId: Str -> Bool
  (let [(matches (filter (fn [(s WorktreeSlot)] (and s.isActive (= s.taskId taskId))) slots))] (> (listLength matches) 0))

fn makeDefaultHubConfig -> MeshHubConfig
  (MeshHubConfig :socketPath "~/.asl/run/hub.sock" :defaultTimeoutSec 300 :maxConcurrentWorkers 8)

fn makeIdeTask taskId: Str runtime: IdeRuntime intentKind: Str prompt: Str worktreePath: Str now: Int64 -> IdeTaskEnvelope
  (IdeTaskEnvelope :taskId taskId :runtime runtime :intentKind intentKind :prompt prompt :worktreePath worktreePath :timeoutSec 300 :enqueuedAt now)

fn formatClaudeCliDispatch task: IdeTaskEnvelope -> Str
  (str "cd " task.worktreePath " && claude -p \"" (stringReplace task.prompt "\"" "") "\"")

fn formatAntigravityCliDispatch task: IdeTaskEnvelope -> Str
  (str "cd " task.worktreePath " && agy -p \"" (stringReplace task.prompt "\"" "") "\"")

fn formatHubEnvelopeAsn task: IdeTaskEnvelope -> Str
  (str "(:mesh-envelope :task-id \"" task.taskId "\" :runtime \"" (runtimeToStr task.runtime) "\" :worktree \"" task.worktreePath "\" :timeout " (stringFromInt64 task.timeoutSec) ")")

fn makeExecutionReceipt taskId: Str runtime: IdeRuntime exitCode: Int64 asserts: Int64 files: Int64 duration: Int64 digest: Str -> IdeExecutionReceipt
  (IdeExecutionReceipt :taskId taskId :runtime runtime :exitCode exitCode :assertionsPassed asserts :filesModified files :durationMs duration :digest digest)

fn isReceiptFalsifiedAndGreen? r: IdeExecutionReceipt -> Bool
  (and (= r.exitCode 0) (> r.assertionsPassed 0))

fn formatReceiptAloud r: IdeExecutionReceipt -> Str
  (let [(rtName (runtimeToStr r.runtime)) (tid r.taskId)] (if (isReceiptFalsifiedAndGreen? r) (str "Task " tid " verified on " rtName ". " (stringFromInt64 r.assertionsPassed) " assertions green across " (stringFromInt64 r.filesModified) " files.") (str "Task " tid " failed on " rtName " with exit code " (stringFromInt64 r.exitCode) ".")))

fn makeMeshCoordinator config: MeshHubConfig -> IdeMeshCoordinator
  (IdeMeshCoordinator :config config :worktrees (list) :dispatchedTasks (list) :receipts (list))

fn allocateTaskWorktree mesh: IdeMeshCoordinator taskId: Str repoRoot: Str now: Int64 -> IdeMeshCoordinator
  (if (hasWorktreeCollision? mesh.worktrees taskId) mesh (let [(slot (makeWorktreeSlot taskId repoRoot now)) (updated (listAppend mesh.worktrees (list slot)))] (with mesh :worktrees updated)))

fn releaseTaskWorktree mesh: IdeMeshCoordinator taskId: Str -> IdeMeshCoordinator
  (let [(filtered (filter (fn [(s WorktreeSlot)] (not (= s.taskId taskId))) mesh.worktrees))] (with mesh :worktrees filtered))

fn dispatchTaskToMesh mesh: IdeMeshCoordinator envelope: IdeTaskEnvelope -> IdeMeshCoordinator
  (let [(updated (listAppend mesh.dispatchedTasks (list envelope)))] (with mesh :dispatchedTasks updated))

fn recordTaskSettlement mesh: IdeMeshCoordinator receipt: IdeExecutionReceipt -> IdeMeshCoordinator
  (let [(tid receipt.taskId) (activeTasks (filter (fn [(e IdeTaskEnvelope)] (not (= e.taskId tid))) mesh.dispatchedTasks)) (activeWorktrees (filter (fn [(s WorktreeSlot)] (not (= s.taskId tid))) mesh.worktrees)) (updatedReceipts (listAppend mesh.receipts (list receipt)))] (with mesh :worktrees activeWorktrees :dispatchedTasks activeTasks :receipts updatedReceipts))

fn renderMeshStatusAsn mesh: IdeMeshCoordinator -> Str
  (let [(wCount (listLength mesh.worktrees)) (tCount (listLength mesh.dispatchedTasks)) (rCount (listLength mesh.receipts))] (str "(:ide-mesh :socket \"" mesh.config.socketPath "\" :worktrees " (stringFromInt64 wCount) " :in-flight " (stringFromInt64 tCount) " :settled " (stringFromInt64 rCount) ")"))
