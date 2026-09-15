(module aslPack/pack
  :d "Universal cross-platform packaging orchestrator for standalone AgentScript executables and libraries."
  :x [BuildSpec
      PackageArtifact
      planPackage
      generatePackagingManifest]
  :i [(runtime :a rt)
      (platform :a plat)])

(dfs BuildSpec
  (:f appName Str "Application or toolchain binary name")
  (:f version Str "Semver release version string")
  (:f entryModule Str "Root ASL entrypoint module path")
  (:f targetPlatform plat/PlatformDescriptor "Target OS and CPU architecture")
  (:f environment rt/TargetEnvironment "Target deployment environment")
  (:f strictNoJit Bool "Enforces Ahead-of-Time or interpreted execution without dynamic JIT")
  (:f embedWasm Bool "Embeds compiled WebAssembly bytecode directly into runner payload"))

(dfs PackageArtifact
  (:f binaryName Str "Canonical output executable name")
  (:f targetTriple Str "Target LLVM platform triple")
  (:f runtimeName Str "Configured WebAssembly runtime engine")
  (:f executionMode Str "Selected compilation or interpretation strategy")
  (:f outputPath Str "Destination directory or file path"))

(df planPackage [(spec BuildSpec)] -> PackageArtifact
  :d "Resolves runtime profile, platform triple, and produces deterministic packaging plan."
  (let [(p (.-targetPlatform spec))
        (binName (plat/formatBinaryName (.-appName spec) p))
        (profile (rt/recommendRuntimeProfile (.-environment spec) true (.-strictNoJit spec)))
        (rtStr (rt/runtimeName (.-runtime profile)))
        (modeStr (rt/modeName (.-mode profile)))
        (outPath (str "dist/" binName))]
    (PackageArtifact
      :binaryName binName
      :targetTriple (.-triple p)
      :runtimeName rtStr
      :executionMode modeStr
      :outputPath outPath)))

(df generatePackagingManifest [(artifact PackageArtifact)] -> Str
  :d "Serializes package artifact plan into standard ASN metadata header."
  (str "pack:{"
       (.-binaryName artifact) "|"
       (.-targetTriple artifact) "|"
       (.-runtimeName artifact) "|"
       (.-executionMode artifact) "|"
       (.-outputPath artifact) "}"))
