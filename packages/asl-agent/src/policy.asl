(module aslAgent/policy :x [AutonomyLevel ActionCategory PermissionManifest PermissionResult levelAsk levelGuarded levelAuto catRead catTest catWrite catExec makeManifest allowSilent allowPrompt denyStrict denyUnauthorized hasTraversal? isSystemPath? isInWorktrees? actionToCategory autonomyLevelToString checkPermission checkAutonomyPermission] :i [])

(enum AutonomyLevel (:c levelAsk [] "L0: Prompt for every file edit and shell command") (:c levelGuarded [] "L1: Auto-allow read/search/test; prompt for write/exec") (:c levelAuto [] "L2: Fully autonomous execution within workspace sandbox"))

(enum ActionCategory (:c catRead [] "Read-only file inspection, grep, search") (:c catTest [] "Sandboxed verification and test runner") (:c catWrite [] "File modification, deletion, or creation") (:c catExec [] "Shell command execution"))

(schema PermissionManifest (:f workspaceRoot Str) (:f worktreeRoots (List Str)) (:f tempDir Str) (:f readOnly Bool))

(schema PermissionResult (:f allowed Bool) (:f silent Bool) (:f reason Str) (:f code Str))

fn makeManifest workspaceRoot: Str worktreeRoots: (List Str) tempDir: Str readOnly: Bool -> PermissionManifest
  (PermissionManifest :workspaceRoot workspaceRoot :worktreeRoots worktreeRoots :tempDir tempDir :readOnly readOnly)

fn allowSilent reason: Str -> PermissionResult
  (PermissionResult :allowed true :silent true :reason reason :code "ALLOW_SILENT")

fn allowPrompt reason: Str -> PermissionResult
  (PermissionResult :allowed true :silent false :reason reason :code "ALLOW_PROMPT")

fn denyStrict reason: Str -> PermissionResult
  (PermissionResult :allowed false :silent false :reason reason :code "DENY_STRICT")

fn denyUnauthorized reason: Str -> PermissionResult
  (PermissionResult :allowed false :silent false :reason reason :code "DENY_UNAUTHORIZED")

fn actionToCategory action: Str -> ActionCategory
  (cond ((= action "read") (catRead)) ((= action "view") (catRead)) ((= action "grep") (catRead)) ((= action "search") (catRead)) ((= action "test") (catTest)) ((= action "audit") (catTest)) ((= action "write") (catWrite)) ((= action "patch") (catWrite)) ((= action "delete") (catWrite)) ((= action "exec") (catExec)) ((= action "shell") (catExec)) (else (catWrite)))

fn autonomyLevelToString lvl: AutonomyLevel -> Str
  (mt lvl ((levelAsk) "L0:Ask") ((levelGuarded) "L1:Guarded") ((levelAuto) "L2:FullAuto"))

fn hasTraversal? p: Str -> Bool
  (cond ((stringContains? p "../") true) ((stringContains? p "/..") true) ((= p "..") true) ((stringStartsWith? p "..") true) (else false))

fn isSystemPath? p: Str -> Bool
  (cond ((stringStartsWith? p "/etc") true) ((stringStartsWith? p "/root") true) ((stringStartsWith? p "/sys") true) ((stringStartsWith? p "/proc") true) ((stringStartsWith? p "/dev") true) ((stringStartsWith? p "~/.ssh") true) ((stringContains? p ".ssh") true) (else false))

fn isInWorktrees? p: Str worktrees: (List Str) -> Bool
  (mt (listHead worktrees) ((none) false) ((some root) (if (or (= p root) (stringStartsWith? p (str root "/"))) true (isInWorktrees? p (optionOr (listTail worktrees) (list))))))

fn checkAutonomyPermission action: Str targetPath: Str manifest: PermissionManifest level: AutonomyLevel -> PermissionResult
  (if (hasTraversal? targetPath) (denyStrict "sandbox escape: directory traversal rejected") (if (isSystemPath? targetPath) (denyStrict "sandbox escape: sensitive system path rejected") (if (and manifest.readOnly (or (= action "write") (= action "patch"))) (denyStrict "permission denied: manifest is read-only") (let [(inWs (or (= targetPath manifest.workspaceRoot) (stringStartsWith? targetPath (str manifest.workspaceRoot "/")))) (inTmp (or (= targetPath manifest.tempDir) (stringStartsWith? targetPath (str manifest.tempDir "/")))) (inWt (isInWorktrees? targetPath manifest.worktreeRoots)) (isAuthorized (or inWs (or inTmp inWt)))] (if (not isAuthorized) (denyUnauthorized "path outside authorized manifest boundaries") (let [(cat (actionToCategory action))] (mt level ((levelAsk) (mt cat ((catRead) (allowSilent "path authorized (read-only)")) ((catTest) (allowSilent "test verification authorized")) ((catWrite) (allowPrompt "confirmation required in L0:Ask mode for file write")) ((catExec) (allowPrompt "confirmation required in L0:Ask mode for command execution")))) ((levelGuarded) (mt cat ((catRead) (allowSilent "path authorized (auto-read)")) ((catTest) (allowSilent "test verification authorized (auto-test)")) ((catWrite) (allowPrompt "confirmation required in L1:Guarded mode for mutation")) ((catExec) (allowPrompt "confirmation required in L1:Guarded mode for execution")))) ((levelAuto) (allowSilent "path authorized for autonomous execution (L2:FullAuto)")))))))))

fn checkPermission action: Str targetPath: Str manifest: PermissionManifest -> PermissionResult
  (checkAutonomyPermission action targetPath manifest (levelAuto))
