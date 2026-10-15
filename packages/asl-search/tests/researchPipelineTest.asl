(module aslWebApiSearch/tests/researchPipelineTest
  :x [testResearchPlanning testFactSynthesis testSourceClassification testReportFormatting testExtractionFromResults runTests]
  :i [(research :a res) (engine :a eng)])

fn testResearchPlanning -> Bool
  (let [(flashPlan (res/makeResearchPlan "AgentSlang Wasm" "flash"))
        (targetPlan (res/makeResearchPlan "AgentSlang Wasm" "targeted"))
        (bipolarPlan (res/makeResearchPlan "Wasm SIMD speedup" "bipolar"))
        (matrixPlan (res/makeResearchPlan "Distributed Consensus" "matrix"))]
    (assert (= flashPlan.depth "flash") "flash plan depth mismatch")
    (assert (= (listLength (res/buildResearchQueries flashPlan)) 1) "flash plan must have exactly 1 query")
    (assert (= flashPlan.maxResults 3) "flash max results must be 3")

    (assert (= targetPlan.depth "targeted") "target plan depth mismatch")
    (assert (= (listLength (res/buildResearchQueries targetPlan)) 2) "targeted plan must have 2 queries")
    (assert (= targetPlan.maxResults 5) "targeted max results must be 5")

    (assert (= bipolarPlan.depth "bipolar") "bipolar plan depth mismatch")
    (assert (= (listLength (res/buildResearchQueries bipolarPlan)) 2) "bipolar plan must have 2 queries (pos/neg)")
    (assert (stringContains? (optionOr (listHead (res/buildResearchQueries bipolarPlan)) "") "verified") "bipolar first query is positive")
    (refute (stringContains? (optionOr (listHead (res/buildResearchQueries bipolarPlan)) "") "bottleneck") "bipolar first query refutes negative suffix")

    (assert (= matrixPlan.depth "matrix") "matrix plan depth mismatch")
    (assert (= (listLength (res/buildResearchQueries matrixPlan)) 4) "matrix plan must have 4 decomposed queries")
    (assert (= matrixPlan.maxResults 10) "matrix max results must be 10")
    true)

fn testFactSynthesis -> Bool
  (let [(f1 (res/makeSynthesizedFact "f1" "Wasm is fast" "Measured 1.2ms latency" "https://aslang.dev/docs?utm_source=ad" false "primaryArtifact" "unfalsified" 1 false))
        (f2 (res/makeSynthesizedFact "f2" "Wasm cold start" "Cold start overhead 15ms" "https://arxiv.org/abs/2301.0001" true "" "" 2 false))
        (f3 (res/makeSynthesizedFact "f3" "Crowdsourced claim" "Community wiki note" "https://en.wikipedia.org/wiki/Wasm" false "" "" 3 false))]
    (assert (= f1.id "f1") "fact 1 id mismatch")
    (assert (not (stringContains? f1.sourceUrl "utm_source")) "source URL must be cleaned of tracking params")
    (assert (not f1.isFalsifying) "f1 is affirmative")
    (assert (= f1.sourceKind "primaryArtifact") "f1 sourceKind preserved")
    (assert (= f1.verificationStatus "unfalsified") "f1 verificationStatus is unfalsified")
    (assert (= f1.predicate "is") "f1 predicate auto-derived as is")

    (assert f2.isFalsifying "f2 is falsifying")
    (assert (= f2.sourceKind "peerReviewed") "f2 auto-classified as peerReviewed from arxiv.org")
    (assert (= f2.verificationStatus "disputed") "f2 auto-classified as disputed because falsifying")

    (assert (= f3.sourceKind "crowdsourced") "f3 auto-classified as crowdsourced from wikipedia.org")
    (assert (= f3.verificationStatus "unfalsified") "f3 auto-classified as unfalsified")
    true)

fn testSourceClassification -> Bool
  (do
    (assert (= (res/classifySourceKind "https://arxiv.org/abs/1234") "peerReviewed") "arxiv is peerReviewed")
    (assert (= (res/classifySourceKind "https://github.com/GenSEAM/asl") "primaryArtifact") "github is primaryArtifact")
    (assert (= (res/classifySourceKind "https://en.wikipedia.org/wiki/Lisp") "crowdsourced") "wikipedia is crowdsourced")
    (assert (= (res/classifySourceKind "https://medium.com/post") "secondaryReport") "medium is secondaryReport")
    (assert (= (res/classifySourceKind "https://example.com/item") "unverifiedWeb") "generic is unverifiedWeb")

    (assert (= (res/deriveVerificationStatus false false false) "unfalsified") "default status is unfalsified")
    (assert (= (res/deriveVerificationStatus true false false) "disputed") "falsifying claim is disputed")
    (assert (= (res/deriveVerificationStatus false false true) "corroborated") "multi-source is corroborated")
    (assert (= (res/deriveVerificationStatus false true false) "empiricallyVerified") "empirical test is empiricallyVerified")
    (assert (= (res/deriveVerificationStatus true true false) "refuted") "empirical falsification is refuted")
    true)

fn testExtractionFromResults -> Bool
  (let [(item1 (eng/SearchResult :title "ASL Substrate" :url "https://github.com/GenSEAM/asl" :snippet "Native AgentSlang" :engine "ddg" :score 0.92))
        (item2 (eng/SearchResult :title "ASL Compiler" :url "https://arxiv.org/abs/2400.1234" :snippet "LLVM emitter" :engine "brave" :score 0.88))
        (facts (res/extractKeyFacts (list item1 item2) false))]
    (assert (= (listLength facts) 2) "extracted facts count should be 2")
    (mt (listHead facts)
      ((none) (assert false "first fact must exist"))
      ((some fact1)
        (assert (= fact1.claim "ASL Substrate") "first fact claim matches title")
        (assert (= fact1.sourceKind "primaryArtifact") "first fact sourceKind is primaryArtifact")
        (assert (= fact1.verificationStatus "unfalsified") "first fact status is unfalsified")
        (assert (not fact1.isFalsifying) "fact1 is affirmative")))
    true)

fn testReportFormatting -> Bool
  (let [(f1 (res/makeSynthesizedFact "f1" "High throughput verified" "Measured 100k rps" "https://aslang.dev/bench" false "primaryArtifact" "empiricallyVerified" 1 false))
        (f2 (res/makeSynthesizedFact "f2" "Memory pressure on GC" "Excess allocations in hot loops" "https://arxiv.org/abs/2301.0001" true "peerReviewed" "disputed" 2 false))
        (sources (list "https://aslang.dev/bench" "https://arxiv.org/abs/2301.0001"))
        (report (res/makeResearchReport
                  "ASL High Load Web"
                  "verified"
                  (list f1 f2)
                  sources
                  "Achieved target concurrency with non-blocking reactor"
                  "Requires zero-copy arena allocation to prevent GC spikes"
                  "ASL can sustain 100k rps when configured with fiber pool."))]
    (let [(md (res/formatResearchReport report))]
      (assert (stringContains? md "# Research Report: ASL High Load Web [verified]") "report title matches")
      (assert (stringContains? md "## Executive Summary") "summary header present")
      (assert (stringContains? md "100k rps") "summary content present")
      (assert (stringContains? md "## Affirmative Findings") "positive section present")
      (assert (stringContains? md "[AFFIRMATIVE]") "affirmative badge present")
      (assert (stringContains? md "## Counter-Evidence & Limitations") "critique section present")
      (assert (stringContains? md "[CRITIQUE/LIMITATION]") "critique badge present")
      (assert (stringContains? md "[primaryArtifact - empiricallyVerified]") "categorical badge 1 present")
      (assert (stringContains? md "[peerReviewed - disputed]") "categorical badge 2 present")
      (refute (stringContains? md "Confidence: 0.") "Refutes arbitrary float confidence")
      (assert (stringContains? md "## Sources Consulted (2)") "sources section present")
      (refute (stringContains? md "undefined") "zero undefined in output")
      true))

fn testAsnReportFormatting -> Bool
  (let [(f1 (res/makeSynthesizedFact "f1" "ASL Wasm Speed" "1.2ms latency" "https://aslang.dev/bench" false "primaryArtifact" "corroborated" 1 true))
        (f2 (res/makeSynthesizedFact "f2" "Cold start overhead" "15ms cold start" "https://arxiv.org/abs/2301.0001" true "peerReviewed" "disputed" 2 false))
        (sources (list "https://aslang.dev/bench" "https://arxiv.org/abs/2301.0001"))
        (report (res/makeResearchReport
                  "ASL High Load Web"
                  "verified"
                  (list f1 f2)
                  sources
                  "Achieved target concurrency with non-blocking reactor"
                  "Requires zero-copy arena allocation to prevent GC spikes"
                  "ASL can sustain 100k rps when configured with fiber pool."))
        (asn (res/formatResearchReportAsn report))
        (triage (res/formatResearchTriageAsn report))]
    (assert (= f1.srcRef 1) "fact 1 srcRef is 1")
    (assert f1.crawled "fact 1 crawled is true")
    (assert (not f2.crawled) "fact 2 crawled is false")
    (assert (stringContains? asn "(:researchReport") "ASN report must start with (:researchReport")
    (assert (stringContains? asn ":topic \"ASL High Load Web\"") "ASN report topic")
    (assert (stringContains? asn ":status :verified") "ASN report status")
    (assert (stringContains? asn ":facts [") "ASN report facts container")
    (assert (stringContains? asn ":predicate") "ASN report predicates")
    (assert (stringContains? asn ":crawled true") "ASN report crawled true tag")
    (assert (stringContains? triage "(:researchTriage") "ASN triage must start with (:researchTriage")
    (assert (stringContains? triage ":predicate") "ASN triage predicates")
    true)

fn runTests -> Bool
  (and (testResearchPlanning)
       (and (testFactSynthesis)
            (and (testSourceClassification)
                 (and (testExtractionFromResults)
                      (and (testReportFormatting)
                           (testAsnReportFormatting))))))
