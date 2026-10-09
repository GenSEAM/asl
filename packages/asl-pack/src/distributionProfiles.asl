(module aslPack/distributionProfiles
  :x [DistributionProfile PackagePullPlan makeDistributionProfile validateCoreEntrypoint validateCoreEntryPoint planPackagePull defaultBundledPackages]
  :i [])

(schema DistributionProfile
  (:f name Str)
  (:f version Str)
  (:f isDynamic Bool)
  (:f isAllInOne Bool)
  (:f isBrowserTarget Bool)
  (:f binaryName Str)
  (:f bundledPackages (List Str))
  (:f outputWasm Str)
  (:f entryHtml Str)
  (:f maxPullDepth I64)
  (:f observationMasking Bool))

(schema PackagePullPlan
  (:f packageName Str)
  (:f gitUrl Str)
  (:f tag Str)
  (:f targetDir Str)
  (:f autoLink Bool)
  (:f sha256 (Option Str)))

fn defaultBundledPackages -> (List Str)
  (list "asl-compiler" "asl-ir" "asl-mem" "asl-mesh" "asl-pack" "asl-target-llvm" "asl-target-wat" "asl-gateway" "asl-help")

fn makeDistributionProfile profileName: Str ver: Str -> DistributionProfile
  (cond
    ((= profileName "core")
      (DistributionProfile
        :name "core"
        :version ver
        :isDynamic true
        :isAllInOne false
        :isBrowserTarget false
        :binaryName "asl"
        :bundledPackages (list "asl-pack")
        :outputWasm ""
        :entryHtml ""
        :maxPullDepth 3
        :observationMasking true))
    ((= profileName "full")
      (DistributionProfile
        :name "full"
        :version ver
        :isDynamic false
        :isAllInOne true
        :isBrowserTarget false
        :binaryName "asl-full"
        :bundledPackages (defaultBundledPackages)
        :outputWasm ""
        :entryHtml ""
        :maxPullDepth 0
        :observationMasking true))
    ((= profileName "browser")
      (DistributionProfile
        :name "browser"
        :version ver
        :isDynamic false
        :isAllInOne false
        :isBrowserTarget true
        :binaryName "asl-web"
        :bundledPackages (list "asl-compiler" "asl-mem")
        :outputWasm "dist/web/asl.wasm"
        :entryHtml "dist/web/index.html"
        :maxPullDepth 0
        :observationMasking true))
    (else
      (DistributionProfile
        :name profileName
        :version ver
        :isDynamic false
        :isAllInOne false
        :isBrowserTarget false
        :binaryName "asl"
        :bundledPackages (list)
        :outputWasm ""
        :entryHtml ""
        :maxPullDepth 3
        :observationMasking true)))

fn validateCoreEntryPoint profile: DistributionProfile -> Bool
  (and (= profile.name "core")
       (= profile.binaryName "asl")
       profile.isDynamic)

fn validateCoreEntrypoint profile: DistributionProfile -> Bool
  (validateCoreEntryPoint profile)

fn planPackagePull pkg: Str url: Str tag: Str -> PackagePullPlan
  (PackagePullPlan
    :packageName pkg
    :gitUrl url
    :tag tag
    :targetDir (str "asl/packages/" pkg)
    :autoLink true
    :sha256 none)
