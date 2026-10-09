(module aslWebApiSearch/research
  :x [ResearchPlan SynthesizedFact UnifiedResearchReport makeResearchPlan makeSynthesizedFact makeResearchReport formatResearchReport formatFactAsn formatResearchReportAsn formatResearchTriageAsn extractKeyFacts buildResearchQueries classifySourceKind deriveVerificationStatus]
  :i [(engine :a eng) (router :a rt) (hybrid :a hyb)])

(schema ResearchPlan
  (:f topic Str)
  (:f depth Str)
  (:f queries (List Str))
  (:f maxResults I64)
  (:f targetEngines (List Str)))

(schema SynthesizedFact
  (:f id Str)
  (:f claim Str)
  (:f evidence Str)
  (:f sourceUrl Str)
  (:f isFalsifying Bool)
  (:f sourceKind Str)
  (:f verificationStatus Str)
  (:f predicate Str)
  (:f srcRef I64)
  (:f crawled Bool))

(schema UnifiedResearchReport
  (:f topic Str)
  (:f status Str)
  (:f facts (List SynthesizedFact))
  (:f sources (List Str))
  (:f positiveSynthesis Str)
  (:f falsificationCritique Str)
  (:f summary Str))

fn makeResearchPlan topic: Str depth: Str -> ResearchPlan
  (let [(d (stringLower depth))
        (cleanT (stringTrim topic))]
    (cond
      ((= d "flash")
       (ResearchPlan
         :topic cleanT
         :depth "flash"
         :queries (list cleanT)
         :maxResults 3
         :targetEngines (list "tavily" "serper" "ddg")))
      ((= d "targeted")
       (ResearchPlan
         :topic cleanT
         :depth "targeted"
         :queries (list cleanT (str cleanT " documentation reference"))
         :maxResults 5
         :targetEngines (list "serper" "tavily" "wikipedia" "ddg")))
      ((= d "bipolar")
       (let [(bipolar (eng/generateBipolarQuery cleanT "architecture"))]
         (ResearchPlan
           :topic cleanT
           :depth "bipolar"
           :queries (list bipolar.positiveQuery bipolar.negativeQuery)
           :maxResults 6
           :targetEngines (list "tavily" "serper" "arxiv" "github"))))
      (else
       (ResearchPlan
         :topic cleanT
         :depth "matrix"
         :queries (list cleanT (str cleanT " architecture design") (str cleanT " benchmarks performance") (str cleanT " limitations drawbacks"))
         :maxResults 10
         :targetEngines (list "tavily" "serper" "brave" "arxiv" "github" "ddg")))))

fn buildResearchQueries plan: ResearchPlan -> (List Str)
  plan.queries

fn classifySourceKind url: Str -> Str
  (let [(clean (stringLower url))]
    (cond
      ((or (stringContains? clean "arxiv.org") (or (stringContains? clean "doi.org") (stringContains? clean "biorxiv.org"))) "peerReviewed")
      ((or (stringContains? clean "github.com") (or (stringContains? clean "gitlab.com") (or (stringContains? clean "ietf.org") (or (stringContains? clean "/docs") (stringContains? clean "docs."))))) "primaryArtifact")
      ((or (stringContains? clean "wikipedia.org") (or (stringContains? clean "stackoverflow.com") (stringContains? clean "stackexchange.com"))) "crowdsourced")
      ((or (stringContains? clean "medium.com") (or (stringContains? clean "dev.to") (or (stringContains? clean "substack.com") (or (stringContains? clean "news.") (stringContains? clean "/blog"))))) "secondaryReport")
      (else "unverifiedWeb")))

fn deriveVerificationStatus isFalsifying: Bool isEmpirical: Bool multiSource: Bool -> Str
  (cond
    (isEmpirical (if isFalsifying "refuted" "empiricallyVerified"))
    (isFalsifying "disputed")
    (multiSource "corroborated")
    (else "unfalsified"))

fn derivePredicate claim: Str -> Str
  (let [(clean (stringLower (stringTrim claim)))]
    (cond
      ((stringContains? clean "optimizes") "optimizes")
      ((stringContains? clean "reduces") "reduces")
      ((stringContains? clean "requires") "requires")
      ((stringContains? clean "exhibits") "exhibits")
      ((stringContains? clean "verif") "verifies")
      ((stringContains? clean "limit") "limits")
      ((stringContains? clean "is") "is")
      (else "asserts")))

fn makeSynthesizedFact id: Str claim: Str evidence: Str sourceUrl: Str isFalsifying: Bool sourceKind: Str verificationStatus: Str srcRef: I64 crawled: Bool -> SynthesizedFact
  (let [(cleanUrl (eng/cleanUrl sourceUrl))
        (kind (if (stringEmpty? sourceKind) (classifySourceKind cleanUrl) sourceKind))
        (status (if (stringEmpty? verificationStatus) (deriveVerificationStatus isFalsifying false false) verificationStatus))
        (pred (derivePredicate claim))]
    (SynthesizedFact
      :id id
      :claim claim
      :evidence evidence
      :sourceUrl cleanUrl
      :isFalsifying isFalsifying
      :sourceKind kind
      :verificationStatus status
      :predicate pred
      :srcRef (if (> srcRef 0) srcRef 1)
      :crawled crawled))

fn makeResearchReport topic: Str status: Str facts: (List SynthesizedFact) sources: (List Str) pos: Str crit: Str sum: Str -> UnifiedResearchReport
  (UnifiedResearchReport
    :topic topic
    :status status
    :facts facts
    :sources sources
    :positiveSynthesis pos
    :falsificationCritique crit
    :summary sum)

fn extractKeyFacts items: (List eng/SearchResult) isFalsifying: Bool -> (List SynthesizedFact)
  (fold (fn [(acc (List SynthesizedFact)) (item eng/SearchResult)] -> (List SynthesizedFact)
          (let [(idx (listLength acc))
                (factId (str "fact-" (stringFromInt64 (+ idx 1))))
                (src item.url)
                (kind (classifySourceKind src))
                (status (if isFalsifying "disputed" "unfalsified"))
                (fact (makeSynthesizedFact
                        factId
                        item.title
                        item.snippet
                        src
                        isFalsifying
                        kind
                        status
                        (+ idx 1)
                        false))]
            (listAppend acc (list fact))))
        (list)
        items)

fn formatFactMarkdown fact: SynthesizedFact -> Str
  (let [(marker (if fact.isFalsifying "[CRITIQUE/LIMITATION]" "[AFFIRMATIVE]"))]
    (str "- " marker " **" fact.claim "**\n  "
         fact.evidence "\n  *Source: <" fact.sourceUrl "> ["
         fact.sourceKind " - " fact.verificationStatus "]*\n"))

fn formatFactAsn fact: SynthesizedFact -> Str
  (let [(fals (if fact.isFalsifying "true" "false"))
        (craw (if fact.crawled " :crawled true" ""))
        (cleanEv (stringReplace fact.evidence "\"" "\\\""))
        (cleanCl (stringReplace fact.claim "\"" "\\\""))]
    (str "    (:fact :id \"" fact.id "\""
         " :predicate (:relation \"" fact.predicate "\" :subject \"" cleanCl "\" :object \"asserts\")"
         " :claim \"" cleanCl "\""
         " :evidence \"" cleanEv "\""
         " :srcRef " (stringFromInt64 fact.srcRef)
         " :source \"" fact.sourceUrl "\""
         " :sourceKind :" fact.sourceKind
         " :verificationStatus :" fact.verificationStatus
         craw
         " :isFalsifying " fals ")"))

fn formatTriageFactAsn fact: SynthesizedFact -> Str
  (let [(fals (if fact.isFalsifying "true" "false"))]
    (str "    (:p :id \"" fact.id "\""
         " :predicate (:relation \"" fact.predicate "\" :subject \"" (stringReplace fact.claim "\"" "\\\"") "\" :object \"asserts\")"
         " :srcRef " (stringFromInt64 fact.srcRef)
         " :verificationStatus :" fact.verificationStatus
         " :isFalsifying " fals ")"))

fn formatResearchReportAsn report: UnifiedResearchReport -> Str
  (let [(factRows (map formatFactAsn report.facts))
        (srcList (map (fn [s] (str "    \"" s "\"")) report.sources))]
    (str "(:researchReport\n"
         "  :topic \"" report.topic "\"\n"
         "  :status :" report.status "\n"
         "  :summary \"" (stringReplace report.summary "\"" "\\\"") "\"\n"
         "  :positiveSynthesis \"" (stringReplace report.positiveSynthesis "\"" "\\\"") "\"\n"
         "  :falsificationCritique \"" (stringReplace report.falsificationCritique "\"" "\\\"") "\"\n"
         "  :facts [\n"
         (stringJoin factRows "\n")
         "\n  ]\n"
         "  :sources (\n"
         (stringJoin srcList "\n")
         "\n  ))\n"))

fn formatResearchTriageAsn report: UnifiedResearchReport -> Str
  (let [(factRows (map formatTriageFactAsn report.facts))
        (srcList (map (fn [s] (str "    \"" s "\"")) report.sources))]
    (str "(:researchTriage\n"
         "  :topic \"" report.topic "\"\n"
         "  :status :" report.status "\n"
         "  :facts [\n"
         (stringJoin factRows "\n")
         "\n  ]\n"
         "  :sources (\n"
         (stringJoin srcList "\n")
         "\n  ))\n"))

fn formatResearchReport report: UnifiedResearchReport -> Str
  (let [(header (str "# Research Report: " report.topic " [" report.status "]\n\n"))
        (execSum (str "## Executive Summary\n" report.summary "\n\n"))
        (posBlock (str "## Affirmative Findings\n" report.positiveSynthesis "\n\n"))
        (critBlock (str "## Counter-Evidence & Limitations\n" report.falsificationCritique "\n\n"))
        (factRows (map formatFactMarkdown report.facts))
        (factsSection (str "## Extracted Evidence (" (stringFromInt64 (listLength report.facts)) " items)\n\n"
                           (stringJoin factRows "\n")))
        (srcList (map (fn [s] (str "- <" s ">")) report.sources))
        (srcSection (str "\n\n## Sources Consulted (" (stringFromInt64 (listLength report.sources)) ")\n\n"
                         (stringJoin srcList "\n")))]
    (str header execSum posBlock critBlock factsSection srcSection "\n"))
