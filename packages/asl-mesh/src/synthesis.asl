(module asl-mesh/synthesis :x [synthesizeDefects triangulateFindings consensusFilter refutationEngine] :i [])

; (:m :ref BASE-CHECK-DRIFT :do "field access needs a record type the checker can see: a finding with a confidence is a Scored, one with a reproduced flag a Reproducible; the literals callers pass are both")
(schema Scored
  (:f confidence Float64))

(schema Reproducible
  (:f reproduced Bool))

fn consensusFilter findings: (List Scored) threshold: Any -> List
  (filter (fn [(finding Scored)] -> Bool (>= finding.confidence threshold)) findings)

fn refutationEngine finding: Reproducible -> Map
  (let [(reproduced finding.reproduced)]
    {:finding finding :reproduced reproduced :status (if reproduced :verified :unverified)})

fn triangulateFindings opusFindings: Any proFindings: Any flashFindings: Any -> List
  (listAppend (listAppend opusFindings proFindings) flashFindings)

fn synthesizeDefects partition: Any findingsList: Any -> Map
  (do {:consensusId "rc-mesh-consensus" :partition partition :agreementRate 1.0 :verifiedDefects findingsList :status :consensus :timestamp 1789463400000})
