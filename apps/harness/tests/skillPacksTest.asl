(module aslHarness/tests/skillPacksTest :x [testMarkerValidation testContextTierScaling testConnectednessRanking testSelectionAndMarkerTail testLargeWindowEscalation runTests] :i [(skillPacks :a sp)])

fn testMarkerValidation -> Bool
  (do (assert (sp/validMarker? "svg") "svg must be a valid marker") (assert (sp/validMarker? "abstract-factory") "hyphenated direct marker is allowed") (assert (not (sp/validMarker? "svg drawing")) "markers must not contain spaces") (assert (not (sp/validMarker? "")) "empty marker must be rejected") true)

fn testContextTierScaling -> Bool
  (let [(small (sp/contextTierForWindow 4096)) (large (sp/contextTierForWindow 250000))] (do (assert (= small.name "small") "4096-token window must use small tier") (assert (= small.frontBudget 250) "small front intelligence budget must be 250") (assert (= small.corpusBudget 150) "small corpus budget must be 150") (assert (not small.secondarySearch) "small tier must not escalate search") (assert (= large.name "large") "250k-token window must use large tier") (assert (= large.frontBudget 1200) "large front intelligence budget must be 1200") (assert (= large.corpusBudget 248800) "large corpus budget must leave a compact front layer") (assert large.secondarySearch "large tier must allow secondary search") (assert large.diffuseLinks "large tier must allow diffuse links") true))

fn testConnectednessRanking -> Bool
  (let [(packs (sp/defaultSkillPacks)) (ranked (sp/rankSkillPacks packs "svg poster design")) (top (optionOr (listHead ranked) (sp/makeSkillMatch (sp/makeSkillPack "" (list) (list) "" "" 0 false) 0)))] (do (assert (= (listLength packs) 9) "Starter graph must contain nine packs") (assert (= top.marker "svg") "svg must rank first for svg poster design") (assert (> top.score 0) "top match must have positive connectedness") (assert (> top.tokens 0) "top match token cost must be numeric") true))

fn testSelectionAndMarkerTail -> Bool
  (let [(selection (sp/selectSkillPacks (sp/defaultSkillPacks) "svg poster design" 4096)) (tail (sp/placeMarkerTail "(:prompt \"body\")" selection))] (do (assert (= selection.tier.name "small") "selection must expose small tier") (assert (> (listLength selection.front) 0) "base layer must retain at least one match") (assert (stringContains? selection.markerTail ":skill-markers") "selection must render marker tail") (assert (stringContains? selection.markerTail "svg") "marker tail must include svg") (assert (stringEndsWith? tail selection.markerTail) "marker tail must be placed at context end") (assert (not selection.secondarySearch) "small selection must not escalate") true))

fn testLargeWindowEscalation -> Bool
  (let [(selection (sp/selectSkillPacks (sp/defaultSkillPacks) "quantum circuit gate" 300000)) (ranked (sp/rankSkillPacks (sp/defaultSkillPacks) "quantum circuit gate"))] (do (assert (= selection.tier.name "large") "300k-token window must use large tier") (assert selection.secondarySearch "large selection must request secondary search") (assert (> (listLength selection.corpus) 0) "quantum query must retain corpus matches") (assert (stringContains? selection.markerTail "quantum") "marker tail must include quantum") (assert (> (optionOr (listHead ranked) (sp/makeSkillMatch (sp/makeSkillPack "" (list) (list) "" "" 0 false) 0)).score 0) "quantum ranking must score a match") true))

fn runTests -> Bool
  (and (testMarkerValidation) (and (testContextTierScaling) (and (testConnectednessRanking) (and (testSelectionAndMarkerTail) (testLargeWindowEscalation)))))
