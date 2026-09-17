(module aslPack/pack
  :d "Universal cross-platform packaging orchestrator for standalone AgentScript executables and libraries."
  :x [BuildSpec
      PackageArtifact
      CapabilityReport
      DceResult
      planPackage
      generatePackagingManifest
      verifyPackageCapabilities
      eliminateDeadCapabilities
      validateManifestHash]
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

(dfs CapabilityReport
  (:f valid Bool "True if all used capabilities are declared")
  (:f unauthorized (List Str) "List of capabilities used without declaration")
  (:f allowed (List Str) "List of authorized capabilities"))

(dfs DceResult
  (:f prunedCode Str "Generated code after dead capability elimination")
  (:f eliminated (List Str) "List of dead capability syscall stubs stripped")
  (:f retained (List Str) "List of active capability syscall stubs retained"))

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

(df verifyPackageCapabilities [(declared (List Str)) (used (List Str))] -> CapabilityReport
  :d "Link-time capability sandboxing pass verifying used capabilities against declared package capabilities."
  (let [(unauth (fold (fn [(acc (List Str)) (cap Str)] -> (List Str)
                        (if (list-contains? declared cap)
                          acc
                          (list-append acc (list cap))))
                      (list)
                      used))]
    (CapabilityReport
      :valid (list-empty? unauth)
      :unauthorized unauth
      :allowed declared)))

(df eliminateDeadCapabilities [(sourceCode Str) (requestedCaps (List Str))] -> DceResult
  :d "Eliminates unreferenced platform syscall stubs from emitted C99 or WASM source code."
  (let [(allPlatformCaps (list "netSocket" "procSpawn" "procWait" "procSignal" "fsWatch" "fsRead" "fsWrite" "fsStat" "timeMonotonic" "memAllocPage" "memFreePage"))
        (deadCaps (fold (fn [(acc (List Str)) (cap Str)] -> (List Str)
                          (if (list-contains? requestedCaps cap)
                            acc
                            (list-append acc (list cap))))
                        (list)
                        allPlatformCaps))
        (pruned (fold (fn [(code Str) (deadCap Str)] -> Str
                        (if (= deadCap "netSocket")
                          (string-replace (string-replace code "asl_platform_darwin_net_socket" "/* dce: netSocket stripped */ 0")
                                          "asl_platform_linux_net_socket" "/* dce: netSocket stripped */ 0")
                          (if (= deadCap "procSpawn")
                            (string-replace (string-replace code "asl_platform_darwin_proc_spawn" "/* dce: procSpawn stripped */ 0")
                                            "asl_platform_linux_proc_spawn" "/* dce: procSpawn stripped */ 0")
                            (if (= deadCap "fsWatch")
                              (string-replace (string-replace code "asl_platform_darwin_fs_watch" "/* dce: fsWatch stripped */ 0")
                                              "asl_platform_linux_fs_watch" "/* dce: fsWatch stripped */ 0")
                              code))))
                      sourceCode
                      deadCaps))]
    (DceResult
      :prunedCode pruned
      :eliminated deadCaps
      :retained requestedCaps)))

(df validateManifestHash [(manifestContent Str) (expectedDigest Str)] -> Bool
  :d "Validates package manifest content against expected integrity digest."
  (if (or (string-empty? manifestContent) (string-empty? expectedDigest))
      false
      (let [(escaped (string-replace manifestContent "'" "'\\''"))
            (cmd (str "printf '%s' '" escaped "' | shasum -a 256 2>/dev/null | awk '{print $1}' || printf '%s' '" escaped "' | sha256sum | awk '{print $1}'"))
            (res (sysExec cmd))]
        (if (!= (.-exitCode res) 0)
            false
            (let [(computed (string-trim (.-stdout res)))]
              (= computed expectedDigest))))))
