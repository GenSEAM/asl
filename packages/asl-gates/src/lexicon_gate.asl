(module asl-gates/lexiconGate
  :d "Pure AgentScript canonical lexicon audit and drift verification gate."
  :x [LexiconTerm LexiconRegistry
      makeLexiconTerm auditLexiconTerms checkLocalAliasTables
      verifyCanonicalReferents isSpokenMishearing?]
  :i [])

(dfs LexiconTerm
  (:f canonical Str "Authoritative canonical term identifier")
  (:f spoken (List Str) "List of recognized acoustic mishearings")
  (:f scope Str "Domain scope e.g. tool, project, agent")
  (:f why Str "Architectural justification for mapping"))

(dfs LexiconRegistry
  (:f version Str "Lexicon schema semantic version")
  (:f terms (List LexiconTerm) "Registered canonical lexicon entries"))

(df makeLexiconTerm [(canonical Str) (spoken (List Str)) (scope Str) (why Str)] -> LexiconTerm
  (LexiconTerm
    :canonical canonical
    :spoken spoken
    :scope scope
    :why why))

(df isSpokenMishearing? [(term Str) (spoken (List Str))] -> Bool
  :d "Checks if a given term matches any known spoken mishearing form."
  (let [(matches (filter (fn [(s Str)] -> Bool (= s term)) spoken))]
    (not (list-empty? matches))))

(df auditLexiconTerms [(registry LexiconRegistry)] -> Bool
  :d "Verifies each lexicon term has non-empty canonical, scope, why, and spoken list."
  (let [(terms (.-terms registry))]
    (if (list-empty? terms)
        false
        (let [(invalid (filter (fn [(t LexiconTerm)] -> Bool
                                 (or (= (string-length (.-canonical t)) 0)
                                     (= (string-length (.-scope t)) 0)
                                     (= (string-length (.-why t)) 0)
                                     (list-empty? (.-spoken t))))
                               terms))]
          (list-empty? invalid)))))

(df checkLocalAliasTables [(files (List Str))] -> Bool
  :d "Verifies no unauthorized local alias tables exist outside canonical lexicon."
  (let [(forbidden (filter (fn [(f Str)] -> Bool
                             (and (string-contains? f "alias_table")
                                  (not (string-contains? f "lexicon.asn"))))
                           files))]
    (list-empty? forbidden)))

(df verifyCanonicalReferents [(terms (List LexiconTerm)) (corpus Str)] -> Bool
  :d "Verifies that every canonical term has at least one active referent in the repository."
  (let [(unreferenced (filter (fn [(t LexiconTerm)] -> Bool
                                (not (string-contains? corpus (.-canonical t))))
                              terms))]
    (list-empty? unreferenced)))
