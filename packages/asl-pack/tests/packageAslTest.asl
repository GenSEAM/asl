(module aslPack/packageAslTest
  :x [runTests]
  :i [(packageAsl :a pkg)])

fn testPackageDefCreation -> Bool
  (let [(dep1 (pkg/PackageDependency :name "asl-core" :sourceType "local" :gitUrl "" :tag "" :checksum ""))
        (dep2 (pkg/PackageDependency :name "asl-crypto" :sourceType "git" :gitUrl "https://github.com/GenSEAM/asl-crypto" :tag "v0.1.0" :checksum "sha256:8f2a"))
        (pDef (pkg/PackageDef
                :name "asl-mesh"
                :version "0.2.0"
                :public true
                :entry "src/main.asl"
                :doc "Distributed consensus mesh"
                :modules (list "asl-mesh/raft" "asl-mesh/coord")
                :dependencies (list dep1 dep2)))]
    (do
      (assert (= pDef.name "asl-mesh") "Package name must match")
      (assert (= pDef.version "0.2.0") "Package version must match")
      (assert pDef.public "Package must be public")
      (assert (= pDef.entry "src/main.asl") "Entry must match")
      (assert (= (listLength pDef.dependencies) 2) "Must have 2 dependencies")
      (assert (pkg/isPublishablePackage pDef) "isPublishablePackage must return true for public package")
      (assert (= dep1.name "asl-core") "dep1 name must match")
      (assert (= dep1.sourceType "local") "dep1 source type must match")
      (assert (= dep2.name "asl-crypto") "dep2 name must match")
      (assert (= dep2.tag "v0.1.0") "dep2 tag must match")
      (refute (stringEmpty? dep2.gitUrl) "Git dependency URL must not be empty")
      (refute (= dep2.sourceType "local") "Git dependency must not be local")
      (refute (stringEmpty? dep2.checksum) "Git dependency checksum must not be empty")
      true))

fn testPrivatePackageFiltering -> Bool
  (let [(pPrivate (pkg/PackageDef
                    :name "internal-core"
                    :version "0.1.0"
                    :public false
                    :entry "src/core.asl"
                    :doc "Internal only"
                    :modules (list)
                    :dependencies (list)))]
    (do
      (assert (= pPrivate.name "internal-core") "Private package name must match")
      (assert (= pPrivate.version "0.1.0") "Private package version must match")
      (refute pPrivate.public "Private package must not be public")
      (refute (pkg/isPublishablePackage pPrivate) "Private package must not be publishable")
      true))

fn testTransitivePublishabilityValidation -> Bool
  (let [(depPrivate (pkg/PackageDependency :name "internal-secret" :sourceType "local" :gitUrl "" :tag "" :checksum ""))
        (depPublicGit (pkg/PackageDependency :name "asl-math" :sourceType "git" :gitUrl "https://github.com/GenSEAM/asl-math" :tag "v1.0" :checksum "sha256:abc"))
        (pkgInvalid (pkg/PackageDef
                      :name "leaky-public"
                      :version "1.0.0"
                      :public true
                      :entry "src/lib.asl"
                      :doc "Leaky public package"
                      :modules (list)
                      :dependencies (list depPrivate)))
        (pkgValid (pkg/PackageDef
                    :name "clean-public"
                    :version "1.0.0"
                    :public true
                    :entry "src/lib.asl"
                    :doc "Clean public package"
                    :modules (list)
                    :dependencies (list depPublicGit)))]
    (do
      (assert (pkg/isPublishablePackage pkgValid) "Clean public package with git dep is publishable")
      (assert (pkg/validatePackageDef pkgValid) "Clean public package must validate successfully")
      (refute (pkg/validatePackageDef pkgInvalid) "Public package depending on private local dep must fail validation")
      (assert (= (listLength pkgValid.dependencies) 1) "Valid pkg has 1 dependency")
      (assert (= depPublicGit.sourceType "git") "depPublicGit is git type")
      (refute (= depPublicGit.sourceType "local") "depPublicGit is not local")
      true))

fn testPackageAslParsing -> Bool
  (let [(src "(:package \"asl-vector\" :version \"1.0.0\" :public true :entry \"src/vector.asl\" :doc \"SIMD vector ops\" :dependencies ((:dep \"asl-core\")))")
        (p (pkg/parsePackageAsl src))]
    (do
      (assert (= p.name "asl-vector") "Parsed name must match")
      (assert (= p.version "1.0.0") "Parsed version must match")
      (assert p.public "Parsed public must be true")
      (assert (= p.entry "src/vector.asl") "Parsed entry must match")
      (assert (= p.doc "SIMD vector ops") "Parsed doc must match")
      (refute (= p.name "") "Name must not be empty")
      (refute (= p.version "0.0.0") "Version must not be 0.0.0")
      true))

fn testArbitraryNestingDiscovery -> Bool
  (let [(mockPaths (list
                     "asl/packages/asl-mesh/package.asl"
                     "asl/packages/nested/deep/sub-pkg/package.asl"
                     "scratch/test/package.asl"
                     "asl/packages/invalid/plain.txt"))
        (discovered (pkg/scanPackageTree mockPaths))]
    (do
      (assert (= (listLength discovered) 2) "Must discover exactly 2 valid packages outside ignored roots")
      (assert (stringContains? (optionOr (listGet discovered 0) "") "asl-mesh") "First must be asl-mesh")
      (assert (stringContains? (optionOr (listGet discovered 1) "") "sub-pkg") "Second must be nested sub-pkg")
      (refute (stringContains? (optionOr (listGet discovered 0) "") "scratch") "Scratch path must be filtered out")
      (refute (stringContains? (optionOr (listGet discovered 1) "") "invalid") "Non-package path must be filtered out")
      true))

fn runTests -> Bool
  (do
    (assert (testPackageDefCreation) "test-package-def-creation must pass")
    (assert (testPrivatePackageFiltering) "test-private-package-filtering must pass")
    (assert (testTransitivePublishabilityValidation) "test-transitive-publishability-validation must pass")
    (assert (testPackageAslParsing) "test-package-asl-parsing must pass")
    (assert (testArbitraryNestingDiscovery) "test-arbitrary-nesting-discovery must pass")
    true)
