(module asl-plugin/plugin
  :d "Formal plugin specification and capability registry for AgentScript core."
  :x [PluginKind PluginCapability PluginExport PluginManifest PluginRegistry PluginCall PluginResult
      empty-registry register-plugin lookup-plugin find-plugins-by-capability
      has-capability? validate-manifest format-manifest dispatch-call]
  :i [])

(dfe PluginKind
  (:c kind-wasm [] "WebAssembly module plugin")
  (:c kind-native-ffi [] "Native host shared object FFI plugin")
  (:c kind-host-driver [] "External driver or subprocess host plugin"))

(dfs PluginCapability
  (:f name Str "Capability identifier e.g. cap-db, cap-fs, cap-net")
  (:f version Str "Capability semantic version string")
  (:f doc Str "Capability specification documentation"))

(dfs PluginExport
  (:f symbol-name Str "Exported function or entrypoint name")
  (:f signature Str "AgentScript typed signature description")
  (:f doc Str "Export documentation"))

(dfs PluginManifest
  (:f id Str "Unique plugin identifier e.g. plugin-postgres")
  (:f name Str "Human-readable plugin name")
  (:f version Str "Plugin semantic version")
  (:f kind PluginKind "Plugin runtime boundary type")
  (:f capabilities (List PluginCapability) "List of implemented capabilities")
  (:f exports (List PluginExport) "List of exposed symbols")
  (:f entrypoint Str "Path or symbol entrypoint"))

(dfs PluginRegistry
  (:f plugins (Map Str PluginManifest) "Map of plugin ID to plugin manifest")
  (:f capability-index (Map Str (List Str)) "Map of capability name to list of providing plugin IDs"))

(dfs PluginCall
  (:f plugin-id Str "Target plugin ID")
  (:f symbol-name Str "Target symbol name to invoke")
  (:f payload Str "Serialized input arguments"))

(dfs PluginResult
  (:f success Bool "True if execution completed without error")
  (:f payload Str "Serialized return payload on success")
  (:f error-msg Str "Error message on failure"))

(df empty-registry [] -> PluginRegistry
  :d "Initializes an empty plugin registry."
  (PluginRegistry :plugins (map-empty) :capability-index (map-empty)))

(df index-plugin-capabilities [(cap-index (Map Str (List Str))) (plugin-id Str) (caps (List PluginCapability))] -> (Map Str (List Str))
  :d "Indexes all capabilities provided by a plugin into the registry index."
  (fold (fn [(acc (Map Str (List Str))) (c PluginCapability)] -> (Map Str (List Str))
          (let [(c-name (.-name c))
                (existing (option-or (map-get acc c-name) (list)))
                (updated (list-cons plugin-id existing))]
            (map-set acc c-name updated)))
        cap-index
        caps))

(df register-plugin [(reg PluginRegistry) (manifest PluginManifest)] -> PluginRegistry
  :d "Registers a plugin manifest into the registry and updates capability indexing."
  (let [(p-id (.-id manifest))
        (updated-plugins (map-set (.-plugins reg) p-id manifest))
        (updated-index (index-plugin-capabilities (.-capability-index reg) p-id (.-capabilities manifest)))]
    (PluginRegistry :plugins updated-plugins :capability-index updated-index)))

(df lookup-plugin [(reg PluginRegistry) (plugin-id Str)] -> (Option PluginManifest)
  :d "Looks up a plugin manifest by its identifier."
  (map-get (.-plugins reg) plugin-id))

(df find-plugins-by-capability [(reg PluginRegistry) (capability-name Str)] -> (List Str)
  :d "Returns all plugin identifiers providing a given capability."
  (option-or (map-get (.-capability-index reg) capability-name) (list)))

(df has-capability? [(manifest PluginManifest) (capability-name Str)] -> Bool
  :d "Checks whether a plugin manifest implements a specific capability."
  (let [(matches (filter (fn [(c PluginCapability)] -> Bool
                           (= (.-name c) capability-name))
                         (.-capabilities manifest)))]
    (not (list-empty? matches))))

(df validate-manifest [(manifest PluginManifest)] -> (Result Unit Str)
  :d "Validates that a plugin manifest meets all core structural requirements."
  (cond
    ((string-empty? (.-id manifest)) (err "Plugin ID cannot be empty"))
    ((string-empty? (.-name manifest)) (err "Plugin name cannot be empty"))
    ((string-empty? (.-version manifest)) (err "Plugin version cannot be empty"))
    ((string-empty? (.-entrypoint manifest)) (err "Plugin entrypoint cannot be empty"))
    (:else (ok ()))))

(df format-kind [(k PluginKind)] -> Str
  :d "Formats plugin runtime kind into string."
  (mt k
    ((kind-wasm) "wasm")
    ((kind-native-ffi) "ffi")
    ((kind-host-driver) "driver")))

(df format-manifest [(m PluginManifest)] -> Str
  :d "Formats plugin manifest into concise diagnostic summary string."
  (str "plugin:" (.-id m) "@" (.-version m) "[" (format-kind (.-kind m)) "]"
       " caps:" (string-join (map (fn [(c PluginCapability)] -> Str (.-name c)) (.-capabilities m)) ",")))

(df dispatch-call [(reg PluginRegistry) (call PluginCall)] -> PluginResult
  :d "Dispatches a foreign call to a registered plugin verifying its presence and exports."
  (let [(p-opt (lookup-plugin reg (.-plugin-id call)))]
    (mt p-opt
      ((none) (PluginResult :success false :payload "" :error-msg (str "Plugin not found: " (.-plugin-id call))))
      ((some m)
       (let [(exp-matches (filter (fn [(e PluginExport)] -> Bool
                                    (= (.-symbol-name e) (.-symbol-name call)))
                                  (.-exports m)))]
         (if (list-empty? exp-matches)
             (PluginResult :success false :payload "" :error-msg (str "Symbol not exported by plugin: " (.-symbol-name call)))
             (PluginResult :success true :payload (str "ok:" (.-payload call)) :error-msg "")))))))
