(module aslPack/targetAdapterTest
  :x [runTests]
  :i [(targetAdapter :a ta)])

fn testTargetAdapterCreation -> Bool
  (let [(proj1 (ta/TargetProjection :id "native" :backend "llvm" :outputArtifact "dist/asl-mesh" :options (list "-O3")))
        (proj2 (ta/TargetProjection :id "wasm" :backend "wat" :outputArtifact "dist/mesh.wasm" :options (list "-Os")))
        (adapter (ta/TargetAdapter
                   :package "asl-mesh"
                   :authority "D93"
                   :substrate "pure-asl"
                   :projections (list proj1 proj2)))]
    (do
      (assert (= adapter.package "asl-mesh") "Package name must match")
      (assert (= adapter.substrate "pure-asl") "Substrate must be pure-asl")
      (assert (= (listLength adapter.projections) 2) "Must contain 2 projections")
      (assert (ta/validateTargetAdapterContract adapter) "Adapter contract must be valid")
      (assert (= proj1.id "native") "proj1 id must be native")
      (assert (= proj1.backend "llvm") "proj1 backend must be llvm")
      (assert (= proj2.id "wasm") "proj2 id must be wasm")
      (assert (= proj2.backend "wat") "proj2 backend must be wat")
      (refute (listEmpty? adapter.projections) "Projections must not be empty")
      (refute (= adapter.substrate "c-shim") "Substrate must not be c-shim")
      true))

fn testNegativeContractValidation -> Bool
  (let [(projBadBackend (ta/TargetProjection :id "bad" :backend "unknown-backend" :outputArtifact "bin/bad" :options (list)))
        (adapterBadBackend (ta/TargetAdapter :package "test-pkg" :authority "D93" :substrate "pure-asl" :projections (list projBadBackend)))
        (adapterBadSubstrate (ta/TargetAdapter :package "test-pkg" :authority "D93" :substrate "c-shim" :projections (list)))
        (adapterEmpty (ta/TargetAdapter :package "test-pkg" :authority "D93" :substrate "pure-asl" :projections (list)))]
    (do
      (refute (ta/validateTargetAdapterContract adapterBadBackend) "Adapter with unknown backend must fail contract validation")
      (refute (ta/validateTargetAdapterContract adapterBadSubstrate) "Adapter with non-pure substrate must fail contract validation")
      (refute (ta/validateTargetAdapterContract adapterEmpty) "Adapter with empty projections must fail contract validation")
      (assert (= projBadBackend.backend "unknown-backend") "Backend check")
      true))

fn testTargetAdapterPlanEmission -> Bool
  (let [(proj1 (ta/TargetProjection :id "native" :backend "llvm" :outputArtifact "dist/asl-mesh" :options (list "-O3")))
        (proj2 (ta/TargetProjection :id "wasm" :backend "wat" :outputArtifact "dist/mesh.wasm" :options (list "-Os")))
        (adapter (ta/TargetAdapter :package "asl-mesh" :authority "D93" :substrate "pure-asl" :projections (list proj1 proj2)))
        (planNative (ta/emitTargetAdapterPlan adapter "native"))
        (planWasm (ta/emitTargetAdapterPlan adapter "wasm"))]
    (do
      (assert (= planNative.targetId "native") "Native plan target ID must match")
      (assert (= planNative.backend "llvm") "Native plan backend must be llvm")
      (assert (stringContains? planNative.output "dist/asl-mesh") "Native output path must match")
      (assert planNative.ready "Native plan must be ready")
      (assert (= planWasm.targetId "wasm") "Wasm plan target ID must match")
      (assert (= planWasm.backend "wat") "Wasm plan backend must be wat")
      (assert (stringContains? planWasm.output "dist/mesh.wasm") "Wasm output path must match")
      (refute (= planNative.backend "c99") "Native backend must not be c99")
      (refute (= planWasm.backend "c99") "Wasm backend must not be c99")
      true))

fn testProjectionToBuildTargetBridging -> Bool
  (let [(proj (ta/TargetProjection :id "native" :backend "llvm" :outputArtifact "dist/asl-mesh" :options (list "-O3")))
        (bTarget (ta/projectionToBuildTarget proj "aarch64-apple-darwin"))]
    (do
      (assert (= bTarget.name "native") "BuildTarget name must match projection id")
      (assert (= bTarget.backend "llvm") "BuildTarget backend must match projection backend")
      (assert (= bTarget.targetTriple "aarch64-apple-darwin") "BuildTarget triple must match")
      (assert (= bTarget.optLevel "O3") "BuildTarget optLevel must match extracted option")
      (assert (= bTarget.outputArtifact "dist/asl-mesh") "BuildTarget outputArtifact must match")
      (refute (= bTarget.optLevel "O0") "Opt level must not default to O0")
      true))

fn runTests -> Bool
  (do
    (assert (testTargetAdapterCreation) "test-target-adapter-creation must pass")
    (assert (testNegativeContractValidation) "test-negative-contract-validation must pass")
    (assert (testTargetAdapterPlanEmission) "test-target-adapter-plan-emission must pass")
    (assert (testProjectionToBuildTargetBridging) "test-projection-to-build-target-bridging must pass")
    true)
