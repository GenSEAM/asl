(module aslHarness/cognition :x [CognitiveScratchpad IntentAtom PolyglotEcosystem ToolchainManifest makeCognitiveScratchpad calculateSud calculateDir checkDyckBalance teleologyToOntology getForcedOntologyEntities detectEcosystemFromManifest resolveToolchainCommands makeIntentAtom validateAtomProvenance isAtomGrounded] :i [])

(schema CognitiveScratchpad (:f perceive Str) (:f hypotheses (List Str)) (:f falsificationGates (List Str)) (:f selectedHypothesis Str) (:f actionSteps (List Str)) (:f tokenCount I64) (:f constraintCount I64))

(schema IntentAtom (:f id Str) (:f verb Str) (:f targetObject Str) (:f constraint Str) (:f provenanceSpan Str) (:f confidence F64) (:f isGrounded Bool))

(schema ToolchainManifest (:f manifestFile Str) (:f ecosystem Str) (:f buildCmd Str) (:f testCmd Str) (:f lintCmd Str))

fn makeCognitiveScratchpad perceive: Str hypotheses: (List Str) gates: (List Str) selected: Str actions: (List Str) tokens: I64 constraints: I64 -> CognitiveScratchpad
  (CognitiveScratchpad :perceive perceive :hypotheses hypotheses :falsificationGates gates :selectedHypothesis selected :actionSteps actions :tokenCount tokens :constraintCount constraints)

fn calculateSud constraints: I64 tokens: I64 -> F64
  (if (<= tokens 0) 0.0 (/ (int64ToFloat64 constraints) (int64ToFloat64 tokens)))

fn calculateDir mutualInfo: F64 tokenEntropy: F64 -> F64
  (if (<= tokenEntropy 0.0) 0.0 (/ mutualInfo tokenEntropy))

fn checkDyckHelper trace: Str idx: I64 len: I64 depth: I64 -> Bool
  (if (= idx len) (= depth 0) (let [(ch (optionOr (stringSlice trace idx (+ idx 1)) ""))] (cond ((= ch "(") (checkDyckHelper trace (+ idx 1) len (+ depth 1))) ((= ch ")") (if (<= depth 0) false (checkDyckHelper trace (+ idx 1) len (- depth 1)))) (else (checkDyckHelper trace (+ idx 1) len depth)))))

fn checkDyckBalance trace: Str -> Bool
  (let [(len (stringLength trace))] (checkDyckHelper trace 0 len 0))

fn teleologyToOntology valueRank: I64 -> (List Str)
  (cond ((= valueRank 0) (list "humanOverride" "airgap" "consentReceipt")) ((= valueRank 1) (list "owns" "vfsBuffer" "delimiterState" "invariantGuard")) ((= valueRank 2) (list "intentAtom" "sMap" "acceptanceCriteria")) ((= valueRank 3) (list "claim" "falsificationGate" "mutant" "fMap" "witness")) ((= valueRank 4) (list "diffHunk" "entropyBudget" "bMap" "causalCone")) ((= valueRank 5) (list "asnSexpr" "bareSymbol" "tokenCompressor")) ((= valueRank 6) (list "memoCache" "pipelineScheduler" "batchAction")) (else (list)))

fn accumulateForcedEntities currentRank: I64 maxRank: I64 acc: (List Str) -> (List Str)
  (if (> currentRank maxRank) acc (accumulateForcedEntities (+ currentRank 1) maxRank (listAppend acc (teleologyToOntology currentRank))))

fn getForcedOntologyEntities maxRank: I64 -> (List Str)
  (accumulateForcedEntities 0 maxRank (list))

fn detectEcosystemFromManifest manifestPath: Str -> Str
  (cond ((stringContains? manifestPath "Cargo.toml") "rust") ((stringContains? manifestPath "pyproject.toml") "python") ((stringContains? manifestPath "setup.py") "python") ((stringContains? manifestPath "package.json") "nodeTypescript") ((stringContains? manifestPath "go.mod") "go") ((stringContains? manifestPath "CMakeLists.txt") "cpp") ((stringContains? manifestPath "Makefile") "cSystem") ((stringContains? manifestPath "asl.json") "asl") (else "unknown"))

fn resolveToolchainCommands ecosystem: Str -> ToolchainManifest
  (cond ((= ecosystem "rust") (ToolchainManifest :manifestFile "Cargo.toml" :ecosystem "rust" :buildCmd "cargo check" :testCmd "cargo test" :lintCmd "cargo clippy")) ((= ecosystem "python") (ToolchainManifest :manifestFile "pyproject.toml" :ecosystem "python" :buildCmd "python -m py_compile" :testCmd "pytest" :lintCmd "ruff check")) ((= ecosystem "nodeTypescript") (ToolchainManifest :manifestFile "package.json" :ecosystem "nodeTypescript" :buildCmd "npm run build" :testCmd "npm test" :lintCmd "npm run lint")) ((= ecosystem "go") (ToolchainManifest :manifestFile "go.mod" :ecosystem "go" :buildCmd "go build ./..." :testCmd "go test ./..." :lintCmd "golangci-lint run")) ((= ecosystem "cpp") (ToolchainManifest :manifestFile "CMakeLists.txt" :ecosystem "cpp" :buildCmd "cmake --build build" :testCmd "ctest --test-dir build" :lintCmd "clang-tidy")) ((= ecosystem "cSystem") (ToolchainManifest :manifestFile "Makefile" :ecosystem "cSystem" :buildCmd "make" :testCmd "make test" :lintCmd "make lint")) ((= ecosystem "asl") (ToolchainManifest :manifestFile "asl.json" :ecosystem "asl" :buildCmd "./bin/asl check" :testCmd "./bin/asl test" :lintCmd "./bin/asl audit")) (else (ToolchainManifest :manifestFile "unknown" :ecosystem "unknown" :buildCmd "echo 'Unknown ecosystem build' && exit 1" :testCmd "echo 'Unknown ecosystem test' && exit 1" :lintCmd "echo 'Unknown ecosystem lint' && exit 1")))

fn makeIntentAtom id: Str verb: Str target: Str constraint: Str provenance: Str confidence: F64 isGrounded: Bool -> IntentAtom
  (IntentAtom :id id :verb verb :targetObject target :constraint constraint :provenanceSpan provenance :confidence confidence :isGrounded isGrounded)

fn validateAtomProvenance atom: IntentAtom promptText: Str -> Bool
  (if (stringEmpty? atom.provenanceSpan) false (stringContains? promptText atom.provenanceSpan))

fn isAtomGrounded atom: IntentAtom -> Bool
  (and atom.isGrounded (> atom.confidence 0.5))
