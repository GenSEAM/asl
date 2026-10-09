(module aslPack/pack :x [BuildSpec PackageArtifact CapabilityReport DceResult planPackage generatePackagingManifest verifyPackageCapabilities eliminateDeadCapabilities validateManifestHash!] :i [(runtime :a rt) (platform :a plat)])

(schema BuildSpec (:f appName Str) (:f version Str) (:f entryModule Str) (:f targetPlatform plat/PlatformDescriptor) (:f environment rt/TargetEnvironment) (:f strictNoJit Bool) (:f embedWasm Bool))

(schema PackageArtifact (:f binaryName Str) (:f targetTriple Str) (:f runtimeName Str) (:f executionMode Str) (:f outputPath Str))

(schema CapabilityReport (:f valid Bool) (:f unauthorized (List Str)) (:f allowed (List Str)))

(schema DceResult (:f prunedCode Str) (:f eliminated (List Str)) (:f retained (List Str)))

fn planPackage spec: BuildSpec -> PackageArtifact
  (let [(p spec.targetPlatform) (binName (plat/formatBinaryName spec.appName p)) (profile (rt/recommendRuntimeProfile spec.environment true spec.strictNoJit)) (rtStr (rt/runtimeName profile.runtime)) (modeStr (rt/modeName profile.mode)) (outPath (str "dist/" binName))] (PackageArtifact :binaryName binName :targetTriple p.triple :runtimeName rtStr :executionMode modeStr :outputPath outPath))

fn generatePackagingManifest artifact: PackageArtifact -> Str
  (str "pack:{" artifact.binaryName "|" artifact.targetTriple "|" artifact.runtimeName "|" artifact.executionMode "|" artifact.outputPath "}")

fn verifyPackageCapabilities declared: (List Str) used: (List Str) -> CapabilityReport
  (let [(unauth (fold (fn [(acc (List Str)) (cap Str)] -> (List Str) (if (listContains? declared cap) acc (listAppend acc (list cap)))) (list) used))] (CapabilityReport :valid (listEmpty? unauth) :unauthorized unauth :allowed declared))

fn eliminateDeadCapabilities sourceCode: Str requestedCaps: (List Str) -> DceResult
  (let [(allPlatformCaps (list "netSocket" "procSpawn" "procWait" "procSignal" "fsWatch" "fsRead" "fsWrite" "fsStat" "timeMonotonic" "memAllocPage" "memFreePage")) (deadCaps (fold (fn [(acc (List Str)) (cap Str)] -> (List Str) (if (listContains? requestedCaps cap) acc (listAppend acc (list cap)))) (list) allPlatformCaps)) (pruned (fold (fn [(code Str) (deadCap Str)] -> Str (if (= deadCap "netSocket") (stringReplace (stringReplace code "asl_platform_darwin_net_socket" "/* dce: netSocket stripped */ 0") "asl_platform_linux_net_socket" "/* dce: netSocket stripped */ 0") (if (= deadCap "procSpawn") (stringReplace (stringReplace code "asl_platform_darwin_proc_spawn" "/* dce: procSpawn stripped */ 0") "asl_platform_linux_proc_spawn" "/* dce: procSpawn stripped */ 0") (if (= deadCap "fsWatch") (stringReplace (stringReplace code "asl_platform_darwin_fs_watch" "/* dce: fsWatch stripped */ 0") "asl_platform_linux_fs_watch" "/* dce: fsWatch stripped */ 0") code)))) sourceCode deadCaps))] (DceResult :prunedCode pruned :eliminated deadCaps :retained requestedCaps))

fn validateManifestHash! manifestContent: Str expectedDigest: Str -> Bool
  (if (or (stringEmpty? manifestContent) (stringEmpty? expectedDigest)) false (let [(escaped (stringReplace manifestContent "'" "'\\''")) (cmd (str "printf '%s' '" escaped "' | shasum -a 256 2>/dev/null | awk '{print $1}' || printf '%s' '" escaped "' | sha256sum | awk '{print $1}'")) (res (processRun cmd))] (if (!= res.exitCode 0) false (let [(computed (stringTrim res.stdout))] (= computed expectedDigest)))))
