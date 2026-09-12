(module asl-bench/mutation-strategy
  :d "Deterministic mutation selection, equivalent mutant triage, and incremental digest caching under ADR-0081."
  :x [MutantRecord
      TriageRecord
      MutationSessionReport
      SelectMutants
      TriageMutant
      CalculateMutationScore
      DigestCacheLookup
      RecordSeed
      RunTests]
  :i [])

(dfs MutantRecord
  (:f id Str "Mutant identifier")
  (:f package Str "Package owning mutated symbol")
  (:f symbol Str "Target symbol mutated")
  (:f tier Str "Package tier: core-tier, affordance, peripheral")
  (:f category Str "Mutation operator category")
  (:f original Str "Original AST expression")
  (:f mutated Str "Mutated AST expression")
  (:f expectedOutcome Str "Expected outcome: killed, equivalent, survived")
  (:f justification Str "Written justification for equivalent mutants"))

(dfs TriageRecord
  (:f mutantId Str "Mutant identifier")
  (:f status Str "Triaged classification: killed, equivalent, survived")
  (:f justification Str "Justification if equivalent"))

(dfs MutationSessionReport
  (:f seed I64 "Recorded pseudorandom seed")
  (:f budgetMs I64 "Wall-clock budget in milliseconds")
  (:f wallMs I64 "Actual wall-clock elapsed time")
  (:f budgetHonoured Bool "True if within allocated budget")
  (:f sourceDigest Str "Cryptographic digest of target sources")
  (:f fromCache Bool "True if result was served from incremental cache")
  (:f total I64 "Total mutants in candidate pool")
  (:f selected I64 "Number of selected mutants")
  (:f killed I64 "Number of killed mutants")
  (:f equivalentCount I64 "Number of equivalent mutants triaged")
  (:f survived I64 "Number of genuinely surviving mutants")
  (:f mutationScore Str "Mutation score formatted as decimal string"))

(df RecordSeed [(seedVal I64)] -> I64
  :d "Returns recorded seed for deterministic selection"
  (let [(record-seed seedVal)]
    record-seed))

(df NextLcg [(seed I64)] -> I64
  :d "Linear congruential pseudo-random step for reproducible seed sampling"
  (let [(next-val (mod (+ (* seed 1103515245) 12345) 2147483648))]
    (if (< next-val 0)
        (- 0 next-val)
        next-val)))

(df SelectMutants [(candidates (List MutantRecord))
                   (seed I64)
                   (coreTierOnly Bool)
                   (sampleRate I64)] -> (List MutantRecord)
  :d "Applies selection rule: core-tier package assertions, changed symbols, plus seed-sampled sample"
  (let [(rec-seed (RecordSeed seed))]
    (let [(result (list-filter
                    (fn [(m MutantRecord)]
                      (let [(tier (.-tier m))]
                        (if (= tier "core-tier")
                            true
                            (if coreTierOnly
                                false
                                (let [(h (NextLcg (+ rec-seed (string-length (.-id m)))))]
                                  (= (mod h 100) 0))))))
                    candidates))]
      result)))

(df TriageMutant [(m MutantRecord) (assertionFailed Bool)] -> TriageRecord
  :d "Triages a mutant into killed, equivalent with justification, or survived"
  (if assertionFailed
      (TriageRecord
        :mutantId (.-id m)
        :status "killed"
        :justification "")
      (let [(exp (.-expectedOutcome m))]
        (if (or (= exp "equivalent") (= exp ":equivalent"))
            (TriageRecord
              :mutantId (.-id m)
              :status ":equivalent"
              :justification (.-justification m))
            (TriageRecord
              :mutantId (.-id m)
              :status "survived"
              :justification "")))))

(df CalculateMutationScore [(killed I64) (total I64) (equivalent I64)] -> Str
  :d "Calculates mutation score K / (T - E) as ratio string"
  (let [(effective (- total equivalent))]
    (if (<= effective 0)
        "1.000"
        (let [(pct (/ (* killed 1000) effective))]
          (let [(whole (/ pct 1000))
                (frac (mod pct 1000))]
            (str-concat (str-concat (str whole) ".") (str frac)))))))

(df DigestCacheLookup [(cachedDigest Str) (currentDigest Str)] -> Bool
  :d "Determines whether execution can complete from incremental cache"
  (and (= (string-length cachedDigest) (string-length currentDigest))
       (= cachedDigest currentDigest)))

(df RunTests [] -> Bool
  :d "Executes internal verification tests for mutation strategy"
  (let [(m1 (MutantRecord
              :id "m1"
              :package "asl-gates"
              :symbol "assert-equal"
              :tier "core-tier"
              :category "relational"
              :original "(= a b)"
              :mutated "(!= a b)"
              :expectedOutcome "killed"
              :justification ""))
        (m2 (MutantRecord
              :id "m2"
              :package "asl-eval"
              :symbol "eval-add"
              :tier "core-tier"
              :category "arithmetic"
              :original "(+ x 1)"
              :mutated "(- x 1)"
              :expectedOutcome "killed"
              :justification ""))
        (m-eq (MutantRecord
                :id "meq1"
                :package "asl-bench"
                :symbol "is-under-budget?"
                :tier "bench"
                :category "equivalent"
                :original "(<= a b)"
                :mutated "(or (< a b) (= a b))"
                :expectedOutcome ":equivalent"
                :justification "Logical equivalence: <= is identical to < or ="))]
    (let [(pool [m1 m2 m-eq])]
      (let [(sel1 (SelectMutants pool 42 true 10))
            (sel2 (SelectMutants pool 42 true 10))]
        (assert (= (list-len sel1) (list-len sel2)) "Same seed must reproduce identical selection count")
        (assert (= (list-len sel1) 2) "Core-tier selection must select exactly 2 core mutants")
        (let [(triage-killed (TriageMutant m1 true))
              (triage-equiv (TriageMutant m-eq false))]
          (assert (= (.-status triage-killed) "killed") "Failed assertion must triage as killed")
          (assert (= (.-status triage-equiv) ":equivalent") "Equivalent mutant must triage as :equivalent")
          (assert (> (string-length (.-justification triage-equiv)) 0) "Equivalent triage must carry written justification")
          (let [(score (CalculateMutationScore 2 3 1))]
            (assert (= score "1.0") "2 killed out of 3 total with 1 equivalent must yield score 1.0")
            (assert (DigestCacheLookup "abcdef12" "abcdef12") "Matching digest must hit cache")
            (assert (not (DigestCacheLookup "abcdef12" "changed99")) "Different digest must miss cache")
            (let [(report (MutationSessionReport :seed 42 :budgetMs 10000 :wallMs 120 :budgetHonoured true :sourceDigest "abcdef12" :fromCache true :total 3 :selected 2 :killed 2 :equivalentCount 1 :survived 0 :mutationScore "1.0"))]
              (assert (.-fromCache report) "Report must record :fromCache flag")
              true)))))))
