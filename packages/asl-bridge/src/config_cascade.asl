(module asl-bridge/configCascade
  :d "AgentScript Hierarchical Configuration Cascading and Dynamic Secret Resolution Engine."
  :x [ConfigCascadeEntry ResolvedTool
      makeCascadeEntry makeResolvedTool
      cascadeMerge resolveSecretValue maskSecret
      resolveEnvBinding isLevelHigher?]
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

(df makeCascadeEntry [(path Str) (level Str) (params (Map Str Str))] -> ConfigCascadeEntry
  :d "Constructs a configuration cascade entry."
  (ConfigCascadeEntry
    :path path
    :level level
    :params params))

(df makeResolvedTool [(id Str)
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

(df isLevelHigher? [(a Str) (b Str)] -> Bool
  :d "Returns true if hierarchy level a has higher precedence than b (local > subproject > workspace > user)."
  (if (= a "local")
      true
      (if (and (= a "subproject") (not (= b "local")))
          true
          (if (and (= a "workspace") (= b "user"))
              true
              false))))

(df cascadeMerge [(parent (Map Str Str)) (leaf (Map Str Str))] -> (Map Str Str)
  :d "Merges parent and leaf configuration maps where leaf overrides parent keys."
  (mapMerge parent leaf))

(df resolveSecretValue [(source Str) (ref Str) (fallback Str) (env (Map Str Str))] -> Str
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

(df maskSecret [(secret Str)] -> Str
  :d "Masks sensitive credential strings to prevent accidental leakage in telemetry."
  (if (= secret "")
      ""
      "[REDACTED]"))

(df resolveEnvBinding [(key Str) (rawVal Str) (source Str) (env (Map Str Str))] -> Str
  :d "Resolves an environment binding key-value pair."
  (resolveSecretValue source rawVal "" env))
