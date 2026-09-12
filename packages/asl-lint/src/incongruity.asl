(module asl-lint/incongruity
  :d "AgentScript monorepo forensic scanner validating zero sigils, zero foreign files, crutch eradication, and 1-to-2 token compliance (d41, d46, d48)."
  :x [IncongruityReport
      scan-monorepo-incongruities
      detect-crutches
      detect-lingering-sigils
      make-incongruity-report]
  :i [(asl-lint/tokens :a tok)])

(dfs IncongruityReport
  (:f total-scanned I64 "Total items, files, or symbols scanned")
  (:f sigil-violations I64 "Count of lingering sigils discovered")
  (:f foreign-violations I64 "Count of foreign files or illegal markdown memory ledgers")
  (:f token-violations I64 "Count of symbols exceeding the 2-token ceiling")
  (:f crutch-violations I64 "Count of temporary crutches or scaffolding patterns")
  (:f passed Bool "True if all invariant checks pass with zero violations"))

(df make-incongruity-report [(scanned I64) (sigils I64) (foreign I64) (tokens I64) (crutches I64)] -> IncongruityReport
  :d "Constructs an IncongruityReport and evaluates pass/fail status based on zero violations."
  (let [(ok? (and (= sigils 0)
                  (and (= foreign 0)
                       (and (= tokens 0)
                            (= crutches 0)))))]
    (IncongruityReport
      :total-scanned scanned
      :sigil-violations sigils
      :foreign-violations foreign
      :token-violations tokens
      :crutch-violations crutches
      :passed ok?)))

(df has-sigil? [(text Str)] -> Bool
  :d "Checks if a string contains prohibited sigils per c5 and d48."
  (or (string-contains? text "@")
      (string-contains? text "#")))

(df detect-lingering-sigils [(items (List Str))] -> I64
  :d "Counts occurrences of prohibited sigils across a list of text strings."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (has-sigil? item)
            (+ acc 1)
            acc))
        0
        items))

(df is-crutch-token? [(text Str)] -> Bool
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

(df detect-crutches [(items (List Str))] -> I64
  :d "Counts instances of temporary crutches and scaffolding markers across a list of items."
  (fold (fn [(acc I64) (item Str)] -> I64
          (if (is-crutch-token? item)
            (+ acc 1)
            acc))
        0
        items))

(df is-foreign-file? [(path Str)] -> Bool
  :d "Checks if a path violates pure AgentScript rules."
  (or (string-ends-with? path ".py")
      (or (string-ends-with? path ".js")
          (or (string-ends-with? path ".ts")
              (or (string-ends-with? path ".rs")
                  (and (string-contains? path ".asl/mem/")
                       (string-ends-with? path ".md")))))))

(df detect-foreign-files [(paths (List Str))] -> I64
  :d "Counts foreign files and illegal markdown memory ledgers."
  (fold (fn [(acc I64) (path Str)] -> I64
          (if (is-foreign-file? path)
            (+ acc 1)
            acc))
        0
        paths))

(df is-token-compliant? [(sym Str)] -> Bool
  :d "Checks whether an identifier complies with 1-to-2 token ceiling."
  (<= (tok/estimate-identifier-tokens sym) 2))

(df detect-token-violations [(symbols (List Str))] -> I64
  :d "Counts identifiers exceeding the 2-token ceiling."
  (fold (fn [(acc I64) (sym Str)] -> I64
          (if (is-token-compliant? sym)
            acc
            (+ acc 1)))
        0
        symbols))

(df scan-monorepo-incongruities [(paths (List Str)) (symbols (List Str)) (snippets (List Str))] -> IncongruityReport
  :d "Performs forensic monorepo scan aggregating sigils, foreign files, token ceiling, and crutch violations."
  (let [(sigils (+ (detect-lingering-sigils paths)
                   (+ (detect-lingering-sigils symbols)
                      (detect-lingering-sigils snippets))))
        (foreign (detect-foreign-files paths))
        (tokens (detect-token-violations symbols))
        (crutches (detect-crutches snippets))
        (total (+ (list-length paths)
                  (+ (list-length symbols)
                     (list-length snippets))))]
    (make-incongruity-report total sigils foreign tokens crutches)))
