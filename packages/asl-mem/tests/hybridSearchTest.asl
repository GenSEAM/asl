(module aslMem/tests/hybridSearchTest :x [runTests testTokenizeStripsBrackets testSimhashFnvAndPopcount testSimhashIdenticalText testSimhashSmallPerturbation testSimhashUnrelatedText testRrfScoringAndFusion testPromptCachePrefixStability testSubtreeMemoizationAndIncrementalDiff] :i [(simhash :a sh) (rrf :a rrf) (subtreeCache :a sc) (aslHarness/promptCache :a pc)])

fn testSimhashFnvAndPopcount -> Bool
  (let [(hEmpty (sh/fnv1a64 ""))
        (hHello (sh/fnv1a64 "hello"))
        (hHello2 (sh/fnv1a64 "hello"))
        (hWorld (sh/fnv1a64 "world"))
        (pop0 (popcount64 0))
        (pop1 (popcount64 1))
        (pop7 (popcount64 7))
        (pop15 (popcount64 15))
        (popNeg1 (popcount64 -1))
        (xorNeg1 (^ -1 0))]
    (assert (!= hEmpty 0) "FNV-1a empty string hash must not be zero")
    (assert (= hEmpty -3750763034362895579) "FNV-1a empty string hash must match authentic 64-bit FNV offset")
    (assert (= hHello hHello2) "FNV-1a must be deterministic for identical strings")
    (assert (!= hHello hWorld) "FNV-1a must produce different hashes for distinct strings")
    (assert (= hHello -6615550055289275125) "FNV-1a of hello must match authentic 64-bit hash")
    (assert (= pop0 0) "Popcount of 0 must be 0")
    (assert (= pop1 1) "Popcount of 1 must be 1")
    (assert (= pop7 3) "Popcount of 7 (111b) must be 3")
    (assert (= pop15 4) "Popcount of 15 (1111b) must be 4")
    (assert (= popNeg1 64) "Popcount of -1 (64-bit two's complement) must be 64")
    (assert (= xorNeg1 -1) "Bit-xor of -1 and 0 must be -1")
    (assert (= (charCode " ") 32) "Char code of space must be 32")
    (assert (= (charCode "!") 33) "Char code of ! must be 33")
    (assert (= (charCode "A") 65) "Char code of A must be 65")
    true)

fn testSimhashIdenticalText -> Bool
  (let [(t1 "pure agentslang high speed in memory hybrid search engine") (t2 "pure agentslang high speed in memory hybrid search engine") (t3 "pure agentslang, high speed in-memory hybrid search engine!") (h1 (sh/simhash64 t1)) (h2 (sh/simhash64 t2)) (h3 (sh/simhash64 t3)) (dist12 (sh/hammingDistance h1 h2)) (dist13 (sh/hammingDistance h1 h3)) (sim12 (sh/simhashSimilarity h1 h2)) (sim13 (sh/simhashSimilarity h1 h3))] (assert (!= h1 0) "SimHash of non-empty text must be non-zero") (assert (= h1 2785872806574449515) "SimHash64 of identical text must match authentic 64-bit value") (assert (= h1 h2) "SimHash of identical text must be bitwise identical") (assert (= dist12 0) "Hamming distance of identical text must be 0") (assert (= dist13 0) "Hamming distance of punctuation variant text must be 0") (assert (>= sim12 0.999) "Similarity of identical text must be 1.0") (assert (>= sim13 0.999) "Similarity of punctuation variant text must be 1.0") true)

fn testSimhashSmallPerturbation -> Bool
  (let [(tBase "deterministic compiler pipeline emitting compact bytecode for webassembly target") (tPert "deterministic compiler pipeline emitting compact binary for webassembly target") (hBase (sh/simhash64 tBase)) (hPert (sh/simhash64 tPert)) (dist (sh/hammingDistance hBase hPert)) (sim (sh/simhashSimilarity hBase hPert))] (assert (> dist 0) "Perturbed text must produce non-identical hash") (assert (= dist 10) "Single word perturbation Hamming distance must be 10") (assert (<= dist 10) "Single word perturbation Hamming distance must be bounded by 10") (assert (>= sim 0.84) "Perturbed text similarity must remain above 0.84") (assert (<= sim 1.0) "Similarity must be bounded above by 1.0") true)

fn testSimhashUnrelatedText -> Bool
  (let [(tQuantum "quantum entanglement qubit superposition decoherence state vector hermitian") (tCooking "culinary recipe italian pasta tomato garlic olive basil parmesan simmering") (hQ (sh/simhash64 tQuantum)) (hC (sh/simhash64 tCooking)) (dist (sh/hammingDistance hQ hC)) (sim (sh/simhashSimilarity hQ hC))] (assert (= dist 25) "Unrelated texts Hamming distance must be 25") (assert (>= dist 18) "Unrelated texts Hamming distance must be >= 18") (assert (<= dist 46) "Unrelated texts Hamming distance must be <= 46") (assert (< sim 0.75) "Unrelated texts similarity must be below 0.75") (assert (> sim 0.25) "Unrelated texts similarity must be above 0.25") true)

fn testRrfScoringAndFusion -> Bool
  (let [(s0 (rrf/computeRrfScore 0 60)) (s1 (rrf/computeRrfScore 1 60)) (s2 (rrf/computeRrfScore 2 60)) (c1-a (rrf/RankedCandidate :id "doc-consensus" :score 0.0 :rank 1)) (c2-a (rrf/RankedCandidate :id "doc-lexical-only" :score 0.0 :rank 2)) (c1-b (rrf/RankedCandidate :id "doc-consensus" :score 0.0 :rank 1)) (c3-b (rrf/RankedCandidate :id "doc-semantic-only" :score 0.0 :rank 2)) (channelA (list c1-a c2-a)) (channelB (list c1-b c3-b)) (fused (rrf/hybridCodeSearch channelA channelB)) (topOpt (listHead fused)) (topCand (optionOr topOpt (rrf/RankedCandidate :id "" :score 0.0 :rank 0)))] (assert (= s0 0.0) "Invalid rank score must be 0.0") (assert (> s1 0.015) "Rank 1 RRF score must exceed 0.015") (assert (> s1 s2) "Rank 1 RRF score must exceed Rank 2 RRF score") (assert (= (listLength fused) 3) "Fused results must contain all 3 distinct candidate IDs") (assert (= topCand.id "doc-consensus") "Multi-channel consensus item must rank top") (assert (> topCand.score 0.03) "Consensus candidate score must exceed single channel score") (assert (= topCand.rank 1) "Top candidate must be assigned rank 1") true)

fn testPromptCachePrefixStability -> Bool
  (let [(axioms (list "D0015: Token Arbitrage" "D0016: Agent-Native Autonomy" "D0017: Falsifiable Observability")) (tools (list "run_command" "view_file" "grep_search" "replace_file_content")) (prefix (pc/freezeSystemPrefix axioms tools)) (turn1 (pc/assembleCachedPrompt prefix (list "User: Report system status." "Agent: Status is nominal."))) (turn2 (pc/assembleCachedPrompt prefix (list "User: Execute task 336." "Agent: Running tests..."))) (isStable (pc/verifyPrefixStability turn1 turn2)) (corruptedPrompt (str "(:system-prefix\n  :axioms [\"modified\"])\n(:dynamic-turn-marker)\nUser: test")) (isUnstable (pc/verifyPrefixStability turn1 corruptedPrompt))] (assert (> (stringLength prefix.axiomsHash) 0) "Axioms content hash must be non-empty") (assert (> (stringLength prefix.toolsHash) 0) "Tools content hash must be non-empty") (assert (stringContains? prefix.canonicalPrefix "(:system-prefix") "Prefix must contain :system-prefix") (assert (stringContains? prefix.canonicalPrefix "(:dynamic-turn-marker)") "Prefix must contain marker") (assert isStable "Prefix must be bit-for-bit stable across divergent dynamic turns") (assert (not isUnstable) "Corrupted prefix must fail stability verification") true)

fn testSubtreeMemoizationAndIncrementalDiff -> Bool
  (let [(src1 (str "(module asl-mem/test-source\n" "  :doc \"Test source module\")\n\n" "(schema MyRecord\n" "  (:f id Str \"record identifier\"))\n\n" "(fn compute-val [(x I64)] -> I64\n" "  :doc \"computes value\"\n" "  (+ x 10))\n")) (c1 (sc/indexSubtrees src1)) (entries1 c1.entries) (src2 (str "(module asl-mem/test-source\n" "  :doc \"Test source module\")\n\n" "(schema MyRecord\n" "  (:f id Str \"record identifier\"))\n\n" "(fn compute-val [(x I64)] -> I64\n" "  :doc \"computes value\"\n" "  (+ x 99))\n")) (res (sc/reconcileIncrementalDiff c1 src2)) (unchanged (pairFirst res)) (c2 (pairSecond res)) (src1Identical (sc/reconcileIncrementalDiff c1 src1)) (unchangedAll (pairFirst src1Identical))] (assert (= (mapSize entries1) 3) "Source 1 must contain 3 indexed top-level subtrees") (assert (= (listLength unchanged) 2) "Source 2 must reuse exactly 2 unchanged subtrees from cache") (assert (= (mapSize c2.entries) 3) "Updated cache must contain 3 entries") (assert (= (listLength unchangedAll) 3) "Identical source must reuse 100% of subtrees from cache") true)

fn testTokenizeStripsBrackets -> Bool
  (let [(toks (sh/tokenizeWords "alpha[beta]"))]
    (assert (= toks (list "alpha" "beta")) "alpha[beta] tokenizes to alpha and beta")
    (assert (not (listAny? (fn [(t Str)] -> Bool (stringContains? t "[")) toks)) "no token keeps [")
    true)

fn runTests -> Bool
  (and (testTokenizeStripsBrackets) (and (testSimhashFnvAndPopcount) (and (testSimhashIdenticalText) (and (testSimhashSmallPerturbation) (and (testSimhashUnrelatedText) (and (testRrfScoringAndFusion) (and (testPromptCachePrefixStability) (testSubtreeMemoizationAndIncrementalDiff))))))))
