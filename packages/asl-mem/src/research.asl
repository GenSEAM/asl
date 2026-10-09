(module aslMem/research :x [ResearchFact ResearchReport ResearchQueryOutcome makeResearchFact makeResearchReport queryResearchMemory storeResearchFact] :i [])

(schema ResearchFact (:f id Str) (:f query Str) (:f fact Str) (:f source Str) (:f confidence F64) (:f timestamp I64))

(schema ResearchReport (:f id Str) (:f topic Str) (:f hypothesis Str) (:f facts (List Str)) (:f notes (List Str)) (:f synthesis Str) (:f status Str))

(schema ResearchQueryOutcome (:f isDirectHit Bool) (:f fact Str) (:f tokenCost I64) (:f delegated Bool))

fn makeResearchFact id: Str query: Str fact: Str source: Str confidence: F64 -> ResearchFact
  (ResearchFact :id id :query query :fact fact :source source :confidence confidence :timestamp 0)

fn makeResearchReport id: Str topic: Str hypothesis: Str facts: (List Str) notes: (List Str) synthesis: Str status: Str -> ResearchReport
  (ResearchReport :id id :topic topic :hypothesis hypothesis :facts facts :notes notes :synthesis synthesis :status status)

fn storeResearchFact fact: ResearchFact index: (List ResearchFact) -> (List ResearchFact)
  (if (listEmpty? index) (list fact) (let [(filtered (filter (fn [(f ResearchFact)] -> Bool (and (!= f.id fact.id) (!= f.query fact.query))) index))] (cons fact filtered)))

fn findMatchingFactLoop q: Str facts: (List ResearchFact) -> (Option ResearchFact)
  (if (listEmpty? facts) (none) (let [(f (optionOr (listHead facts) (ResearchFact :id "" :query "" :fact "" :source "" :confidence 0.0 :timestamp 0))) (rest (optionOr (listTail facts) (list))) (fQuery f.query)] (if (or (= fQuery q) (or (stringContains? fQuery q) (stringContains? q fQuery))) (some f) (findMatchingFactLoop q rest))))

fn findMatchingFact q: Str facts: (List ResearchFact) -> (Option ResearchFact)
  (findMatchingFactLoop q facts)

fn queryResearchMemory query: Str index: (List ResearchFact) threshold: F64 -> ResearchQueryOutcome
  (let [(facts index) (minConf (if (<= threshold 0.0) 0.85 threshold)) (matchedOpt (findMatchingFact query facts))] (mt matchedOpt ((none) (ResearchQueryOutcome :isDirectHit false :fact "" :tokenCost 150 :delegated true)) ((some f) (if (>= f.confidence minConf) (ResearchQueryOutcome :isDirectHit true :fact f.fact :tokenCost 0 :delegated false) (ResearchQueryOutcome :isDirectHit false :fact f.fact :tokenCost 150 :delegated true)))))
