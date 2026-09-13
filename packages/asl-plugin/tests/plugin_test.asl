(module asl-plugin/test
  :d "Unit tests for modular plugin architecture and registry."
  :x [runTests]
  :i [(plugin :a pl)])

(df testRegistryAndLookup [] -> Bool
  :d "Tests registering and looking up a plugin."
  (let [(reg (pl/emptyRegistry))
        (cap (pl/PluginCapability :name "cap-db" :version "1.0.0" :doc "SQL database access"))
        (exp (pl/PluginExport :symbolName "query" :signature "(query Str (List Str)) -> (Result Str Str)" :doc "Executes SQL query"))
        (manifest (pl/PluginManifest :id "plugin-sqlite"
                                     :name "SQLite Embedded Driver"
                                     :version "0.1.0"
                                     :kind (pl/kindWasm)
                                     :capabilities (list cap)
                                     :exports (list exp)
                                     :entrypoint "dist/sqlite.wasm"))
        (updatedReg (pl/registerPlugin reg manifest))
        (found (pl/lookupPlugin updatedReg "plugin-sqlite"))
        (byCap (pl/findPluginsByCapability updatedReg "cap-db"))]
    (assert (is-some? found) "plugin found")
    (assert (= (list-length byCap) 1) "cap-db plugins count")
    (assert (pl/hasCapability? manifest "cap-db") "has capability")
    true))

(df testValidateManifest [] -> Bool
  :d "Tests manifest validation checks."
  (let [(valid (pl/PluginManifest :id "p1" :name "Plugin One" :version "1.0.0" :kind (pl/kindWasm) :capabilities (list) :exports (list) :entrypoint "main.wasm"))
        (invalid (pl/PluginManifest :id "" :name "Invalid" :version "1.0.0" :kind (pl/kindWasm) :capabilities (list) :exports (list) :entrypoint "main.wasm"))]
    (assert (is-ok? (pl/validateManifest valid)) "valid manifest ok")
    (assert (is-err? (pl/validateManifest invalid)) "invalid manifest err")
    true))

(df testDispatchCall [] -> Bool
  :d "Tests plugin call dispatch validation."
  (let [(reg (pl/emptyRegistry))
        (exp (pl/PluginExport :symbolName "exec" :signature "() -> Unit" :doc "Executes"))
        (m (pl/PluginManifest :id "p-sh" :name "Shell Driver" :version "0.1.0" :kind (pl/kindHostDriver) :capabilities (list) :exports (list exp) :entrypoint "sh"))
        (reg2 (pl/registerPlugin reg m))
        (resOk (pl/dispatchCall reg2 (pl/PluginCall :pluginId "p-sh" :symbolName "exec" :payload "ls")))
        (resMissingSym (pl/dispatchCall reg2 (pl/PluginCall :pluginId "p-sh" :symbolName "non-existent" :payload "")))
        (resMissingPlugin (pl/dispatchCall reg2 (pl/PluginCall :pluginId "unknown" :symbolName "exec" :payload "")))]
    (assert (.-success resOk) "res-ok success")
    (refute (.-success resMissingSym) "missing-sym fails")
    (refute (.-success resMissingPlugin) "missing-plugin fails")
    true))

(df runTests [] -> Bool
  :d "Runs all plugin test suites."
  (do
    (assert (testRegistryAndLookup) "test-registry-and-lookup must pass")
    (assert (testValidateManifest) "test-validate-manifest must pass")
    (assert (testDispatchCall) "test-dispatch-call must pass")
    true))
