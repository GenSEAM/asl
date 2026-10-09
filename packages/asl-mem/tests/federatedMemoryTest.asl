(module aslMem/federatedMemoryTest
  :x [runTests]
  :i [(federatedMemory :a fmem)])

fn testPackageScopedMemoryRecord -> Bool
  (let [(rec (fmem/PackageScopedMemory
               :package "asl-mesh"
               :category "roadmap"
               :path "asl/packages/asl-mesh/mem/roadmap.asn"
               :entriesCount 3))
        (formatted (fmem/formatFederatedMemoryRecord rec "Raft joint consensus verified"))]
    (do
      (assert (= rec.package "asl-mesh") "Package name must match")
      (assert (= rec.category "roadmap") "Category must match")
      (assert (= rec.path "asl/packages/asl-mesh/mem/roadmap.asn") "Path must match")
      (assert (= rec.entriesCount 3) "Entries count must match")
      (assert (stringContains? formatted ":package \"asl-mesh\"") "Formatted record must contain package tag")
      (assert (stringContains? formatted ":scope :local") "Formatted record must declare local scope")
      (assert (stringContains? formatted "Raft joint consensus verified") "Formatted record must contain content")
      (refute (stringContains? formatted ":scope :global") "Package-scoped memory must not be marked global")
      (refute (= rec.entriesCount 0) "Entries count must not be 0")
      true))

fn testFederatedMemoryQueryFiltering -> Bool
  (let [(rec1 (fmem/PackageScopedMemory :package "asl-mesh" :category "roadmap" :path "asl/packages/asl-mesh/mem/roadmap.asn" :entriesCount 3))
        (rec2 (fmem/PackageScopedMemory :package "asl-compiler" :category "adr" :path "asl/packages/asl-compiler/mem/adr.asn" :entriesCount 5))
        (rec3 (fmem/PackageScopedMemory :package "asl-mesh" :category "intent" :path "asl/packages/asl-mesh/mem/intent.asn" :entriesCount 2))
        (allMemories (list rec1 rec2 rec3))
        (filtered (fmem/filterMemoriesByPackage allMemories "asl-mesh"))]
    (do
      (assert (= (listLength filtered) 2) "Filtered list must contain exactly 2 records for asl-mesh")
      (assert (mt (listGet filtered 0) ((some v) (= v.package "asl-mesh")) ((none) false)) "First filtered package must be asl-mesh")
      (assert (mt (listGet filtered 1) ((some v) (= v.package "asl-mesh")) ((none) false)) "Second filtered package must be asl-mesh")
      (refute (mt (listGet filtered 0) ((some v) (= v.package "asl-compiler")) ((none) true)) "Compiler memory must be filtered out")
      (refute (= (listLength filtered) 3) "Must not return all 3 memories")
      true))

fn testBoundedFederatedMemoryQuery -> Bool
  (let [(rec1 (fmem/PackageScopedMemory :package "asl-mesh" :category "roadmap" :path "p1" :entriesCount 1))
        (rec2 (fmem/PackageScopedMemory :package "asl-mesh" :category "roadmap" :path "p2" :entriesCount 1))
        (rec3 (fmem/PackageScopedMemory :package "asl-mesh" :category "roadmap" :path "p3" :entriesCount 1))
        (allMemories (list rec1 rec2 rec3))
        (resultsBounded (fmem/queryFederatedPackageMemory allMemories "asl-mesh" "roadmap" 2))]
    (do
      (assert (= (listLength resultsBounded) 2) "Bounded query must return at most limit records (2)")
      (assert (mt (listGet resultsBounded 0) ((some v) (= v.category "roadmap")) ((none) false)) "Category must match")
      (assert (mt (listGet resultsBounded 0) ((some v) (= v.package "asl-mesh")) ((none) false)) "Package must match")
      (refute (= (listLength resultsBounded) 3) "Query must not exceed limit 2")
      (refute (listEmpty? resultsBounded) "Results must not be empty")
      true))

fn testPackageMemoryDiscovery -> Bool
  (let [(mockPaths (list
                     "asl/packages/asl-mesh/mem/roadmap.asn"
                     "asl/packages/asl-pack/mem/adr.asn"
                     "asl/packages/asl-mesh/src/raft.asl"
                     "scratch/mem/temp.asn"))
        (discovered (fmem/discoverPackageMemories mockPaths))]
    (do
      (assert (= (listLength discovered) 2) "Must discover exactly 2 valid package memory files")
      (assert (mt (listGet discovered 0) ((some v) (stringContains? v "asl-mesh/mem/roadmap.asn")) ((none) false)) "First must be asl-mesh roadmap")
      (assert (mt (listGet discovered 1) ((some v) (stringContains? v "asl-pack/mem/adr.asn")) ((none) false)) "Second must be asl-pack adr")
      (refute (mt (listGet discovered 0) ((some v) (stringContains? v "src")) ((none) true)) "Source file must be filtered out")
      (refute (mt (listGet discovered 1) ((some v) (stringContains? v "scratch")) ((none) true)) "Scratch path must be filtered out")
      true))

fn runTests -> Bool
  (do
    (assert (testPackageScopedMemoryRecord) "test-package-scoped-memory-record must pass")
    (assert (testFederatedMemoryQueryFiltering) "test-federated-memory-query-filtering must pass")
    (assert (testBoundedFederatedMemoryQuery) "test-bounded-federated-memory-query must pass")
    (assert (testPackageMemoryDiscovery) "test-package-memory-discovery must pass")
    true)
