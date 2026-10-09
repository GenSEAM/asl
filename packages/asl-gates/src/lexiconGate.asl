(module asl-gates/lexiconGate :x [LexiconTerm LexiconRegistry makeLexiconTerm auditLexiconTerms checkLocalAliasTables verifyCanonicalReferents isSpokenMishearing?] :i [])

(schema LexiconTerm (:f canonical Str) (:f spoken (List Str)) (:f scope Str) (:f why Str))

(schema LexiconRegistry (:f version Str) (:f terms (List LexiconTerm)))

fn makeLexiconTerm canonical: Str spoken: (List Str) scope: Str why: Str -> LexiconTerm
  (LexiconTerm :canonical canonical :spoken spoken :scope scope :why why)

fn isSpokenMishearing? term: Str spoken: (List Str) -> Bool
  (let [(matches (filter (fn [(s Str)] -> Bool (= s term)) spoken))] (not (listEmpty? matches)))

fn auditLexiconTerms registry: LexiconRegistry -> Bool
  (let [(terms registry.terms)] (if (listEmpty? terms) false (let [(invalid (filter (fn [(t LexiconTerm)] -> Bool (or (= (stringLength t.canonical) 0) (= (stringLength t.scope) 0) (= (stringLength t.why) 0) (listEmpty? t.spoken))) terms))] (listEmpty? invalid))))

fn checkLocalAliasTables files: (List Str) -> Bool
  (let [(forbidden (filter (fn [(f Str)] -> Bool (and (stringContains? f "alias_table") (not (stringContains? f "lexicon.asn")))) files))] (listEmpty? forbidden))

fn verifyCanonicalReferents terms: (List LexiconTerm) corpus: Str -> Bool
  (let [(unreferenced (filter (fn [(t LexiconTerm)] -> Bool (not (stringContains? corpus t.canonical))) terms))] (listEmpty? unreferenced))
