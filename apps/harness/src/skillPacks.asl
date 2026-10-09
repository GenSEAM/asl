(module aslHarness/skillPacks :x [SkillPack SkillLink SkillMatch ContextTier SkillSelection validMarker? makeSkillPack makeContextTier contextTierForWindow connectednessScore rankSkillPacks selectSkillPacks renderMarkerTail placeMarkerTail defaultSkillPacks makeSkillMatch])

(schema SkillLink (:f target Str) (:f strength I64) (:f membership I64))

(schema SkillPack (:f marker Str) (:f tags (List Str)) (:f related (List Str)) (:f links (List SkillLink)) (:f segment Str) (:f payload Str) (:f tokens I64) (:f base Bool) (:f applicability Str) (:f required Bool) (:f membership I64))

(schema SkillMatch (:f marker Str) (:f segment Str) (:f score I64) (:f tokens I64) (:f base Bool) (:f payload Str) (:f retained Bool))

(schema ContextTier (:f name Str) (:f totalBudget I64) (:f frontBudget I64) (:f corpusBudget I64) (:f secondarySearch Bool) (:f diffuseLinks Bool))

(schema SkillSelection (:f tier ContextTier) (:f front (List SkillMatch)) (:f corpus (List SkillMatch)) (:f markerTail Str) (:f secondarySearch Bool))

fn validMarker? marker: Str -> Bool
  (and (> (stringLength marker) 0) (and (not (stringContains? marker " ")) (and (not (stringContains? marker "\n")) (not (stringContains? marker "\t")))))

fn makeSkillLink target: Str strength: I64 membership: I64 -> SkillLink
  (SkillLink :target target :strength strength :membership membership)

fn makeSkillLinks targets: (List Str) strength: I64 membership: I64 -> (List SkillLink)
  (if (listEmpty? targets) (list) (let [(head (optionOr (listHead targets) "")) (tail (optionOr (listTail targets) (list)))] (cons (makeSkillLink head strength membership) (makeSkillLinks tail strength membership))))

fn makeSkillPack marker: Str tags: (List Str) related: (List Str) segment: Str payload: Str tokens: I64 base: Bool -> SkillPack
  (SkillPack :marker marker :tags tags :related related :links (makeSkillLinks related 70 (if base 100 50)) :segment segment :payload payload :tokens tokens :base base :applicability (if base "universal" "conditional") :required base :membership (if base 100 50))

fn makeContextTier name: Str total: I64 front: I64 corpus: I64 secondary: Bool diffuse: Bool -> ContextTier
  (ContextTier :name name :totalBudget total :frontBudget front :corpusBudget corpus :secondarySearch secondary :diffuseLinks diffuse)

fn contextTierForWindow window: I64 -> ContextTier
  (if (<= window 4096) (makeContextTier "small" window 250 150 false false) (if (>= window 250000) (makeContextTier "large" window 1200 (- window 1200) true true) (makeContextTier "medium" window 600 1000 false true)))

fn countHits terms: (List Str) query: Str -> I64
  (if (listEmpty? terms) 0 (let [(head (optionOr (listHead terms) "")) (tail (optionOr (listTail terms) (list)))] (if (stringContains? query head) (+ 1 (countHits tail query)) (countHits tail query))))

fn connectednessScore pack: SkillPack query: Str -> I64
  (let [(markerHit (if (stringContains? query pack.marker) 4 0)) (tagHits (* 2 (countHits pack.tags query))) (relatedHits (countHits pack.related query)) (baseBonus (if pack.base 1 0))] (+ markerHit (+ tagHits (+ relatedHits baseBonus))))

fn makeSkillMatch pack: SkillPack score: I64 -> SkillMatch
  (SkillMatch :marker pack.marker :segment pack.segment :score score :tokens pack.tokens :base pack.base :payload pack.payload :retained false)

fn matchPacksLoop packs: (List SkillPack) query: Str acc: (List SkillMatch) -> (List SkillMatch)
  (if (listEmpty? packs) acc (let [(pack (optionOr (listHead packs) (makeSkillPack "" (list) (list) "" "" 0 false))) (tail (optionOr (listTail packs) (list))) (score (connectednessScore pack query))] (if (or (> score 0) pack.base) (matchPacksLoop tail query (cons (makeSkillMatch pack score) acc)) (matchPacksLoop tail query acc))))

fn insertSkillMatch item: SkillMatch sorted: (List SkillMatch) -> (List SkillMatch)
  (if (listEmpty? sorted) (list item) (let [(head (optionOr (listHead sorted) (SkillMatch :marker "" :segment "" :score 0 :tokens 0 :base false :payload "" :retained false))) (tail (optionOr (listTail sorted) (list)))] (if (> item.score head.score) (cons item sorted) (cons head (insertSkillMatch item tail)))))

fn sortSkillMatchesLoop remaining: (List SkillMatch) sorted: (List SkillMatch) -> (List SkillMatch)
  (if (listEmpty? remaining) sorted (let [(head (optionOr (listHead remaining) (SkillMatch :marker "" :segment "" :score 0 :tokens 0 :base false :payload "" :retained false))) (tail (optionOr (listTail remaining) (list)))] (sortSkillMatchesLoop tail (insertSkillMatch head sorted))))

fn rankSkillPacks packs: (List SkillPack) query: Str -> (List SkillMatch)
  (sortSkillMatchesLoop (matchPacksLoop packs query (list)) (list))

fn retainMatchesLoop remaining: (List SkillMatch) budget: I64 spent: I64 base: Bool acc: (List SkillMatch) -> (List SkillMatch)
  (if (listEmpty? remaining) acc (let [(head (optionOr (listHead remaining) (SkillMatch :marker "" :segment "" :score 0 :tokens 0 :base false :payload "" :retained false))) (tail (optionOr (listTail remaining) (list)))] (if (and (if base head.base (not head.base)) (<= (+ spent head.tokens) budget)) (let [(kept (SkillMatch :marker head.marker :segment head.segment :score head.score :tokens head.tokens :base head.base :payload head.payload :retained true))] (retainMatchesLoop tail budget (+ spent head.tokens) base (listAppend acc (list kept)))) (retainMatchesLoop tail budget spent base acc))))

fn markerListLoop matches: (List SkillMatch) acc: (List Str) -> (List Str)
  (if (listEmpty? matches) acc (let [(head (optionOr (listHead matches) (SkillMatch :marker "" :segment "" :score 0 :tokens 0 :base false :payload "" :retained false))) (tail (optionOr (listTail matches) (list)))] (markerListLoop tail (listAppend acc (list head.marker)))))

fn renderMarkersLoop markers: (List Str) acc: Str -> Str
  (if (listEmpty? markers) acc (let [(head (optionOr (listHead markers) "")) (tail (optionOr (listTail markers) (list))) (next (if (= acc "") (str "\"" head "\"") (str acc " \"" head "\"")))] (renderMarkersLoop tail next)))

fn renderMarkerTail matches: (List SkillMatch) -> Str
  (str "(:skill-markers [" (renderMarkersLoop (markerListLoop matches (list)) "") "])")

fn combineMatches front: (List SkillMatch) corpus: (List SkillMatch) -> (List SkillMatch)
  (listAppend front corpus)

fn selectSkillPacks packs: (List SkillPack) query: Str window: I64 -> SkillSelection
  (let [(tier (contextTierForWindow window)) (ranked (rankSkillPacks packs query)) (front (retainMatchesLoop ranked tier.frontBudget 0 true (list))) (corpus (retainMatchesLoop ranked tier.corpusBudget 0 false (list))) (all (combineMatches front corpus))] (SkillSelection :tier tier :front front :corpus corpus :markerTail (renderMarkerTail all) :secondarySearch tier.secondarySearch))

fn placeMarkerTail body: Str selection: SkillSelection -> Str
  (str body "\n\n" selection.markerTail)

fn defaultSkillPacks -> (List SkillPack)
  (list (makeSkillPack "svg" (list "graphics" "vector" "poster" "logo" "accessibility") (list "design") "graphics" "Use valid SVG geometry, explicit viewBox, readable contrast and a tested render target." 90 true) (makeSkillPack "design" (list "composition" "hierarchy" "colour" "rhythm") (list "svg" "poster") "graphics" "Prefer a clear focal point, deliberate spacing and a style justified by the audience." 110 true) (makeSkillPack "poster" (list "layout" "headline" "audience" "print") (list "design" "marketing") "graphics" "Choose hierarchy and scale for the stated audience, keep the message legible at the target size." 80 false) (makeSkillPack "marketing" (list "positioning" "message" "evidence" "audience") (list "poster" "copy") "delivery" "State the audience, promise and evidence, avoid invented demand or performance claims." 95 false) (makeSkillPack "context-tool" (list "retrieval" "budget" "cache" "provenance") (list "paradigm" "testing") "code" "Retrieve by linked markers, retain provenance and fit the selected blocks to the available tier budget." 100 true) (makeSkillPack "join" (list "relational" "keys" "cardinality" "nullability") (list "query" "testing") "code" "State join keys, cardinality and null behaviour before choosing a query shape." 85 false) (makeSkillPack "abstract-factory" (list "construction" "polymorphism" "interface" "testing") (list "paradigm" "design") "code" "Use a factory family when construction varies behind a stable interface, document the trade-off." 105 false) (makeSkillPack "paradigm" (list "invariants" "tradeoffs" "composition" "boundaries") (list "context-tool" "design") "code" "Name the invariant, boundary and trade-off before selecting a specialised technique." 100 true) (makeSkillPack "quantum" (list "qubit" "gate" "circuit" "measurement") (list "simulation" "verification") "code" "Treat a quantum circuit as a testable proposal, specify gates, measurement and simulator assumptions." 120 false))
