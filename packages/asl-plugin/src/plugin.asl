(module asl-plugin/plugin
  :d "Formal plugin specification and capability registry for AgentScript core."
  :x [PluginKind PluginCapability PluginExport PluginManifest PluginRegistry PluginCall PluginResult
      emptyRegistry registerPlugin lookupPlugin findPluginsByCapability
      hasCapability? validateManifest formatManifest dispatchCall]
  :i [])

(dfe PluginKind
  (:c kindWasm [] "WebAssembly module plugin")
  (:c kindNativeFfi [] "Native host shared object FFI plugin")
  (:c kindHostDriver [] "External driver or subprocess host plugin"))

(dfs PluginCapability
  (:f name Str "Capability identifier e.g. cap-db, cap-fs, cap-net")
  (:f version Str "Capability semantic version string")
  (:f doc Str "Capability specification documentation"))

(dfs PluginExport
  (:f symbolName Str "Exported function or entrypoint name")
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
  (:f capabilityIndex (Map Str (List Str)) "Map of capability name to list of providing plugin IDs"))

(dfs PluginCall
  (:f pluginId Str "Target plugin ID")
  (:f symbolName Str "Target symbol name to invoke")
  (:f payload Str "Serialized input arguments"))

(dfs PluginResult
  (:f success Bool "True if execution completed without error")
  (:f payload Str "Serialized return payload on success")
  (:f errorMsg Str "Error message on failure"))

(df emptyRegistry [] -> PluginRegistry
  :d "Initializes an empty plugin registry."
  (PluginRegistry :plugins (map-empty) :capabilityIndex (map-empty)))

(df indexPluginCapabilities [(capIndex (Map Str (List Str))) (pluginId Str) (caps (List PluginCapability))] -> (Map Str (List Str))
  :d "Indexes all capabilities provided by a plugin into the registry index."
  (fold (fn [(acc (Map Str (List Str))) (c PluginCapability)] -> (Map Str (List Str))
          (let [(cName (.-name c))
                (existing (option-or (map-get acc cName) (list)))
                (updated (list-cons pluginId existing))]
            (map-set acc cName updated)))
        capIndex
        caps))

(df registerPlugin [(reg PluginRegistry) (manifest PluginManifest)] -> PluginRegistry
  :d "Registers a plugin manifest into the registry and updates capability indexing."
  (let [(pId (.-id manifest))
        (updatedPlugins (map-set (.-plugins reg) pId manifest))
        (updatedIndex (indexPluginCapabilities (.-capabilityIndex reg) pId (.-capabilities manifest)))]
    (PluginRegistry :plugins updatedPlugins :capabilityIndex updatedIndex)))

(df lookupPlugin [(reg PluginRegistry) (pluginId Str)] -> (Option PluginManifest)
  :d "Looks up a plugin manifest by its identifier."
  (map-get (.-plugins reg) pluginId))

(df findPluginsByCapability [(reg PluginRegistry) (capabilityName Str)] -> (List Str)
  :d "Returns all plugin identifiers providing a given capability."
  (option-or (map-get (.-capabilityIndex reg) capabilityName) (list)))

(df hasCapability? [(manifest PluginManifest) (capabilityName Str)] -> Bool
  :d "Checks whether a plugin manifest implements a specific capability."
  (let [(matches (filter (fn [(c PluginCapability)] -> Bool
                           (= (.-name c) capabilityName))
                         (.-capabilities manifest)))]
    (not (list-empty? matches))))

(df validateManifest [(manifest PluginManifest)] -> (Result Unit Str)
  :d "Validates that a plugin manifest meets all core structural requirements."
  (cond
    ((string-empty? (.-id manifest)) (err "Plugin ID cannot be empty"))
    ((string-empty? (.-name manifest)) (err "Plugin name cannot be empty"))
    ((string-empty? (.-version manifest)) (err "Plugin version cannot be empty"))
    ((string-empty? (.-entrypoint manifest)) (err "Plugin entrypoint cannot be empty"))
    (:else (ok ()))))

(df formatKind [(k PluginKind)] -> Str
  :d "Formats plugin runtime kind into string."
  (mt k
    ((kindWasm) "wasm")
    ((kindNativeFfi) "ffi")
    ((kindHostDriver) "driver")))

(df formatManifest [(m PluginManifest)] -> Str
  :d "Formats plugin manifest into concise diagnostic summary string."
  (str "plugin:" (.-id m) "@" (.-version m) "[" (formatKind (.-kind m)) "]"
       " caps:" (string-join (map (fn [(c PluginCapability)] -> Str (.-name c)) (.-capabilities m)) ",")))

(df dispatchCall [(reg PluginRegistry) (call PluginCall)] -> PluginResult
  :d "Dispatches a foreign call to a registered plugin verifying its presence and exports."
  (let [(pOpt (lookupPlugin reg (.-pluginId call)))]
    (mt pOpt
      ((none) (PluginResult :success false :payload "" :errorMsg (str "Plugin not found: " (.-pluginId call))))
      ((some m)
       (let [(expMatches (filter (fn [(e PluginExport)] -> Bool
                                    (= (.-symbolName e) (.-symbolName call)))
                                  (.-exports m)))]
         (if (list-empty? expMatches)
             (PluginResult :success false :payload "" :errorMsg (str "Symbol not exported by plugin: " (.-symbolName call)))
             (PluginResult :success true :payload (str "ok:" (.-payload call)) :errorMsg "")))))))
