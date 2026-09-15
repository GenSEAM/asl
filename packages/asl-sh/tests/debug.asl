(module asl-sh/debug
  :x [runTests]
  :i [(plugin :a pl)
      (security :a sec)])
(df runTests [] -> Bool
  (let [(hash2 "6403203dd5a0867eb14d104ee8a73730bd72dd9ad92e78d996a6dba0a5dcfc01")
        (cap (pl/PluginCapability :name "cap-db" :version "1.0.0" :doc "SQL database access"))
        (exp (pl/PluginExport :symbolName "query" :signature "(query Str (List Str)) -> (Result Str Str)" :requiredCapability "cap-db"))
        (valid (pl/PluginManifest :id "p1" :name "Plugin One" :version "1.0.0" :kind (pl/kindWasm) :capabilities (list cap) :exports (list exp) :entrypoint "main.wasm" :integritySha256 hash2))
        (res (sec/validateManifestSecurity valid "sandbox"))]
    (mt res
      ((ok _) (assert (= 1 2) "success"))
      ((err e) 
       (mt e
         ((errNotFound id) (assert (= 1 2) (str "errNotFound " id)))
         ((errDuplicateId id) (assert (= 1 2) (str "errDuplicateId " id)))
         ((errInvalidSignature id) (assert (= 1 2) (str "errInvalidSignature " id)))
         ((errUnauthorized id) (assert (= 1 2) (str "errUnauthorized " id)))
         ((errSandboxEscape id) (assert (= 1 2) (str "errSandboxEscape " id)))
         ((errExecutionTrap id) (assert (= 1 2) (str "errExecutionTrap " id)))
         ((errTimeout id) (assert (= 1 2) "errTimeout"))
         ((errUnimplemented id) (assert (= 1 2) (str "errUnimplemented " id)))
         ((errRegistrySealed) (assert (= 1 2) "errRegistrySealed")))))
    true))
