(module asl-plugin/types
  :d "Core types and algebraic data models for the plugin architecture."
  :x [PluginKind PluginCapability PluginExport PluginManifest PluginInstance PluginRegistry PluginBuffer PluginError PluginResult PluginCall CallerAuth
      DispatchReceipt DispatchFault
      kindWasm kindNativeFfi kindHostDriver
      errNotFound errDuplicateId errInvalidSignature errUnauthorized errSandboxEscape errExecutionTrap errTimeout errUnimplemented errRegistrySealed]
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
  (:f doc Str "Export documentation")
  (:f requiredCapability Str "Capability token required to invoke this export"))

(dfs PluginManifest
  (:f id Str "Unique plugin identifier e.g. plugin-postgres")
  (:f name Str "Human-readable plugin name")
  (:f version Str "Plugin semantic version")
  (:f kind PluginKind "Plugin runtime boundary type")
  (:f capabilities (List PluginCapability) "List of implemented capabilities")
  (:f exports (List PluginExport) "List of exposed symbols")
  (:f entrypoint Str "Path or symbol entrypoint")
  (:f integritySha256 Str "Cryptographic hash of the artifact for integrity verification"))

(dfs PluginInstance
  (:f pluginId Str "Identifier of the associated plugin manifest")
  (:f memoryHandle Int64 "Opaque pointer to native memory or Wasm instance")
  (:f invocationCount Int64 "Number of times this plugin was dispatched"))

(dfs PluginRegistry
  (:f manifests (Map Str PluginManifest) "Map of plugin ID to plugin manifest")
  (:f instances (Map Str PluginInstance) "Map of active plugin instances")
  (:f capabilityIndex (Map Str (List Str)) "Map of capability name to list of providing plugin IDs")
  (:f callerNonces (Map Str Int64) "Map of caller identity to latest monotonic anti-replay nonce")
  (:f sealed Bool "If true, no further mutations are allowed (prevents poisoning)"))

(dfs PluginBuffer
  (:f ptr Int64 "Pointer to the linear memory or arena offset")
  (:f size Int64 "Size of the buffer in bytes"))

(dfe PluginError
  (:c errNotFound [pluginId Str])
  (:c errDuplicateId [pluginId Str])
  (:c errInvalidSignature [detail Str])
  (:c errUnauthorized [detail Str])
  (:c errSandboxEscape [path Str])
  (:c errExecutionTrap [reason Str])
  (:c errTimeout [timeoutMs Int64])
  (:c errUnimplemented [reason Str])
  (:c errRegistrySealed []))

(dfs PluginResult
  (:f buffer PluginBuffer "Output binary data")
  (:f updatedInstance PluginInstance "The state-evolved instance after dispatch"))

(dfs CallerAuth
  (:f identity Str "Caller identity or session ID")
  (:f grantedCapabilities (List Str) "List of capabilities granted to this caller")
  (:f nonce Str "Anti-replay monotonic timestamp or cryptographic nonce")
  (:f signature Str "HMAC-SHA256 hex signature over identity, nonce, and capabilities"))

(dfs PluginCall
  (:f pluginId Str "Target plugin ID")
  (:f symbolName Str "Target symbol name to invoke")
  (:f auth CallerAuth "Structured capability authorization token from caller")
  (:f buffer PluginBuffer "Input binary payload"))

(dfs DispatchReceipt
  (:f registry PluginRegistry "State-evolved plugin registry maintaining SSOT")
  (:f buffer PluginBuffer "Zero-copy output execution payload buffer")
  (:f invocationCount Int64 "Updated invocation count for the invoked plugin"))

(dfs DispatchFault
  (:f registry PluginRegistry "Preserved registry state preventing Asymmetric Fault Drop")
  (:f error PluginError "Root cause failure classification"))
