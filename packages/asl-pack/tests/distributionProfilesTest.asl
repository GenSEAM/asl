(module aslPack/distributionProfilesTest
  :x [runTests]
  :i [(distributionProfiles :a dp)])

fn testCoreDistributionProfile -> Bool
  (let [(profile (dp/makeDistributionProfile "core" "0.2.0"))]
    (do
      (assert (= profile.name "core") "Profile name must be core")
      (assert profile.isDynamic "Core profile must enable dynamic loading")
      (assert (= profile.binaryName "asl") "Core binary name must be asl")
      (assert (dp/validateCoreEntrypoint profile) "Core entrypoint must be valid single point of entry")
      (refute profile.isAllInOne "Core profile must not be fat/all-in-one")
      true))

fn testPackagePullPlanning -> Bool
  (let [(pullPlan (dp/planPackagePull "asl-mesh" "https://github.com/GenSEAM/asl.git" "v0.2.0"))]
    (do
      (assert (= pullPlan.packageName "asl-mesh") "Pull plan package name must match")
      (assert (= pullPlan.gitUrl "https://github.com/GenSEAM/asl.git") "Git URL must match")
      (assert (= pullPlan.tag "v0.2.0") "Tag must match")
      (assert (stringContains? pullPlan.targetDir "asl/packages/asl-mesh") "Target dir must be package dir")
      (assert pullPlan.autoLink "Pull plan must enable auto-linking")
      (refute (stringEmpty? pullPlan.gitUrl) "Git URL must not be empty")
      (refute (= pullPlan.tag "") "Tag must not be empty")
      true))

fn testFullDistributionProfile -> Bool
  (let [(fullProf (dp/makeDistributionProfile "full" "0.2.0"))]
    (do
      (assert (= fullProf.name "full") "Profile name must be full")
      (assert fullProf.isAllInOne "Full profile must be all-in-one fat binary")
      (assert (= fullProf.binaryName "asl-full") "Full binary name must be asl-full")
      (assert (>= (listLength fullProf.bundledPackages) 6) "Full binary must bundle at least 6 primary packages")
      (assert (listContains? fullProf.bundledPackages "asl-compiler") "Full binary must bundle asl-compiler")
      (assert (listContains? fullProf.bundledPackages "asl-ir") "Full binary must bundle asl-ir")
      (assert (listContains? fullProf.bundledPackages "asl-mem") "Full binary must bundle asl-mem")
      (assert (listContains? fullProf.bundledPackages "asl-mesh") "Full binary must bundle asl-mesh")
      (refute fullProf.isDynamic "Full binary does not depend on dynamic pull")
      true))

fn testBrowserDistributionProfile -> Bool
  (let [(browserProf (dp/makeDistributionProfile "browser" "0.2.0"))]
    (do
      (assert (= browserProf.name "browser") "Profile name must be browser")
      (assert browserProf.isBrowserTarget "Browser profile must target browser")
      (assert (= browserProf.outputWasm "dist/web/asl.wasm") "WASM path must match")
      (assert (= browserProf.entryHtml "dist/web/index.html") "Entry HTML must match")
      (refute browserProf.isAllInOne "Browser profile must not be native fat binary")
      true))

fn runTests -> Bool
  (do
    (assert (testCoreDistributionProfile) "testCoreDistributionProfile must pass")
    (assert (testPackagePullPlanning) "testPackagePullPlanning must pass")
    (assert (testFullDistributionProfile) "testFullDistributionProfile must pass")
    (assert (testBrowserDistributionProfile) "testBrowserDistributionProfile must pass")
    true)
