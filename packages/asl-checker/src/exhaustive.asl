(module asl-checker/exhaustive
  :x [ExhaustiveReport makeExhaustiveReport checkMatchExhaustiveness isArmCovered?]
  :i [])

(schema ExhaustiveReport
  (:f isExhaustive Bool)
  (:f missingVariants (List String))
  (:f hasWildcard Bool)
  (:f diagnostic String))

fn makeExhaustiveReport isExhaustive: Bool missing: (List String) hasWildcard: Bool diag: String -> ExhaustiveReport
  (ExhaustiveReport :isExhaustive isExhaustive :missingVariants missing :hasWildcard hasWildcard :diagnostic diag)

fn isArmCovered? covered: (List String) variant: String -> Bool
  (listContains? covered variant)

fn checkMatchExhaustiveness allVariants: (List String) coveredArms: (List String) hasWildcard: Bool -> ExhaustiveReport
  (if hasWildcard
    (makeExhaustiveReport true (list) true "")
    (let [(missing (filter (fn [(v String)] (not (listContains? coveredArms v))) allVariants))]
      (if (listEmpty? missing)
        (makeExhaustiveReport true (list) false "")
        (makeExhaustiveReport false missing false (str "Non-exhaustive pattern match: missing cases [" (stringJoin missing ", ") "]")))))
