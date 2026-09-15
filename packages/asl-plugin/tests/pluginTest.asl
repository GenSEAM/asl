(module asl-plugin/tests/pluginTest
  :d "Unit tests for modular plugin architecture and registry."
  :x [runTests]
  :i [(plugin :a pl)
      (security :a sec)])

(df ensureTestFixtures [(dir Str)] -> Bool
  :d "Prepares sandbox artifacts for plugin tests"
  (let [(cmd (str "mkdir -p " dir " && printf 'sqlite-wasm-payload' > " dir "/sqlite.wasm && printf 'main-wasm-payload' > " dir "/main.wasm && printf 'sh-bin-payload' > " dir "/sh.bin"))
        (res (sysExec cmd))]
    (= (.-exitCode res) 0)))

(df testRegistryAndLookup [] -> Bool
  :d "Tests registering and looking up a plugin."
  (let [(dir "tmp/sandbox_plugin_test_reg")]
    (do
      (ensureTestFixtures dir)
      (let [(reg (pl/emptyRegistry))
            (hash1 "21d9fc8331ad4a1c506ad427cb9e64fcad1efb189d621a8bdbcc226be959673e")
            (cap (pl/PluginCapability :name "cap-db" :version "1.0.0" :doc "SQL database access"))
            (exp (pl/PluginExport :symbolName "query" :signature "(query Str (List Str)) -> (Result Str Str)" :doc "SQL query" :requiredCapability "cap-db"))
            (manifest (pl/PluginManifest :id "plugin-sqlite"
                                         :name "SQLite Embedded Driver"
                                         :version "0.1.0"
                                         :kind (pl/kindWasm)
                                         :capabilities (list cap)
                                         :exports (list exp)
                                         :entrypoint "sqlite.wasm"
                                         :integritySha256 hash1))
            (updatedRegRes (pl/registerPlugin reg manifest dir))]
        (assert (is-ok? updatedRegRes) "register plugin ok")
        (mt updatedRegRes
          ((ok updatedReg)
           (let [(found (pl/lookupManifest updatedReg "plugin-sqlite"))
                 (inst (pl/lookupInstance updatedReg "plugin-sqlite"))
                 (hasCap (pl/hasCapability? manifest "cap-db"))]
             (assert (is-some? found) "plugin found")
             (assert (is-some? inst) "instance found")
             (assert hasCap "has capability")
             true))
          ((err _) false))))))

(df testValidateManifest [] -> Bool
  :d "Tests manifest validation checks."
  (let [(dir "tmp/sandbox_plugin_test_val")]
    (do
      (ensureTestFixtures dir)
      (let [(hash2 "d44bce49ea9c053b17999a06853aabfdf591c61724425fcac597a776dc982767")
            (cap (pl/PluginCapability :name "cap-db" :version "1.0.0" :doc "SQL database access"))
            (exp (pl/PluginExport :symbolName "query" :signature "(query Str (List Str)) -> (Result Str Str)" :doc "SQL query" :requiredCapability "cap-db"))
            (valid (pl/PluginManifest :id "p1" :name "Plugin One" :version "1.0.0" :kind (pl/kindWasm) :capabilities (list cap) :exports (list exp) :entrypoint "main.wasm" :integritySha256 hash2))
            (invalid (pl/PluginManifest :id "" :name "Invalid" :version "1.0.0" :kind (pl/kindWasm) :capabilities (list) :exports (list) :entrypoint "main.wasm" :integritySha256 "mock-hash"))]
        (assert (is-ok? (sec/validateManifestSecurity valid dir)) "valid manifest ok")
        (assert (is-err? (sec/validateManifestSecurity invalid dir)) "invalid manifest err")
        true))))

(df testDispatchCall [] -> Bool
  :d "Tests plugin call dispatch validation."
  (let [(dir "tmp/sandbox_plugin_test_disp")]
    (do
      (ensureTestFixtures dir)
      (let [(reg (pl/emptyRegistry))
            (hash3 "1af2c6494b4a15fab5654e5f7ddae87166239460c270545386f132010e89db9a")
            (cap (pl/PluginCapability :name "cap-sh" :version "0.1.0" :doc "Shell Driver"))
            (exp (pl/PluginExport :symbolName "exec" :signature "() -> Unit" :doc "Shell execution" :requiredCapability "cap-sh"))
            (m (pl/PluginManifest :id "p-sh" :name "Shell Driver" :version "0.1.0" :kind (pl/kindHostDriver) :capabilities (list cap) :exports (list exp) :entrypoint "sh.bin" :integritySha256 hash3))
            (reg2Res (pl/registerPlugin reg m dir))]
        (assert (is-ok? reg2Res) "reg2 ok")
        (mt reg2Res
          ((ok reg2)
           (let [(secret "test-key")
                 (sigOk (sec/computeCallerSignature "user-1" (list "cap-sh") "100" secret))
                 (sigBad (sec/computeCallerSignature "user-2" (list) "100" secret))
                 (authOk (pl/CallerAuth :identity "user-1" :grantedCapabilities (list "cap-sh") :nonce "100" :signature sigOk))
                 (authBad (pl/CallerAuth :identity "user-2" :grantedCapabilities (list) :nonce "100" :signature sigBad))
                 (buf (pl/PluginBuffer :ptr 0 :size 0))
                 (resOk (pl/dispatchCall reg2 (pl/PluginCall :pluginId "p-sh" :symbolName "exec" :auth authOk :buffer buf) secret))
                 (resMissingSym (pl/dispatchCall reg2 (pl/PluginCall :pluginId "p-sh" :symbolName "non-existent" :auth authOk :buffer buf) secret))
                 (resMissingPlugin (pl/dispatchCall reg2 (pl/PluginCall :pluginId "unknown" :symbolName "exec" :auth authOk :buffer buf) secret))
                 (resAuthFail (pl/dispatchCall reg2 (pl/PluginCall :pluginId "p-sh" :symbolName "exec" :auth authBad :buffer buf) secret))]
             (assert (is-ok? resOk) "res-ok success")
             (refute (is-ok? resMissingSym) "missing-sym fails")
             (refute (is-ok? resMissingPlugin) "missing-plugin fails")
             (refute (is-ok? resAuthFail) "auth-fail fails")
             (mt resOk
               ((ok receipt)
                (do
                  (assert (= (.-invocationCount receipt) 1) "receipt count is 1")
                  true))
               ((err _) false))))
          ((err _) false))))))

(df runTests [] -> Bool
  :d "Runs all plugin test suites."
  (let [(r1 (testRegistryAndLookup))
        (r2 (testValidateManifest))
        (r3 (testDispatchCall))]
    (and r1 (and r2 r3))))
