(module aslPack/buildGraphTest
  :x [runTests]
  :i [(buildGraph :a bg)])

fn testBuildGraphSchemaCreation -> Bool
  (let [(m1 (bg/BuildModule :id "asl-core" :directory "asl/packages/asl-core" :moduleType "library" :entry "" :sources (list "src/**/*.asl") :deps (list) :capabilities (list) :doc "Core ASL"))
        (m2 (bg/BuildModule :id "asl-parser" :directory "asl/packages/asl-parser" :moduleType "library" :entry "" :sources (list "src/**/*.asl") :deps (list "asl-core") :capabilities (list) :doc "Parser"))
        (m3 (bg/BuildModule :id "asl-cli" :directory "asl/packages/asl-cli" :moduleType "executable" :entry "src/main.asl" :sources (list "src/**/*.asl") :deps (list "asl-parser") :capabilities (list "fsRead" "procSpawn") :doc "CLI"))
        (t1 (bg/BuildTarget :id "asl-native" :rootModule "asl-cli" :backend "llvm" :output "bin/asl" :triple "aarch64-apple-darwin" :optLevel "release" :postBuildGates (list "./bin/asl check") :doc "Native binary"))
        (graph (bg/BuildGraph :version "1.0.0" :substrate "pure-asl" :defaultBackend "llvm" :modules (list m1 m2 m3) :targets (list t1)))]
    (do
      (assert (= graph.version "1.0.0") "Graph version must match")
      (assert (= graph.substrate "pure-asl") "Graph substrate must be pure-asl")
      (assert (= (listLength graph.modules) 3) "Graph must contain 3 modules")
      (assert (= (listLength graph.targets) 1) "Graph must contain 1 target")
      (refute (= graph.defaultBackend "c99") "Default backend must not be legacy c99")
      (refute (= graph.defaultBackend "gcc") "Default backend must not be gcc")
      true))

fn testDagTopologicalResolution -> Bool
  (let [(m1 (bg/BuildModule :id "core" :directory "core" :moduleType "library" :entry "" :sources (list) :deps (list) :capabilities (list) :doc "core"))
        (m2 (bg/BuildModule :id "parser" :directory "parser" :moduleType "library" :entry "" :sources (list) :deps (list "core") :capabilities (list) :doc "parser"))
        (m3 (bg/BuildModule :id "ir" :directory "ir" :moduleType "library" :entry "" :sources (list) :deps (list "core" "parser") :capabilities (list) :doc "ir"))
        (m4 (bg/BuildModule :id "compiler" :directory "compiler" :moduleType "library" :entry "" :sources (list) :deps (list "ir") :capabilities (list) :doc "compiler"))
        (m5 (bg/BuildModule :id "cli" :directory "cli" :moduleType "executable" :entry "main.asl" :sources (list) :deps (list "compiler") :capabilities (list) :doc "cli"))
        (graph (bg/BuildGraph :version "1.0.0" :substrate "pure-asl" :defaultBackend "llvm" :modules (list m5 m3 m1 m4 m2) :targets (list)))
        (validation (bg/validateModuleDag graph))
        (order (bg/computeTopologicalOrder graph))
        (waves (bg/computeCompilationWaves graph))]
    (do
      (assert validation.acyclic "DAG must be reported as acyclic")
      (assert (listEmpty? validation.unresolvedDeps) "There must be zero unresolved dependencies")
      (assert (= (listLength order) 5) "Topological order must include all 5 modules")
      (assert (= (optionOr (listGet order 0) "") "core") "First compiled module must be core")
      (assert (= (optionOr (listGet order 1) "") "parser") "Second compiled module must be parser")
      (assert (= (optionOr (listGet order 2) "") "ir") "Third compiled module must be ir")
      (assert (= (optionOr (listGet order 3) "") "compiler") "Fourth compiled module must be compiler")
      (assert (= (optionOr (listGet order 4) "") "cli") "Fifth compiled module must be cli")
      (assert (> (listLength waves) 0) "Compilation waves must be computed")
      (refute (= (optionOr (listGet order 0) "") "cli") "CLI cannot be compiled before dependencies")
      (refute (= (optionOr (listGet order 1) "") "compiler") "Compiler cannot be compiled before IR")
      (refute (listEmpty? waves) "Waves must not be empty")
      true))

fn testCycleDetectionRefutation -> Bool
  (let [(m1 (bg/BuildModule :id "modA" :directory "a" :moduleType "library" :entry "" :sources (list) :deps (list "modB") :capabilities (list) :doc "A"))
        (m2 (bg/BuildModule :id "modB" :directory "b" :moduleType "library" :entry "" :sources (list) :deps (list "modC") :capabilities (list) :doc "B"))
        (m3 (bg/BuildModule :id "modC" :directory "c" :moduleType "library" :entry "" :sources (list) :deps (list "modA") :capabilities (list) :doc "C"))
        (graph (bg/BuildGraph :version "1.0.0" :substrate "pure-asl" :defaultBackend "llvm" :modules (list m1 m2 m3) :targets (list)))
        (validation (bg/validateModuleDag graph))]
    (do
      (refute validation.acyclic "Cyclic graph must NOT be reported as acyclic")
      (assert (> (stringLength validation.cyclePath) 0) "Cycle path must be reported")
      (assert (stringContains? validation.cyclePath "modA") "Cycle path must identify modA")
      (refute (= validation.cyclePath "") "Cycle path must not be empty string")
      true))

fn testMissingDependencyDetection -> Bool
  (let [(m1 (bg/BuildModule :id "alpha" :directory "alpha" :moduleType "library" :entry "" :sources (list) :deps (list "nonExistentPkg") :capabilities (list) :doc "alpha"))
        (graph (bg/BuildGraph :version "1.0.0" :substrate "pure-asl" :defaultBackend "llvm" :modules (list m1) :targets (list)))
        (validation (bg/validateModuleDag graph))]
    (do
      (assert (not (listEmpty? validation.unresolvedDeps)) "Unresolved dependencies must be detected")
      (assert (listContains? validation.unresolvedDeps "nonExistentPkg") "Unresolved dependency must name nonExistentPkg")
      (refute (listEmpty? validation.unresolvedDeps) "Unresolved list must not be empty")
      true))

fn testTargetCompilationPlan -> Bool
  (let [(m1 (bg/BuildModule :id "asl-core" :directory "core" :moduleType "library" :entry "" :sources (list "src/core.asl") :deps (list) :capabilities (list) :doc "core"))
        (m2 (bg/BuildModule :id "asl-cli" :directory "cli" :moduleType "executable" :entry "src/main.asl" :sources (list "src/main.asl") :deps (list "asl-core") :capabilities (list) :doc "cli"))
        (t1 (bg/BuildTarget :id "asl-native" :rootModule "asl-cli" :backend "llvm" :output "bin/asl" :triple "aarch64-apple-darwin" :optLevel "release" :postBuildGates (list "./bin/asl check") :doc "Native"))
        (t2 (bg/BuildTarget :id "asl-wasm" :rootModule "asl-cli" :backend "wat" :output "dist/asl.wasm" :triple "wasm32-wasi" :optLevel "size" :postBuildGates (list) :doc "Wasm"))
        (graph (bg/BuildGraph :version "1.0.0" :substrate "pure-asl" :defaultBackend "llvm" :modules (list m1 m2) :targets (list t1 t2)))
        (plan1 (bg/planTargetCompilation graph "asl-native"))
        (plan2 (bg/planTargetCompilation graph "asl-wasm"))
        (receipt (bg/emitBuildReceipt plan1 42))]
    (do
      (assert plan1.valid "Native LLVM plan must be valid")
      (assert (= plan1.targetId "asl-native") "Target ID must match")
      (assert (= plan1.backend "llvm") "Backend must be llvm")
      (assert (= plan1.output "bin/asl") "Output path must match")
      (assert (= (listLength plan1.stages) 6) "Plan must have 6 pipeline stages")
      (assert plan2.valid "WASM plan must be valid")
      (assert (= plan2.backend "wat") "Backend must be wat")
      (assert (stringContains? receipt "(:buildReceipt") "Receipt must format as typed ASN")
      (assert (stringContains? receipt ":target \"asl-native\"") "Receipt must contain target name")
      (assert (stringContains? receipt ":status :ok") "Receipt must indicate ok status")
      (refute (stringContains? receipt ":error") "Successful receipt must not contain error")
      (refute (= plan1.output "") "Output path must not be empty")
      (refute (= plan1.backend "c99") "Backend must not be c99")
      true))

fn runTests -> Bool
  (do
    (assert (testBuildGraphSchemaCreation) "test-build-graph-schema-creation must pass")
    (assert (testDagTopologicalResolution) "test-dag-topological-resolution must pass")
    (assert (testCycleDetectionRefutation) "test-cycle-detection-refutation must pass")
    (assert (testMissingDependencyDetection) "test-missing-dependency-detection must pass")
    (assert (testTargetCompilationPlan) "test-target-compilation-plan must pass")
    true)
