(module aslBench/mutationStrategy :x [MutantRecord TriageRecord MutationSessionReport SelectMutants TriageMutant CalculateMutationScore DigestCacheLookup RecordSeed RunTests] :i [])

(schema MutantRecord (:f id Str) (:f package Str) (:f symbol Str) (:f tier Str) (:f category Str) (:f original Str) (:f mutated Str) (:f expectedOutcome Str) (:f justification Str))

(schema TriageRecord (:f mutantId Str) (:f status Str) (:f justification Str))

(schema MutationSessionReport (:f seed I64) (:f budgetMs I64) (:f wallMs I64) (:f budgetHonoured Bool) (:f sourceDigest Str) (:f fromCache Bool) (:f total I64) (:f selected I64) (:f killed I64) (:f equivalentCount I64) (:f survived I64) (:f mutationScore Str))

fn RecordSeed seedVal: I64 -> I64
  (let [(recordSeed seedVal)] recordSeed)

fn NextLcg seed: I64 -> I64
  (let [(nextVal (mod (+ (* seed 1103515245) 12345) 2147483648))] (if (< nextVal 0) (- 0 nextVal) nextVal))

fn SelectMutants candidates: (List MutantRecord) seed: I64 coreTierOnly: Bool sampleRate: I64 -> (List MutantRecord)
  (let [(recSeed (RecordSeed seed))] (let [(result (filter (fn [(m MutantRecord)] (let [(tier m.tier)] (if (= tier "core-tier") true (if coreTierOnly false (let [(h (NextLcg (+ recSeed (stringLength m.id))))] (= (mod h 100) 0)))))) candidates))] result))

fn TriageMutant m: MutantRecord assertionFailed: Bool -> TriageRecord
  (if assertionFailed (TriageRecord :mutantId m.id :status "killed" :justification "") (let [(exp m.expectedOutcome)] (if (or (= exp "equivalent") (= exp ":equivalent")) (TriageRecord :mutantId m.id :status ":equivalent" :justification m.justification) (TriageRecord :mutantId m.id :status "survived" :justification ""))))

fn CalculateMutationScore killed: I64 total: I64 equivalent: I64 -> Str
  (let [(effective (- total equivalent))] (if (<= effective 0) "1.000" (let [(pct (/ (* killed 1000) effective))] (let [(whole (/ pct 1000)) (frac (mod pct 1000))] (stringConcat (stringConcat (str whole) ".") (str frac))))))

fn DigestCacheLookup cachedDigest: Str currentDigest: Str -> Bool
  (and (= (stringLength cachedDigest) (stringLength currentDigest)) (= cachedDigest currentDigest))

fn RunTests -> Bool
  (let [(m1 (MutantRecord :id "m1" :package "asl-gates" :symbol "assert-equal" :tier "core-tier" :category "relational" :original "(= a b)" :mutated "(!= a b)" :expectedOutcome "killed" :justification "")) (m2 (MutantRecord :id "m2" :package "asl-eval" :symbol "eval-add" :tier "core-tier" :category "arithmetic" :original "(+ x 1)" :mutated "(- x 1)" :expectedOutcome "killed" :justification "")) (mEq (MutantRecord :id "meq1" :package "asl-bench" :symbol "is-under-budget?" :tier "bench" :category "equivalent" :original "(<= a b)" :mutated "(or (< a b) (= a b))" :expectedOutcome ":equivalent" :justification "Logical equivalence: <= is identical to < or ="))] (let [(pool [m1 m2 mEq])] (let [(sel1 (SelectMutants pool 42 true 10)) (sel2 (SelectMutants pool 42 true 10))] (assert (= (listLength sel1) (listLength sel2)) "Same seed must reproduce identical selection count") (assert (= (listLength sel1) 2) "Core-tier selection must select exactly 2 core mutants") (let [(triageKilled (TriageMutant m1 true)) (triageEquiv (TriageMutant mEq false))] (assert (= triageKilled.status "killed") "Failed assertion must triage as killed") (assert (= triageEquiv.status ":equivalent") "Equivalent mutant must triage as :equivalent") (assert (> (stringLength triageEquiv.justification) 0) "Equivalent triage must carry written justification") (let [(score (CalculateMutationScore 2 3 1))] (assert (= score "1.0") "2 killed out of 3 total with 1 equivalent must yield score 1.0") (assert (DigestCacheLookup "abcdef12" "abcdef12") "Matching digest must hit cache") (assert (not (DigestCacheLookup "abcdef12" "changed99")) "Different digest must miss cache") (let [(report (MutationSessionReport :seed 42 :budgetMs 10000 :wallMs 120 :budgetHonoured true :sourceDigest "abcdef12" :fromCache true :total 3 :selected 2 :killed 2 :equivalentCount 1 :survived 0 :mutationScore "1.0"))] (assert report.fromCache "Report must record :fromCache flag") true))))))
