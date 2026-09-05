(module asl-eddie/policy
  :d "Capability-based sandboxing and zero-spam permission policy."
  :x [PermissionManifest PermissionResult
      make-manifest allow-silent deny-strict deny-unauthorized
      has-traversal? is-system-path? is-in-worktrees?
      check-permission]
  :i [])

(dfs PermissionManifest
  (:f workspace-root Str "Canonical workspace root directory")
  (:f worktree-roots (List Str) "List of authorized git worktree root directories")
  (:f temp-dir Str "Authorized sandbox temporary directory")
  (:f read-only Bool "True if entire sandbox is read-only"))

(dfs PermissionResult
  (:f allowed Bool "True if access is granted")
  (:f silent Bool "True if granted without user prompt")
  (:f reason Str "Diagnostic reason or error message")
  (:f code Str "Status code: ALLOW_SILENT, ALLOW_PROMPT, DENY_TRAVERSAL, DENY_ROOT, DENY_READONLY, DENY_UNAUTHORIZED"))

(df make-manifest [(workspace-root Str) (worktree-roots (List Str)) (temp-dir Str) (read-only Bool)] -> PermissionManifest
  :d "Constructs an authorized capability permission manifest."
  (PermissionManifest
    :workspace-root workspace-root
    :worktree-roots worktree-roots
    :temp-dir temp-dir
    :read-only read-only))

(df allow-silent [(reason Str)] -> PermissionResult
  :d "Constructs an allow-silent permission result without user prompt."
  (PermissionResult
    :allowed true
    :silent true
    :reason reason
    :code "ALLOW_SILENT"))

(df deny-strict [(reason Str)] -> PermissionResult
  :d "Constructs a strict denial permission result for traversal or escape attacks."
  (PermissionResult
    :allowed false
    :silent false
    :reason reason
    :code "DENY_STRICT"))

(df deny-unauthorized [(reason Str)] -> PermissionResult
  :d "Constructs an unauthorized denial permission result."
  (PermissionResult
    :allowed false
    :silent false
    :reason reason
    :code "DENY_UNAUTHORIZED"))

(df has-traversal? [(p Str)] -> Bool
  :d "Detects directory traversal sequences in path."
  (cond
    ((string-contains? p "../") true)
    ((string-contains? p "/..") true)
    ((= p "..") true)
    ((string-starts-with? p "..") true)
    (:else false)))

(df is-system-path? [(p Str)] -> Bool
  :d "Detects access to sensitive system paths."
  (cond
    ((string-starts-with? p "/etc") true)
    ((string-starts-with? p "/root") true)
    ((string-starts-with? p "/sys") true)
    ((string-starts-with? p "/proc") true)
    ((string-starts-with? p "/dev") true)
    ((string-starts-with? p "~/.ssh") true)
    ((string-contains? p ".ssh") true)
    (:else false)))

(df is-in-worktrees? [(p Str) (worktrees (List Str))] -> Bool
  :d "Checks whether target path resides within any authorized worktree root."
  (mt (list-head worktrees)
    ((none) false)
    ((some root)
     (if (string-starts-with? p root)
       true
       (is-in-worktrees? p (option-or (list-tail worktrees) (list)))))))

(df check-permission [(action Str) (target-path Str) (manifest PermissionManifest)] -> PermissionResult
  :d "Evaluates action and path against manifest capabilities."
  (if (has-traversal? target-path)
    (deny-strict "sandbox escape: directory traversal rejected")
    (if (is-system-path? target-path)
      (deny-strict "sandbox escape: sensitive system path rejected")
      (if (and (.-read-only manifest) (= action "write"))
        (deny-strict "permission denied: manifest is read-only")
        (if (string-starts-with? target-path (.-workspace-root manifest))
          (allow-silent "path within authorized workspace root")
          (if (string-starts-with? target-path (.-temp-dir manifest))
            (allow-silent "path within authorized temp dir")
            (if (is-in-worktrees? target-path (.-worktree-roots manifest))
              (allow-silent "path within authorized worktree root")
              (deny-unauthorized "path outside authorized manifest boundaries"))))))))
