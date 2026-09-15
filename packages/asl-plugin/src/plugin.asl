(module asl-plugin/plugin
  :d "Formal plugin specification and capability registry for AgentScript core."
  :x [emptyRegistry registerPlugin lookupManifest lookupInstance hasCapability? findPluginsByCapability dispatchCall sealRegistry
      PluginKind PluginCapability PluginExport PluginManifest PluginInstance PluginRegistry PluginBuffer PluginError PluginResult PluginCall CallerAuth
      DispatchReceipt DispatchFault
      kindWasm kindNativeFfi kindHostDriver
      errNotFound errDuplicateId errInvalidSignature errUnauthorized errSandboxEscape errExecutionTrap errTimeout errUnimplemented errRegistrySealed]
  :i [(asl-plugin/types) (asl-plugin/security)])

(df emptyRegistry [] -> PluginRegistry
  :d "Initializes an empty sealed-off plugin registry."
  (PluginRegistry :manifests (map-empty) :instances (map-empty) :capabilityIndex (map-empty) :callerNonces (map-empty) :sealed false))

(df sealRegistry [(reg PluginRegistry)] -> PluginRegistry
  :d "Seals the registry, preventing any further plugin registration (Registry Poisoning defense)."
  (PluginRegistry :manifests (.-manifests reg) :instances (.-instances reg) :capabilityIndex (.-capabilityIndex reg) :callerNonces (.-callerNonces reg) :sealed true))

(df indexPluginCapabilities [(capIndex (Map Str (List Str))) (pluginId Str) (caps (List PluginCapability))] -> (Result (Map Str (List Str)) PluginError)
  :d "Indexes all capabilities provided by a plugin into the registry index with deduplication."
  (fold (fn [(acc (Result (Map Str (List Str)) PluginError)) (c PluginCapability)] -> (Result (Map Str (List Str)) PluginError)
          (mt acc
            ((err e) (err e))
            ((ok index)
             (let [(cName (.-name c))]
               (if (string-starts-with? cName "core-")
                   (err (errInvalidSignature (str "Cannot register core capability namespace: " cName)))
                   (let [(existing (option-or (map-get index cName) (list)))]
                     (if (list-contains? existing pluginId)
                         (ok index)
                         (let [(updated (list-concat existing (list pluginId)))]
                           (ok (map-set index cName updated))))))))))
        (ok capIndex)
        caps))

(df registerPlugin [(reg PluginRegistry) (manifest PluginManifest) (sandboxRoot Str)] -> (Result PluginRegistry PluginError)
  :d "Validates and registers a plugin manifest, blocking if sealed or duplicated."
  (let [(pId (.-id manifest))]
    (cond
      ((.-sealed reg)
       (err (errRegistrySealed)))
      ((option-some? (map-get (.-manifests reg) pId))
       (err (errDuplicateId pId)))
      (:else
       (mt (validateManifestSecurity manifest sandboxRoot)
         ((err e) (err e))
         ((ok _)
          (let [(indexRes (indexPluginCapabilities (.-capabilityIndex reg) pId (.-capabilities manifest)))]
         (mt indexRes
           ((err e) (err e))
           ((ok updatedIndex)
            (let [(updatedManifests (map-set (.-manifests reg) pId manifest))
                  (initialInstance (PluginInstance :pluginId pId :memoryHandle 0 :invocationCount 0))
                  (updatedInstances (map-set (.-instances reg) pId initialInstance))]
              (ok (PluginRegistry :manifests updatedManifests :instances updatedInstances :capabilityIndex updatedIndex :callerNonces (.-callerNonces reg) :sealed (.-sealed reg)))))))))))))

(df lookupManifest [(reg PluginRegistry) (pluginId Str)] -> (Option PluginManifest)
  :d "Looks up a plugin manifest by its identifier."
  (map-get (.-manifests reg) pluginId))

(df lookupInstance [(reg PluginRegistry) (pluginId Str)] -> (Option PluginInstance)
  :d "Looks up a plugin active instance by its identifier."
  (map-get (.-instances reg) pluginId))

(df hasCapability? [(manifest PluginManifest) (capabilityName Str)] -> Bool
  :d "Checks whether a plugin manifest implements a specific capability."
  (let [(matches (filter (fn [(c PluginCapability)] -> Bool
                           (= (.-name c) capabilityName))
                         (.-capabilities manifest)))]
    (not (list-empty? matches))))
(df findPluginsByCapability [(reg PluginRegistry) (capabilityName Str)] -> (List Str)
  :d "Retrieves list of plugin IDs advertising the requested capability."
  (option-or (map-get (.-capabilityIndex reg) capabilityName) (list)))

(df dispatchCall [(reg PluginRegistry) (call PluginCall) (secretKey Str)] -> (Result DispatchReceipt DispatchFault)
  :d "Dispatches a foreign call, enforcing authorization and returning algebraic state updates including the updated registry."
  (let [(pOpt (lookupInstance reg (.-pluginId call)))]
    (mt pOpt
      ((none) (err (DispatchFault :registry reg :error (errNotFound (.-pluginId call)))))
      ((some inst)
       (let [(mOpt (lookupManifest reg (.-pluginId call)))]
         (mt mOpt
           ((none) (err (DispatchFault :registry reg :error (errNotFound (.-pluginId call)))))
           ((some manifest)
            (let [(expMatches (filter (fn [(e PluginExport)] -> Bool
                                        (= (.-symbolName e) (.-symbolName call)))
                                      (.-exports manifest)))]
              (if (list-empty? expMatches)
                  (err (DispatchFault :registry reg :error (errInvalidSignature (str "Symbol not exported: " (.-symbolName call)))))
                  (let [(expDef (option-or (list-head expMatches) (PluginExport :symbolName "" :signature "" :doc "" :requiredCapability "")))
                        (auth (.-auth call))
                        (callerId (.-identity auth))
                        (hasNonce? (not (string-empty? (.-nonce auth))))]
                    (if hasNonce?
                        (let [(nonceOpt (string-to-int64 (.-nonce auth)))]
                          (mt nonceOpt
                            ((none)
                             (err (DispatchFault :registry reg :error (errUnauthorized "Invalid nonce format"))))
                            ((some nonceVal)
                             (let [(lastNonce (option-or (map-get (.-callerNonces reg) callerId) 0))]
                               (if (<= nonceVal lastNonce)
                                   (err (DispatchFault :registry reg :error (errUnauthorized "Replayed or out-of-order nonce")))
                                   (let [(authRes (authorizeCall auth expDef secretKey))]
                                     (mt authRes
                                       ((err e) (err (DispatchFault :registry reg :error e)))
                                       ((ok _)
                                        (let [(updatedNonces (map-set (.-callerNonces reg) callerId nonceVal))
                                              (updatedInst (PluginInstance :pluginId (.-pluginId inst) :memoryHandle (.-memoryHandle inst) :invocationCount (+ (.-invocationCount inst) 1)))
                                              (mockOutBuffer (PluginBuffer :ptr 0 :size 0))
                                              (updatedInstances (map-set (.-instances reg) (.-pluginId call) updatedInst))
                                              (updatedReg (PluginRegistry :manifests (.-manifests reg) :instances updatedInstances :capabilityIndex (.-capabilityIndex reg) :callerNonces updatedNonces :sealed (.-sealed reg)))]
                                          (ok (DispatchReceipt :registry updatedReg :buffer mockOutBuffer :invocationCount (.-invocationCount updatedInst))))))))))))
                        (let [(authRes (authorizeCall auth expDef secretKey))]
                          (mt authRes
                            ((err e) (err (DispatchFault :registry reg :error e)))
                            ((ok _)
                             (let [(updatedInst (PluginInstance :pluginId (.-pluginId inst) :memoryHandle (.-memoryHandle inst) :invocationCount (+ (.-invocationCount inst) 1)))
                                   (mockOutBuffer (PluginBuffer :ptr 0 :size 0))
                                   (updatedInstances (map-set (.-instances reg) (.-pluginId call) updatedInst))
                                   (updatedReg (PluginRegistry :manifests (.-manifests reg) :instances updatedInstances :capabilityIndex (.-capabilityIndex reg) :callerNonces (.-callerNonces reg) :sealed (.-sealed reg)))]
                               (ok (DispatchReceipt :registry updatedReg :buffer mockOutBuffer :invocationCount (.-invocationCount updatedInst))))))))))))))))))

