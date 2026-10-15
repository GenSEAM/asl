(module asl-plugin/types
  :x [PluginKind PluginCapability PluginExport PluginManifest PluginInstance PluginRegistry PluginBuffer PluginError PluginResult PluginCall CallerAuth
      DispatchReceipt DispatchFault
      kindWasm kindNativeFfi kindHostDriver
      errNotFound errDuplicateId errInvalidSignature errUnauthorized errSandboxEscape errExecutionTrap errTimeout errUnimplemented errRegistrySealed]
  :i [])

(enum PluginKind
  (:c kindWasm [] "WebAssembly module plugin")
  (:c kindNativeFfi [] "Native host shared object FFI plugin")
  (:c kindHostDriver [] "External driver or subprocess host plugin"))

(schema PluginCapability
  (:f name Str)
  (:f version Str "Capability semantic version string")
  (:f doc Str "Capability specification documentation"))

(schema PluginExport
  (:f symbolName Str)
  (:f signature Str "AgentSlang typed signature description")
  (:f doc Str "Export documentation")
  (:f requiredCapability Str "Capability token required to invoke this export"))

(schema PluginManifest
  (:f id Str)
  (:f name Str)
  (:f version Str)
  (:f kind PluginKind)
  (:f capabilities (List PluginCapability))
  (:f exports (List PluginExport) "List of exposed symbols")
  (:f entrypoint Str "Path or symbol entrypoint")
  (:f integritySha256 Str "Cryptographic hash of the artifact for integrity verification"))

(schema PluginInstance
  (:f pluginId Str "Identifier of the associated plugin manifest")
  (:f memoryHandle Int64 "Opaque pointer to native memory or Wasm instance")
  (:f invocationCount Int64 "Number of times this plugin was dispatched"))

(schema PluginRegistry
  (:f manifests (Map Str PluginManifest))
  (:f instances (Map Str PluginInstance))
  (:f capabilityIndex (Map Str (List Str)) "Map of capability name to list of providing plugin IDs")
  (:f callerNonces (Map Str Int64) "Map of caller identity to latest monotonic anti-replay nonce")
  (:f sealed Bool "If true, no further mutations are allowed (prevents poisoning)"))

(schema PluginBuffer
  (:f ptr Int64 "Pointer to the linear memory or arena offset")
  (:f size Int64 "Size of the buffer in bytes"))

(enum PluginError
  (:c errNotFound [pluginId Str])
  (:c errDuplicateId [pluginId Str])
  (:c errInvalidSignature [detail Str])
  (:c errUnauthorized [detail Str])
  (:c errSandboxEscape [path Str])
  (:c errExecutionTrap [reason Str])
  (:c errTimeout [timeoutMs Int64])
  (:c errUnimplemented [reason Str])
  (:c errRegistrySealed []))

(schema PluginResult
  (:f buffer PluginBuffer "Output binary data")
  (:f updatedInstance PluginInstance "The state-evolved instance after dispatch"))

(schema CallerAuth
  (:f identity Str "Caller identity or session ID")
  (:f grantedCapabilities (List Str) "List of capabilities granted to this caller")
  (:f nonce Str "Anti-replay monotonic timestamp or cryptographic nonce")
  (:f signature Str "HMAC-SHA256 hex signature over identity, nonce, and capabilities"))

(schema PluginCall
  (:f pluginId Str "Target plugin ID")
  (:f symbolName Str "Target symbol name to invoke")
  (:f auth CallerAuth "Structured capability authorization token from caller")
  (:f buffer PluginBuffer "Input binary payload"))

(schema DispatchReceipt
  (:f registry PluginRegistry "State-evolved plugin registry maintaining SSOT")
  (:f buffer PluginBuffer "Zero-copy output execution payload buffer")
  (:f invocationCount Int64 "Updated invocation count for the invoked plugin"))

(schema DispatchFault
  (:f registry PluginRegistry "Preserved registry state preventing Asymmetric Fault Drop")
  (:f error PluginError "Root cause failure classification"))
