(module asl-plugin/test
  :d "Unit tests for modular plugin architecture and registry."
  :x [run-tests]
  :i [(plugin :a pl)])

(df test-registry-and-lookup [] -> Bool
  :d "Tests registering and looking up a plugin."
  (let [(reg (pl/empty-registry))
        (cap (pl/PluginCapability :name "cap-db" :version "1.0.0" :doc "SQL database access"))
        (exp (pl/PluginExport :symbol-name "query" :signature "(query Str (List Str)) -> (Result Str Str)" :doc "Executes SQL query"))
        (manifest (pl/PluginManifest :id "plugin-sqlite"
                                     :name "SQLite Embedded Driver"
                                     :version "0.1.0"
                                     :kind (pl/kind-wasm)
                                     :capabilities (list cap)
                                     :exports (list exp)
                                     :entrypoint "dist/sqlite.wasm"))
        (updated-reg (pl/register-plugin reg manifest))
        (found (pl/lookup-plugin updated-reg "plugin-sqlite"))
        (by-cap (pl/find-plugins-by-capability updated-reg "cap-db"))]
    (and (is-some? found)
         (and (= (list-length by-cap) 1)
              (pl/has-capability? manifest "cap-db")))))

(df test-validate-manifest [] -> Bool
  :d "Tests manifest validation checks."
  (let [(valid (pl/PluginManifest :id "p1" :name "Plugin One" :version "1.0.0" :kind (pl/kind-wasm) :capabilities (list) :exports (list) :entrypoint "main.wasm"))
        (invalid (pl/PluginManifest :id "" :name "Invalid" :version "1.0.0" :kind (pl/kind-wasm) :capabilities (list) :exports (list) :entrypoint "main.wasm"))]
    (and (is-ok? (pl/validate-manifest valid))
         (is-err? (pl/validate-manifest invalid)))))

(df test-dispatch-call [] -> Bool
  :d "Tests plugin call dispatch validation."
  (let [(reg (pl/empty-registry))
        (exp (pl/PluginExport :symbol-name "exec" :signature "() -> Unit" :doc "Executes"))
        (m (pl/PluginManifest :id "p-sh" :name "Shell Driver" :version "0.1.0" :kind (pl/kind-host-driver) :capabilities (list) :exports (list exp) :entrypoint "sh"))
        (reg2 (pl/register-plugin reg m))
        (res-ok (pl/dispatch-call reg2 (pl/PluginCall :plugin-id "p-sh" :symbol-name "exec" :payload "ls")))
        (res-missing-sym (pl/dispatch-call reg2 (pl/PluginCall :plugin-id "p-sh" :symbol-name "non-existent" :payload "")))
        (res-missing-plugin (pl/dispatch-call reg2 (pl/PluginCall :plugin-id "unknown" :symbol-name "exec" :payload "")))]
    (and (.-success res-ok)
         (and (not (.-success res-missing-sym))
              (not (.-success res-missing-plugin))))))

(df run-tests [] -> Bool
  :d "Runs all plugin test suites."
  (and (test-registry-and-lookup)
       (and (test-validate-manifest)
            (test-dispatch-call))))
