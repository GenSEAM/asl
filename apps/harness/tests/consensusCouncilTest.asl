(module aslHarness/consensusCouncilTest :x [testDefaultCouncilModels testConsensusCalculation testConsensusCertification testDeliberationSynthesis testDualPolarityRefutations runTests] :i [(consensusCouncil :a cc)])

fn testDefaultCouncilModels -> Bool
  (let [(names (cc/defaultCouncilModelNames))]
    (assert (= (listLength names) 3) "council contains exactly 3 models (Flagship Trio)")
    (assert (stringContains? (stringJoin names " ") "gpt-6-astra") "gpt-6-astra is present")
    (assert (stringContains? (stringJoin names " ") "deepseek-v4.1-flash") "deepseek is present")
    (assert (stringContains? (stringJoin names " ") "glm-5.3") "glm-5.3 is present")
    true)

fn testConsensusCalculation -> Bool
  (let [(v1 (cc/makeCouncilVote "deepseek-v4.1-flash" ":approved" 0.95 24.5))
        (v2 (cc/makeCouncilVote "glm-5.3" ":approved" 0.90 32.1))
        (v3 (cc/makeCouncilVote "muse-spark-1.3" ":approved" 0.88 35.0))
        (v4 (cc/makeCouncilVote "qwen3.8-max" ":gapsDetected" 0.70 28.4))
        (votes (list v1 v2 v3 v4))
        (ratio (cc/calculateConsensusRatio votes))]
    (assert (= ratio 0.75) "3 of 4 approved yields 0.75 ratio")
    (assert (cc/isConsensusCertified? ratio) "0.75 meets 75% consensus threshold")
    true)

fn testConsensusCertification -> Bool
  (let [(v1 (cc/makeCouncilVote "deepseek-v4.1-flash" ":approved" 0.95 24.5))
        (v2 (cc/makeCouncilVote "glm-5.3" ":approved" 0.90 32.1))
        (v3 (cc/makeCouncilVote "muse-spark-1.3" ":rejected" 0.50 35.0))
        (v4 (cc/makeCouncilVote "qwen3.8-max" ":gapsDetected" 0.70 28.4))
        (votes (list v1 v2 v3 v4))
        (ratio (cc/calculateConsensusRatio votes))]
    (assert (= ratio 0.50) "2 of 4 approved yields 0.50 ratio")
    (assert (not (cc/isConsensusCertified? ratio)) "0.50 does not meet consensus threshold")
    true)

fn testDeliberationSynthesis -> Bool
  (let [(v1 (cc/makeCouncilVote "deepseek-v4.1-flash" ":approved" 0.95 24.5))
        (v2 (cc/makeCouncilVote "glm-5.3" ":approved" 0.90 32.1))
        (v3 (cc/makeCouncilVote "muse-spark-1.3" ":approved" 0.88 35.0))
        (v4 (cc/makeCouncilVote "qwen3.8-max" ":approved" 0.92 28.4))
        (votes (list v1 v2 v3 v4))
        (lenses (list "falsification" "concurrency" "architecture" "non-vacuity"))
        (verdict (cc/evaluateCouncilDeliberation "agentSelfOrganizationToolkit.asn" votes lenses))
        (receipt (cc/formatConsensusReceipt verdict))]
    (assert verdict.certified "4 of 4 yields certified consensus")
    (assert (= verdict.consensusRatio 1.0) "unanimous yields 1.0 ratio")
    (assert (= verdict.approvedCount 4) "4 approved recorded")
    (assert (stringContains? receipt ":status :certified") "receipt formats certified status")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(failingVotes (list (cc/makeCouncilVote "m1" ":rejected" 0.0 1.0)))
        (failRatio (cc/calculateConsensusRatio failingVotes))
        (failingVerdict (cc/evaluateCouncilDeliberation "target" failingVotes (list)))]
    (refute (cc/isConsensusCertified? failRatio) "zero approvals must not be certified")
    (refute failingVerdict.certified "failing deliberation verdict must not be certified")
    (refute (stringContains? (cc/formatConsensusReceipt failingVerdict) ":status :certified") "failing receipt must not be certified")
    true)

fn runTests -> Bool
  (do
    (testDefaultCouncilModels)
    (testConsensusCalculation)
    (testConsensusCertification)
    (testDeliberationSynthesis)
    (testDualPolarityRefutations)
    true)
