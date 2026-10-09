(module asl-bridge/configCascade :x [ConfigCascadeEntry ResolvedTool makeCascadeEntry makeResolvedTool cascadeMerge resolveSecretValue maskSecret resolveEnvBinding isLevelHigher?] :i [])

(schema ConfigCascadeEntry (:f path Str) (:f level Str) (:f params (Map Str Str)))

(schema ResolvedTool (:f id Str) (:f name Str) (:f cmd Str) (:f args (List Str)) (:f env (Map Str Str)) (:f safety Str) (:f guidance Str) (:f redacted Bool))

fn makeCascadeEntry path: Str level: Str params: (Map Str Str) -> ConfigCascadeEntry
  (ConfigCascadeEntry :path path :level level :params params)

fn makeResolvedTool id: Str name: Str cmd: Str args: (List Str) env: (Map Str Str) safety: Str guidance: Str redacted: Bool -> ResolvedTool
  (ResolvedTool :id id :name name :cmd cmd :args args :env env :safety safety :guidance guidance :redacted redacted)

fn isLevelHigher? a: Str b: Str -> Bool
  (if (= a "local") true (if (and (= a "subproject") (not (= b "local"))) true (if (and (= a "workspace") (= b "user")) true false)))

fn cascadeMerge parent: (Map Str Str) leaf: (Map Str Str) -> (Map Str Str)
  (mapFromPairs (listAppend (mapPairs parent) (mapPairs leaf)))

fn resolveSecretValue source: Str ref: Str fallback: Str env: (Map Str Str) -> Str
  (cond ((= source "literal") ref) ((or (= source "env") (or (= source "file") (= source "keychain"))) (let [(val (optionOr (mapGet env ref) fallback))] (if (= val "") fallback val))) (true fallback))

fn maskSecret secret: Str -> Str
  (if (= secret "") "" "[REDACTED]")

fn resolveEnvBinding key: Str rawVal: Str source: Str env: (Map Str Str) -> Str
  (resolveSecretValue source rawVal "" env)
