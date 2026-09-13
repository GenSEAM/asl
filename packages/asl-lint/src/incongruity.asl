(module asl-lint/incongruity
  :d "AgentScript monorepo forensic scanner validating zero sigils, zero foreign files, crutch eradication, and 1-to-2 token compliance (d41, d46, d48)."
  :x [IncongruityReport
      scanMonorepoIncongruities
      detectCrutches
      detectLingeringSigils
      makeIncongruityReport]
  :i [(asl-lint/tokens :a tok)])

(dfs IncongruityReport
  (:f totalScanned I64 "Total items, files, or symbols scanned")
  (:f sigilViolations I64 "Count of lingering sigils discovered")
  (:f foreignViolations I64 "Count of foreign files or illegal markdown memory ledgers")
  (:f tokenViolations I64 "Count of symbols exceeding the 2-token ceiling")
  (:f crutchViolations I64 "Count of temporary crutches or scaffolding patterns")
  (:f passed Bool "True if all invariant checks pass with zero violations"))

(df makeIncongruityReport [(scanned I64) (sigils I64) (foreign I64) (tokens I64) (crutches I64)] -> IncongruityReport
  :d "Constructs an IncongruityReport and evaluates pass/fail status based on zero violations."
  (let [(ok? (and (= sigils 0)
                  (and (= foreign 0)
                       (and (= tokens 0)
                            (= crutches 0)))))]
    (IncongruityReport
      :totalScanned scanned
      :sigilViolations sigils
      :foreignViolations foreign
      :tokenViolations tokens
      :crutchViolations crutches
      :passed ok?)))

(df hasSigil? [(text Str)] -> Bool
  :d "Checks if a string contains prohibited sigils per c5 and d48."
  (or (string-contains? text "@")
      (string-contains? text "#")))

(df detectLingeringSigils [(items (List Str))] -> I64
  :d "Counts occurrences of prohibited sigils across a list of text strings."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (hasSigil? item)
            (+ acc 1)
            acc))
        0
        items))

(df isCrutchToken? [(text Str)] -> Bool
  :d "Checks if a string contains known temporary scaffolding or crutch markers."
  (or (string-contains? text "TODO")
      (or (string-contains? text "todo")
          (or (string-contains? text "FIXME")
              (or (string-contains? text "HACK")
                  (or (string-contains? text "STUB")
                      (or (string-contains? text "stub")
                          (or (string-contains? text "MOCK")
                              (or (string-contains? text "mock")
                                  (or (string-contains? text "SWALLOW")
                                      (or (string-contains? text "swallow")
                                          (or (string-contains? text "crutch")
                                              (string-contains? text "temporary-scaffolding")))))))))))))

(df detectCrutches [(items (List Str))] -> I64
  :d "Counts instances of temporary crutches and scaffolding markers across a list of items."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (isCrutchToken? item)
            (+ acc 1)
            acc))
        0
        items))

(df isForeignFile? [(path Str)] -> Bool
  :d "Checks if a path violates pure AgentScript rules."
  (or (string-ends-with? path ".py")
      (or (string-ends-with? path ".js")
          (or (string-ends-with? path ".ts")
              (or (string-ends-with? path ".rs")
                  (and (string-contains? path ".asl/mem/")
                       (string-ends-with? path ".md")))))))

(df detectForeignFiles [(paths (List Str))] -> I64
  :d "Counts foreign files and illegal markdown memory ledgers."
  (fold (fn [(acc I64) (path Str)] -> I64
          (if (isForeignFile? path)
            (+ acc 1)
            acc))
        0
        paths))

(df isTokenCompliant? [(sym Str)] -> Bool
  :d "Checks whether an identifier complies with 1-to-2 token ceiling."
  (<= (tok/estimateIdentifierTokens sym) 2))

(df detectTokenViolations [(symbols (List Str))] -> I64
  :d "Counts identifiers exceeding the 2-token ceiling."
  (fold (fn [(acc I64) (sym Str)] -> I64
          (if (isTokenCompliant? sym)
            acc
            (+ acc 1)))
        0
        symbols))

(df scanMonorepoIncongruities [(paths (List Str)) (symbols (List Str)) (snippets (List Str))] -> IncongruityReport
  :d "Performs forensic monorepo scan aggregating sigils, foreign files, token ceiling, and crutch violations."
  (let [(sigils (+ (detectLingeringSigils paths)
                   (+ (detectLingeringSigils symbols)
                      (detectLingeringSigils snippets))))
        (foreign (detectForeignFiles paths))
        (tokens (detectTokenViolations symbols))
        (crutches (detectCrutches snippets))
        (total (+ (list-length paths)
                  (+ (list-length symbols)
                     (list-length snippets))))]
    (makeIncongruityReport total sigils foreign tokens crutches)))
