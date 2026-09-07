(module asl-bridge/config-cascade
  :d "AgentScript Hierarchical Configuration Cascading and Dynamic Secret Resolution Engine."
  :x [ConfigCascadeEntry ResolvedTool
      make-cascade-entry make-resolved-tool
      cascade-merge resolve-secret-value mask-secret
      resolve-env-binding is-level-higher?]
  :i [])

(dfs ConfigCascadeEntry
  (:f path Str "Filesystem path where config was loaded")
  (:f level Str "Hierarchy level: user, workspace, subproject, local")
  (:f params (Map Str Str) "Configuration key-value pairs"))

(dfs ResolvedTool
  (:f id Str "Canonical tool identifier")
  (:f name Str "Human readable tool name")
  (:f cmd Str "Executable command binary")
  (:f args (List Str) "Configured arguments")
  (:f env (Map Str Str) "Resolved environment map")
  (:f safety Str "Tool safety tier")
  (:f guidance Str "Operational guidance for agents")
  (:f redacted Bool "True if secrets are masked"))

(df make-cascade-entry [(path Str) (level Str) (params (Map Str Str))] -> ConfigCascadeEntry
  :d "Constructs a configuration cascade entry."
  (ConfigCascadeEntry
    :path path
    :level level
    :params params))

(df make-resolved-tool [(id Str)
                        (name Str)
                        (cmd Str)
                        (args (List Str))
                        (env (Map Str Str))
                        (safety Str)
                        (guidance Str)
                        (redacted Bool)] -> ResolvedTool
  :d "Constructs a resolved tool descriptor."
  (ResolvedTool
    :id id
    :name name
    :cmd cmd
    :args args
    :env env
    :safety safety
    :guidance guidance
    :redacted redacted))

(df is-level-higher? [(a Str) (b Str)] -> Bool
  :d "Returns true if hierarchy level a has higher precedence than b (local > subproject > workspace > user)."
  (if (= a "local")
      true
      (if (and (= a "subproject") (not (= b "local")))
          true
          (if (and (= a "workspace") (= b "user"))
              true
              false))))

(df cascade-merge [(parent (Map Str Str)) (leaf (Map Str Str))] -> (Map Str Str)
  :d "Merges parent and leaf configuration maps where leaf overrides parent keys."
  (map-merge parent leaf))

(df resolve-secret-value [(source Str) (ref Str) (fallback Str) (env (Map Str Str))] -> Str
  :d "Resolves a secret or environment reference with fallback support."
  (if (= source "literal")
      ref
      (if (= source "env")
          (if (map-has? env ref)
              (let [(v (map-get env ref))]
                (if (= v "") fallback v))
              fallback)
          (if (or (= source "file") (= source "keychain"))
              (if (map-has? env ref)
                  (map-get env ref)
                  fallback)
              fallback))))

(df mask-secret [(secret Str)] -> Str
  :d "Masks sensitive credential strings to prevent accidental leakage in telemetry."
  (if (= secret "")
      ""
      "[REDACTED]"))

(df resolve-env-binding [(key Str) (raw-val Str) (source Str) (env (Map Str Str))] -> Str
  :d "Resolves an environment binding key-value pair."
  (resolve-secret-value source raw-val "" env))
