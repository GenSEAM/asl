(module asl-plugin/plugin :x [emptyRegistry registerPlugin lookupManifest lookupInstance hasCapability? findPluginsByCapability dispatchCall sealRegistry] :i [(asl-plugin/types :a t) (asl-plugin/security :a sec)])

fn emptyRegistry -> t/PluginRegistry
  (t/PluginRegistry :manifests (mapEmpty) :instances (mapEmpty) :capabilityIndex (mapEmpty) :callerNonces (mapEmpty) :sealed false)

fn sealRegistry reg: t/PluginRegistry -> t/PluginRegistry
  (t/PluginRegistry :manifests reg.manifests :instances reg.instances :capabilityIndex reg.capabilityIndex :callerNonces reg.callerNonces :sealed true)

fn indexPluginCapabilities capIndex: (Map Str (List Str)) pluginId: Str caps: (List t/PluginCapability) -> (Result (Map Str (List Str)) t/PluginError)
  (fold (fn [(acc (Result (Map Str (List Str)) t/PluginError)) (c t/PluginCapability)] -> (Result (Map Str (List Str)) t/PluginError) (mt acc ((err e) (err e)) ((ok index) (let [(cName c.name)] (if (stringStartsWith? cName "core-") (err (t/errInvalidSignature (str "Cannot register core capability namespace: " cName))) (let [(existing (optionOr (mapGet index cName) (list)))] (if (listContains? existing pluginId) (ok index) (let [(updated (listAppend existing (list pluginId)))] (ok (mapSet index cName updated)))))))))) (ok capIndex) caps)

fn ! registerPlugin reg: t/PluginRegistry manifest: t/PluginManifest sandboxRoot: Str -> (Result t/PluginRegistry t/PluginError)
  (let [(pId manifest.id)] (cond (reg.sealed (err (t/errRegistrySealed))) ((some? (mapGet reg.manifests pId)) (err (t/errDuplicateId pId))) (else (mt (sec/validateManifestSecurity! manifest sandboxRoot) ((err e) (err e)) ((ok _) (let [(indexRes (indexPluginCapabilities reg.capabilityIndex pId manifest.capabilities))] (mt indexRes ((err e) (err e)) ((ok updatedIndex) (let [(updatedManifests (mapSet reg.manifests pId manifest)) (initialInstance (t/PluginInstance :pluginId pId :memoryHandle 0 :invocationCount 0)) (updatedInstances (mapSet reg.instances pId initialInstance))] (ok (t/PluginRegistry :manifests updatedManifests :instances updatedInstances :capabilityIndex updatedIndex :callerNonces reg.callerNonces :sealed reg.sealed)))))))))))

fn lookupManifest reg: t/PluginRegistry pluginId: Str -> (Option t/PluginManifest)
  (mapGet reg.manifests pluginId)

fn lookupInstance reg: t/PluginRegistry pluginId: Str -> (Option t/PluginInstance)
  (mapGet reg.instances pluginId)

fn hasCapability? manifest: t/PluginManifest capabilityName: Str -> Bool
  (let [(matches (filter (fn [(c t/PluginCapability)] -> Bool (= c.name capabilityName)) manifest.capabilities))] (not (listEmpty? matches)))

fn findPluginsByCapability reg: t/PluginRegistry capabilityName: Str -> (List Str)
  (optionOr (mapGet reg.capabilityIndex capabilityName) (list))

fn ! dispatchCall reg: t/PluginRegistry call: t/PluginCall secretKey: Str -> (Result t/DispatchReceipt t/DispatchFault)
  (let [(pOpt (lookupInstance reg call.pluginId))] (mt pOpt ((none) (err (t/DispatchFault :registry reg :error (t/errNotFound call.pluginId)))) ((some inst) (let [(mOpt (lookupManifest reg call.pluginId))] (mt mOpt ((none) (err (t/DispatchFault :registry reg :error (t/errNotFound call.pluginId)))) ((some manifest) (let [(expMatches (filter (fn [(e t/PluginExport)] -> Bool (= e.symbolName call.symbolName)) manifest.exports))] (if (listEmpty? expMatches) (err (t/DispatchFault :registry reg :error (t/errInvalidSignature (str "Symbol not exported: " call.symbolName)))) (let [(expDef (optionOr (listHead expMatches) (t/PluginExport :symbolName "" :signature "" :doc "" :requiredCapability ""))) (auth call.auth) (callerId auth.identity) (hasNonce? (not (stringEmpty? auth.nonce)))] (if hasNonce? (let [(nonceOpt (stringToInt64 auth.nonce))] (mt nonceOpt ((none) (err (t/DispatchFault :registry reg :error (t/errUnauthorized "Invalid nonce format")))) ((some nonceVal) (let [(lastNonce (optionOr (mapGet reg.callerNonces callerId) 0))] (if (<= nonceVal lastNonce) (err (t/DispatchFault :registry reg :error (t/errUnauthorized "Replayed or out-of-order nonce"))) (let [(authRes (sec/authorizeCall! auth expDef secretKey))] (mt authRes ((err e) (err (t/DispatchFault :registry reg :error e))) ((ok _) (let [(updatedNonces (mapSet reg.callerNonces callerId nonceVal)) (updatedInst (t/PluginInstance :pluginId inst.pluginId :memoryHandle inst.memoryHandle :invocationCount (+ inst.invocationCount 1))) (mockOutBuffer (t/PluginBuffer :ptr 0 :size 0)) (updatedInstances (mapSet reg.instances call.pluginId updatedInst)) (updatedReg (t/PluginRegistry :manifests reg.manifests :instances updatedInstances :capabilityIndex reg.capabilityIndex :callerNonces updatedNonces :sealed reg.sealed))] (ok (t/DispatchReceipt :registry updatedReg :buffer mockOutBuffer :invocationCount updatedInst.invocationCount))))))))))) (let [(authRes (sec/authorizeCall! auth expDef secretKey))] (mt authRes ((err e) (err (t/DispatchFault :registry reg :error e))) ((ok _) (let [(updatedInst (t/PluginInstance :pluginId inst.pluginId :memoryHandle inst.memoryHandle :invocationCount (+ inst.invocationCount 1))) (mockOutBuffer (t/PluginBuffer :ptr 0 :size 0)) (updatedInstances (mapSet reg.instances call.pluginId updatedInst)) (updatedReg (t/PluginRegistry :manifests reg.manifests :instances updatedInstances :capabilityIndex reg.capabilityIndex :callerNonces reg.callerNonces :sealed reg.sealed))] (ok (t/DispatchReceipt :registry updatedReg :buffer mockOutBuffer :invocationCount updatedInst.invocationCount))))))))))))))))
