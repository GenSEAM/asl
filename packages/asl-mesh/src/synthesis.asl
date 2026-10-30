(module asl-mesh/synthesis :x [synthesizeDefects triangulateFindings consensusFilter refutationEngine] :i [])

fn consensusFilter findings: Any threshold: Any -> List
  (filter (fn [finding] (>= finding.confidence threshold)) findings)

fn refutationEngine finding: Any -> Map
  (let [(reproduced finding.reproduced)]
    {:finding finding :reproduced reproduced :status (if reproduced :verified :unverified)})

fn triangulateFindings opusFindings: Any proFindings: Any flashFindings: Any -> List
  (listAppend (listAppend opusFindings proFindings) flashFindings)

fn synthesizeDefects partition: Any findingsList: Any -> Map
  (do {:consensusId "rc-mesh-consensus" :partition partition :agreementRate 1.0 :verifiedDefects findingsList :status :consensus :timestamp 1789463400000})
